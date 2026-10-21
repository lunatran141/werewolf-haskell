
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent
  ( forkIO
  , newEmptyMVar
  , putMVar
  , takeMVar
  , threadDelay
  )

import Control.Concurrent.STM
  ( atomically
  , readTVar
  , writeTChan
  , writeTVar
  )

import Control.Monad (void)

import Data.Aeson (eitherDecode, encode)
import qualified Data.ByteString.Lazy as BL

import Domain.Types
  ( Appearance(..)
  , ChatChannel(..)
  , ChatRecord(..)
  , defaultAppearance
  , DomainEvent(..)
  , GameState(..)
  , NightChoice(..)
  , LifeStatus(..)
  , Phase(..)
  , Player(..)
  , Role(..)
  , Team(..)
  )

import qualified Network.WebSockets as WS

import Protocol.Types
  ( ClientMessage(..)
  , PlayerView(..)
  , ServerMessage(..)
  )

import Server.GameLoop (runLobbyLoop)

import Server.Room
  ( RoomRegistry
  , RoomRuntime(..)
  , RoomUpdate(..)
  , findRoom
  , newRoomRegistry
  )

import Server.WebSocket (webSocketApp)

import System.Timeout (timeout)

import Test.Hspec
  ( describe
  , expectationFailure
  , hspec
  , it
  , shouldBe
  , shouldSatisfy
  )

-- Cong WebSocket danh rieng cho test.
serverPort :: Int
serverPort = 18765

-- Appearance tuy chinh hop le theo preset T07.
customAppearance :: Appearance
customAppearance =
  Appearance
    { appearanceHair = "ponytail"
    , appearanceHairColor = "#8B5CF6"
    , appearanceSkin = "#C28865"
    , appearanceOutfit = "#064E3B"
    , appearanceAccessory = "flower_crown"
    }

-- Gioi han thoi gian cho tung bai test.
withTestTimeout :: IO () -> IO ()
withTestTimeout action = do
  result <- timeout 8000000 action

  case result of
    Nothing ->
      expectationFailure
        "WebSocket test timeout sau 8 giay."

    Just () ->
      pure ()

-- Gui ClientMessage duoi dang JSON.
sendMessage :: WS.Connection -> ClientMessage -> IO ()
sendMessage connection message =
  WS.sendTextData connection (encode message)

-- Nhan va giai ma ServerMessage.
-- Moi lan doc duoc gioi han trong 3 giay.
receiveMessage :: WS.Connection -> IO ServerMessage
receiveMessage connection = do
  message <- receiveAnyMessage connection
  case message of
    MsgRoomVersion {} -> receiveMessage connection
    _ -> pure message

receiveAnyMessage :: WS.Connection -> IO ServerMessage
receiveAnyMessage connection = do
  received <- timeout 3000000
    (WS.receiveData connection :: IO BL.ByteString)

  case received of
    Nothing -> do
      expectationFailure
        "Khong nhan duoc ServerMessage sau 3 giay."
      fail "Receive timeout"

    Just payload ->
      case eitherDecode payload of
        Right message ->
          pure message

        Left err -> do
          expectationFailure
            ("Khong doc duoc ServerMessage: " ++ err)
          fail err

receiveUntil :: WS.Connection -> (ServerMessage -> Bool) -> IO ServerMessage
receiveUntil connection predicate = do
  message <- receiveMessage connection
  if predicate message then pure message else receiveUntil connection predicate

receiveUntilAny :: WS.Connection -> (ServerMessage -> Bool) -> IO ServerMessage
receiveUntilAny connection predicate = do
  message <- receiveAnyMessage connection
  if predicate message then pure message else receiveUntilAny connection predicate

isLobbySnapshot :: ServerMessage -> Bool
isLobbySnapshot MsgLobbySnapshot {} = True
isLobbySnapshot _ = False

isRoomVersion :: ServerMessage -> Bool
isRoomVersion MsgRoomVersion {} = True
isRoomVersion _ = False

isChatHistorySnapshot :: ServerMessage -> Bool
isChatHistorySnapshot MsgChatHistorySnapshot {} = True
isChatHistorySnapshot _ = False

-- Tao phong va lay PlayerId do Server cap.
createRoom :: WS.Connection -> String -> IO String
createRoom connection rid = do
  sendMessage connection
    (ClientCreateRoom "create" rid "SeerPlayer")

  response <- receiveUntil connection isLobbySnapshot

  case response of
    MsgLobbySnapshot actualRoom selfId _ _ -> do
      actualRoom `shouldBe` rid
      pure selfId

    _ -> do
      expectationFailure
        "CreateRoom khong tra LobbySnapshot."
      fail "CreateRoom failed"

-- Tham gia phong va lay PlayerId do Server cap.
joinRoom :: WS.Connection -> String -> IO String
joinRoom connection rid = do
  sendMessage connection
    (ClientJoin "join" rid "OtherPlayer")

  response <- receiveUntil connection isLobbySnapshot

  case response of
    MsgLobbySnapshot actualRoom selfId _ _ -> do
      actualRoom `shouldBe` rid
      pure selfId

    _ -> do
      expectationFailure
        "JoinGame khong tra LobbySnapshot."
      fail "JoinGame failed"

-- Kiem tra thong diep tu choi theo requestId va code.
expectRejected
  :: WS.Connection
  -> String
  -> String
  -> IO ()
