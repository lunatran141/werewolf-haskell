
-- | Mot duong xu ly Command chung tu queue toi Pure Engine.
module Server.GameLoop
  ( processNextLobbyCommand
  , runLobbyLoop
  , runGameLoopWithTimeouts
  , applyInternalCommand
  , CreateRoomError(..)
  , createRoomWithHost
  , createRoomWithHostAppearance
  ) where

import Control.Concurrent.MVar (modifyMVar)

import Control.Concurrent.STM
  ( STM, atomically, check, orElse, registerDelay
  , newEmptyTMVarIO
  , putTMVar
  , readTBQueue
  , readTVar
  , readTVarIO
  , takeTMVar
  , writeTBQueue
  , writeTChan
  , writeTVar
  )

import Data.Char (isSpace)

import Domain.Engine
  ( applyCommand
  , applyLobbyCommand
  , applyNightCommand
  , applyPhaseCommand
  , closeWolfVoting
  , completeNightTurn
  , resolveNightTurn
  )

import Domain.Night (wolfVotingComplete)

import Domain.Types
  ( Command(..)
  , DomainEvent
  , GameError(..)
  , GameState(..)
  , LifeStatus(..)
  , NightChoice(..)
  , Phase(..)
  , Player(..)
  , PlayerId
  , Role(..)
  , Appearance
  )

import Protocol.Types (RequestId, RoomId)

import Server.Room
  ( QueuedCommand(..)
  , RoomRegistry(..)
  , RoomRuntime(..)
  , RoomUpdate(..)
  , newRoomRuntime
  )

-- Xac thuc PlayerId cua command voi phien ket noi.
-- Lenh noi bo khong duoc gui truc tiep tu Browser.
actorMatches :: QueuedCommand -> Bool
actorMatches request =
  case queuedCommand request of
    Join pid _ ->
      pid == queuedActorId request
    -- Kiem tra PlayerId cua lenh Join co Appearance.
    JoinWithAppearance pid _ _ ->
      pid == queuedActorId request
    Leave pid ->
      pid == queuedActorId request

    SetReady pid _ ->
      pid == queuedActorId request

    StartGame pid _ ->
      pid == queuedActorId request

    NightAction pid _ ->
      pid == queuedActorId request

    -- T06: Vote cung phai dung PlayerId cua session, khong tin ID tu client.
    Vote pid _ ->
      pid == queuedActorId request

    -- Chỉ Handler đã xác thực mới tạo lệnh Hunter; Domain kiểm quyền pending.
    ResolveHunter pid _ -> pid == queuedActorId request

    -- Chat thuộc người chơi; ResolveVoting vẫn chỉ do bộ đếm giờ nội bộ gọi.
    -- HunterAction được Handler đổi thành ResolveHunter với ID của session.
    Chat pid _ ->
      pid == queuedActorId request

    -- Khong cho phep client tu goi lenh noi bo.
    _ ->
      False

-- Kiem tra mot nguoi choi da gui NightAction dung vai.
hasSubmittedNightAction :: GameState -> Player -> Bool
hasSubmittedNightAction state player =
  any actionMatches (gameNightActions state)
  where
    actorId = playerId player

    actionMatches (pid, choice)
      | pid /= actorId =
          False

      | otherwise =
          case (playerRole player, choice) of
            (Just Werewolf, WolfTarget _) ->
              True

            (Just Seer, SeerTarget _) ->
              True

            (Just Guard, GuardTarget _) ->
              True

            (Just Witch, WitchHeal) ->
              True

            (Just Witch, WitchPoison _) ->
              True

            (Just Witch, WitchPass) ->
              True

            _ ->
              False

-- Chi cac vai co hanh dong Night moi phai cho.
-- Villager va Hunter con song khong can gui NightAction.
needsNightAction :: Player -> Bool
needsNightAction player =
  playerLifeStatus player == Alive
    && playerRole player `elem`
      [ Just Werewolf
      , Just Seer
      , Just Guard
      , Just Witch
      ]

-- Kiem tra toan bo cac vai can hanh dong da hoan thanh.
-- Witch phai duoc quyen chon sau khi khoa phieu Soi.
allNightActionsSubmitted :: GameState -> Bool
allNightActionsSubmitted state =
  all (hasSubmittedNightAction state) activePlayers
  where
    activePlayers =
      filter needsNightAction (gamePlayers state)

-- Sau khi Soi cuoi cung bo phieu, tu dong khoa phieu.
-- Khong ResolveNight tai day vi Witch co the chua chon.
closeCompletedWolfVote
  :: GameState
  -> [DomainEvent]
  -> Either GameError (GameState, [DomainEvent])
closeCompletedWolfVote state actionEvents
  | gameWolfVotingClosed state =
      Right (state, actionEvents)

  | not (wolfVotingComplete state) =
      Right (state, actionEvents)

  | otherwise = do
      (closedState, closeEvents) <-
        closeWolfVoting state False

      pure
        ( closedState
        , actionEvents ++ closeEvents
        )

