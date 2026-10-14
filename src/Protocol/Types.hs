
{-# LANGUAGE OverloadedStrings #-}

-- | Contract Command va Event dung chung giua frontend va server.
module Protocol.Types where

import Domain.Types
  ( NightChoice(..)
  , Role(..)
  , Team(..)
  , Phase(..)
  , GameResult(..)
  )
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , Value
  , (.:)
  , (.=)
  , object
  , withObject
  )
import Data.Aeson.Types (Parser)

type RequestId = String
type RoomId = String

-- Lenh nhan tu Browser. Khong co PlayerId hoac Role.
-- Server phai lay PlayerId tu phien ket noi da xac thuc.
data ClientMessage
  = ClientCreateRoom RequestId RoomId String
  | ClientJoin RequestId RoomId String
  | ClientLeave RequestId RoomId
  | ClientSetReady RequestId RoomId Bool
  | ClientNightAction RequestId RoomId NightChoice
  -- T06: Browser chỉ gửi targetId; PlayerId voter lấy từ session Server.
  | ClientVote RequestId RoomId String
  -- null là Hunter bỏ qua; không nhận actor/role do Browser khai báo.
  | ClientHunterChoice RequestId RoomId (Maybe String)
  deriving (Eq, Show)

-- Mot nguoi trong danh sach Lobby gui cho Browser.
data PlayerView = PlayerView
  { viewPlayerId :: String
  , viewDisplayName :: String
  , viewReady :: Bool
  } deriving (Eq, Show)

-- T06: Snapshot chỉ chứa thông tin công khai, không đưa vai sống lên mạng.
data VotingPlayerView = VotingPlayerView String String Bool
  deriving (Eq, Show)

instance ToJSON VotingPlayerView where
  toJSON (VotingPlayerView pid name alive) = object
    ["playerId" .= pid, "displayName" .= name, "alive" .= alive]

instance FromJSON VotingPlayerView where
  parseJSON = withObject "VotingPlayerView" $ \obj ->
    VotingPlayerView <$> obj .: "playerId" <*> obj .: "displayName" <*> obj .: "alive"

-- Tin Server gui ve Browser.
data ServerMessage
  = MsgLobbySnapshot RoomId String String [PlayerView]
  | MsgPlayerJoined RoomId PlayerView
  | MsgPlayerLeft RoomId String
  | MsgHostChanged RoomId String
  | MsgReadyChanged RoomId String Bool
  | MsgRejected (Maybe RequestId) String String

  -- T05: Night Server Events.
  | MsgNightActionAccepted RoomId
  | MsgSeerResult RoomId Team
  | MsgWitchVictimNotice RoomId (Maybe String)
  | MsgNightResolved RoomId [String]
  | MsgPlayerRoleRevealed RoomId String Role Team
  | MsgPhaseChanged RoomId Phase
  | MsgGameFinished RoomId GameResult

  -- T06: Vote receipt private và death result public/private theo event.
  | MsgVoteUpdated RoomId
  | MsgPlayerEliminated RoomId String
  | MsgHunterShotPending RoomId
  | MsgHunterShotResolved RoomId (Maybe String)
  | MsgVotingResolved RoomId [(String, Int)] (Maybe String)
  | MsgActionAccepted RequestId RoomId
  -- hasVoted/canShoot được tính riêng cho người nhận, không cho xem phiếu người khác.
  | MsgVotingSnapshot RoomId Phase Int [VotingPlayerView] Bool Bool Bool (Maybe GameResult)
  deriving (Eq, Show)

-- Doc NightChoice ma khong tao orphan FromJSON instance.
-- HunterShot va HunterPass duoc xu ly boi luong T06 rieng.
parseNightChoice :: Value -> Parser NightChoice
parseNightChoice = withObject "NightChoice" $ \obj -> do
  actionType <- obj .: "action" :: Parser String
  case actionType of
    "WolfTarget" ->
      WolfTarget <$> obj .: "targetId"

    "SeerTarget" ->
      SeerTarget <$> obj .: "targetId"

    "GuardTarget" ->
      GuardTarget <$> obj .: "targetId"

    "WitchHeal" ->
      pure WitchHeal

    "WitchPoison" ->
      WitchPoison <$> obj .: "targetId"

    "WitchPass" ->
      pure WitchPass

    "NoAction" ->
      pure NoAction

    _ ->
      fail ("Night action khong hop le: " ++ actionType)

