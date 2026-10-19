module Main (main) where

import Control.Concurrent
  ( forkIO
  , killThread
  , newEmptyMVar
  , putMVar
  , readMVar
  , takeMVar
  , threadDelay
  )
import Control.Concurrent.STM
  ( atomically
  , dupTChan
  , isEmptyTChan
  , newEmptyTMVarIO
  , readTChan
  , readTVarIO
  , takeTMVar
  , writeTBQueue
  , writeTVar
  )
import Control.Exception (SomeException, bracket, try)
import Control.Monad (forM, forM_)
import Domain.Engine
  ( closeWolfVoting
  , completeNightTurn
  , resolveNightTurn
  )
import Domain.Types
  ( ChatChannel(..)
  , ChatRecord(..)
  , Command(..)
  , DomainEvent(..)
  , GameError(..)
  , GameResult(..)
  , GameState(..)
  , LifeStatus(..)
  , NightChoice(..)
  , Phase(..)
  , Player(..)
  , PlayerId
  , Role(..)
  , Team(..)
  , defaultAppearance
  , emptyLobby
  , gameHost
  , gamePhase
  , gamePlayers
  , playerId
  , playerLifeStatus
  , playerName
  , playerRole
  )
import Domain.Validation (validateGameInvariant)
import Protocol.Types
  ( PlayerView(..)
  , ServerMessage(..)
  , VotingPlayerView(..)
  )
import Server.Broadcast
  ( chatHistorySnapshot
  , chatMessageForState
  , discussionSkipStateMessage
  , lobbyMessages
  , lobbyReply
  , lobbySnapshot
  , nightMessagesForState
  , privateActionStateMessage
  , votingSnapshot
  , wolfTeamMessage
  )
import Server.Connection
  ( newOutboundQueueWithCapacity
  , sendBounded
  , tryEnqueueRoomCommand
  , tryReadOutbound
  , writeBoundedDropOldest
  )
import Server.GameLoop
  ( CreateRoomError(..)
  , applyInternalCommand
  , createRoomWithHost
  , processNextLobbyCommand
  , runGameLoopWithPhaseTimeouts
  , trySubmitCommand
  )
import Server.Room
  ( QueuedCommand(..)
  , RoomRuntime(..)
  , RoomUpdate(..)
  , findRoom
  , newRoomRegistry
  , newRoomRuntime
  , newRoomRuntimeWithCapacity
  )
import Server.Supervisor
  ( SupervisorEvent(..)
  , activeWorkerCount
  , forkSupervised
  , newSupervisor
  , shutdownSupervisor
  , supervisorEvents
  , withSupervisedGroup
  )
import Test.Hspec
  ( Spec
  , describe
  , expectationFailure
  , hspec
  , it
  , shouldBe
  , shouldSatisfy
  )

-- Đưa một lệnh vào queue với requestId tự chọn rồi chạy đúng một lượt GameLoop.
submitWithReq :: RoomRuntime -> String -> String -> Command -> IO (Either GameError GameState)
submitWithReq room reqId actor command = do
  reply <- newEmptyTMVarIO
  atomically $
    writeTBQueue (roomCommands room)
      QueuedCommand
        { queuedRequestId = reqId
        , queuedActorId = actor
        , queuedCommand = command
        , queuedReply = reply
        }

  processNextLobbyCommand room
  atomically (takeTMVar reply)

-- Đưa một lệnh vào queue rồi chạy đúng một lượt GameLoop.
submit :: RoomRuntime -> String -> Command -> IO (Either GameError GameState)
submit room = submitWithReq room "req-test"

-- Gửi lệnh vào phòng khi đang có worker chạy nền và chờ kết quả.
enqueueAndAwait :: RoomRuntime -> String -> String -> Command -> IO (Either GameError GameState)
enqueueAndAwait room reqId actor command = do
  reply <- newEmptyTMVarIO
  atomically $
    writeTBQueue (roomCommands room)
      QueuedCommand
        { queuedRequestId = reqId
        , queuedActorId = actor
        , queuedCommand = command
        , queuedReply = reply
        }
  atomically (takeTMVar reply)

ninePlayerIds :: [PlayerId]
ninePlayerIds = ["p" ++ show idx | idx <- [1 .. 9 :: Int]]

nineRolePreset :: [Role]
nineRolePreset =
  [ Werewolf
  , Werewolf
  , Werewolf
  , Seer
  , Guard
  , Witch
  , Hunter
  , Villager
  , Villager
  ]

