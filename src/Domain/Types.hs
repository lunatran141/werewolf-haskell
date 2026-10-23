-- | Cac kieu du lieu mien cua tro choi duoc chot trong T02.
module Domain.Types where

import Control.DeepSeq (NFData)
import GHC.Generics (Generic)

type PlayerId = String

-- Moi Role thuoc dung mot Team; phe duoc suy ra tu Role.
data Role = Werewolf | Seer | Guard | Witch | Hunter | Villager
  deriving (Eq, Ord, Show, Read, Enum, Bounded, Generic)
instance NFData Role

data Team = Wolves | Village
  deriving (Eq, Ord, Show, Read, Generic)
instance NFData Team

teamOfRole :: Role -> Team
teamOfRole Werewolf = Wolves
teamOfRole _        = Village

data Phase = Lobby | Night | Day | Voting | GameOver
  deriving (Eq, Ord, Show, Read, Enum, Bounded, Generic)
instance NFData Phase

-- T02: Thong tin huong dan kha nang cho tung Role.
-- Day la mo ta chung theo loai vai, khong chua PlayerId.
-- Server chi gui Role thuc cua actor cho dung chu so huu.
data RoleAbilityInfo = RoleAbilityInfo
  { abilityRole        :: Role
  , abilityDescription :: String
  , abilityPhase       :: Maybe Phase
  , abilityTargetRules :: String
  } deriving (Eq, Show, Read)

-- Mo ta kha nang va gioi han theo Game Rules T01.
roleAbilityInfo :: Role -> RoleAbilityInfo
roleAbilityInfo role =
  case role of
    Werewolf ->
      RoleAbilityInfo
        Werewolf
        "Mỗi đêm, mỗi Sói còn sống chọn một người thuộc phe Dân để cắn. Mỗi Sói có một phiếu; mục tiêu có số phiếu cao nhất duy nhất sẽ bị tấn công. Nếu hòa phiếu cao nhất hoặc không ai bỏ phiếu thì không có nạn nhân."
        (Just Night)
        "Chỉ chọn người còn sống thuộc phe Dân. Không được chọn Sói đồng đội."

    Seer ->
      RoleAbilityInfo
        Seer
        "Mỗi đêm soi một người để biết người đó thuộc phe Sói hay phe Dân. Kết quả chỉ được gửi riêng cho Tiên Tri, không tiết lộ vai cụ thể."
        (Just Night)
        "Chỉ chọn một người còn sống khác bản thân."

    Guard ->
      RoleAbilityInfo
        Guard
        "Mỗi đêm bảo vệ một người khỏi bị Sói cắn. Có thể tự bảo vệ, nhưng không được bảo vệ cùng một người trong hai đêm liên tiếp."
        (Just Night)
        "Chỉ chọn người còn sống. Không chọn lại mục tiêu đã bảo vệ ở đêm liền trước."

    Witch ->
      RoleAbilityInfo
        Witch
        "Mỗi đêm chọn một hành động: cứu, đầu độc hoặc bỏ qua. Mỗi bình thuốc cứu và thuốc độc chỉ được dùng một lần trong cả ván. Thuốc cứu chỉ cứu nạn nhân bị Sói cắn."
        (Just Night)
        "Chỉ cứu sau khi đã chốt phiếu Sói và có nạn nhân. Đầu độc một người còn sống khác bản thân; bỏ qua không cần chọn mục tiêu."

    Hunter ->
      RoleAbilityInfo
        Hunter
        "Khi chết vì bất kỳ nguyên nhân nào, Thợ Săn có thể bắn tối đa một người khi server mở lượt bắn."
        Nothing
        "Chỉ được bắn trong lượt dành riêng cho Thợ Săn. Có thể bỏ qua; hết thời gian mà chưa chọn cũng tính là bỏ qua."

    Villager ->
      RoleAbilityInfo
        Villager
        "Tham gia thảo luận ban ngày và bỏ phiếu loại người nghi là Sói. Không có khả năng đặc biệt vào ban đêm."
        (Just Voting)
        "Khi bỏ phiếu, chọn một người còn sống khác bản thân."

data LifeStatus = Alive | Dead
  deriving (Eq, Show, Read, Generic)
instance NFData LifeStatus

-- Ket noi thuc te do Server quan ly; Domain khong chua socket.
data ConnectionStatus = Connected | Disconnected
  deriving (Eq, Show, Read)

-- Cau hinh ngoai hinh cong khai theo giao dien T07.
-- Ngoai hinh khong quyet dinh Role hoac Team.
data Appearance = Appearance
  { appearanceHair      :: String
  , appearanceHairColor :: String
  , appearanceSkin      :: String
  , appearanceOutfit    :: String
  , appearanceAccessory :: String
  } deriving (Eq, Show, Read)

-- Cau hinh mac dinh dung voi web/app.js cua T07.
defaultAppearance :: Appearance
defaultAppearance = Appearance
  { appearanceHair = "messy"
  , appearanceHairColor = "#1E293B"
  , appearanceSkin = "#FDE2D0"
  , appearanceOutfit = "#1E1B4B"
  , appearanceAccessory = "none"
  }

-- Moi kenh chat co quyen truy cap khac nhau.
data ChatChannel
  = PublicDay
  | WolvesNight
  deriving (Eq, Ord, Show, Read)

-- Lich su chat doc lap voi ket noi WebSocket.
data ChatRecord = ChatRecord
  { chatRoomId    :: String
  , chatDay       :: Int
  , chatChannel   :: ChatChannel
  , chatMessageId :: String
  , chatSequence  :: Int
  , chatSenderId  :: PlayerId
  , chatText      :: String
  } deriving (Eq, Show, Read)

