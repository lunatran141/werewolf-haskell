module Main (main) where

import Control.Concurrent.STM
  ( atomically
  , dupTChan
  , isEmptyTChan
  , newEmptyTMVarIO
  , readTChan
  , readTVarIO
  , takeTMVar
  , writeTBQueue
  )
import Domain.Types
  ( Command(..)
  , DomainEvent(..)
  , GameError(..)
  , GameState
  , Role(..)
  , gameHost
  , emptyLobby
  , gamePlayers
  , playerName
  )
import Server.GameLoop
  ( CreateRoomError(..)
  , createRoomWithHost
  , processNextLobbyCommand
  )
import Server.Room
  ( QueuedCommand(..)
  , RoomRuntime(..)
  , RoomUpdate(..)
  , newRoomRuntime
  , findRoom
  , newRoomRegistry
  )
import Test.Hspec (describe, hspec, it, shouldBe, expectationFailure)
import Protocol.Types (PlayerView(..), ServerMessage(..))
import Server.Broadcast (lobbyMessages, lobbyReply, lobbySnapshot)

-- Đưa một lệnh vào queue rồi chạy đúng một lượt GameLoop.
submit :: RoomRuntime -> String -> Command -> IO (Either GameError GameState)
submit room actor command = do
  reply <- newEmptyTMVarIO
  atomically $
    writeTBQueue (roomCommands room)
      QueuedCommand
        { queuedRequestId = "req-test"
        , queuedActorId = actor
        , queuedCommand = command
        , queuedReply = reply
        }

  processNextLobbyCommand room
  atomically (takeTMVar reply)

main :: IO ()
main = hspec $ describe "T08 Lobby GameLoop" $ do

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
          [PlayerView "p1" "Van" False]

    lobbyMessages "ROOM-01" update
      `shouldBe`
        [MsgPlayerJoined "ROOM-01" (PlayerView "p1" "Van" False)]

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
          RoomUpdate 1 emptyLobby [PlayerRoleAssigned "p1" Werewolf]

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
          [PlayerView "p1" "Van" True]

  it "Lenh loi tra CommandRejected dung requestId" $ do
    room <- newRoomRuntime "ROOM-01"

    _ <- submit room "p1" (Join "p1" "Van")
    result <- submit room "p1" (Join "p1" "Binh")

    case lobbyReply "ROOM-01" "req-2" "p1" (Join "p1" "Binh") result of
      MsgRejected requestId code _ -> do
        requestId `shouldBe` Just "req-2"
        code `shouldBe` "DUPLICATE_PLAYER_ID"
      other ->
        error ("Mong doi CommandRejected, nhan: " ++ show other)

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