-- Kiểm thử T06 tại queue STM: xác thực session, commit Vote và chống trùng.
module Main (main) where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Concurrent.MVar (modifyMVar_, withMVar)
import Control.Concurrent.STM
  ( atomically
  , check
  , dupTChan
  , isEmptyTChan
  , newEmptyTMVarIO
  , readTChan
  , readTVar
  , readTVarIO
  , takeTMVar
  , writeTBQueue
  , writeTVar
  )
import Control.Exception (bracket)
import Domain.Types
import Server.GameLoop
  ( applyInternalCommand
  , createRoomWithHost
  , processNextLobbyCommand
  , runGameLoopWithPhaseTimeouts
  , runGameLoopWithExpiryTimeouts
  , runRegisteredLobbyLoopWithExpiryTimeouts
  )
import Server.Room
  ( QueuedCommand(..)
  , RoomRegistry(..)
  , RoomRuntime(..)
  , RoomUpdate(..)
  , newRoomRegistry
  , newRoomRuntime
  )
import Test.Hspec
import System.Timeout (timeout)

roles8 :: [Role]
roles8 = [Werewolf, Werewolf, Seer, Guard, Witch, Hunter, Villager, Villager]

votingState :: GameState
votingState =
  emptyLobby
    { gamePlayers =
        [ Player pid ("Nguoi " ++ pid) (Just role) True Alive defaultAppearance
        | (pid, role) <- zip (map ("p" ++) (map show [1 :: Int .. 8])) roles8
        ]
    , gameHost = "p1"
    , gamePhase = Voting
    , gameDay = 1
    , gameConfiguredRoles = roles8
    }

submitVote :: RoomRuntime -> String -> String -> IO (Either GameError GameState)
submitVote room sessionActor commandActor = do
  reply <- newEmptyTMVarIO
  atomically $
    writeTBQueue (roomCommands room)
      QueuedCommand
        { queuedRequestId = "vote-request"
        , queuedActorId = sessionActor
        , queuedCommand = Vote commandActor "p7"
        , queuedReply = reply
        }
  processNextLobbyCommand room
  atomically (takeTMVar reply)

