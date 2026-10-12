-- | Các kiểu dữ liệu miền của trò chơi sẽ được chốt trong T02.
module Domain.Types where

type PlayerId = String

-- Mỗi role thuộc đúng 1 Team; phe được suy ra từ Role.
data Role = Werewolf | Seer | Guard | Witch | Hunter | Villager
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

data Team = Wolves | Village
  deriving (Eq, Ord, Show, Read)

teamOfRole :: Role -> Team
teamOfRole Werewolf = Wolves
teamOfRole _        = Village

data Phase = Lobby | Night | Day | Voting | GameOver
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

data LifeStatus = Alive | Dead
  deriving (Eq, Show, Read)

-- Kết nối thực tế do Server quản lý; Domain không chứa socket.
data ConnectionStatus = Connected | Disconnected
  deriving (Eq, Show, Read)

-- Trong Lobby, playerRole = Nothing. Sau StartGame = Just role.
data Player = Player
  { playerId         :: PlayerId
  , playerName       :: String
  , playerRole       :: Maybe Role
  , playerReady      :: Bool
  , playerLifeStatus :: LifeStatus
  } deriving (Eq, Show, Read)

-- DTO cho UI; Server ghép ConnectionStatus khi tạo snapshot.
data LobbyMember = LobbyMember
  { lobbyMemberId         :: PlayerId
  , lobbyMemberName       :: String
  , lobbyMemberReady      :: Bool
  , lobbyMemberConnection :: ConnectionStatus
  } deriving (Eq, Show, Read)

-- Draw khác với Nothing (game chưa kết thúc).
data GameResult = Winner Team | Draw
  deriving (Eq, Show, Read)

-- LowestPlayerId là biến thể cũ; Validation phải từ chối.
data TiePolicy = NoElimination | LowestPlayerId
  deriving (Eq, Show, Read)

-- Witch chỉ một action / đêm. HunterShot chỉ hợp lệ khi pending.
data NightChoice
  = WolfTarget PlayerId
  | SeerTarget PlayerId
  | GuardTarget PlayerId
  | WitchHeal
  | WitchPoison PlayerId
  | WitchPass
  | HunterShot PlayerId
  | HunterPass
  | NoAction
  deriving (Eq, Show, Read)

-- T02 định nghĩa lệnh; T03--T07 thực thi state transition.
-- Resolve* và AdvancePhase chỉ do Server nội bộ gọi sau authorization.
data Command
  = Join PlayerId String
  | Leave PlayerId
  | SetReady PlayerId Bool
  | StartGame PlayerId [Role]
  | AdvancePhase
  | NightAction PlayerId NightChoice
  | Vote PlayerId PlayerId
  | Chat PlayerId String
  | ResolveNight
  | ResolveVoting
  | ResolveHunter PlayerId (Maybe PlayerId)
  deriving (Eq, Show, Read)

data GameError
  = InvalidPlayerId | InvalidPlayerName
  | DuplicatePlayerId | DuplicatePlayerName
  | InvalidPlayerCount | NotAllReady | NotAuthorized
  | WrongPhase | DeadPlayer | PlayerNotFound | InvalidTarget
  | AlreadyVoted | GameAlreadyStarted | GameAlreadyOver
  | RoomFull | InvalidRole | InvalidCommand | InvalidNightAction
  | InvalidRoleConfiguration | InvalidGameState
  | AbilityAlreadyUsed | HunterNotPending | InvalidTiePolicy
  | DuplicateNightAction | EmptyChat | NotReady
  deriving (Eq, Show, Read)

data EventVisibility = Public | Private PlayerId
  deriving (Eq, Show)

-- Sự kiện là contract; T03/Server quyết định nội dung snapshot và delivery.
-- Không broadcast event Private đến tất cả client.
data DomainEvent
  = PlayerJoined PlayerId
  | PlayerJoinedDetailed PlayerId String Bool
  | PlayerLeft PlayerId
  | HostChanged PlayerId
  | ReadyChanged PlayerId Bool
  | LobbyUpdated [LobbyMember]
  | GameStarted
  | PhaseChanged Phase
  | PlayerRoleAssigned PlayerId Role
  | NightActionAccepted PlayerId
  | SeerResult PlayerId Team
  | WitchVictimNotice PlayerId (Maybe PlayerId)
  | NightResolved [PlayerId]
  | VoteUpdated PlayerId PlayerId
  | PlayerEliminated PlayerId
  | PlayerRoleRevealed PlayerId Role Team
  | HunterShotPending PlayerId
  | HunterShotResolved PlayerId (Maybe PlayerId)
  | GameEnded Team
  | GameFinished GameResult
  | ChatMessage PlayerId String
  deriving (Eq, Show)

eventVisibility :: DomainEvent -> EventVisibility
eventVisibility event =
  case event of
    PlayerRoleAssigned pid _ -> Private pid
    SeerResult pid _         -> Private pid
    NightActionAccepted pid  -> Private pid
    VoteUpdated voter _      -> Private voter
    HunterShotPending pid    -> Private pid
    WitchVictimNotice pid _ -> Private pid
    _                        -> Public

-- Dữ liệu trạng thái nghiệp vụ; không chứa connection/socket.
data GameState = GameState
  { gamePlayers          :: [Player]
  , gameHost             :: PlayerId
  , gamePhase            :: Phase
  , gameDay              :: Int
  , gameVotes            :: [(PlayerId, PlayerId)]
  , gameNightActions     :: [(PlayerId, NightChoice)]
  , gameWolfVotingClosed :: Bool
  , gameConfiguredRoles  :: [Role]
  , gameWolfTiePolicy    :: TiePolicy
  , gameVoteTiePolicy    :: TiePolicy
  , gameWitchHealReady   :: Bool
  , gameWitchPoisonReady :: Bool
  , gameLastProtected    :: Maybe PlayerId
  , gamePendingReveals   :: [PlayerId]
  , gamePendingHunter    :: Maybe PlayerId
  , gameHunterTriggered  :: Bool
  , gameNightResolved    :: Bool
  , gameVotingResolved   :: Bool
  , gameResult           :: Maybe GameResult
  } deriving (Eq, Show)

-- Trạng thái khởi tạo cho room. T03 thực thi Join và gán Host đầu tiên.
emptyLobby :: GameState
emptyLobby = GameState
  { gamePlayers = []
  , gameHost = ""
  , gamePhase = Lobby
  , gameDay = 0
  , gameVotes = []
  , gameNightActions = []
  , gameWolfVotingClosed = False
  , gameConfiguredRoles = []
  , gameWolfTiePolicy = NoElimination
  , gameVoteTiePolicy = NoElimination
  , gameWitchHealReady = True
  , gameWitchPoisonReady = True
  , gameLastProtected = Nothing
  , gamePendingReveals = []
  , gamePendingHunter = Nothing
  , gameHunterTriggered = False
  , gameNightResolved = False
  , gameVotingResolved = False
  , gameResult = Nothing
  }

-- Dùng callback từ Server để thêm thông tin kết nối vào Lobby snapshot.
makeLobbyMembers :: GameState -> (PlayerId -> ConnectionStatus) -> [LobbyMember]
makeLobbyMembers game connectionOf =
  [ LobbyMember
      (playerId p)
      (playerName p)
      (playerReady p)
      (connectionOf (playerId p))
  | p <- gamePlayers game
  ]