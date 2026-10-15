
{-# LANGUAGE OverloadedStrings #-}

-- | Contract Command va Event dung chung giua frontend va server.
module Protocol.Types where

import Domain.Types
  ( Appearance(..)
  , NightChoice(..)
  , Role(..)
  , Team(..)
  , Phase(..)
  , GameResult(..)
  )

import Domain.Types
  ( RoleAbilityInfo
      ( abilityDescription
      , abilityPhase
      , abilityTargetRules
      )
  , roleAbilityInfo
  )

import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , Value
  , (.:)
  , (.:?)
  , (.=)
  , object
  , withObject
  )

import Data.Aeson.Types (Parser)

type RequestId = String
type RoomId = String

-- Lenh nhan tu Browser.
-- PlayerId va Role phai do Server xac dinh.
data ClientMessage
  = ClientCreateRoom RequestId RoomId String
  | ClientCreateRoomWithAppearance RequestId RoomId String Appearance
  | ClientJoin RequestId RoomId String
  | ClientJoinWithAppearance RequestId RoomId String Appearance
  | ClientLeave RequestId RoomId
  | ClientSetReady RequestId RoomId Bool
  | ClientStartGame RequestId RoomId
  | ClientNightAction RequestId RoomId NightChoice
  -- T06: Browser chi gui targetId; PlayerId voter lay tu session Server.
  | ClientVote RequestId RoomId String
  | ClientHunterAction RequestId RoomId NightChoice
  deriving (Eq, Show)

-- Thong tin Player cong khai.
-- Khong chua Role hoac Team.
data PlayerView = PlayerView
  { viewPlayerId :: String
  , viewDisplayName :: String
  , viewReady :: Bool
  , viewAlive :: Bool
  , viewAppearance :: Appearance
  } deriving (Eq, Show)

-- T06: Snapshot chi chua thong tin cong khai.
data VotingPlayerView = VotingPlayerView String String Bool
  deriving (Eq, Show)

instance ToJSON VotingPlayerView where
  toJSON (VotingPlayerView pid name alive) =
    object
      [ "playerId" .= pid
      , "displayName" .= name
      , "alive" .= alive
      ]

instance FromJSON VotingPlayerView where
  parseJSON = withObject "VotingPlayerView" $ \obj ->
    VotingPlayerView
      <$> obj .: "playerId"
      <*> obj .: "displayName"
      <*> obj .: "alive"

-- Tin Server gui ve Browser.
data ServerMessage
  = MsgLobbySnapshot RoomId String String [PlayerView]
  | MsgPlayerJoined RoomId PlayerView
  | MsgPlayerLeft RoomId String
  | MsgHostChanged RoomId String
  | MsgReadyChanged RoomId String Bool
  | MsgRejected (Maybe RequestId) String String

  -- StartGame: Role chi duoc gui rieng cho chu so huu.
  | MsgYourRole RoomId Role

  -- T05: Night Server Events.
  | MsgNightActionAccepted RoomId
  | MsgSeerResult RoomId Team
  | MsgWitchVictimNotice RoomId (Maybe String)
  | MsgHunterShotPending RoomId
  | MsgHunterShotResolved RoomId String (Maybe String)
  
  | MsgNightResolved RoomId [String]

  -- Contract cu, giu tam thoi de khong pha test T05/T06.
  -- Broadcast se khong gui RoleReveal khi nguoi choi chet.
  | MsgPlayerRoleRevealed RoomId String Role Team

  -- T02: Chi thong bao PlayerId khi nguoi choi chet.
  | MsgPlayerDied RoomId String

  -- T02: Chi cong khai toan bo Role khi GameOver.
  | MsgGameRolesRevealed RoomId [(String, Role)]

  | MsgPhaseChanged RoomId Phase
  | MsgGameFinished RoomId GameResult


  -- T06: Vote receipt private va death result public/private.
  | MsgVoteUpdated RoomId
  | MsgPlayerEliminated RoomId String
  | MsgVotingResolved RoomId [(String, Int)] (Maybe String)
  | MsgActionAccepted RequestId RoomId

  -- hasVoted/canShoot duoc tinh rieng cho nguoi nhan.
  | MsgVotingSnapshot RoomId Phase Int [VotingPlayerView] Bool Bool Bool (Maybe GameResult)
  deriving (Eq, Show)

-- Doc NightChoice ma khong tao orphan FromJSON instance.
-- HunterShot va HunterPass dung thong diep HunterAction rieng.
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

-- Doc lua chon Hunter rieng.
parseHunterChoice :: Value -> Parser NightChoice
parseHunterChoice = withObject "HunterChoice" $ \obj -> do
  actionType <- obj .: "action" :: Parser String
  case actionType of
    "HunterShot" -> HunterShot <$> obj .: "targetId"
    "HunterPass" -> pure HunterPass
    _ -> fail ("Hunter action khong hop le: " ++ actionType)

-- Ghi NightChoice thanh JSON.
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

