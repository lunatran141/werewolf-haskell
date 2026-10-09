-- | Các hàm kiểm tra Command và invariant sẽ được triển khai trong T02.
module Domain.Validation where

import Data.Char (isSpace)
import Domain.Types

-- Kiểm tra ID không rỗng
validatePlayerId :: PlayerId -> Either GameError PlayerId
validatePlayerId pid
  | all isSpace pid = Left InvalidPlayerId
  | otherwise       = Right pid

-- Kiểm tra tên không rỗng
validatePlayerName :: String -> Either GameError String
validatePlayerName name
  | all isSpace name = Left InvalidPlayerName
  | otherwise        = Right name

-- Kiểm tra ID không trùng
validateUniquePlayerIds :: [Player] -> Either GameError ()
validateUniquePlayerIds players
  | hasDuplicates (map playerId players) = Left DuplicatePlayerId
  | otherwise = Right ()

-- Kiểm tra tên không trùng
validateUniquePlayerNames :: [Player] -> Either GameError ()
validateUniquePlayerNames players
  | hasDuplicates (map playerName players) = Left DuplicatePlayerName
  | otherwise = Right ()

-- Kiểm tra phần tử trùng nhau
hasDuplicates :: Eq a => [a] -> Bool
hasDuplicates [] = False
hasDuplicates (x : xs) =
  x `elem` xs || hasDuplicates xs

-- Kiểm tra số người có thể bắt đầu ván
validatePlayerCount :: [Player] -> Either GameError ()
validatePlayerCount players
  | count >= 8 && count <= 9 = Right ()
  | otherwise = Left InvalidPlayerCount
  where
    count = length players

-- Kiểm tra tất cả người chơi đã sẵn sàng
validateAllReady :: [Player] -> Either GameError ()
validateAllReady players
  | not (null players) && all playerReady players = Right ()
  | otherwise = Left NotAllReady

-- Tìm người chơi theo ID
validatePlayerExists
  :: PlayerId
  -> [Player]
  -> Either GameError Player
validatePlayerExists pid players =
  case filter ((== pid) . playerId) players of
    []    -> Left PlayerNotFound
    p : _ -> Right p

-- Kiểm tra người chơi còn sống
validatePlayerAlive :: Player -> Either GameError Player
validatePlayerAlive player
  | playerLifeStatus player == Alive = Right player
  | otherwise = Left DeadPlayer

-- Kiểm tra mục tiêu tồn tại và còn sống
validateLivingTarget
  :: PlayerId
  -> [Player]
  -> Either GameError Player
validateLivingTarget target players = do
  player <- validatePlayerExists target players
  validatePlayerAlive player