-- Trong Lobby, playerRole = Nothing. Sau StartGame = Just role.
-- Appearance duoc Server kiem tra truoc khi luu va co the cong khai.
data Player = Player
  { playerId         :: PlayerId
  , playerName       :: String
  , playerRole       :: Maybe Role
  , playerReady      :: Bool
  , playerLifeStatus :: LifeStatus
  , playerAppearance :: Appearance
  } deriving (Eq, Show, Read)

-- DTO cho UI; Server ghep ConnectionStatus khi tao snapshot.
data LobbyMember = LobbyMember
  { lobbyMemberId         :: PlayerId
  , lobbyMemberName       :: String
  , lobbyMemberReady      :: Bool
  , lobbyMemberConnection :: ConnectionStatus
  } deriving (Eq, Show, Read)

-- Draw khac voi Nothing (game chua ket thuc).
data GameResult = Winner Team | Draw
  deriving (Eq, Show, Read, Generic)
instance NFData GameResult

-- LowestPlayerId la bien the cu; Validation phai tu choi.
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
  | JoinWithAppearance PlayerId String Appearance
  | Leave PlayerId
  | KickPlayer PlayerId PlayerId
  | SetReady PlayerId Bool
  | StartGame PlayerId [Role]
  | EndGame PlayerId
  | AdvancePhase
  | NightAction PlayerId NightChoice
  | Vote PlayerId PlayerId
  | Chat PlayerId String
  | ChatInChannel PlayerId ChatChannel String
  | SkipDiscussion PlayerId
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
  | DuplicateNightAction | EmptyChat | ChatTooLong | NotReady
  | AlreadySkippedDiscussion
  -- T08(fix): Lỗi vận hành khi queue đầy hoặc worker không phản hồi kịp.
  | ServerBusy | ServerTimeout
  -- T06: Một request đã thành công không được phát lại ở vòng sau.
  | DuplicateRequest
  | InvalidAppearance
  deriving (Eq, Show, Read)

data EventVisibility
  = Public
  | Private PlayerId
  | TeamOnly Team
  deriving (Eq, Show)

-- Su kien la contract; T03/Server quyet dinh snapshot va delivery.
-- Khong broadcast event Private den tat ca client.
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
  -- Tien do bo phieu cua Soi, khong chua danh tinh nguoi bo phieu.
  | WolfVoteUpdated Int Int
  -- Ket qua khoa phieu Soi, chi phe Soi duoc nhan.
  | WolfTargetLocked (Maybe PlayerId)
  | SeerResult PlayerId Team
  | WitchVictimNotice PlayerId (Maybe PlayerId)
  | NightResolved [PlayerId]
  | VoteUpdated PlayerId PlayerId
  -- Chi cong bo tong phieu theo muc tieu khi da khoa Voting.
  | VotingResolved [(PlayerId, Int)] (Maybe PlayerId)
  | PlayerEliminated PlayerId
  | PlayerRoleRevealed PlayerId Role Team
  | PlayerDied PlayerId
  | GameRolesRevealed [(PlayerId, Role)]
  | HunterShotPending PlayerId
  | HunterShotResolved PlayerId (Maybe PlayerId)
  | GameEnded Team
  | GameFinished GameResult
  | ChatMessage PlayerId String
  | ChatMessageInChannel ChatChannel PlayerId String
  deriving (Eq, Show)

eventVisibility :: DomainEvent -> EventVisibility
eventVisibility event =
  case event of
    PlayerRoleAssigned pid _ -> Private pid
    -- Khong cho cong khai Role cua nguoi chet.
    -- Su kien cu khong duoc broadcast cho nguoi choi.
    PlayerRoleRevealed _ _ _ -> TeamOnly Village
    SeerResult pid _         -> Private pid
    NightActionAccepted pid  -> Private pid
    -- Chi phe Soi duoc nhan tien do va ket qua khoa phieu.
    WolfVoteUpdated _ _     -> TeamOnly Wolves
    WolfTargetLocked _      -> TeamOnly Wolves
    VoteUpdated voter _      -> Private voter
    HunterShotPending pid    -> Private pid
    WitchVictimNotice pid _ -> Private pid
    ChatMessageInChannel WolvesNight _ _ -> TeamOnly Wolves
    _                        -> Public

-- Du lieu trang thai nghiep vu; khong chua connection/socket.
data GameState = GameState
  { gamePlayers          :: [Player]
  , gameHost             :: PlayerId
  , gamePhase            :: Phase
  , gameDay              :: Int
  , gameVotes            :: [(PlayerId, PlayerId)]
  , gameDiscussionSkips  :: [PlayerId]
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

-- Trang thai khoi tao cho room. T03 thuc thi Join va gan Host dau tien.
emptyLobby :: GameState
emptyLobby = GameState
  { gamePlayers = []
  , gameHost = ""
  , gamePhase = Lobby
  , gameDay = 0
  , gameVotes = []
  , gameDiscussionSkips = []
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

-- Dung callback tu Server de them ket noi vao Lobby snapshot.
makeLobbyMembers :: GameState -> (PlayerId -> ConnectionStatus) -> [LobbyMember]
makeLobbyMembers game connectionOf =
  [ LobbyMember
      (playerId p)
      (playerName p)
      (playerReady p)
      (connectionOf (playerId p))
  | p <- gamePlayers game
  ]