-- Khởi tạo phòng 9 người đã Ready và StartGame với bộ vai chuẩn 9 người.
setupStartedNinePlayerRoom :: IO (RoomRuntime, RoomUpdate)
setupStartedNinePlayerRoom = do
  room <- newRoomRuntime "ROOM-9P"
  updates <- atomically (dupTChan (roomUpdates room))
  forM_ ninePlayerIds $ \pid -> do
    _ <- submitWithReq room ("join-" ++ pid) pid (Join pid ("Player-" ++ pid))
    _ <- atomically (readTChan updates)
    _ <- submitWithReq room ("ready-" ++ pid) pid (SetReady pid True)
    _ <- atomically (readTChan updates)
    pure ()
  startRes <- submitWithReq room "start-game" "p1" (StartGame "p1" nineRolePreset)
  case startRes of
    Left err -> do
      expectationFailure ("StartGame 9 nguoi phai thanh cong, loi: " ++ show err)
      pure (room, RoomUpdate 0 emptyLobby [] Nothing)
    Right _ -> do
      startUpdate <- atomically (readTChan updates)
      pure (room, startUpdate)

findPlayersByRole :: Role -> GameState -> [Player]
findPlayersByRole targetRole state =
  [ player
  | player <- gamePlayers state
  , playerRole player == Just targetRole
  ]

-- Chuyển phòng từ Night sang Day hợp lệ bằng các hàm pure của Domain.Engine.
transitionNightToDay :: RoomRuntime -> IO GameState
transitionNightToDay room = do
  current <- readTVarIO (roomState room)
  let step = do
        (locked, _) <- closeWolfVoting current True
        (resolved, _) <- resolveNightTurn locked
        completeNightTurn resolved
  case step of
    Left err -> do
      expectationFailure ("Khong the chuyen Night -> Day: " ++ show err)
      pure current
    Right (dayState, _) -> do
      atomically (writeTVar (roomState room) dayState)
      pure dayState

main :: IO ()
main = hspec $ do
  lobbySpec
  e02RolePrivacySpec
  e07ConcurrentStmSpec
  e11IdempotencySpec
  e13TimerRaceSpec
  e14BackpressureSpec
  e17SupervisionSpec
  chatAndPrivacyFilterSpec