-- ResolveNight khi da du cac hanh dong.
-- Neu Hunter bi loai, dung lai cho T06 xu ly HunterShot.
-- Neu khong co Hunter pending, cong bo vai va chuyen Day.
finishCompletedNight
  :: GameState
  -> [DomainEvent]
  -> Either GameError (GameState, [DomainEvent])
finishCompletedNight state priorEvents
  | gamePhase state /= Night =
      Right (state, priorEvents)

  | gameNightResolved state =
      Right (state, priorEvents)

  | not (gameWolfVotingClosed state) =
      Right (state, priorEvents)

  | not (allNightActionsSubmitted state) =
      Right (state, priorEvents)

  | otherwise = do
      (resolvedState, resolveEvents) <-
        resolveNightTurn state

      let eventsAfterResolve =
            priorEvents ++ resolveEvents

      case gamePendingHunter resolvedState of
        Just _ ->
          -- Hunter phai duoc xu ly truoc khi cong bo ket qua.
          pure (resolvedState, eventsAfterResolve)

        Nothing -> do
          (completedState, completeEvents) <-
            completeNightTurn resolvedState

          pure
            ( completedState
            , eventsAfterResolve ++ completeEvents
            )

-- Chon Pure Engine theo loai command.
-- Cac buoc Night duoc ket hop thanh mot ket qua thuan tuy.
dispatchPlayerCommand
  :: GameState
  -> Command
  -> Either GameError (GameState, [DomainEvent])
dispatchPlayerCommand state command =
  case command of

    -- T04: Bat dau van.
    StartGame _ _ ->
      applyPhaseCommand state command

    -- T05: Soi bo phieu, sau do kiem tra dong phieu.
    NightAction _ (WolfTarget _) -> do
      (nextState, actionEvents) <-
        applyNightCommand state command

      (closedState, closedEvents) <-
        closeCompletedWolfVote nextState actionEvents

      finishCompletedNight closedState closedEvents

    -- T05: Seer, Guard, Witch.
    -- Sau moi hanh dong, kiem tra co the ket thuc Night chua.
    NightAction _ _ -> do
      (nextState, actionEvents) <-
        applyNightCommand state command

      finishCompletedNight nextState actionEvents

    -- Lobby.
    Join _ _ ->
      applyLobbyCommand state command
    -- Xu ly Join voi ngoai hinh da duoc validate.
    JoinWithAppearance _ _ _ ->
      applyLobbyCommand state command
    Leave _ ->
      applyLobbyCommand state command

    SetReady _ _ ->
      applyLobbyCommand state command

    -- T06: Dùng cùng queue và validation; không mở ResolveVoting cho client.
    Vote _ _ -> applyCommand state command
    ResolveHunter _ _ -> applyCommand state command
    Chat _ _ -> applyCommand state command

    -- Browser khong duoc goi command noi bo.
    _ ->
      Left NotAuthorized

-- Xu ly mot command tu queue.
-- State, version va events duoc commit trong cung STM.
processNextLobbyCommand :: RoomRuntime -> IO ()
processNextLobbyCommand room = atomically (processPlayerCommand room)

-- T06: Dùng chung giao dịch cho worker và kiểm thử một lệnh.
processPlayerCommand :: RoomRuntime -> STM ()
processPlayerCommand room = do
  request <- readTBQueue (roomCommands room)
  currentState <- readTVar (roomState room)
  accepted <- readTVar (roomAcceptedRequests room)

  let key = (queuedActorId request, queuedRequestId request)
      tracked = case queuedCommand request of
        Vote _ _ -> True
        ResolveHunter _ _ -> True
        _ -> False
      result =
        if tracked && key `elem` accepted then Left DuplicateRequest
        else if actorMatches request
          then dispatchPlayerCommand currentState (queuedCommand request)
          else Left NotAuthorized

  case result of
    Left err -> do
      -- Command loi khong doi state hay version.
      putTMVar (queuedReply request) (Left err)

    Right (nextState, events) -> do
      if tracked then writeTVar (roomAcceptedRequests room) (key : accepted) else pure ()
      currentVersion <- readTVar (roomVersion room)

      let nextVersion = currentVersion + 1

      writeTVar (roomState room) nextState
      writeTVar (roomVersion room) nextVersion

      -- Gui DomainEvent de Broadcast loc theo tung client.
      writeTChan (roomUpdates room)
        RoomUpdate
          { updateVersion = nextVersion
          , updateState = nextState
          , updateEvents = events
          }

      putTMVar (queuedReply request) (Right nextState)

-- Worker xu ly Command Queue.
-- Dung khi nguoi cuoi cung roi phong.
runLobbyLoop :: RoomRuntime -> IO ()
runLobbyLoop = runGameLoopWithTimeouts 60000000 30000000