-- Appearance: JSON theo cau truc frontend T07.
parseAppearance :: Value -> Parser Appearance
parseAppearance = withObject "Appearance" $ \obj ->
  Appearance
    <$> obj .: "hair"
    <*> obj .: "hairColor"
    <*> obj .: "skin"
    <*> obj .: "outfit"
    <*> obj .: "accessory"

appearanceToJSON :: Appearance -> Value
appearanceToJSON appearance =
  object
    [ "hair" .= appearanceHair appearance
    , "hairColor" .= appearanceHairColor appearance
    , "skin" .= appearanceSkin appearance
    , "outfit" .= appearanceOutfit appearance
    , "accessory" .= appearanceAccessory appearance
    ]

-- ClientMessage: FromJSON.
instance FromJSON ClientMessage where
  parseJSON = withObject "ClientMessage" $ \obj -> do
    messageType <- obj .: "type" :: Parser String
    requestId <- obj .: "requestId"
    roomId <- obj .: "roomId"

    case messageType of
      "CreateRoom" -> do
        name <- obj .: "playerName"
        maybeAppearance <- obj .:? "appearance"
        case maybeAppearance of
          Nothing ->
            pure (ClientCreateRoom requestId roomId name)
          Just appearanceValue -> do
            appearance <- parseAppearance appearanceValue
            pure
              (ClientCreateRoomWithAppearance
                requestId roomId name appearance)

      "JoinGame" -> do
        name <- obj .: "playerName"
        maybeAppearance <- obj .:? "appearance"
        case maybeAppearance of
          Nothing ->
            pure (ClientJoin requestId roomId name)
          Just appearanceValue -> do
            appearance <- parseAppearance appearanceValue
            pure
              (ClientJoinWithAppearance
                requestId roomId name appearance)

      "LeaveGame" ->
        pure (ClientLeave requestId roomId)

      "SetReady" ->
        ClientSetReady requestId roomId
          <$> obj .: "ready"

      "StartGame" ->
        pure (ClientStartGame requestId roomId)

      "NightAction" -> do
        choiceValue <- obj .: "choice"
        choice <- parseNightChoice choiceValue
        pure (ClientNightAction requestId roomId choice)

      "Vote" ->
        ClientVote requestId roomId <$> obj .: "targetId"

      "HunterAction" -> do
        choiceValue <- obj .: "choice"
        choice <- parseHunterChoice choiceValue
        pure (ClientHunterAction requestId roomId choice)

      _ ->
        fail ("Loai command khong ho tro: " ++ messageType)