lobbySpec :: Spec
lobbySpec = describe "T08 Lobby GameLoop" $ do

  it "Join hop le commit state, tang version va phat event" $ do
    room <- newRoomRuntime "ROOM-01"
    updates <- atomically (dupTChan (roomUpdates room))

    result <- submit room "p1" (Join "p1" "Van")
    fmap gameHost result `shouldBe` Right "p1"

    committedState <- readTVarIO (roomState room)
    version <- readTVarIO (roomVersion room)
    gameHost committedState `shouldBe` "p1"
    version `shouldBe` 1

    hasUpdate <- atomically (fmap not (isEmptyTChan updates))
    hasUpdate `shouldBe` True

    update <- atomically (readTChan updates)
    updateVersion update `shouldBe` 1
    updateState update `shouldBe` committedState
    updateEvents update `shouldBe` [PlayerJoined "p1"]

  it "Join trung ID khong doi state, version hay phat event" $ do
    room <- newRoomRuntime "ROOM-01"
    updates <- atomically (dupTChan (roomUpdates room))

    _ <- submit room "p1" (Join "p1" "Van")
    _ <- atomically (readTChan updates)
    before <- readTVarIO (roomState room)

    result <- submit room "p1" (Join "p1" "Binh")
    result `shouldBe` Left DuplicatePlayerId

    after <- readTVarIO (roomState room)
    version <- readTVarIO (roomVersion room)
    noNewUpdate <- atomically (isEmptyTChan updates)

    after `shouldBe` before
    version `shouldBe` 1
    noNewUpdate `shouldBe` True

  it "Tu choi lenh co PlayerId khac ID phien ket noi" $ do
    room <- newRoomRuntime "ROOM-01"
    updates <- atomically (dupTChan (roomUpdates room))

    result <- submit room "p999" (Join "p1" "Van")
    result `shouldBe` Left NotAuthorized

    state <- readTVarIO (roomState room)
    version <- readTVarIO (roomVersion room)
    noUpdate <- atomically (isEmptyTChan updates)

    state `shouldBe` emptyLobby
    version `shouldBe` 0
    noUpdate `shouldBe` True

  it "Join tao snapshot va PlayerJoined dung du lieu Browser" $ do
    room <- newRoomRuntime "ROOM-01"
    updates <- atomically (dupTChan (roomUpdates room))

    _ <- submit room "p1" (Join "p1" "Van")
    update <- atomically (readTChan updates)

    lobbySnapshot "ROOM-01" "p1" (updateState update)
      `shouldBe`
        MsgLobbySnapshot "ROOM-01" "p1" "p1"
          [PlayerView "p1" "Van" False True defaultAppearance]

    lobbyMessages "ROOM-01" update
      `shouldBe`
        [MsgPlayerJoined "ROOM-01"
          (PlayerView "p1" "Van" False True defaultAppearance)]

  it "Host roi tao PlayerLeft roi HostChanged dung thu tu" $ do
    room <- newRoomRuntime "ROOM-01"
    updates <- atomically (dupTChan (roomUpdates room))

    _ <- submit room "p1" (Join "p1" "Van")
    _ <- atomically (readTChan updates)

    _ <- submit room "p2" (Join "p2" "Binh")
    _ <- atomically (readTChan updates)

    _ <- submit room "p1" (Leave "p1")
    update <- atomically (readTChan updates)

    lobbyMessages "ROOM-01" update
      `shouldBe`
        [ MsgPlayerLeft "ROOM-01" "p1"
        , MsgHostChanged "ROOM-01" "p2"
        ]

  it "Event chia vai khong di qua Broadcast Lobby" $ do
    let update =
          RoomUpdate 1 emptyLobby [PlayerRoleAssigned "p1" Werewolf] Nothing

    lobbyMessages "ROOM-01" update `shouldBe` []

  it "Ready cung gia tri van tra snapshot de UI het cho" $ do
    room <- newRoomRuntime "ROOM-01"
    updates <- atomically (dupTChan (roomUpdates room))

    _ <- submit room "p1" (Join "p1" "Van")
    _ <- atomically (readTChan updates)

    _ <- submit room "p1" (SetReady "p1" True)
    _ <- atomically (readTChan updates)

    result <- submit room "p1" (SetReady "p1" True)
    update <- atomically (readTChan updates)

    updateEvents update `shouldBe` []
    lobbyReply "ROOM-01" "req-3" "p1" (SetReady "p1" True) result
      `shouldBe`
        MsgLobbySnapshot "ROOM-01" "p1" "p1"
          [PlayerView "p1" "Van" True True defaultAppearance]

  it "Lenh loi tra CommandRejected dung requestId" $ do
    room <- newRoomRuntime "ROOM-01"

    _ <- submit room "p1" (Join "p1" "Van")
    result <- submit room "p1" (Join "p1" "Binh")

    case lobbyReply "ROOM-01" "req-2" "p1" (Join "p1" "Binh") result of
      MsgRejected requestId code _ -> do
        requestId `shouldBe` Just "req-2"
        code `shouldBe` "DUPLICATE_PLAYER_ID"
      other ->
        expectationFailure ("Mong doi CommandRejected, nhan: " ++ show other)

  it "Leave thanh cong tra PlayerLeft cho nguoi roi" $ do
    room <- newRoomRuntime "ROOM-01"

    _ <- submit room "p1" (Join "p1" "Van")
    result <- submit room "p1" (Leave "p1")

    lobbyReply "ROOM-01" "req-2" "p1" (Leave "p1") result
      `shouldBe` MsgPlayerLeft "ROOM-01" "p1"

  it "CreateRoom thanh cong: Host Join truoc khi cong bo phong" $ do
    registry <- newRoomRegistry

    result <-
      createRoomWithHost registry "ROOM-02" "req-1" "p1" "An"
        (\_ -> pure ())

    case result of
      Left _ ->
        expectationFailure "CreateRoom phai thanh cong"

      Right (room, state) -> do
        gameHost state `shouldBe` "p1"
        map playerName (gamePlayers state) `shouldBe` ["An"]

        version <- readTVarIO (roomVersion room)
        version `shouldBe` 1

        found <- findRoom registry "ROOM-02"
        fmap roomId found `shouldBe` Just "ROOM-02"

  it "CreateRoom tu choi ma phong trung" $ do
    registry <- newRoomRegistry

    first <-
      createRoomWithHost registry "ROOM-02" "req-1" "p1" "An"
        (\_ -> pure ())

    case first of
      Left _ ->
        expectationFailure "Lan tao dau phai thanh cong"

      Right (room, _) -> do
        second <-
          createRoomWithHost registry "ROOM-02" "req-2" "p2" "Binh"
            (\_ -> pure ())

        case second of
          Left RoomAlreadyExists -> pure ()
          _ -> expectationFailure "Phai tu choi ma phong trung"

        state <- readTVarIO (roomState room)
        gameHost state `shouldBe` "p1"
        length (gamePlayers state) `shouldBe` 1

  it "Host Join loi thi khong cong bo phong" $ do
    registry <- newRoomRegistry

    result <-
      createRoomWithHost registry "ROOM-02" "req-1" "p1" "   "
        (\_ -> pure ())

    case result of
      Left (HostJoinRejected InvalidPlayerName) -> pure ()
      _ -> expectationFailure "Phai tu choi ten Host khong hop le"

    found <- findRoom registry "ROOM-02"
    fmap roomId found `shouldBe` Nothing

  it "CreateRoom tu choi ma phong co khoang trang" $ do
    registry <- newRoomRegistry

    result <-
      createRoomWithHost registry "ROOM 02" "req-1" "p1" "An"
        (\_ -> pure ())

    case result of
      Left InvalidRoomId -> pure ()
      _ -> expectationFailure "Phai tu choi ma phong khong hop le"

    found <- findRoom registry "ROOM 02"
    fmap roomId found `shouldBe` Nothing