-- T06: Điểm nối cho bộ điều phối T04/T05. Không được gọi từ JSON client.
-- Cập nhật phase và phát sự kiện trong cùng STM với queue người chơi.
applyInternalCommand :: RoomRuntime -> Command -> STM (Either GameError GameState)
applyInternalCommand room command = do
  state <- readTVar (roomState room)
  case applyCommand state command of
    Left err -> pure (Left err)
    Right (nextState, events) -> do
      version <- readTVar (roomVersion room)
      writeTVar (roomState room) nextState
      writeTVar (roomVersion room) (version + 1)
      writeTChan (roomUpdates room) (RoomUpdate (version + 1) nextState events)
      pure (Right nextState)

-- Khóa cửa sổ bằng phase/vòng/Hunter: phiếu mới không gia hạn timer.
votingWindow :: GameState -> Maybe (Phase, Int, Maybe PlayerId)
votingWindow state
  | gamePhase state `elem` [Night, Voting], Just hunter <- gamePendingHunter state =
      Just (gamePhase state, gameDay state, Just hunter)
  | gamePhase state == Voting && not (gameVotingResolved state) =
      Just (Voting, gameDay state, Nothing)
  | otherwise = Nothing

-- Thời gian tính bằng microsecond, truyền vào để test nhanh mà không đổi luật.
-- Timer và Vote tranh chấp trên cùng TVar: sau khi chốt, phiếu đến muộn bị từ chối.
runGameLoopWithTimeouts :: Int -> Int -> RoomRuntime -> IO ()
runGameLoopWithTimeouts voteMicros hunterMicros room = startWindow
  where
    startWindow = do
      state <- readTVarIO (roomState room)
      let window = votingWindow state
          duration = case window of
            Just (_, _, Just _) -> hunterMicros
            _ -> voteMicros
      timer <- registerDelay (max 1 duration)
      let loop = do
            restart <- atomically $
              (do current <- readTVar (roomState room)
                  check (votingWindow current /= window || null (gamePlayers current))
                  pure True)
              `orElse`
              (do check (window /= Nothing)
                  expired <- readTVar timer
                  check expired
                  let command = case window of
                        Just (_, _, Just hunter) -> ResolveHunter hunter Nothing
                        _ -> ResolveVoting
                  result <- applyInternalCommand room command
                  case result of
                    Left err -> error ("T06: trạng thái timer không hợp lệ: " ++ show err)
                    Right _ -> pure True)
              `orElse`
              (processPlayerCommand room >> pure False)
            if restart then do
              current <- readTVarIO (roomState room)
              if null (gamePlayers current) then pure () else startWindow
            else loop
      loop


-- Loi khi tao phong.
data CreateRoomError
  = InvalidRoomId
  | RoomAlreadyExists
  | HostJoinRejected GameError
  deriving (Eq, Show)

-- Tao phong va Host theo contract cu.
-- Giu lai de khong anh huong T03/T06.
createRoomWithHost
  :: RoomRegistry
  -> RoomId
  -> RequestId
  -> PlayerId
  -> String
  -> (RoomRuntime -> IO ())
  -> IO (Either CreateRoomError (RoomRuntime, GameState))
createRoomWithHost registry rid requestId actor name startWorker =
  createRoomWithHostCommand
    registry rid requestId actor
    (Join actor name)
    startWorker

-- Tao phong va Host voi Appearance do nguoi choi chon.
createRoomWithHostAppearance
  :: RoomRegistry
  -> RoomId
  -> RequestId
  -> PlayerId
  -> String
  -> Appearance
  -> (RoomRuntime -> IO ())
  -> IO (Either CreateRoomError (RoomRuntime, GameState))
createRoomWithHostAppearance registry rid requestId actor name appearance startWorker =
  createRoomWithHostCommand
    registry rid requestId actor
    (JoinWithAppearance actor name appearance)
    startWorker

-- Tao phong bang Command da chon.
-- Chi cong bo phong sau khi Host Join thanh cong.
createRoomWithHostCommand
  :: RoomRegistry
  -> RoomId
  -> RequestId
  -> PlayerId
  -> Command
  -> (RoomRuntime -> IO ())
  -> IO (Either CreateRoomError (RoomRuntime, GameState))
createRoomWithHostCommand registry rid requestId actor joinCommand startWorker
  | null rid || length rid > 32 || any isSpace rid =
      pure (Left InvalidRoomId)

  | otherwise =
      modifyMVar (registryRooms registry) $ \rooms ->
        case lookup rid rooms of
          Just _ ->
            pure (rooms, Left RoomAlreadyExists)

          Nothing -> do
            room <- newRoomRuntime rid
            reply <- newEmptyTMVarIO

            atomically $
              writeTBQueue (roomCommands room)
                QueuedCommand
                  { queuedRequestId = requestId
                  , queuedActorId = actor
                  , queuedCommand = joinCommand
                  , queuedReply = reply
                  }

            -- Phong chua duoc cong bo.
            processNextLobbyCommand room

            result <- atomically (takeTMVar reply)

            case result of
              Left err ->
                pure (rooms, Left (HostJoinRejected err))

              Right state -> do
                startWorker room

                pure
                  ( (rid, room) : rooms
                  , Right (room, state)
                  )
