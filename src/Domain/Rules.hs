-- | Các hàm luật thuần túy của trò chơi Ma Sói.
-- Module này không chứa IO hay xử lý mạng.
--
-- T06 tập trung các phép tính không có hiệu ứng phụ: tìm người còn sống,
-- đếm phiếu, xác định hòa phiếu và kiểm tra điều kiện kết thúc ván.

module Domain.Rules
  ( minPlayers
  , maxPlayers
  , rolesForPlayerCount
  , findPlayer
  , livingPlayers
  , playersWithRole
  , isLobby
  , isNight
  , isDay
  , isVoting
  , isGameOver
  , isAlive
  , allPlayersReady
  , validateRoleConfiguration
  , tallyVotes
  , voteWinners
  , uniqueVoteWinner
  , voteWinner
  , lynchTarget
  , resolveTie
  , checkWin
  , checkWinner
  , nextPhase
  , uniqueIds
  ) where

import Data.List (foldl', sort)
import Domain.Types

minPlayers :: Int
minPlayers = 8

maxPlayers :: Int
maxPlayers = 9

-- Bộ vai chuẩn được lặp lại ở đây để module luật vẫn thuần và không phụ
-- thuộc ngược vào Validation. Thứ tự không quan trọng khi kiểm tra preset.
rolesForPlayerCount :: Int -> Maybe [Role]
rolesForPlayerCount 8 =
  Just [Werewolf, Werewolf, Seer, Guard, Witch, Hunter, Villager, Villager]
rolesForPlayerCount 9 =
  Just [Werewolf, Werewolf, Werewolf, Seer, Guard, Witch, Hunter, Villager, Villager]
rolesForPlayerCount _ = Nothing

findPlayer :: PlayerId -> [Player] -> Maybe Player
findPlayer pid = go
  where
    go [] = Nothing
    go (player : rest)
      | playerId player == pid = Just player
      | otherwise = go rest

livingPlayers :: [Player] -> [Player]
livingPlayers = filter isAlive

playersWithRole :: Role -> [Player] -> [Player]
playersWithRole role = filter ((== Just role) . playerRole)

isLobby, isNight, isDay, isVoting, isGameOver :: GameState -> Bool
isLobby = (== Lobby) . gamePhase
isNight = (== Night) . gamePhase
isDay = (== Day) . gamePhase
isVoting = (== Voting) . gamePhase
isGameOver = (== GameOver) . gamePhase

isAlive :: Player -> Bool
isAlive = (== Alive) . playerLifeStatus

allPlayersReady :: [Player] -> Bool
allPlayersReady players = not (null players) && all playerReady players

validateRoleConfiguration :: Int -> [Role] -> Bool
validateRoleConfiguration count roles =
  case rolesForPlayerCount count of
    Just expected -> sort roles == sort expected
    Nothing -> False

-- Tally chỉ đếm target. Voter đã được xác thực ở Domain.Validation trước
-- khi đi vào đây, vì vậy hàm này không tự sinh thêm phiếu giả.
tallyVotes :: [(PlayerId, PlayerId)] -> [(PlayerId, Int)]
tallyVotes = foldl' addVote [] . map snd
  where
    addVote [] target = [(target, 1)]
    addVote ((currentTarget, count) : rest) target
      | currentTarget == target = (currentTarget, count + 1) : rest
      | otherwise = (currentTarget, count) : addVote rest target

-- Trả về tất cả target có số phiếu cao nhất. Giữ thứ tự xuất hiện để kết
-- quả ổn định, dù kết quả hòa sau đó vẫn phải được xử lý là không loại.
voteWinners :: [(PlayerId, PlayerId)] -> [PlayerId]
voteWinners votes =
  case tallyVotes votes of
    [] -> []
    tallies ->
      let highest = maximum (map snd tallies)
      in [target | (target, count) <- tallies, count == highest]

uniqueVoteWinner :: [(PlayerId, PlayerId)] -> Maybe PlayerId
uniqueVoteWinner votes =
  case voteWinners votes of
    [target] -> Just target
    _ -> Nothing

-- Tên tương thích với các phần khác của project; luật MVP không cho vote lại.
voteWinner :: [(PlayerId, PlayerId)] -> Maybe PlayerId
voteWinner = uniqueVoteWinner

-- Hòa phiếu hoặc không có phiếu đều không tạo nạn nhân.
lynchTarget :: [(PlayerId, PlayerId)] -> Maybe PlayerId
lynchTarget = uniqueVoteWinner

resolveTie :: TiePolicy -> [PlayerId] -> Maybe PlayerId
resolveTie NoElimination _ = Nothing
resolveTie LowestPlayerId winners =
  case sort winners of
    target : _ -> Just target
    [] -> Nothing

checkWin :: GameState -> Maybe GameResult
checkWin state
  | isLobby state = Nothing
  | gamePendingHunter state /= Nothing = Nothing
  | isGameOver state = gameResult state
  | null alive = Just Draw
  | null wolves = Just (Winner Village)
  | length wolves >= length village = Just (Winner Wolves)
  | otherwise = Nothing
  where
    alive = livingPlayers (gamePlayers state)
    wolves = playersWithRole Werewolf alive
    village = filter isVillagePlayer alive
    isVillagePlayer player =
      case playerRole player of
        Just role -> teamOfRole role == Village
        Nothing -> False

-- Hàm tên ngắn phục vụ các caller cũ muốn hỏi trực tiếp phe thắng.
checkWinner :: [Player] -> Maybe Team
checkWinner players
  | null alive = Nothing
  | null wolves = Just Village
  | length wolves >= length village = Just Wolves
  | otherwise = Nothing
  where
    alive = livingPlayers players
    wolves = playersWithRole Werewolf alive
    village = filter isVillagePlayer alive
    isVillagePlayer player =
      case playerRole player of
        Just role -> teamOfRole role == Village
        Nothing -> False

nextPhase :: Phase -> Maybe Phase
nextPhase Lobby = Just Night
nextPhase Night = Just Day
nextPhase Day = Just Voting
nextPhase Voting = Just Night
nextPhase GameOver = Nothing

-- Loại ID trùng nhưng vẫn giữ thứ tự đầu tiên để log và event ổn định.
uniqueIds :: [PlayerId] -> [PlayerId]
uniqueIds = foldl' addUnique []
  where
    addUnique seen pid
      | pid `elem` seen = seen
      | otherwise = seen ++ [pid]