-- =============================================================================
-- E02: Role Privacy & Dashboard State Routing
-- =============================================================================
e02RolePrivacySpec :: Spec
e02RolePrivacySpec = describe "T08 E02 - Role Privacy & Dashboard State Routing" $ do

  it "StartGame chi gui MsgYourRole cho dung chu nhan va MsgWolfTeam cho Soi" $ do
    (_, startUpdate) <- setupStartedNinePlayerRoom
    let state = updateState startUpdate
        events = updateEvents startUpdate
    validateGameInvariant state `shouldBe` Right ()

    forM_ (gamePlayers state) $ \recipient -> do
      let rid = playerId recipient
          expectedRole = playerRole recipient
          msgs = nightMessagesForState "ROOM-9P" rid state events
          roleMsgs = [r | MsgYourRole _ r <- msgs]

      case expectedRole of
        Nothing -> expectationFailure ("Nguoi choi phai duoc chia vai: " ++ rid)
        Just role -> roleMsgs `shouldBe` [role]

      let wolfMsg = wolfTeamMessage "ROOM-9P" rid state
      case expectedRole of
        Just Werewolf -> do
          let allWolves = map playerId (findPlayersByRole Werewolf state)
          wolfMsg `shouldBe` Just (MsgWolfTeam "ROOM-9P" allWolves)
        _ ->
          wolfMsg `shouldBe` Nothing

  it "Snapshot cong khai (Lobby/Voting) va dashboard helper khong ro ri Role cua nguoi khac" $ do
    (_, startUpdate) <- setupStartedNinePlayerRoom
    let state = updateState startUpdate

    case votingSnapshot "ROOM-9P" "p1" state of
      MsgVotingSnapshot _ _ _ publicPlayers _ _ _ _ -> do
        length publicPlayers `shouldBe` 9
        let pubIds = [pid | VotingPlayerView pid _ _ <- publicPlayers]
        pubIds `shouldBe` ninePlayerIds
      other ->
        expectationFailure ("Mong doi MsgVotingSnapshot, nhan: " ++ show other)

    -- Khi đang ở Night, privateActionStateMessage và discussionSkipStateMessage đồng bộ đúng state riêng
    forM_ (gamePlayers state) $ \p -> do
      let pid = playerId p
          expectedPrivate =
            case playerRole p of
              Just Witch -> MsgPrivateActionState "ROOM-9P" False (Just True) (Just True) Nothing
              _ -> MsgPrivateActionState "ROOM-9P" False Nothing Nothing Nothing
      privateActionStateMessage "ROOM-9P" pid state `shouldBe` expectedPrivate
      discussionSkipStateMessage "ROOM-9P" pid state
        `shouldBe` MsgDiscussionSkipState "ROOM-9P" 0 9 False

