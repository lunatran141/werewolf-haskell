{-# LANGUAGE OverloadedStrings #-}

-- | Contract Command và Event dùng chung giữa frontend và server.
module Protocol.Types where

import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , (.:)
  , (.=)
  , object
  , withObject
  )
import Data.Aeson.Types (Parser)

type RequestId = String
type RoomId = String

-- Lệnh nhận từ Browser. Không có PlayerId hoặc Role.
data ClientMessage
  = ClientCreateRoom RequestId RoomId String
  | ClientJoin RequestId RoomId String
  | ClientLeave RequestId RoomId
  | ClientSetReady RequestId RoomId Bool
  deriving (Eq, Show)

-- Một người trong danh sách Lobby gửi cho Browser.
data PlayerView = PlayerView
  { viewPlayerId :: String
  , viewDisplayName :: String
  , viewReady :: Bool
  } deriving (Eq, Show)

-- Tin Server gửi về Browser.
data ServerMessage
  = MsgLobbySnapshot RoomId String String [PlayerView]
  | MsgPlayerJoined RoomId PlayerView
  | MsgPlayerLeft RoomId String
  | MsgHostChanged RoomId String
  | MsgReadyChanged RoomId String Bool
  | MsgRejected (Maybe RequestId) String String
  deriving (Eq, Show)

instance FromJSON ClientMessage where
  parseJSON = withObject "ClientMessage" $ \obj -> do
    messageType <- obj .: "type" :: Parser String
    requestId <- obj .: "requestId"
    roomId <- obj .: "roomId"

    case messageType of
      "CreateRoom" ->
        ClientCreateRoom requestId roomId <$> obj .: "playerName"
      "JoinGame" ->
        ClientJoin requestId roomId <$> obj .: "playerName"
      "LeaveGame" ->
        pure (ClientLeave requestId roomId)
      "SetReady" ->
        ClientSetReady requestId roomId <$> obj .: "ready"
      _ ->
        fail ("Loai command khong ho tro: " ++ messageType)

instance ToJSON ClientMessage where
  toJSON message =
    case message of
      ClientCreateRoom requestId roomId playerName ->
        object
          [ "type" .= ("CreateRoom" :: String)
          , "requestId" .= requestId
          , "roomId" .= roomId
          , "playerName" .= playerName
          ]

      ClientJoin requestId roomId playerName ->
        object
          [ "type" .= ("JoinGame" :: String)
          , "requestId" .= requestId
          , "roomId" .= roomId
          , "playerName" .= playerName
          ]

      ClientLeave requestId roomId ->
        object
          [ "type" .= ("LeaveGame" :: String)
          , "requestId" .= requestId
          , "roomId" .= roomId
          ]

      ClientSetReady requestId roomId ready ->
        object
          [ "type" .= ("SetReady" :: String)
          , "requestId" .= requestId
          , "roomId" .= roomId
          , "ready" .= ready
          ]

instance FromJSON PlayerView where
  parseJSON = withObject "PlayerView" $ \obj ->
    PlayerView
      <$> obj .: "playerId"
      <*> obj .: "displayName"
      <*> obj .: "ready"

instance ToJSON PlayerView where
  toJSON player =
    object
      [ "playerId" .= viewPlayerId player
      , "displayName" .= viewDisplayName player
      , "ready" .= viewReady player
      ]

instance FromJSON ServerMessage where
  parseJSON = withObject "ServerMessage" $ \obj -> do
    messageType <- obj .: "type" :: Parser String

    case messageType of
      "LobbySnapshot" ->
        MsgLobbySnapshot
          <$> obj .: "roomId"
          <*> obj .: "selfPlayerId"
          <*> obj .: "hostPlayerId"
          <*> obj .: "players"

      "PlayerJoined" ->
        MsgPlayerJoined
          <$> obj .: "roomId"
          <*> obj .: "player"

      "PlayerLeft" ->
        MsgPlayerLeft
          <$> obj .: "roomId"
          <*> obj .: "playerId"

      "HostChanged" ->
        MsgHostChanged
          <$> obj .: "roomId"
          <*> obj .: "hostPlayerId"

      "ReadyChanged" ->
        MsgReadyChanged
          <$> obj .: "roomId"
          <*> obj .: "playerId"
          <*> obj .: "ready"

      "CommandRejected" ->
        MsgRejected
          <$> obj .: "requestId"
          <*> obj .: "code"
          <*> obj .: "message"

      _ ->
        fail ("Loai server message khong ho tro: " ++ messageType)

instance ToJSON ServerMessage where
  toJSON message =
    case message of
      MsgLobbySnapshot roomId selfId hostId players ->
        object
          [ "type" .= ("LobbySnapshot" :: String)
          , "roomId" .= roomId
          , "selfPlayerId" .= selfId
          , "hostPlayerId" .= hostId
          , "players" .= players
          ]

      MsgPlayerJoined roomId player ->
        object
          [ "type" .= ("PlayerJoined" :: String)
          , "roomId" .= roomId
          , "player" .= player
          ]

      MsgPlayerLeft roomId playerId ->
        object
          [ "type" .= ("PlayerLeft" :: String)
          , "roomId" .= roomId
          , "playerId" .= playerId
          ]

      MsgHostChanged roomId hostId ->
        object
          [ "type" .= ("HostChanged" :: String)
          , "roomId" .= roomId
          , "hostPlayerId" .= hostId
          ]

      MsgReadyChanged roomId playerId ready ->
        object
          [ "type" .= ("ReadyChanged" :: String)
          , "roomId" .= roomId
          , "playerId" .= playerId
          , "ready" .= ready
          ]

      MsgRejected requestId code messageText ->
        object
          [ "type" .= ("CommandRejected" :: String)
          , "requestId" .= requestId
          , "code" .= code
          , "message" .= messageText
          ]