main :: IO ()
main = hspec $ describe "T06 GameLoop Vote" $ do
  it "Soi co 60 giay, sau do cac vai Dan dung chung 30 giay va dem tu ket thuc" $ do
    room <- newRoomRuntime "ROOM-NIGHT-TIMER"
    atomically (writeTVar (roomState room) votingState
      { gamePhase = Night, gameVotes = [] })
    -- 30ms/30ms chỉ dành cho bài test; production dùng 60s/30s.
    bracket
      (forkIO (runGameLoopWithPhaseTimeouts 1000000 30000 30000 room))
      killThread $ \_ -> do
        timeout 2000000 (atomically $ do
          state <- readTVar (roomState room)
          check (gameWolfVotingClosed state)) `shouldReturn` Just ()
        timeout 2000000 (atomically $ do
          state <- readTVar (roomState room)
          check (gamePhase state == Day)) `shouldReturn` Just ()

  it "Khong cho vai Dan hanh dong truoc khi khoa luot Soi" $ do
    room <- newRoomRuntime "ROOM-WOLF-FIRST"
    atomically (writeTVar (roomState room) votingState
      { gamePhase = Night, gameVotes = [] })
    reply <- newEmptyTMVarIO
    atomically $ writeTBQueue (roomCommands room) QueuedCommand
      { queuedRequestId = "seer-early"
      , queuedActorId = "p3"
      , queuedCommand = NightAction "p3" (SeerTarget "p1")
      , queuedReply = reply
      }
    processNextLobbyCommand room
    atomically (takeTMVar reply) `shouldReturn` Left InvalidNightAction

  it "Sau thoi gian ket thuc, moi nguoi deu roi phong" $ do
    room <- newRoomRuntime "ROOM-AUTO-CLOSE"
    atomically (writeTVar (roomState room) votingState {gamePhase = Day})
    result <- atomically (applyInternalCommand room (EndGame "p1"))
    fmap gamePhase result `shouldBe` Right GameOver
    bracket
      (forkIO (runGameLoopWithExpiryTimeouts 1000000 1000000 1000000 50000 room))
      killThread $ \_ ->
        timeout 2000000 (atomically $ do
          state <- readTVar (roomState room)
          check (null (gamePlayers state))) `shouldReturn` Just ()

  it "Phong ket thuc duoc giai phong va cho phep tao lai cung ma" $ do
    registry <- newRoomRegistry
    room <- newRoomRuntime "ROOM-REUSE"
    atomically (writeTVar (roomState room) votingState {gamePhase = Day})
    modifyMVar_ (registryRooms registry) (pure . ((roomId room, room) :))
    result <- atomically (applyInternalCommand room (EndGame "p1"))
    fmap gamePhase result `shouldBe` Right GameOver
    bracket
      (forkIO (runRegisteredLobbyLoopWithExpiryTimeouts
        1000000 1000000 1000000 50000 registry room))
      killThread $ \_ -> do
        let waitForRemoval = do
              found <- withMVar (registryRooms registry)
                (pure . lookup "ROOM-REUSE")
              case found of
                Nothing -> pure ()
                Just _ -> threadDelay 10000 >> waitForRemoval
        timeout 2000000 waitForRemoval `shouldReturn` Just ()
    recreated <- createRoomWithHost registry "ROOM-REUSE" "new-room"
      "new-host" "Host moi" (\_ -> pure ())
    case recreated of
      Right _ -> pure ()
      Left err -> expectationFailure ("Khong the tao lai phong: " ++ show err)

  it "Day tu dong chuyen sang Voting sau thoi gian thao luan" $ do
    room <- newRoomRuntime "ROOM-DAY"
    atomically (writeTVar (roomState room) votingState {gamePhase = Day})
    let waitForVoting = timeout 2000000 $ atomically $ do
          state <- readTVar (roomState room)
          check (gamePhase state == Voting)
    bracket
      (forkIO (runGameLoopWithPhaseTimeouts 50000 1000000 1000000 room))
      killThread
      (\_ -> waitForVoting `shouldReturn` Just ())

  it "Vote hop le duoc commit qua queue va phat event" $ do
    room <- newRoomRuntime "ROOM-01"
    updates <- atomically (dupTChan (roomUpdates room))
    atomically (writeTVar (roomState room) votingState)

    result <- submitVote room "p1" "p1"
    fmap gameVotes result `shouldBe` Right [("p1", "p7")]

    version <- readTVarIO (roomVersion room)
    version `shouldBe` 1
    update <- atomically (readTChan updates)
    updateEvents update `shouldBe` [VoteUpdated "p1" "p7"]

  it "Session khong duoc Vote thay PlayerId khac" $ do
    room <- newRoomRuntime "ROOM-01"
    updates <- atomically (dupTChan (roomUpdates room))
    atomically (writeTVar (roomState room) votingState)

    result <- submitVote room "p1" "p2"
    result `shouldBe` Left NotAuthorized
    readTVarIO (roomVersion room) `shouldReturn` 0
    atomically (isEmptyTChan updates) `shouldReturn` True

  it "Vote trung cung round bi tu choi va khong tang version" $ do
    room <- newRoomRuntime "ROOM-01"
    updates <- atomically (dupTChan (roomUpdates room))
    atomically (writeTVar (roomState room) votingState)

    _ <- submitVote room "p1" "p1"
    _ <- atomically (readTChan updates)
    result <- submitVote room "p1" "p1"

    result `shouldBe` Left DuplicateRequest
    readTVarIO (roomVersion room) `shouldReturn` 1
    atomically (isEmptyTChan updates) `shouldReturn` True

  it "Ket qua Voting va nguoi chet duoc luu vao lich su chat cong khai" $ do
    room <- newRoomRuntime "ROOM-HISTORY"
    updates <- atomically (dupTChan (roomUpdates room))
    atomically (writeTVar (roomState room) votingState {gameVotes = [("p1", "p7")]})

    result <- atomically (applyInternalCommand room ResolveVoting)
    fmap gamePhase result `shouldBe` Right Night
    update <- atomically (readTChan updates)
    case updateChatRecord update of
      Nothing -> expectationFailure "Phai luu thong bao ket qua Voting"
      Just record -> do
        chatDay record `shouldBe` 1
        chatChannel record `shouldBe` PublicDay
        chatSenderId record `shouldBe` "__system__"
        chatText record `shouldContain` "Kết quả bỏ phiếu vòng 1"
        chatText record `shouldContain` "Nguoi p7"
    history <- readTVarIO (roomChatHistory room)
    history `shouldBe` maybe [] pure (updateChatRecord update)
