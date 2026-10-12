
-- | T05: Các hàm luật thuần túy cho Sói, Tiên Tri, Bảo Vệ và Phù Thủy.
-- Không sử dụng IO, WebSocket hoặc random; cùng đầu vào luôn cho cùng kết quả.
module Domain.Night
  ( NightOutcome(..)
  , livingWolves, wolfVotes, wolfTally, wolfVotingComplete, wolfVictim
  , seerInspection, nightActionPrivateEvents
  , guardedTarget, witchChoice, witchHealUsed, witchPoisonTarget
  , resolveNightEffects, nightDeaths
  ) where

import Data.List (nub)
import Domain.Types
import Domain.Validation (validateNightAction)

-- Kết quả giải quyết Night để Engine cập nhật trạng thái và phát sự kiện.
data NightOutcome = NightOutcome
  { outcomeWolfVictim         :: Maybe PlayerId
  , outcomeGuardedTarget      :: Maybe PlayerId
  , outcomeWitchHealed        :: Bool
  , outcomePoisonTarget       :: Maybe PlayerId
  , outcomeDeaths             :: [PlayerId]
  , outcomeHealReadyAfter     :: Bool
  , outcomePoisonReadyAfter   :: Bool
  , outcomeLastProtectedAfter :: Maybe PlayerId
  } deriving (Eq, Show)

-- Tìm người chơi theo ID; trả Nothing nếu không tồn tại.
findPlayer :: PlayerId -> GameState -> Maybe Player
findPlayer pid state =
  case filter ((== pid) . playerId) (gamePlayers state) of
    player : _ -> Just player
    []         -> Nothing

-- Kiểm tra người chơi còn sống.
isAlive :: PlayerId -> GameState -> Bool
isAlive pid state =
  case findPlayer pid state of
    Just player -> playerLifeStatus player == Alive
    Nothing     -> False

-- Kiểm tra người chơi còn sống và có đúng vai.
isLivingRole :: Role -> PlayerId -> GameState -> Bool
isLivingRole role pid state =
  case findPlayer pid state of
    Just player -> playerLifeStatus player == Alive && playerRole player == Just role
    Nothing     -> False

-- Sói chỉ được chọn mục tiêu thuộc phe Village còn sống.
isLivingVillage :: PlayerId -> GameState -> Bool
isLivingVillage pid state =
  case findPlayer pid state of
    Just player ->
      playerLifeStatus player == Alive &&
      case playerRole player of
        Just role -> teamOfRole role == Village
        Nothing   -> False
    Nothing -> False

-- Lấy danh sách Sói còn sống bằng map, filter và hợp thành hàm.
livingWolves :: GameState -> [PlayerId]
livingWolves = map playerId . filter isWolf . gamePlayers
  where
    isWolf player =
      playerLifeStatus player == Alive && playerRole player == Just Werewolf

-- Lấy mục tiêu từ các phiếu Sói hợp lệ đã lưu trong GameState.
wolfVotes :: GameState -> [PlayerId]
wolfVotes state =
  [ target
  | (actor, WolfTarget target) <- gameNightActions state
  , actor `elem` livingWolves state
  , isLivingVillage target state
  ]

-- Đếm phiếu từng mục tiêu, ví dụ: [("V1",2),("V2",1)].
wolfTally :: GameState -> [(PlayerId, Int)]
wolfTally state = map countVotes (nub votes)
  where
    votes = wolfVotes state
    countVotes target = (target, length (filter (== target) votes))

-- Kiểm tra tất cả Sói còn sống đã gửi phiếu hay chưa.
-- Khi hết hạn, Sói chưa bỏ phiếu được xem là bỏ qua.
wolfVotingComplete :: GameState -> Bool
wolfVotingComplete state = all hasVoted (livingWolves state)
  where
    hasVoted wolfId = any (isVoteBy wolfId) (gameNightActions state)
    isVoteBy wolfId (actor, WolfTarget _) = actor == wolfId
    isVoteBy _ _ = False

-- Mục tiêu có phiếu cao nhất duy nhất bị Sói chọn; hòa hoặc không phiếu trả Nothing.
-- Engine chỉ chốt kết quả sau khi lượt Sói đã đóng; không random phá hòa.
wolfVictim :: GameState -> Maybe PlayerId
wolfVictim state =
  case tally of
    [] -> Nothing
    _  -> case winners of
      [(target, _)] -> Just target
      _             -> Nothing
  where
    tally = wolfTally state
    highest = maximum (map snd tally)
    winners = filter ((== highest) . snd) tally