-- ClientMessage: ToJSON.
instance ToJSON ClientMessage where
  toJSON message =
    case message of
      -- CreateRoom cu: khong gui Appearance.
      ClientCreateRoom requestId roomId playerName ->
        object
          [ "type" .= ("CreateRoom" :: String)
          , "requestId" .= requestId
          , "roomId" .= roomId
          , "playerName" .= playerName
          ]

      -- CreateRoom moi: gui Appearance.
      ClientCreateRoomWithAppearance requestId roomId playerName appearance ->
        object
          [ "type" .= ("CreateRoom" :: String)
          , "requestId" .= requestId
          , "roomId" .= roomId
          , "playerName" .= playerName
          , "appearance" .= appearanceToJSON appearance
          ]

      -- JoinGame cu: khong gui Appearance.
      ClientJoin requestId roomId playerName ->
        object
          [ "type" .= ("JoinGame" :: String)
          , "requestId" .= requestId
          , "roomId" .= roomId
          , "playerName" .= playerName
          ]

      -- JoinGame moi: gui Appearance.
      ClientJoinWithAppearance requestId roomId playerName appearance ->
        object
          [ "type" .= ("JoinGame" :: String)
          , "requestId" .= requestId
          , "roomId" .= roomId
          , "playerName" .= playerName
          , "appearance" .= appearanceToJSON appearance
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

      ClientStartGame requestId roomId ->
        object
          [ "type" .= ("StartGame" :: String)
          , "requestId" .= requestId
          , "roomId" .= roomId
          ]

      ClientNightAction requestId roomId choice ->
        object
          [ "type" .= ("NightAction" :: String)
          , "requestId" .= requestId
          , "roomId" .= roomId
          , "choice" .= nightChoiceToJSON choice
          ]

      ClientHunterAction requestId roomId choice ->
        object
          [ "type" .= ("HunterAction" :: String)
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

-- PlayerView: FromJSON va ToJSON.
instance FromJSON PlayerView where
  parseJSON = withObject "PlayerView" $ \obj -> do
    pid <- obj .: "playerId"
    name <- obj .: "displayName"
    ready <- obj .: "ready"
    alive <- obj .: "alive"
    appearanceValue <- obj .: "appearance"
    appearance <- parseAppearance appearanceValue
    pure (PlayerView pid name ready alive appearance)

instance ToJSON PlayerView where
  toJSON player =
    object
      [ "playerId" .= viewPlayerId player
      , "displayName" .= viewDisplayName player
      , "ready" .= viewReady player
      , "alive" .= viewAlive player
      , "appearance" .= appearanceToJSON (viewAppearance player)
      ]

-- ServerMessage: FromJSON.
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

      "YourRole" -> do
        roomId <- obj .: "roomId"
        roleText <- obj .: "role"
        role <- parseRole roleText
        pure (MsgYourRole roomId role)

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

      "HunterShotPending" ->
        MsgHunterShotPending <$> obj .: "roomId"

      "HunterShotResolved" ->
        MsgHunterShotResolved
          <$> obj .: "roomId"
          <*> obj .: "hunterId"
          <*> obj .: "targetId"

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

        
      -- T02: Nguoi chet chi cong khai PlayerId.
      "PlayerDied" ->
        MsgPlayerDied
          <$> obj .: "roomId"
          <*> obj .: "playerId"

      -- T02: Chi doc danh sach Role khi GameOver.
      "GameRolesRevealed" -> do
        roomId <- obj .: "roomId"
        entries <- obj .: "roles"

        roles <- mapM
          (withObject "RevealedRole" $ \entry -> do
            pid <- entry .: "playerId"
            roleText <- entry .: "role"
            role <- parseRole roleText
            pure (pid, role))
          entries

        pure (MsgGameRolesRevealed roomId roles)

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

      "ActionAccepted" ->
        MsgActionAccepted
          <$> obj .: "requestId"
          <*> obj .: "roomId"

      "VotingResolved" ->
        MsgVotingResolved
          <$> obj .: "roomId"
          <*> obj .: "tally"
          <*> obj .: "targetId"

      "VotingSnapshot" -> do
        phase <- obj .: "phase" >>= parsePhase
        result <- obj .: "result" >>= traverse parseGameResult
        MsgVotingSnapshot
          <$> obj .: "roomId"
          <*> pure phase
          <*> obj .: "day"
          <*> obj .: "players"
          <*> obj .: "hasVoted"
          <*> obj .: "canShoot"
          <*> obj .: "resolved"
          <*> pure result

      "PlayerEliminated" ->
        MsgPlayerEliminated
          <$> obj .: "roomId"
          <*> obj .: "playerId"

      _ ->
        fail ("Loai server message khong ho tro: " ++ messageType)

-- ServerMessage: ToJSON.
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

      MsgYourRole roomId role ->
        let info = roleAbilityInfo role
        in object
          [ "type" .= ("YourRole" :: String)
          , "roomId" .= roomId
          , "role" .= show role
          , "ability" .= object
              [ "description" .= abilityDescription info
              , "phase" .= fmap show (abilityPhase info)
              , "targetRules" .= abilityTargetRules info
              ]
          ]

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

      MsgHunterShotPending roomId ->
        object
          [ "type" .= ("HunterShotPending" :: String)
          , "roomId" .= roomId
          ]

      MsgHunterShotResolved roomId hunterId targetId ->
        object
          [ "type" .= ("HunterShotResolved" :: String)
          , "roomId" .= roomId
          , "hunterId" .= hunterId
          , "targetId" .= targetId
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

      
      -- T02: Thong bao nguoi chet, khong gui Role/Team.
      MsgPlayerDied roomId playerId ->
        object
          [ "type" .= ("PlayerDied" :: String)
          , "roomId" .= roomId
          , "playerId" .= playerId
          ]

      -- T02: Cong khai danh sach Role khi van choi ket thuc.
      MsgGameRolesRevealed roomId roles ->
        object
          [ "type" .= ("GameRolesRevealed" :: String)
          , "roomId" .= roomId
          , "roles" .=
              [ object
                  [ "playerId" .= pid
                  , "role" .= show role
                  ]
              | (pid, role) <- roles
              ]
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

      -- T06: Khong leak voter/target qua VoteUpdated.
      MsgVoteUpdated roomId ->
        object
          [ "type" .= ("VoteUpdated" :: String)
          , "roomId" .= roomId
          ]

      MsgActionAccepted requestId roomId ->
        object
          [ "type" .= ("ActionAccepted" :: String)
          , "requestId" .= requestId
          , "roomId" .= roomId
          ]

      MsgVotingResolved roomId tally targetId ->
        object
          [ "type" .= ("VotingResolved" :: String)
          , "roomId" .= roomId
          , "tally" .= tally
          , "targetId" .= targetId
          ]

      MsgVotingSnapshot roomId phase day players hasVoted canShoot resolved result ->
        object
          [ "type" .= ("VotingSnapshot" :: String)
          , "roomId" .= roomId
          , "phase" .= show phase
          , "day" .= day
          , "players" .= players
          , "hasVoted" .= hasVoted
          , "canShoot" .= canShoot
          , "resolved" .= resolved
          , "result" .= fmap gameResultText result
          ]

      MsgPlayerEliminated roomId playerId ->
        object
          [ "type" .= ("PlayerEliminated" :: String)
          , "roomId" .= roomId
          , "playerId" .= playerId
          ]