expectRejected connection requestId expectedCode = do
  response <- receiveMessage connection

  case response of
    MsgRejected actualId code _ -> do
      actualId `shouldBe` Just requestId
      code `shouldBe` expectedCode

    _ ->
      expectationFailure
        "Server khong tra CommandRejected."

-- Khoi dong WebSocket Server cho bo test.
-- Server chay trong thread phu.
-- Khong killThread khi ket thuc Hspec vi thao tac
-- dung Server truoc do co dau hieu bi treo tren Windows.
startTestServer :: IO RoomRegistry
startTestServer = do
  registry <- newRoomRegistry

  let startWorker room =
        if roomId room == "ROOM-SLOW-WORKER"
          then pure ()
          else void (forkIO (runLobbyLoop room))

  _ <- forkIO $
    WS.runServer
      "127.0.0.1"
      serverPort
      (webSocketApp registry startWorker)

  -- Cho WebSocket Server mo cong truoc khi test.
  threadDelay 500000

  pure registry

-- Lay RoomRuntime cua phong dang test.
requireRoom :: RoomRegistry -> String -> IO RoomRuntime
requireRoom registry rid = do
  found <- findRoom registry rid

  case found of
    Just room ->
      pure room

    Nothing -> do
      expectationFailure
        ("Khong tim thay RoomRuntime: " ++ rid)
      fail "Room not found"

-- Phat DomainEvent thu nghiem vao channel cua phong.
-- Chi test fixture moi duoc thao tac truc tiep.
publishTestEvents :: RoomRuntime -> [DomainEvent] -> IO ()
publishTestEvents room events =
  atomically $ do
    currentState <- readTVar (roomState room)
    currentVersion <- readTVar (roomVersion room)

    writeTChan (roomUpdates room)
      RoomUpdate
        { updateVersion = currentVersion
        , updateState = currentState
        , updateEvents = events
        , updateChatRecord = Nothing
        }

-- Lay PlayerView theo ID tu danh sach cong khai.
requirePlayerView :: String -> [PlayerView] -> IO PlayerView
requirePlayerView pid players =
  case filter ((== pid) . viewPlayerId) players of
    [playerView] ->
      pure playerView

    _ -> do
      expectationFailure
        ("Khong tim thay PlayerView duy nhat: " ++ pid)
      fail "PlayerView not found"

-- Lay Player theo ID tu GameState.
requireDomainPlayer :: String -> GameState -> IO Player
requireDomainPlayer pid state =
  case filter ((== pid) . playerId) (gamePlayers state) of
    [player] ->
      pure player

    _ -> do
      expectationFailure
        ("Khong tim thay Player duy nhat: " ++ pid)
      fail "Domain Player not found"