-- Tiên Tri soi người khác còn sống và chỉ lấy kết quả Team.
-- Tái sử dụng Validation T02; Engine chịu trách nhiệm gửi kết quả riêng.
seerInspection :: GameState -> PlayerId -> PlayerId -> Either GameError Team
seerInspection state seerId targetId = do
  validateNightAction state seerId (SeerTarget targetId)
  case findPlayer targetId state of
    Nothing -> Left PlayerNotFound
    Just player ->
      case playerRole player of
        Nothing   -> Left InvalidRole
        Just role -> Right (teamOfRole role)

-- Tạo sự kiện riêng tư sau khi kiểm tra NightAction.
-- NightActionAccepted và SeerResult phải được Server gửi đúng người nhận.
nightActionPrivateEvents
  :: GameState -> PlayerId -> NightChoice -> Either GameError [DomainEvent]
nightActionPrivateEvents state actor choice = do
  validateNightAction state actor choice
  case choice of
    SeerTarget target -> do
      team <- seerInspection state actor target
      pure [NightActionAccepted actor, SeerResult actor team]
    _ -> pure [NightActionAccepted actor]

-- Lấy mục tiêu Guard bảo vệ; Guard có thể tự bảo vệ.
-- Validation T02 kiểm tra không trùng mục tiêu hai đêm liên tiếp.
guardedTarget :: GameState -> Maybe PlayerId
guardedTarget state =
  case targets of
    target : _ -> Just target
    []         -> Nothing
  where
    targets =
      [ target
      | (actor, GuardTarget target) <- gameNightActions state
      , isLivingRole Guard actor state
      , isAlive target state
      ]

-- Lấy lựa chọn của Witch; mỗi đêm chỉ được Heal, Poison hoặc Pass một lần.
witchChoice :: GameState -> Maybe NightChoice
witchChoice state =
  case choices of
    choice : _ -> Just choice
    []         -> Nothing
  where
    choices =
      [ choice
      | (actor, choice) <- gameNightActions state
      , isLivingRole Witch actor state
      , isWitchChoice choice
      ]
    isWitchChoice WitchHeal       = True
    isWitchChoice (WitchPoison _) = True
    isWitchChoice WitchPass       = True
    isWitchChoice _               = False

-- Kiểm tra Witch có sử dụng bình Heal trong đêm hiện tại hay không.
witchHealUsed :: GameState -> Bool
witchHealUsed state = witchChoice state == Just WitchHeal

-- Lấy mục tiêu bị Witch chọn Poison.
witchPoisonTarget :: GameState -> Maybe PlayerId
witchPoisonTarget state =
  case witchChoice state of
    Just (WitchPoison target) | isAlive target state -> Just target
    _ -> Nothing

-- Giải quyết hiệu ứng Night sau khi Engine đã xác thực và khóa lượt.
-- Guard và Heal chặn Sói; Poison không bị Guard hoặc Heal ngăn chặn.
-- Kết quả chỉ là dữ liệu, chưa trực tiếp cập nhật GameState.
resolveNightEffects :: GameState -> NightOutcome
resolveNightEffects state = NightOutcome
  { outcomeWolfVictim = victim
  , outcomeGuardedTarget = protected
  , outcomeWitchHealed = healed
  , outcomePoisonTarget = poisoned
  , outcomeDeaths = deaths
  , outcomeHealReadyAfter = healReadyAfter
  , outcomePoisonReadyAfter = poisonReadyAfter
  , outcomeLastProtectedAfter = protected
  }
  where
    victim = wolfVictim state
    protected = guardedTarget state
    healed = witchHealUsed state
    poisoned = witchPoisonTarget state

    -- Chỉ bị Sói giết nếu không được Guard hoặc Witch cứu.
    wolfDeaths = case victim of
      Just pid | protected /= Just pid && not healed -> [pid]
      _ -> []

    -- Poison gây chết độc lập với bảo vệ và Heal.
    poisonDeaths = case poisoned of
      Just pid -> [pid]
      Nothing  -> []

    -- Loại bỏ người trùng trong danh sách chết.
    deaths = nub (wolfDeaths ++ poisonDeaths)

    -- Bình thuốc đã sử dụng sẽ không còn khả dụng ở đêm sau.
    healReadyAfter = gameWitchHealReady state && not healed
    poisonReadyAfter = gameWitchPoisonReady state && poisoned == Nothing

-- Lấy danh sách người chết bằng hợp thành hàm.
nightDeaths :: GameState -> [PlayerId]
nightDeaths = outcomeDeaths . resolveNightEffects