-- =============================================================================
-- E07: Concurrent Commands via STM (9 Clients)
-- =============================================================================
e07ConcurrentStmSpec :: Spec
e07ConcurrentStmSpec = describe "T08 E07 - Concurrent Commands via STM (9 Clients)" $ do

  it "9 client dong thoi gui Join, SetReady va ChatInChannel qua STM ma khong mat update hay trung version" $ do
    room <- newRoomRuntime "ROOM-CONCURRENT"
    -- Host p1 vào phòng trước khi khởi chạy worker (đúng quy trình createRoomWithHost)
    hostJoin <- submitWithReq room "join-p1" "p1" (Join "p1" "Name-p1")
    fmap gameHost hostJoin `shouldBe` Right "p1"

    startGate <- newEmptyMVar
    let guestIds = ["p" ++ show idx | idx <- [2 .. 9 :: Int]]

    bracket
      (forkIO (runGameLoopWithPhaseTimeouts 60000000 60000000 60000000 room))
      killThread
      $ \_ -> do
        -- 8 luồng khách cùng chờ hiệu lệnh rồi gửi Join đồng thời
        joinWaiters <- forM guestIds $ \pid -> do
          done <- newEmptyMVar
          _ <- forkIO $ do
            readMVar startGate
            res <- enqueueAndAwait room ("join-" ++ pid) pid (Join pid ("Name-" ++ pid))
            putMVar done res
          pure done

        putMVar startGate ()
        joinResults <- mapM takeMVar joinWaiters
        length [st | Right st <- joinResults] `shouldBe` 8

        stateAfterJoin <- readTVarIO (roomState room)
        versionAfterJoin <- readTVarIO (roomVersion room)
        length (gamePlayers stateAfterJoin) `shouldBe` 9
        versionAfterJoin `shouldBe` 9
        validateGameInvariant stateAfterJoin `shouldBe` Right ()

        -- 9 luồng đồng thời gửi SetReady True
        readyGate <- newEmptyMVar
        readyWaiters <- forM ninePlayerIds $ \pid -> do
          done <- newEmptyMVar
          _ <- forkIO $ do
            readMVar readyGate
            res <- enqueueAndAwait room ("ready-" ++ pid) pid (SetReady pid True)
            putMVar done res
          pure done

        putMVar readyGate ()
        readyResults <- mapM takeMVar readyWaiters
        length [st | Right st <- readyResults] `shouldBe` 9

        -- Host StartGame rồi chuyển qua Day để 9 người đồng thời gửi ChatInChannel PublicDay
        currentHost <- fmap gameHost (readTVarIO (roomState room))
        startRes <- enqueueAndAwait room "start-conc" currentHost (StartGame currentHost nineRolePreset)
        case startRes of
          Left err -> expectationFailure ("StartGame phai thanh cong: " ++ show err)
          Right _ -> pure ()

        stateInDay <- transitionNightToDay room
        gamePhase stateInDay `shouldBe` Day

        verBeforeChat <- readTVarIO (roomVersion room)
        chatGate <- newEmptyMVar
        chatWaiters <- forM ninePlayerIds $ \pid -> do
          done <- newEmptyMVar
          _ <- forkIO $ do
            readMVar chatGate
            res <-
              enqueueAndAwait
                room
                ("chat-" ++ pid)
                pid
                (ChatInChannel pid PublicDay ("Hello from " ++ pid))
            putMVar done res
          pure done

        putMVar chatGate ()
        chatResults <- mapM takeMVar chatWaiters
        length [st | Right st <- chatResults] `shouldBe` 9

        versionAfterChat <- readTVarIO (roomVersion room)
        nextChatSeq <- readTVarIO (roomNextChatSequence room)
        chatHist <- readTVarIO (roomChatHistory room)
        stateAfterChat <- readTVarIO (roomState room)

        versionAfterChat `shouldBe` (verBeforeChat + 9)
        nextChatSeq `shouldBe` 10
        length chatHist `shouldBe` 9
        map chatSequence chatHist `shouldBe` [1 .. 9]
        validateGameInvariant stateAfterChat `shouldBe` Right ()