-- Ghi NightChoice thanh JSON.
-- Bao phu tat ca constructor de -Wall khong canh bao.
-- Viec ghi HunterShot/HunterPass khong co nghia
-- Browser duoc phep gui qua T05.
nightChoiceToJSON :: NightChoice -> Value
nightChoiceToJSON choice =
  case choice of
    WolfTarget target ->
      actionWithTarget "WolfTarget" target

    SeerTarget target ->
      actionWithTarget "SeerTarget" target

    GuardTarget target ->
      actionWithTarget "GuardTarget" target

    WitchHeal ->
      actionWithoutTarget "WitchHeal"

    WitchPoison target ->
      actionWithTarget "WitchPoison" target

    WitchPass ->
      actionWithoutTarget "WitchPass"

    HunterShot target ->
      actionWithTarget "HunterShot" target

    HunterPass ->
      actionWithoutTarget "HunterPass"

    NoAction ->
      actionWithoutTarget "NoAction"
  where
    actionWithTarget actionName target =
      object
        [ "action" .= (actionName :: String)
        , "targetId" .= target
        ]

    actionWithoutTarget actionName =
      object
        [ "action" .= (actionName :: String)
        ]

-- Doc Role tu JSON.
parseRole :: String -> Parser Role
parseRole value =
  case value of
    "Werewolf" -> pure Werewolf
    "Seer" -> pure Seer
    "Guard" -> pure Guard
    "Witch" -> pure Witch
    "Hunter" -> pure Hunter
    "Villager" -> pure Villager
    _ -> fail ("Role khong hop le: " ++ value)

-- Doc Team tu JSON.
parseTeam :: String -> Parser Team
parseTeam value =
  case value of
    "Wolves" -> pure Wolves
    "Village" -> pure Village
    _ -> fail ("Team khong hop le: " ++ value)

-- Doc Phase tu JSON.
parsePhase :: String -> Parser Phase
parsePhase value =
  case value of
    "Lobby" -> pure Lobby
    "Night" -> pure Night
    "Day" -> pure Day
    "Voting" -> pure Voting
    "GameOver" -> pure GameOver
    _ -> fail ("Phase khong hop le: " ++ value)

-- Doc GameResult tu JSON.
parseGameResult :: String -> Parser GameResult
parseGameResult value =
  case value of
    "Draw" -> pure Draw
    "WinnerWolves" -> pure (Winner Wolves)
    "WinnerVillage" -> pure (Winner Village)
    _ -> fail ("GameResult khong hop le: " ++ value)

-- Ghi GameResult thanh chuoi JSON.
gameResultText :: GameResult -> String
gameResultText result =
  case result of
    Draw -> "Draw"
    Winner Wolves -> "WinnerWolves"
    Winner Village -> "WinnerVillage"

-- ClientMessage: FromJSON

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

      "NightAction" -> do
        choiceValue <- obj .: "choice"
        choice <- parseNightChoice choiceValue
        pure (ClientNightAction requestId roomId choice)

      "Vote" ->
        ClientVote requestId roomId <$> obj .: "targetId"

      "HunterChoice" ->
        ClientHunterChoice requestId roomId <$> obj .: "targetId"

      _ ->
        fail ("Loai command khong ho tro: " ++ messageType)

-- ClientMessage: ToJSON

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

      ClientNightAction requestId roomId choice ->
        object
          [ "type" .= ("NightAction" :: String)
          , "requestId" .= requestId
          , "roomId" .= roomId
          , "choice" .= nightChoiceToJSON choice
          ]

      ClientVote requestId roomId targetId ->
        object
          [ "type" .= ("Vote" :: String)
          , "requestId" .= requestId
          , "roomId" .= roomId
          , "targetId" .= targetId
          ]

      ClientHunterChoice requestId roomId targetId -> object
        [ "type" .= ("HunterChoice" :: String), "requestId" .= requestId
        , "roomId" .= roomId, "targetId" .= targetId ]

-- PlayerView: FromJSON va ToJSON

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


