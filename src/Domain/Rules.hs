-- | Các hàm luật thuần túy của trò chơi Ma Sói.
-- Module này không chứa IO hay xử lý mạng.

module Domain.Rules where

import Data.List (foldl', sort)
import Domain.Types

-- Số người chơi tối thiểu và tối đa của một ván.
minPlayers, maxPlayers :: Int
minPlayers = 8
maxPlayers = 9

-- Xác định phe của người chơi dựa trên vai trò.
teamOfRole :: Role -> Team
teamOfRole Werewolf = Wolves
teamOfRole _        = Village

-- Trả về cấu hình vai trò theo số người chơi.
-- Lưu ý: cấu hình 8 người cần được nhóm xác nhận trước khi chốt.
rolesForPlayerCount :: Int -> Maybe [Role]
rolesForPlayerCount 8 =
  Just
    [ Werewolf, Werewolf, Werewolf
    , Seer, Guard, Witch, Hunter, Villager
    ]
rolesForPlayerCount 9 =
  Just
    [ Werewolf, Werewolf, Werewolf
    , Seer, Guard, Witch, Hunter
    , Villager, Villager
    ]
rolesForPlayerCount _ = Nothing

-- Tìm người chơi theo ID.
findPlayer :: PlayerId -> [Player] -> Maybe Player
findPlayer pid players =
  case filter ((== pid) . playerId) players of
    []    -> Nothing
    p : _ -> Just p

-- Lấy danh sách người chơi còn sống.
livingPlayers :: [Player] -> [Player]
livingPlayers =
  filter ((== Alive) . playerLifeStatus)

-- Lấy danh sách người chơi có vai trò được chỉ định.
playersWithRole :: Role -> [Player] -> [Player]
playersWithRole role =
  filter ((== Just role) . playerRole)

-- Kiểm tra giai đoạn hiện tại của ván đấu.
isLobby, isNight, isDay, isVoting, isGameOver
  :: GameState -> Bool
isLobby    = (== Lobby) . gamePhase
isNight    = (== Night) . gamePhase
isDay      = (== Day) . gamePhase
isVoting   = (== Voting) . gamePhase
isGameOver = (== GameOver) . gamePhase

-- Kiểm tra người chơi còn sống hay đã chết.
isAlive :: Player -> Bool
isAlive = (== Alive) . playerLifeStatus

-- Kiểm tra danh sách không rỗng và tất cả người chơi đã sẵn sàng.
allPlayersReady :: [Player] -> Bool
allPlayersReady players =
  not (null players) && all playerReady players

-- Kiểm tra cấu hình vai trò có khớp với số người chơi.
validateRoleConfiguration :: Int -> [Role] -> Bool
validateRoleConfiguration count roles =
  rolesForPlayerCount count == Just roles

-- Đếm số phiếu nhận được của từng mục tiêu.
-- Mỗi cặp trong danh sách biểu diễn một người bỏ phiếu và mục tiêu.
tallyVotes :: [(PlayerId, PlayerId)] -> [(PlayerId, Int)]
tallyVotes votes =
  foldl' addVote [] (map snd votes)
  where
    addVote [] target = [(target, 1)]
    addVote counts target =
      case lookup target counts of
        Nothing ->
          counts ++ [(target, 1)]
        Just _ ->
          map
            (\(pid, count) ->
              if pid == target
                then (pid, count + 1)
                else (pid, count))
            counts

-- Tìm tất cả mục tiêu có số phiếu cao nhất.
-- Nếu hòa, trả về toàn bộ mục tiêu hòa theo thứ tự ID.
voteWinners :: [(PlayerId, PlayerId)] -> [PlayerId]
voteWinners votes =
  case tallyVotes votes of
    [] -> []
    counts ->
      let highest = maximum (map snd counts)
      in sort
           [ pid
           | (pid, count) <- counts
           , count == highest
           ]

-- Xử lý kết quả hòa theo chính sách hiện có.
-- NoElimination: không loại ai.
-- LowestPlayerId: chọn mục tiêu có ID nhỏ nhất.
-- Quy trình bỏ phiếu lại phải được quản lý bởi Engine.
resolveTie :: TiePolicy -> [PlayerId] -> Maybe PlayerId
resolveTie _ [] = Nothing
resolveTie NoElimination _ = Nothing
resolveTie LowestPlayerId candidates =
  case sort candidates of
    []    -> Nothing
    x : _ -> Just x

-- Kiểm tra điều kiện thắng của hai phe.
-- Nếu không còn người sống, hàm trả Nothing.
-- Kiểu Maybe Team hiện tại chưa phân biệt được hòa ván
-- với trường hợp ván đấu chưa có phe chiến thắng.
checkWinner :: [Player] -> Maybe Team
checkWinner players
  | null alive = Nothing
  | null aliveWolves = Just Village
  | length aliveWolves >= length aliveNonWolves = Just Wolves
  | otherwise = Nothing
  where
    alive = livingPlayers players
    aliveWolves =
      filter ((== Just Werewolf) . playerRole) alive
    aliveNonWolves =
      filter ((/= Just Werewolf) . playerRole) alive

-- Xác định giai đoạn tiếp theo theo vòng đời cơ bản.
-- Engine phải kiểm tra điều kiện thắng trước khi chuyển giai đoạn.
nextPhase :: Phase -> Maybe Phase
nextPhase Lobby    = Just Night
nextPhase Night    = Just Day
nextPhase Day      = Just Voting
nextPhase Voting   = Just Night
nextPhase GameOver = Nothing