main :: IO ()
main = do
  registry <- startTestServer

  hspec $ do

    describe "T07 - WebSocket reconnect" $ do
      it "Join vao phong co worker treo khong chan phong khac" $
        withTestTimeout $ do
          WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
            sendMessage connection
              (ClientCreateRoom "slow-create" "ROOM-SLOW-WORKER" "SlowHost")
            _ <- receiveUntil connection isLobbySnapshot
            pure ()
          WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
            sendMessage connection
              (ClientCreateRoom "fast-create" "ROOM-FAST-WORKER" "FastHost")
            _ <- receiveUntil connection isLobbySnapshot
            pure ()

          started <- newEmptyMVar
          slowResult <- newEmptyMVar
          _ <- forkIO $ WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
            sendMessage connection
              (ClientJoin "slow-join" "ROOM-SLOW-WORKER" "SlowJoiner")
            putMVar started ()
            received <- timeout 6500000
              (WS.receiveData connection :: IO BL.ByteString)
            putMVar slowResult $ case received of
              Just payload -> either (const Nothing) Just (eitherDecode payload)
              Nothing -> Nothing
          takeMVar started

          fastJoin <- timeout 2500000 $
            WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
              sendMessage connection
                (ClientJoin "fast-join" "ROOM-FAST-WORKER" "FastJoiner")
              receiveUntil connection isLobbySnapshot
          case fastJoin of
            Just (MsgLobbySnapshot "ROOM-FAST-WORKER" _ _ players) ->
              length players `shouldBe` 2
            _ -> expectationFailure
              "Join phòng nhanh bị chặn bởi worker phòng chậm."

          timedOut <- takeMVar slowResult
          case timedOut of
            Just (MsgRejected (Just "slow-join") "ServerTimeout" _) -> pure ()
            _ -> expectationFailure
              "Join tới worker treo không trả ServerTimeout đúng requestId."

      it "giu nguyen PlayerId va snapshot khi noi lai bang token" $
        withTestTimeout $ do
          (originalPlayerId, sessionToken) <-
            WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
              sendMessage connection
                (ClientCreateRoom "reconnect-create" "ROOM-R01" "ReconnectPlayer")
              established <- receiveUntil connection $ \message ->
                case message of
                  MsgSessionEstablished "ROOM-R01" _ _ -> True
                  _ -> False
              case established of
                MsgSessionEstablished _ playerId token -> pure (playerId, token)
                _ -> fail "Khong nhan duoc session token"

          WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
            sendMessage connection
              (ClientReconnect "reconnect" "ROOM-R01" sessionToken)
            established <- receiveUntil connection $ \message ->
              case message of
                MsgSessionEstablished "ROOM-R01" _ _ -> True
                _ -> False
            established `shouldBe`
              MsgSessionEstablished "ROOM-R01" originalPlayerId sessionToken

            snapshot <- receiveUntil connection isLobbySnapshot
            case snapshot of
              MsgLobbySnapshot _ selfId _ players -> do
                selfId `shouldBe` originalPlayerId
                length players `shouldBe` 1
              _ -> fail "Khong nhan duoc LobbySnapshot sau reconnect"
            version <- receiveUntilAny connection isRoomVersion
            version `shouldBe` MsgRoomVersion "ROOM-R01" 1

      it "reconnect khoi phuc snapshot sau khi phong da sang Day 2" $
        withTestTimeout $ do
          token <- WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
            sendMessage connection
              (ClientCreateRoom "day2-create" "ROOM-DAY2-RECONNECT" "DayTwoPlayer")
            established <- receiveUntil connection $ \message ->
              case message of
                MsgSessionEstablished "ROOM-DAY2-RECONNECT" _ _ -> True
                _ -> False
            case established of
              MsgSessionEstablished _ _ value -> pure value
              _ -> fail "Khong nhan duoc reconnect token"

          room <- requireRoom registry "ROOM-DAY2-RECONNECT"
          atomically $ do
            state <- readTVar (roomState room)
            writeTVar (roomState room) state {gamePhase = Day, gameDay = 1}
          atomically $ do
            state <- readTVar (roomState room)
            writeTVar (roomState room) state {gameDay = 2}

          WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
            sendMessage connection
              (ClientReconnect "day2-reconnect" "ROOM-DAY2-RECONNECT" token)
            recovered <- receiveUntilAny connection $ \message ->
              case message of
                MsgVotingSnapshot "ROOM-DAY2-RECONNECT" Day 2 _ _ _ _ _ -> True
                _ -> False
            case recovered of
              MsgVotingSnapshot _ Day 2 _ _ _ _ _ -> pure ()
              _ -> fail "Reconnect khong khoi phuc snapshot Day 2"

      it "reconnect Day 2 giu chat Day 1 va khong nhan doi lich su" $
        withTestTimeout $ do
          (actor, sessionToken) <-
            WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
              sendMessage connection
                (ClientCreateRoom "history-create" "ROOM-HISTORY-RECONNECT" "HistoryPlayer")
              established <- receiveUntil connection $ \message ->
                case message of
                  MsgSessionEstablished "ROOM-HISTORY-RECONNECT" _ _ -> True
                  _ -> False
              (playerId, token) <- case established of
                MsgSessionEstablished _ playerId value -> pure (playerId, value)
                _ -> fail "Khong nhan duoc reconnect token"

              room <- requireRoom registry "ROOM-HISTORY-RECONNECT"
              atomically $ do
                state <- readTVar (roomState room)
                writeTVar (roomState room) state {gamePhase = Day, gameDay = 1}

              sendMessage connection
                (ClientChannelChat
                  "history-chat-day-1"
                  "ROOM-HISTORY-RECONNECT"
                  PublicDay
                  "Tin nhan Ngay 1")
              stored <- receiveUntil connection $ \message ->
                case message of
                  MsgStoredChatMessage "ROOM-HISTORY-RECONNECT" record ->
                    chatMessageId record == "ROOM-HISTORY-RECONNECT-chat-1"
                  _ -> False
              case stored of
                MsgStoredChatMessage _ record -> do
                  chatDay record `shouldBe` 1
                  chatChannel record `shouldBe` PublicDay
                  chatSenderId record `shouldBe` playerId
                  chatText record `shouldBe` "Tin nhan Ngay 1"
                _ -> fail "Khong nhan duoc chat Day 1 da luu"
              pure (playerId, token)

          room <- requireRoom registry "ROOM-HISTORY-RECONNECT"
          atomically $ do
            state <- readTVar (roomState room)
            writeTVar (roomState room) state {gameDay = 2}

          WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
            sendMessage connection
              (ClientReconnect
                "history-reconnect"
                "ROOM-HISTORY-RECONNECT"
                sessionToken)
            historyMessage <- receiveUntil connection isChatHistorySnapshot
            case historyMessage of
              MsgChatHistorySnapshot "ROOM-HISTORY-RECONNECT" records -> do
                length records `shouldBe` 1
                case records of
                  [record] -> do
                    chatDay record `shouldBe` 1
                    chatChannel record `shouldBe` PublicDay
                    chatSenderId record `shouldBe` actor
                    chatText record `shouldBe` "Tin nhan Ngay 1"
                  _ -> expectationFailure
                    "Reconnect da lam mat hoac nhan doi chat Day 1"
              _ -> fail "Reconnect khong tra ChatHistorySnapshot"

      it "gui lai cung requestId sau reconnect khong nhan doi NightAction va Vote" $
        withTestTimeout $ do
          (actor, sessionToken) <-
            WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
              sendMessage connection
                (ClientCreateRoom "idem-create" "ROOM-IDEM-RECONNECT" "RetryPlayer")
              established <- receiveUntil connection $ \message ->
                case message of
                  MsgSessionEstablished "ROOM-IDEM-RECONNECT" _ _ -> True
                  _ -> False
              case established of
                MsgSessionEstablished _ playerId token -> pure (playerId, token)
                _ -> fail "Khong nhan duoc reconnect token"

          room <- requireRoom registry "ROOM-IDEM-RECONNECT"
          let configuredRoles =
                [ Werewolf, Werewolf, Seer, Guard
                , Witch, Hunter, Villager, Villager
                ]
              extraPlayers =
                [ Player "idem-wolf-2" "WolfTwo" (Just Werewolf) False Alive defaultAppearance
                , Player "idem-seer" "Seer" (Just Seer) False Alive defaultAppearance
                , Player "idem-guard" "Guard" (Just Guard) False Alive defaultAppearance
                , Player "idem-witch" "Witch" (Just Witch) False Alive defaultAppearance
                , Player "idem-hunter" "Hunter" (Just Hunter) False Alive defaultAppearance
                , Player "idem-villager-1" "VillagerOne" (Just Villager) False Alive defaultAppearance
                , Player "idem-villager-2" "VillagerTwo" (Just Villager) False Alive defaultAppearance
                ]
              nightTarget = "idem-villager-1"
              voteTarget = "idem-villager-2"

          atomically $ do
            state <- readTVar (roomState room)
            let actorPlayers =
                  [ player {playerRole = Just Werewolf}
                  | player <- gamePlayers state
                  ]
            writeTVar (roomState room) state
              { gamePlayers = actorPlayers ++ extraPlayers
              , gamePhase = Night
              , gameDay = 1
              , gameConfiguredRoles = configuredRoles
              }

          -- Lan gui dau tien thanh cong, sau do ket noi bi dong.
          WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
            sendMessage connection
              (ClientReconnect "idem-night-reconnect" "ROOM-IDEM-RECONNECT" sessionToken)
            _ <- receiveUntil connection $ \message ->
              case message of
                MsgSessionEstablished "ROOM-IDEM-RECONNECT" _ _ -> True
                _ -> False
            sendMessage connection
              (ClientNightAction
                "idem-night-action"
                "ROOM-IDEM-RECONNECT"
                (WolfTarget nightTarget))
            accepted <- receiveUntil connection $ \message ->
              message == MsgNightActionAccepted "ROOM-IDEM-RECONNECT"
            accepted `shouldBe` MsgNightActionAccepted "ROOM-IDEM-RECONNECT"

          versionAfterNight <- atomically (readTVar (roomVersion room))

          -- Browser retry cung requestId sau reconnect: Server phai tu choi
          -- va khong duoc ghi them NightAction.
          WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
            sendMessage connection
              (ClientReconnect "idem-night-retry-reconnect" "ROOM-IDEM-RECONNECT" sessionToken)
            _ <- receiveUntil connection $ \message ->
              case message of
                MsgSessionEstablished "ROOM-IDEM-RECONNECT" _ _ -> True
                _ -> False
            sendMessage connection
              (ClientNightAction
                "idem-night-action"
                "ROOM-IDEM-RECONNECT"
                (WolfTarget nightTarget))
            rejected <- receiveUntil connection $ \message ->
              case message of
                MsgRejected (Just "idem-night-action") "DuplicateRequest" _ -> True
                _ -> False
            case rejected of
              MsgRejected (Just requestId) code _ -> do
                requestId `shouldBe` "idem-night-action"
                code `shouldBe` "DuplicateRequest"
              _ -> fail "Retry NightAction khong bi tu choi dung requestId"

          stateAfterNightRetry <- atomically (readTVar (roomState room))
          versionAfterNightRetry <- atomically (readTVar (roomVersion room))
          gameNightActions stateAfterNightRetry
            `shouldBe` [(actor, WolfTarget nightTarget)]
          versionAfterNightRetry `shouldBe` versionAfterNight

          -- Chuyen fixture sang Voting de kiem tra cung quy tac voi Vote.
          atomically $ do
            state <- readTVar (roomState room)
            writeTVar (roomState room) state
              { gamePhase = Voting
              , gameNightActions = []
              , gameVotes = []
              }

          WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
            sendMessage connection
              (ClientReconnect "idem-vote-reconnect" "ROOM-IDEM-RECONNECT" sessionToken)
            _ <- receiveUntil connection $ \message ->
              case message of
                MsgSessionEstablished "ROOM-IDEM-RECONNECT" _ _ -> True
                _ -> False
            sendMessage connection
              (ClientVote "idem-vote" "ROOM-IDEM-RECONNECT" voteTarget)
            accepted <- receiveUntil connection $ \message ->
              message == MsgActionAccepted "idem-vote" "ROOM-IDEM-RECONNECT"
            accepted `shouldBe` MsgActionAccepted "idem-vote" "ROOM-IDEM-RECONNECT"

          versionAfterVote <- atomically (readTVar (roomVersion room))

          WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
            sendMessage connection
              (ClientReconnect "idem-vote-retry-reconnect" "ROOM-IDEM-RECONNECT" sessionToken)
            _ <- receiveUntil connection $ \message ->
              case message of
                MsgSessionEstablished "ROOM-IDEM-RECONNECT" _ _ -> True
                _ -> False
            sendMessage connection
              (ClientVote "idem-vote" "ROOM-IDEM-RECONNECT" voteTarget)
            rejected <- receiveUntil connection $ \message ->
              case message of
                MsgRejected (Just "idem-vote") "DuplicateRequest" _ -> True
                _ -> False
            case rejected of
              MsgRejected (Just requestId) code _ -> do
                requestId `shouldBe` "idem-vote"
                code `shouldBe` "DuplicateRequest"
              _ -> fail "Retry Vote khong bi tu choi dung requestId"

          stateAfterVoteRetry <- atomically (readTVar (roomState room))
          versionAfterVoteRetry <- atomically (readTVar (roomVersion room))
          gameVotes stateAfterVoteRetry `shouldBe` [(actor, voteTarget)]
          versionAfterVoteRetry `shouldBe` versionAfterVote

      it "nguoi da chet reconnect van doc chat cong khai nhung khong duoc hanh dong" $
        withTestTimeout $ do
          (actor, sessionToken) <-
            WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
              sendMessage connection
                (ClientCreateRoom "dead-create" "ROOM-DEAD-RECONNECT" "DeadPlayer")
              established <- receiveUntil connection $ \message ->
                case message of
                  MsgSessionEstablished "ROOM-DEAD-RECONNECT" _ _ -> True
                  _ -> False
              case established of
                MsgSessionEstablished _ playerId token -> pure (playerId, token)
                _ -> fail "Khong nhan duoc reconnect token"

          room <- requireRoom registry "ROOM-DEAD-RECONNECT"
          let configuredRoles =
                [ Werewolf, Werewolf, Seer, Guard
                , Witch, Hunter, Villager, Villager
                ]
              extraPlayers =
                [ Player "dead-wolf-2" "DeadWolfTwo" (Just Werewolf) False Alive defaultAppearance
                , Player "dead-seer" "DeadSeer" (Just Seer) False Alive defaultAppearance
                , Player "dead-guard" "DeadGuard" (Just Guard) False Alive defaultAppearance
                , Player "dead-witch" "DeadWitch" (Just Witch) False Alive defaultAppearance
                , Player "dead-hunter" "DeadHunter" (Just Hunter) False Alive defaultAppearance
                , Player "dead-villager-1" "DeadVillagerOne" (Just Villager) False Alive defaultAppearance
                , Player "dead-villager-2" "DeadVillagerTwo" (Just Villager) False Alive defaultAppearance
                ]
              target = "dead-villager-1"

          atomically $ do
            state <- readTVar (roomState room)
            let actorPlayers =
                  [ player {playerRole = Just Werewolf}
                  | player <- gamePlayers state
                  ]
            writeTVar (roomState room) state
              { gamePlayers = actorPlayers ++ extraPlayers
              , gamePhase = Day
              , gameDay = 1
              , gameConfiguredRoles = configuredRoles
              }

          -- Tao mot tin cong khai luc actor con song.
          WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
            sendMessage connection
              (ClientReconnect "dead-alive-reconnect" "ROOM-DEAD-RECONNECT" sessionToken)
            _ <- receiveUntil connection $ \message ->
              case message of
                MsgSessionEstablished "ROOM-DEAD-RECONNECT" _ _ -> True
                _ -> False
            sendMessage connection
              (ClientChannelChat
                "dead-public-history"
                "ROOM-DEAD-RECONNECT"
                PublicDay
                "Tin cong khai truoc khi chet")
            stored <- receiveUntil connection $ \message ->
              case message of
                MsgStoredChatMessage "ROOM-DEAD-RECONNECT" record ->
                  chatText record == "Tin cong khai truoc khi chet"
                _ -> False
            case stored of
              MsgStoredChatMessage _ record ->
                chatSenderId record `shouldBe` actor
              _ -> fail "Khong luu duoc chat cong khai"

          -- Danh dau actor da chet, sau do ket noi lai bang cung session.
          atomically $ do
            state <- readTVar (roomState room)
            let deadPlayers =
                  [ if playerId player == actor
                      then player {playerLifeStatus = Dead}
                      else player
                  | player <- gamePlayers state
                  ]
            writeTVar (roomState room) state {gamePlayers = deadPlayers}

          versionBeforeRejectedActions <- atomically (readTVar (roomVersion room))

          WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
            sendMessage connection
              (ClientReconnect "dead-reconnect" "ROOM-DEAD-RECONNECT" sessionToken)
            _ <- receiveUntil connection $ \message ->
              case message of
                MsgSessionEstablished "ROOM-DEAD-RECONNECT" _ _ -> True
                _ -> False

            historyMessage <- receiveUntil connection isChatHistorySnapshot
            case historyMessage of
              MsgChatHistorySnapshot "ROOM-DEAD-RECONNECT" records -> do
                length records `shouldBe` 1
                case records of
                  [record] -> do
                    chatChannel record `shouldBe` PublicDay
                    chatSenderId record `shouldBe` actor
                    chatText record `shouldBe` "Tin cong khai truoc khi chet"
                  _ -> expectationFailure
                    "Nguoi da chet khong nhan dung lich su chat cong khai"
              _ -> fail "Reconnect khong tra lich su chat cong khai"

            sendMessage connection
              (ClientChannelChat
                "dead-chat"
                "ROOM-DEAD-RECONNECT"
                PublicDay
                "Khong duoc gui")
            chatRejected <- receiveUntil connection $ \message ->
              case message of
                MsgRejected (Just "dead-chat") "DeadPlayer" _ -> True
                _ -> False
            case chatRejected of
              MsgRejected _ code _ -> code `shouldBe` "DeadPlayer"
              _ -> fail "Nguoi da chet van gui duoc chat"

            atomically $ do
              state <- readTVar (roomState room)
              writeTVar (roomState room) state {gamePhase = Voting}
            sendMessage connection
              (ClientVote "dead-vote" "ROOM-DEAD-RECONNECT" target)
            voteRejected <- receiveUntil connection $ \message ->
              case message of
                MsgRejected (Just "dead-vote") "DeadPlayer" _ -> True
                _ -> False
            case voteRejected of
              MsgRejected _ code _ -> code `shouldBe` "DeadPlayer"
              _ -> fail "Nguoi da chet van bo phieu duoc"

            atomically $ do
              state <- readTVar (roomState room)
              writeTVar (roomState room) state {gamePhase = Night}
            sendMessage connection
              (ClientNightAction
                "dead-night"
                "ROOM-DEAD-RECONNECT"
                (WolfTarget target))
            nightRejected <- receiveUntil connection $ \message ->
              case message of
                MsgRejected (Just "dead-night") "DeadPlayer" _ -> True
                _ -> False
            case nightRejected of
              MsgRejected _ code _ -> code `shouldBe` "DeadPlayer"
              _ -> fail "Nguoi da chet van thuc hien NightAction duoc"

          finalState <- atomically (readTVar (roomState room))
          finalVersion <- atomically (readTVar (roomVersion room))
          length (gameVotes finalState) `shouldBe` 0
          length (gameNightActions finalState) `shouldBe` 0
          finalVersion `shouldBe` versionBeforeRejectedActions

      it "host roi thi chuyen host va nguoi cuoi roi thi don RoomRuntime" $
        withTestTimeout $
          WS.runClient "127.0.0.1" serverPort "/" $ \hostConnection -> do
            hostId <- createRoom hostConnection "ROOM-LEAVE-CLEANUP"

            WS.runClient "127.0.0.1" serverPort "/" $ \memberConnection -> do
              memberId <- joinRoom memberConnection "ROOM-LEAVE-CLEANUP"

              sendMessage hostConnection
                (ClientLeave "leave-host" "ROOM-LEAVE-CLEANUP")
              hostReply <- receiveUntil hostConnection $ \message ->
                message == MsgPlayerLeft "ROOM-LEAVE-CLEANUP" hostId
              hostReply `shouldBe`
                MsgPlayerLeft "ROOM-LEAVE-CLEANUP" hostId

              memberSawLeave <- receiveUntil memberConnection $ \message ->
                message == MsgPlayerLeft "ROOM-LEAVE-CLEANUP" hostId
              memberSawLeave `shouldBe`
                MsgPlayerLeft "ROOM-LEAVE-CLEANUP" hostId

              memberSawHostChange <- receiveUntil memberConnection $ \message ->
                message == MsgHostChanged "ROOM-LEAVE-CLEANUP" memberId
              memberSawHostChange `shouldBe`
                MsgHostChanged "ROOM-LEAVE-CLEANUP" memberId

              roomAfterHostLeft <- requireRoom registry "ROOM-LEAVE-CLEANUP"
              stateAfterHostLeft <- atomically (readTVar (roomState roomAfterHostLeft))
              gameHost stateAfterHostLeft `shouldBe` memberId
              map playerId (gamePlayers stateAfterHostLeft) `shouldBe` [memberId]

              sendMessage memberConnection
                (ClientLeave "leave-last-member" "ROOM-LEAVE-CLEANUP")
              memberReply <- receiveUntil memberConnection $ \message ->
                message == MsgPlayerLeft "ROOM-LEAVE-CLEANUP" memberId
              memberReply `shouldBe`
                MsgPlayerLeft "ROOM-LEAVE-CLEANUP" memberId

              removed <- findRoom registry "ROOM-LEAVE-CLEANUP"
              case removed of
                Nothing -> pure ()
                Just _ -> expectationFailure
                  "Nguoi cuoi da roi nhung RoomRuntime van con trong registry"

              -- Ma phong phai dung lai duoc ngay sau khi runtime cu da duoc don.
              sendMessage memberConnection
                (ClientCreateRoom
                  "recreate-after-cleanup"
                  "ROOM-LEAVE-CLEANUP"
                  "NewHost")
              recreated <- receiveUntil memberConnection isLobbySnapshot
              case recreated of
                MsgLobbySnapshot "ROOM-LEAVE-CLEANUP" newHostId actualHost players -> do
                  actualHost `shouldBe` newHostId
                  length players `shouldBe` 1
                _ -> fail "Khong tao lai duoc ma phong sau khi cleanup"

      it "reconnect giua Day nhan dung thoi gian con lai, khong reset 3 phut" $
        withTestTimeout $ do
          (sessionToken, firstRemaining) <-
            WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
              sendMessage connection
                (ClientCreateRoom "timer-create" "ROOM-R02" "TimerPlayer")
              established <- receiveUntil connection $ \message ->
                case message of
                  MsgSessionEstablished "ROOM-R02" _ _ -> True
                  _ -> False
              token <- case established of
                MsgSessionEstablished _ _ value -> pure value
                _ -> fail "Khong nhan duoc session token"

              room <- requireRoom registry "ROOM-R02"
              atomically $ do
                state <- readTVar (roomState room)
                writeTVar (roomState room) state {gamePhase = Day, gameDay = 1}

              deadlineMessage <- receiveUntil connection $ \message ->
                case message of
                  MsgPhaseTimeRemaining "ROOM-R02" Day 1 _ -> True
                  _ -> False
              remaining <- case deadlineMessage of
                MsgPhaseTimeRemaining _ _ _ value -> pure value
                _ -> fail "Khong nhan duoc thoi gian Day"
              pure (token, remaining)

          threadDelay 250000

          WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
            sendMessage connection
              (ClientReconnect "timer-reconnect" "ROOM-R02" sessionToken)
            deadlineMessage <- receiveUntil connection $ \message ->
              case message of
                MsgPhaseTimeRemaining "ROOM-R02" Day 1 _ -> True
                _ -> False
            case deadlineMessage of
              MsgPhaseTimeRemaining _ _ _ remaining -> do
                remaining `shouldSatisfy` (> 0)
                remaining `shouldSatisfy` (< firstRemaining)
              _ -> fail "Reconnect khong nhan duoc thoi gian Day"

      it "reconnect khoi phuc action da gui va trang thai thuoc rieng" $
        withTestTimeout $ do
          (actor, sessionToken) <-
            WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
              sendMessage connection
                (ClientCreateRoom "private-create" "ROOM-R03" "WitchPlayer")
              established <- receiveUntil connection $ \message ->
                case message of
                  MsgSessionEstablished "ROOM-R03" _ _ -> True
                  _ -> False
              case established of
                MsgSessionEstablished _ playerId token -> pure (playerId, token)
                _ -> fail "Khong nhan duoc session token"

          room <- requireRoom registry "ROOM-R03"
          atomically $ do
            state <- readTVar (roomState room)
            let players =
                  [ player {playerRole = Just Witch}
                  | player <- gamePlayers state
                  ]
                wolf = Player "wolf-2" "Wolf" (Just Werewolf) False Alive defaultAppearance
                victim = Player "night-victim" "Victim" (Just Villager) False Alive defaultAppearance
            writeTVar (roomState room) state
              { gamePlayers = players ++ [wolf, victim]
              , gamePhase = Night
              , gameDay = 1
              , gameWolfVotingClosed = True
              , gameNightActions = [(actor, WitchPass), ("wolf-2", WolfTarget "night-victim")]
              , gameWitchHealReady = False
              , gameWitchPoisonReady = True
              }

          WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
            sendMessage connection
              (ClientReconnect "private-reconnect" "ROOM-R03" sessionToken)
            victimNotice <- receiveUntil connection $ \message ->
              case message of
                MsgWitchVictimNotice "ROOM-R03" _ -> True
                _ -> False
            victimNotice `shouldBe` MsgWitchVictimNotice "ROOM-R03" (Just "night-victim")
            privateState <- receiveUntil connection $ \message ->
              case message of
                MsgPrivateActionState "ROOM-R03" _ _ _ _ -> True
                _ -> False
            privateState `shouldBe`
              MsgPrivateActionState "ROOM-R03" True (Just False) (Just True) Nothing

      it "danh sach dong doi Soi chi duoc phuc hoi cho ket noi Soi" $
        withTestTimeout $ do
          (actor, sessionToken) <-
            WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
              sendMessage connection
                (ClientCreateRoom "wolf-team-create" "ROOM-R04" "WolfPlayer")
              established <- receiveUntil connection $ \message ->
                case message of
                  MsgSessionEstablished "ROOM-R04" _ _ -> True
                  _ -> False
              case established of
                MsgSessionEstablished _ playerId token -> pure (playerId, token)
                _ -> fail "Khong nhan duoc session token"

          room <- requireRoom registry "ROOM-R04"
          atomically $ do
            state <- readTVar (roomState room)
            let actorPlayers =
                  [ player {playerRole = Just Werewolf}
                  | player <- gamePlayers state
                  ]
                teammate = Player "wolf-2" "Wolf Two" (Just Werewolf) False Alive defaultAppearance
            writeTVar (roomState room) state
              { gamePlayers = actorPlayers ++ [teammate]
              , gamePhase = Night
              , gameDay = 1
              }

          WS.runClient "127.0.0.1" serverPort "/" $ \connection -> do
            sendMessage connection
              (ClientReconnect "wolf-team-reconnect" "ROOM-R04" sessionToken)
            team <- receiveUntil connection $ \message ->
              case message of
                MsgWolfTeam "ROOM-R04" _ -> True
                _ -> False
            team `shouldBe` MsgWolfTeam "ROOM-R04" [actor, "wolf-2"]

    -- Giu nguyen cac test T05 WebSocket.
    describe "T05 - WebSocket NightAction" $ do

      it "W01 - Tu choi NightAction khi chua Join" $
        withTestTimeout $
          WS.runClient
            "127.0.0.1"
            serverPort
            "/" $ \connection -> do

              sendMessage connection
                (ClientNightAction
                  "w01"
                  "ROOM-W01"
                  (WolfTarget "p7"))

              expectRejected connection "w01" "NOT_JOINED"

      it "W02 - Tu choi NightAction gui sai RoomId" $
        withTestTimeout $
          WS.runClient
            "127.0.0.1"
            serverPort
            "/" $ \connection -> do

              _ <- createRoom connection "ROOM-W02"

              sendMessage connection
                (ClientNightAction
                  "w02"
                  "WRONG-ROOM"
                  (WolfTarget "p7"))

              expectRejected connection "w02" "WRONG_ROOM"

      it "W03 - Tu choi NightAction khi dang Lobby" $
        withTestTimeout $
          WS.runClient
            "127.0.0.1"
            serverPort
            "/" $ \connection -> do

              _ <- createRoom connection "ROOM-W03"

              sendMessage connection
                (ClientNightAction
                  "w03"
                  "ROOM-W03"
                  (WolfTarget "p7"))

              expectRejected connection "w03" "WrongPhase"

      it "W04 - SeerResult chi gui den dung WebSocket" $
        withTestTimeout $
          WS.runClient
            "127.0.0.1"
            serverPort
            "/" $ \seerConnection -> do

              seerId <-
                createRoom seerConnection "ROOM-W04"

              WS.runClient
                "127.0.0.1"
                serverPort
                "/" $ \otherConnection -> do

                  otherId <-
                    joinRoom otherConnection "ROOM-W04"

                  -- Client dau nhan PlayerJoined.
                  joinedEvent <- receiveMessage seerConnection

                  joinedEvent `shouldBe`
                    MsgPlayerJoined
                      "ROOM-W04"
                      (PlayerView
                        otherId
                        "OtherPlayer"
                        False
                        True
                        defaultAppearance)

                  room <- requireRoom registry "ROOM-W04"

                  -- Phat event rieng cho Seer va event public.
                  -- Khong can StartGame trong test routing nay.
                  publishTestEvents room
                    [ SeerResult seerId Wolves
                    , PhaseChanged Day
                    ]

                  -- Seer nhan duoc ket qua rieng.
                  seerPrivate <- receiveMessage seerConnection

                  seerPrivate `shouldBe`
                    MsgSeerResult "ROOM-W04" Wolves

                  -- Seer cung nhan event cong khai.
                  seerPublic <- receiveMessage seerConnection

                  seerPublic `shouldBe`
                    MsgPhaseChanged "ROOM-W04" Day

                  -- Client khac chi nhan event public.
                  otherPublic <- receiveMessage otherConnection

                  otherPublic `shouldBe`
                    MsgPhaseChanged "ROOM-W04" Day

    -- Test moi cua T02: Appearance qua WebSocket thuc te.
    describe "T02 - WebSocket Appearance" $ do

      it "A01 - Host tao phong voi Appearance tuy chinh" $
        withTestTimeout $
          WS.runClient
            "127.0.0.1"
            serverPort
            "/" $ \connection -> do

              sendMessage connection
                (ClientCreateRoomWithAppearance
                  "a01"
                  "ROOM-A01"
                  "HostVan"
                  customAppearance)

              response <- receiveUntil connection isLobbySnapshot

              case response of
                MsgLobbySnapshot rid selfId hostId players -> do
                  rid `shouldBe` "ROOM-A01"
                  hostId `shouldBe` selfId
                  length players `shouldBe` 1

                  publicPlayer <-
                    requirePlayerView selfId players

                  viewDisplayName publicPlayer
                    `shouldBe` "HostVan"

                  viewAlive publicPlayer
                    `shouldBe` True

                  viewAppearance publicPlayer
                    `shouldBe` customAppearance

                  -- Kiem tra Appearance thuc su duoc luu.
                  room <- requireRoom registry "ROOM-A01"
                  state <- atomically (readTVar (roomState room))

                  domainPlayer <-
                    requireDomainPlayer selfId state

                  playerAppearance domainPlayer
                    `shouldBe` customAppearance

                _ -> do
                  expectationFailure
                    "CreateRoom co Appearance khong tra LobbySnapshot."

      it "A02 - Join voi Appearance va Host nhan PlayerJoined" $
        withTestTimeout $
          WS.runClient
            "127.0.0.1"
            serverPort
            "/" $ \hostConnection -> do

              hostId <-
                createRoom hostConnection "ROOM-A02"

              WS.runClient
                "127.0.0.1"
                serverPort
                "/" $ \joinConnection -> do

                  sendMessage joinConnection
                    (ClientJoinWithAppearance
                      "a02"
                      "ROOM-A02"
                      "JoinBinh"
                      customAppearance)

                  response <- receiveUntil joinConnection isLobbySnapshot

                  case response of
                    MsgLobbySnapshot rid joinId actualHostId players -> do
                      rid `shouldBe` "ROOM-A02"
                      actualHostId `shouldBe` hostId
                      length players `shouldBe` 2

                      -- Host giu Appearance mac dinh.
                      hostView <-
                        requirePlayerView hostId players

                      viewAppearance hostView
                        `shouldBe` defaultAppearance

                      -- Nguoi Join co Appearance tuy chinh.
                      joinView <-
                        requirePlayerView joinId players

                      viewDisplayName joinView
                        `shouldBe` "JoinBinh"

                      viewAlive joinView
                        `shouldBe` True

                      viewAppearance joinView
                        `shouldBe` customAppearance

                      -- Host cung phai nhan dung Appearance.
                      hostEvent <- receiveMessage hostConnection

                      hostEvent `shouldBe`
                        MsgPlayerJoined
                          "ROOM-A02"
                          (PlayerView
                            joinId
                            "JoinBinh"
                            False
                            True
                            customAppearance)

                      -- Kiem tra GameState phia Server.
                      room <- requireRoom registry "ROOM-A02"
                      state <- atomically (readTVar (roomState room))

                      domainPlayer <-
                        requireDomainPlayer joinId state

                      playerAppearance domainPlayer
                        `shouldBe` customAppearance

                    _ -> do
                      expectationFailure
                        "JoinGame co Appearance khong tra LobbySnapshot."

      it "A03 - Appearance khong hop le khong tao duoc phong" $
        withTestTimeout $
          WS.runClient
            "127.0.0.1"
            serverPort
            "/" $ \connection -> do

              let invalidAppearance =
                    defaultAppearance
                      { appearanceHair = "unknown" }

              sendMessage connection
                (ClientCreateRoomWithAppearance
                  "a03"
                  "ROOM-A03"
                  "InvalidHost"
                  invalidAppearance)

              response <- receiveMessage connection

              case response of
                MsgRejected actualRequestId _ _ ->
                  actualRequestId `shouldBe` Just "a03"

                _ ->
                  expectationFailure
                    "Server khong tu choi Appearance khong hop le."

              -- Phong khong duoc cong bo neu Host Join that bai.
              found <- findRoom registry "ROOM-A03"

              case found of
                Nothing ->
                  pure ()

                Just _ ->
                  expectationFailure
                    "Phong van duoc tao du Appearance khong hop le."