-- ServerMessage: FromJSON

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

      -- T05: Night Events.

      "NightActionAccepted" ->
        MsgNightActionAccepted <$> obj .: "roomId"

      "SeerResult" -> do
        roomId <- obj .: "roomId"
        teamText <- obj .: "team"
        team <- parseTeam teamText
        pure (MsgSeerResult roomId team)

      "WitchVictimNotice" ->
        MsgWitchVictimNotice
          <$> obj .: "roomId"
          <*> obj .: "victimId"

      "NightResolved" ->
        MsgNightResolved
          <$> obj .: "roomId"
          <*> obj .: "deaths"

      "PlayerRoleRevealed" -> do
        roomId <- obj .: "roomId"
        playerId <- obj .: "playerId"
        roleText <- obj .: "role"
        teamText <- obj .: "team"
        role <- parseRole roleText
        team <- parseTeam teamText
        pure (MsgPlayerRoleRevealed roomId playerId role team)

      "PhaseChanged" -> do
        roomId <- obj .: "roomId"
        phaseText <- obj .: "phase"
        phase <- parsePhase phaseText
        pure (MsgPhaseChanged roomId phase)

      "GameFinished" -> do
        roomId <- obj .: "roomId"
        resultText <- obj .: "result"
        result <- parseGameResult resultText
        pure (MsgGameFinished roomId result)

      "VoteUpdated" ->
        MsgVoteUpdated <$> obj .: "roomId"

      "ActionAccepted" -> MsgActionAccepted <$> obj .: "requestId" <*> obj .: "roomId"

      "VotingResolved" ->
        MsgVotingResolved <$> obj .: "roomId" <*> obj .: "tally" <*> obj .: "targetId"

      "VotingSnapshot" -> do
        phase <- obj .: "phase" >>= parsePhase
        result <- obj .: "result" >>= traverse parseGameResult
        MsgVotingSnapshot <$> obj .: "roomId" <*> pure phase <*> obj .: "day"
          <*> obj .: "players" <*> obj .: "hasVoted" <*> obj .: "canShoot"
          <*> obj .: "resolved" <*> pure result

      "PlayerEliminated" ->
        MsgPlayerEliminated <$> obj .: "roomId" <*> obj .: "playerId"

      "HunterShotPending" ->
        MsgHunterShotPending <$> obj .: "roomId"

      "HunterShotResolved" ->
        MsgHunterShotResolved <$> obj .: "roomId" <*> obj .: "targetId"

      _ ->
        fail ("Loai server message khong ho tro: " ++ messageType)

-- ServerMessage: ToJSON

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

      -- T05: Night Events.

      MsgNightActionAccepted roomId ->
        object
          [ "type" .= ("NightActionAccepted" :: String)
          , "roomId" .= roomId
          ]

      MsgSeerResult roomId team ->
        object
          [ "type" .= ("SeerResult" :: String)
          , "roomId" .= roomId
          , "team" .= show team
          ]

      MsgWitchVictimNotice roomId victim ->
        object
          [ "type" .= ("WitchVictimNotice" :: String)
          , "roomId" .= roomId
          , "victimId" .= victim
          ]

      MsgNightResolved roomId deaths ->
        object
          [ "type" .= ("NightResolved" :: String)
          , "roomId" .= roomId
          , "deaths" .= deaths
          ]

      MsgPlayerRoleRevealed roomId playerId role team ->
        object
          [ "type" .= ("PlayerRoleRevealed" :: String)
          , "roomId" .= roomId
          , "playerId" .= playerId
          , "role" .= show role
          , "team" .= show team
          ]

      MsgPhaseChanged roomId phase ->
        object
          [ "type" .= ("PhaseChanged" :: String)
          , "roomId" .= roomId
          , "phase" .= show phase
          ]

      MsgGameFinished roomId result ->
        object
          [ "type" .= ("GameFinished" :: String)
          , "roomId" .= roomId
          , "result" .= gameResultText result
          ]

      -- T06: VoteUpdated không chứa voter/target, vì event gốc đã được lọc
      -- chỉ đến đúng voter và không được leak lựa chọn cho phòng.
      MsgVoteUpdated roomId ->
        object
          [ "type" .= ("VoteUpdated" :: String)
          , "roomId" .= roomId
          ]

      MsgActionAccepted requestId roomId -> object
        ["type" .= ("ActionAccepted" :: String), "requestId" .= requestId, "roomId" .= roomId]

      MsgVotingResolved roomId tally targetId -> object
        [ "type" .= ("VotingResolved" :: String), "roomId" .= roomId
        , "tally" .= tally, "targetId" .= targetId ]

      MsgVotingSnapshot roomId phase day players hasVoted canShoot resolved result -> object
        [ "type" .= ("VotingSnapshot" :: String), "roomId" .= roomId
        , "phase" .= show phase, "day" .= day, "players" .= players
        , "hasVoted" .= hasVoted, "canShoot" .= canShoot, "resolved" .= resolved
        , "result" .= fmap gameResultText result ]

      MsgPlayerEliminated roomId playerId ->
        object
          [ "type" .= ("PlayerEliminated" :: String)
          , "roomId" .= roomId
          , "playerId" .= playerId
          ]

      MsgHunterShotPending roomId ->
        object
          [ "type" .= ("HunterShotPending" :: String)
          , "roomId" .= roomId
          ]

      MsgHunterShotResolved roomId targetId ->
        object
          [ "type" .= ("HunterShotResolved" :: String)
          , "roomId" .= roomId
          , "targetId" .= targetId
          ]