-- =============================================================================
-- E11: Idempotency (Duplicate requestId)
-- =============================================================================
e11IdempotencySpec :: Spec
e11IdempotencySpec = describe "T08 E11 - Idempotency (Duplicate requestId)" $ do

  it "Gui 2 lan cung (actorId, requestId) cho NightAction, ChatInChannel va Vote chi ap dung 1 lan" $ do
    (room, startUpdate) <- setupStartedNinePlayerRoom
    updates <- atomically (dupTChan (roomUpdates room))
    let nightState = updateState startUpdate
        wolves = findPlayersByRole Werewolf nightState
        villagers = findPlayersByRole Villager nightState

    case (wolves, villagers) of
      (wolf : _, villager : _) -> do
        let wid = playerId wolf
            vid = playerId villager

        -- 1. Idempotency cho NightAction (WolfTarget)
        firstNight <-
          submitWithReq room "dup-night-1" wid (NightAction wid (WolfTarget vid))
        case firstNight of
          Right _ -> pure ()
          Left err -> expectationFailure ("NightAction lan 1 phai thanh cong: " ++ show err)
        _ <- atomically (readTChan updates)
        verAfterNight1 <- readTVarIO (roomVersion room)

        secondNight <-
          submitWithReq room "dup-night-1" wid (NightAction wid (WolfTarget vid))
        secondNight `shouldBe` Left DuplicateRequest
        verAfterNight2 <- readTVarIO (roomVersion room)
        noNightUpdate <- atomically (isEmptyTChan updates)
        verAfterNight2 `shouldBe` verAfterNight1
        noNightUpdate `shouldBe` True

        -- 2. Idempotency cho ChatInChannel (WolvesNight)
        firstChat <-
          submitWithReq room "dup-chat-1" wid (ChatInChannel wid WolvesNight "Tan cong!")
        case firstChat of
          Right _ -> pure ()
          Left err -> expectationFailure ("Chat lan 1 phai thanh cong: " ++ show err)
        _ <- atomically (readTChan updates)
        verAfterChat1 <- readTVarIO (roomVersion room)
        histAfterChat1 <- readTVarIO (roomChatHistory room)

        secondChat <-
          submitWithReq room "dup-chat-1" wid (ChatInChannel wid WolvesNight "Tan cong!")
        secondChat `shouldBe` Left DuplicateRequest
        verAfterChat2 <- readTVarIO (roomVersion room)
        histAfterChat2 <- readTVarIO (roomChatHistory room)
        verAfterChat2 `shouldBe` verAfterChat1
        length histAfterChat2 `shouldBe` length histAfterChat1

        -- 3. Chuyển sang Day -> Voting và kiểm tra Idempotency cho Vote
        _ <- transitionNightToDay room
        _ <- atomically (applyInternalCommand room AdvancePhase)
        votingUpdate <- atomically (readTChan updates)
        let votingState = updateState votingUpdate
        gamePhase votingState `shouldBe` Voting

        let livingTargets =
              [ playerId p
              | p <- gamePlayers votingState
              , playerLifeStatus p == Alive
              , playerId p /= wid
              ]
        case livingTargets of
          voteTarget : _ -> do
            firstVote <-
              submitWithReq room "dup-vote-1" wid (Vote wid voteTarget)
            case firstVote of
              Right _ -> pure ()
              Left err -> expectationFailure ("Vote lan 1 phai thanh cong: " ++ show err)
            _ <- atomically (readTChan updates)
            verAfterVote1 <- readTVarIO (roomVersion room)

            secondVote <-
              submitWithReq room "dup-vote-1" wid (Vote wid voteTarget)
            secondVote `shouldBe` Left DuplicateRequest
            verAfterVote2 <- readTVarIO (roomVersion room)
            noVoteUpdate <- atomically (isEmptyTChan updates)
            verAfterVote2 `shouldBe` verAfterVote1
            noVoteUpdate `shouldBe` True
          [] ->
            expectationFailure "Phai con muc tieu song de bo phieu"

      _ ->
        expectationFailure "Phai tim thay it nhat 1 Soi va 1 Dan lang trong phong 9 nguoi"

-- =============================================================================
-- E13: Timer vs Action Race
-- =============================================================================
e13TimerRaceSpec :: Spec
e13TimerRaceSpec = describe "T08 E13 - Timer vs Action Race" $ do

  it "Dua giua Phase Timer va lenh nguoi choi tai ranh gioi het gio khong crash va giu bat bien" $ do
    (room, _) <- setupStartedNinePlayerRoom
    -- Chuyển phòng sang Day trước khi bật vòng lặp có timeout cực ngắn (30ms)
    stateBeforeRace <- transitionNightToDay room
    gamePhase stateBeforeRace `shouldBe` Day

    bracket
      (forkIO (runGameLoopWithPhaseTimeouts 30000 30000 30000 room))
      killThread
      $ \_ -> do
        -- Cho các người chơi gửi SkipDiscussion đồng thời sát mốc hết giờ 30ms
        stateNow <- readTVarIO (roomState room)
        let aliveIds = [playerId p | p <- gamePlayers stateNow, playerLifeStatus p == Alive]
        forM_ aliveIds $ \pid ->
          forkIO $ do
            threadDelay 25000
            _ <- trySubmitCommand room ("skip-" ++ pid) pid (SkipDiscussion pid)
            pure ()

        -- Đợi qua cả cửa sổ Day và Voting (80ms) để kiểm tra timer không bao giờ crash khi Left
        threadDelay 90000

        finalState <- readTVarIO (roomState room)
        validateGameInvariant finalState `shouldBe` Right ()
        -- Phase đã chuyển qua Day/Voting sang Night vòng tiếp theo một cách an toàn
        gamePhase finalState `shouldSatisfy` (/= Lobby)

