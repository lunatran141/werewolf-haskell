
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent
  ( forkIO
  , threadDelay
  )

import Control.Concurrent.STM
  ( atomically
  , readTVar
  , writeTChan
  )

import Control.Monad (void)

import Data.Aeson (eitherDecode, encode)
import qualified Data.ByteString.Lazy as BL

import Domain.Types
  ( Appearance(..)
  , defaultAppearance
  , DomainEvent(..)
  , GameState(..)
  , NightChoice(..)
  , Phase(..)
  , Player(..)
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

-- Tao phong va lay PlayerId do Server cap.
createRoom :: WS.Connection -> String -> IO String
createRoom connection rid = do
  sendMessage connection
    (ClientCreateRoom "create" rid "SeerPlayer")

  response <- receiveMessage connection

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

  response <- receiveMessage connection

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
        void (forkIO (runLobbyLoop room))

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

              response <- receiveMessage connection

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

                  response <- receiveMessage joinConnection

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
