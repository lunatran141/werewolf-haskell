-- | Các kiểu dữ liệu miền của trò chơi sẽ được chốt trong T02.

module Domain.Types where

type PlayerId = String

-- Mỗi role thuốc đúng 1 Team; phe được suy ra từ Role.
data Role = Werewolf | Seer | Guard | Witch | Hunter | Villager
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

data Team = Wolves | Village deriving (Eq, Ord, Show, Read)

teamOfRole :: Role -> Team
teamOfRole Werewolf = Wolves
teamOfRole _        = Village

data Phase = Lobby | Night | Day | Voting | GameOver
  deriving (Eq, Ord, Show, Read, Enum, Bounded)

data LifeStatus = Alive | Dead deriving (Eq, Show, Read)

-- Ket noi thuc te do Server quan ly; Domain khong tu doan socket.
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

-- DTO cho UI; Server ghep ConnectionStatus khi tao snapshot.
data LobbyMember = LobbyMember
  { lobbyMemberId         :: PlayerId
  , lobbyMemberName       :: String
  , lobbyMemberReady      :: Bool
  , lobbyMemberConnection :: ConnectionStatus
  } deriving (Eq, Show, Read)

-- Draw khac voi Nothing (game chua ket thuc).
data GameResult = Winner Team | Draw deriving (Eq, Show, Read)

-- LowestPlayerId la bien the cu; Validation phai tu choi.
-- Giu tam constructor de code cu duoc bao loi cau hinh ro rang.
data TiePolicy = NoElimination | LowestPlayerId
  deriving (Eq, Show, Read)

-- Witch chi mot action / dem. HunterShot chi hop le khi pending.
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

-- T02 dinh nghia lenh; T03--T07 thuc thi state transition.
-- Resolve* va AdvancePhase chi do Server noi bo goi sau authorization.
data Command
  = Join PlayerId String
  | Leave PlayerId
  | SetReady PlayerId Bool
  | StartGame PlayerId
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

data EventVisibility = Public | Private PlayerId deriving (Eq, Show)

-- Su kien la contract; T03/Server quyet dinh noi dung snapshot va delivery.
-- Tuyet doi khong broadcast mot event Private den tat ca client.
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
    -- Role chi duoc gui rieng cho nguoi nhan vai.
    PlayerRoleAssigned pid _ -> Private pid
    -- Ket qua soi chi duoc gui cho Seer.
    SeerResult pid _ -> Private pid
    -- Xac nhan Night Action chi gui cho nguoi thuc hien.
    NightActionAccepted pid -> Private pid
    -- Khong tiet lo lua chon bo phieu cho nguoi khac.
    VoteUpdated voter _ -> Private voter
    -- Yeu cau ban chi gui rieng cho Hunter.
    HunterShotPending pid -> Private pid
    -- Cac su kien con lai la cong khai.
    -- Role Reveal chi duoc phat sau khi Player chet.
    _ -> Public

-- Du lieu trang thai nghiep vu; khong chua connection/socket.
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
  , gamePendingReveals   :: [PlayerId]
  , gamePendingHunter    :: Maybe PlayerId
  , gameHunterTriggered  :: Bool
  , gameResult           :: Maybe GameResult
  } deriving (Eq, Show)

-- Trang thai khoi tao cho room. T03 se thuc thi Join va gan Host dau tien.
emptyLobby :: GameState
emptyLobby = GameState
  { gamePlayers = [], gameHost = "", gamePhase = Lobby, gameDay = 0
  , gameVotes = [], gameNightActions = [], gameConfiguredRoles = []
  , gameWolfTiePolicy = NoElimination, gameVoteTiePolicy = NoElimination
  , gameWitchHealReady = True, gameWitchPoisonReady = True
  , gameLastProtected = Nothing, gamePendingReveals = []
  , gamePendingHunter = Nothing, gameHunterTriggered = False
  , gameResult = Nothing
  }

-- Dung callback tu Server de truyen thong tin ket noi vao Lobby snapshot.
makeLobbyMembers :: GameState -> (PlayerId -> ConnectionStatus) -> [LobbyMember]
makeLobbyMembers game connectionOf =
  [ LobbyMember (playerId p) (playerName p) (playerReady p)
      (connectionOf (playerId p))
  | p <- gamePlayers game
  ]