-- =============================================================================
-- E14: Backpressure & Bounded Queue
-- =============================================================================
e14BackpressureSpec :: Spec
e14BackpressureSpec = describe "T08 E14 - Backpressure & Bounded Queue" $ do

  it "Bounded roomCommands (TBQueue) tu choi ngay khi day ma khong treo producer" $ do
    room <- newRoomRuntimeWithCapacity 3 "ROOM-BOUNDED"

    let mkCmd :: Int -> IO Bool
        mkCmd idx = do
          reply <- newEmptyTMVarIO
          let pid = "p" ++ show idx
          atomically $
            tryEnqueueRoomCommand
              room
              QueuedCommand
                { queuedRequestId = "req-" ++ show idx
                , queuedActorId = pid
                , queuedCommand = Join pid ("P" ++ show idx)
                , queuedReply = reply
                }

    ok1 <- mkCmd 1
    ok2 <- mkCmd 2
    ok3 <- mkCmd 3
    ok4 <- mkCmd 4

    (ok1, ok2, ok3, ok4) `shouldBe` (True, True, True, False)

    -- trySubmitCommand khi queue đầy cũng trả về Nothing ngay lập tức mà không block
    res5 <- trySubmitCommand room "req-5" "p5" (Join "p5" "P5")
    res5 `shouldBe` Nothing

  it "OutboundQueue gioi han suc chua va writeBoundedDropOldest khong lam treo server" $ do
    queue <- newOutboundQueueWithCapacity 3
    let msg p = MsgPlayerDied "ROOM-BP" p

    ok1 <- atomically (sendBounded queue (msg "p1"))
    ok2 <- atomically (sendBounded queue (msg "p2"))
    ok3 <- atomically (sendBounded queue (msg "p3"))
    ok4 <- atomically (sendBounded queue (msg "p4"))

    (ok1, ok2, ok3, ok4) `shouldBe` (True, True, True, False)

    -- Dùng writeBoundedDropOldest để đẩy thêm 2 message mới mà không block
    _ <- atomically (writeBoundedDropOldest queue (msg "p4"))
    _ <- atomically (writeBoundedDropOldest queue (msg "p5"))

    m1 <- atomically (tryReadOutbound queue)
    m2 <- atomically (tryReadOutbound queue)
    m3 <- atomically (tryReadOutbound queue)
    m4 <- atomically (tryReadOutbound queue)

    (m1, m2, m3, m4) `shouldBe` (Just (msg "p3"), Just (msg "p4"), Just (msg "p5"), Nothing)

-- =============================================================================
-- E17: Supervision & Worker Failure Cleanup
-- =============================================================================
e17SupervisionSpec :: Spec
e17SupervisionSpec = describe "T08 E17 - Supervision & Worker Failure Cleanup" $ do

  it "Khi mot worker trong nhom Supervisor nem ngoai le, cac luong anh em bi huy (0 luong mo coi) va phong khac khong bi anh huong" $ do
    otherSup <- newSupervisor
    otherAlive <- newEmptyMVar
    _ <-
      forkSupervised otherSup "other-room-worker" $ do
        putMVar otherAlive ()
        threadDelay 10000000

    takeMVar otherAlive

    siblingCleanedUp <- newEmptyMVar
    result <-
      (try :: IO () -> IO (Either SomeException ())) $
        withSupervisedGroup $ \sup -> do
          _ <-
            forkSupervised sup "sibling-writer" $
              bracket
                (pure ())
                (\_ -> putMVar siblingCleanedUp True)
                (\_ -> threadDelay 10000000)

          _ <-
            forkSupervised sup "crashing-reader" $ do
              threadDelay 20000
              ioError (userError "simulated worker crash")

          -- Chờ sibling-writer bị hủy bởi crashing-reader
          cleaned <- takeMVar siblingCleanedUp
          cleaned `shouldBe` True

          -- Đợi ngắn để finalizer cập nhật supervisorThreads về 0
          threadDelay 20000
          active <- activeWorkerCount sup
          active `shouldBe` 0

          events <- supervisorEvents sup
          let hasCrashEvent =
                any
                  (\ev -> case ev of
                    WorkerFailed name _ -> name == "crashing-reader"
                    _ -> False
                  )
                  events
          hasCrashEvent `shouldBe` True

    case result of
      Right () -> pure ()
      Left err -> expectationFailure ("withSupervisedGroup khong duoc lam crash caller: " ++ show err)

    -- Phòng khác vẫn đang chạy bình thường
    otherCount <- activeWorkerCount otherSup
    otherCount `shouldBe` 1
    shutdownSupervisor otherSup
    otherCountAfter <- activeWorkerCount otherSup
    otherCountAfter `shouldBe` 0

