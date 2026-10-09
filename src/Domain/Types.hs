-- | Các kiểu dữ liệu miền của trò chơi sẽ được chốt trong T02.
module Domain.Types where

-- ID người chơi
type PlayerId = String

-- Vai trò trong game
data Role
  = Werewolf
  | Seer
  | Guard
  | Witch
  | Hunter
  | Villager
  deriving (Eq, Show, Read, Enum, Bounded)

-- Phe của người chơi
data Team = Wolves | Village
  deriving (Eq, Show, Read)

-- Giai đoạn của game
data Phase = Lobby | Night | Day | Voting | GameOver
  deriving (Eq, Show, Read, Enum, Bounded)

-- Trạng thái sống
data LifeStatus = Alive | Dead
  deriving (Eq, Show, Read)

-- Thông tin một người chơi
data Player = Player
  { playerId         :: PlayerId
  , playerName       :: String
  , playerRole       :: Maybe Role
  , playerReady      :: Bool
  , playerLifeStatus :: LifeStatus
  } deriving (Eq, Show)

-- Chính sách xử lý hòa
data TiePolicy = NoElimination | LowestPlayerId
  deriving (Eq, Show, Read)

-- Lựa chọn ban đêm
data NightChoice
  = WolfTarget PlayerId
  | SeerTarget PlayerId
  | GuardTarget PlayerId
  | WitchHeal
  | WitchPoison PlayerId
  | WitchPass
  | NoAction
  deriving (Eq, Show, Read)

-- Lệnh gửi đến Domain Engine
data Command
  = Join PlayerId String
  | Leave PlayerId
  | SetReady PlayerId Bool
  | StartGame PlayerId
  | AdvancePhase
  | NightAction PlayerId NightChoice
  | Vote PlayerId PlayerId
  | Chat PlayerId String
  deriving (Eq, Show, Read)

-- Lỗi xử lý lệnh
data GameError
  = InvalidPlayerId
  | InvalidPlayerName
  | DuplicatePlayerId
  | DuplicatePlayerName
  | InvalidPlayerCount
  | NotAllReady
  | NotAuthorized
  | WrongPhase
  | DeadPlayer
  | PlayerNotFound
  | InvalidTarget
  | AlreadyVoted
  | GameAlreadyStarted
  | GameAlreadyOver
  | RoomFull
  | InvalidRole
  | InvalidCommand
  | InvalidNightAction
  | InvalidRoleConfiguration
  deriving (Eq, Show, Read)

-- Mức độ hiển thị của sự kiện
data EventVisibility = Public | Private PlayerId
  deriving (Eq, Show)

-- Sự kiện Domain tạo ra
data DomainEvent
  = PlayerJoined PlayerId
  | PlayerLeft PlayerId
  | ReadyChanged PlayerId Bool
  | GameStarted
  | PhaseChanged Phase
  | PlayerRoleAssigned PlayerId Role
  | NightActionAccepted PlayerId
  | SeerResult PlayerId Team
  | NightResolved [PlayerId]
  | VoteUpdated PlayerId PlayerId
  | PlayerEliminated PlayerId
  | GameEnded Team
  | ChatMessage PlayerId String
  deriving (Eq, Show)

-- Trạng thái đầy đủ của ván đấu
data GameState = GameState
  { gamePlayers          :: [Player]
  , gameHost             :: PlayerId
  , gamePhase            :: Phase
  , gameDay              :: Int
  , gameVotes            :: [(PlayerId, PlayerId)]
  , gameNightActions     :: [(PlayerId, NightChoice)]
  , gameConfiguredRoles  :: [Role]
  , gameWolfTiePolicy    :: TiePolicy
  , gameVoteTiePolicy    :: TiePolicy
  , gameWitchHealReady   :: Bool
  , gameWitchPoisonReady :: Bool
  , gameLastProtected    :: Maybe PlayerId
  } deriving (Eq, Show)

-- Xác định sự kiện được gửi công khai hay riêng tư
eventVisibility :: DomainEvent -> EventVisibility
eventVisibility (PlayerRoleAssigned pid _) = Private pid
eventVisibility (SeerResult pid _)         = Private pid
eventVisibility _                          = Public