-- =============================================================================
-- Chat & Privacy Filter (Dead Werewolves, Role Reveal only at GameOver)
-- =============================================================================
chatAndPrivacyFilterSpec :: Spec
chatAndPrivacyFilterSpec = describe "T08 - Chat & Privacy Filter" $ do

  it "Dan lang va Soi DA CHET khong nhan duoc chat WolvesNight hay WolfVoteUpdated" $ do
    (room, startUpdate) <- setupStartedNinePlayerRoom
    let initialState = updateState startUpdate
        wolves = findPlayersByRole Werewolf initialState
        villagers = findPlayersByRole Villager initialState

    case (wolves, villagers) of
      (livingWolf : deadWolf : _, villager : _) -> do
        let livingWolfId = playerId livingWolf
            deadWolfId = playerId deadWolf
            villagerId = playerId villager
            -- Giả lập deadWolf đã chết trong state ở pha Night
            updatedPlayers =
              [ if playerId p == deadWolfId
                  then p { playerLifeStatus = Dead }
                  else p
              | p <- gamePlayers initialState
              ]
            stateWithDeadWolf = initialState { gamePlayers = updatedPlayers }

        atomically (writeTVar (roomState room) stateWithDeadWolf)

        let secretRecord =
              ChatRecord
                { chatRoomId = "ROOM-9P"
                , chatDay = 1
                , chatChannel = WolvesNight
                , chatMessageId = "ROOM-9P-chat-1"
                , chatSequence = 1
                , chatSenderId = livingWolfId
                , chatText = "Can p7 nhe"
                }

        -- Kiểm tra chatMessageForState và chatHistorySnapshot
        chatMessageForState "ROOM-9P" livingWolfId stateWithDeadWolf secretRecord
          `shouldBe` Just (MsgStoredChatMessage "ROOM-9P" secretRecord)
        chatMessageForState "ROOM-9P" deadWolfId stateWithDeadWolf secretRecord
          `shouldBe` Nothing
        chatMessageForState "ROOM-9P" villagerId stateWithDeadWolf secretRecord
          `shouldBe` Nothing

        chatHistorySnapshot "ROOM-9P" livingWolfId stateWithDeadWolf [secretRecord]
          `shouldBe` MsgChatHistorySnapshot "ROOM-9P" [secretRecord]
        chatHistorySnapshot "ROOM-9P" deadWolfId stateWithDeadWolf [secretRecord]
          `shouldBe` MsgChatHistorySnapshot "ROOM-9P" []
        chatHistorySnapshot "ROOM-9P" villagerId stateWithDeadWolf [secretRecord]
          `shouldBe` MsgChatHistorySnapshot "ROOM-9P" []

        -- Kiểm tra WolfVoteUpdated và ChatMessageInChannel WolvesNight chỉ tới Sói còn sống
        let wolfEvents =
              [ WolfVoteUpdated 1 2
              , WolfTargetLocked (Just villagerId)
              , ChatMessageInChannel WolvesNight livingWolfId "Can p7 nhe"
              ]
        nightMessagesForState "ROOM-9P" livingWolfId stateWithDeadWolf wolfEvents
          `shouldBe`
            [ MsgWolfVoteUpdated "ROOM-9P" 1 2
            , MsgWolfTargetLocked "ROOM-9P" (Just villagerId)
            , MsgChannelChatMessage "ROOM-9P" 1 WolvesNight livingWolfId "Can p7 nhe"
            ]
        nightMessagesForState "ROOM-9P" deadWolfId stateWithDeadWolf wolfEvents
          `shouldBe` []
        nightMessagesForState "ROOM-9P" villagerId stateWithDeadWolf wolfEvents
          `shouldBe` []

      _ ->
        expectationFailure "Phong 9 nguoi phai co it nhat 2 Soi va 1 Dan lang"

  it "Nguoi chet truoc GameOver chi phat MsgPlayerDied (khong lo Role), va chi tiet lo toan bo Role khi GameOver" $ do
    (_, startUpdate) <- setupStartedNinePlayerRoom
    let state = updateState startUpdate
        dayState = state { gamePhase = Day }
        eventsBeforeEnd =
          [ PlayerDied "p1"
          , PlayerRoleRevealed "p1" Werewolf Wolves
          , PhaseChanged Day
          ]

    let msgsBeforeEnd = nightMessagesForState "ROOM-9P" "p2" dayState eventsBeforeEnd
    msgsBeforeEnd
      `shouldBe`
        [ MsgPlayerDied "ROOM-9P" "p1"
        , MsgPhaseChanged "ROOM-9P" Day
        ]

    let rolePairs =
          [ (playerId p, r)
          | p <- gamePlayers state
          , Just r <- [playerRole p]
          ]
        gameOverState =
          state
            { gamePhase = GameOver
            , gameResult = Just (Winner Village)
            }
        eventsAtGameOver =
          [ GameRolesRevealed rolePairs
          , GameFinished (Winner Village)
          ]

    let msgsAtGameOver = nightMessagesForState "ROOM-9P" "p2" gameOverState eventsAtGameOver
    msgsAtGameOver
      `shouldBe`
        [ MsgGameRolesRevealed "ROOM-9P" rolePairs
        , MsgGameFinished "ROOM-9P" (Winner Village)
        ]
