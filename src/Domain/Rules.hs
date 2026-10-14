-- | Các hàm luật thuần túy của trò chơi Ma Sói.
-- Module này không chứa IO, WebSocket hoặc xử lý mạng.
module Domain.Rules
  ( countAliveTeam
  , checkWin
  ) where

import Domain.Types

-- | Đếm số người còn sống thuộc một phe.
--
-- Người chưa được gán vai sẽ không được tính.
countAliveTeam :: Team -> GameState -> Int
countAliveTeam expectedTeam state =
  length
    [ player
    | player <- gamePlayers state
    , playerLifeStatus player == Alive
    , Just role <- [playerRole player]
    , teamOfRole role == expectedTeam
    ]

-- | Kiểm tra kết quả cuối cùng của ván chơi.
--
-- Thứ tự ưu tiên:
-- 1. Không còn ai sống: Draw.
-- 2. Không còn Sói: Village thắng.
-- 3. Số Sói >= số Dân: Wolves thắng.
-- 4. Trường hợp còn lại: tiếp tục chơi.
checkWin :: GameState -> Maybe GameResult
checkWin state
  | gamePhase state == Lobby =
      Nothing
  | gamePendingHunter state /= Nothing =
      Nothing
  | aliveWolves + aliveVillage == 0 =
      Just Draw
  | aliveWolves == 0 =
      Just (Winner Village)
  | aliveWolves >= aliveVillage =
      Just (Winner Wolves)
  | otherwise =
      Nothing
  where
    aliveWolves = countAliveTeam Wolves state
    aliveVillage = countAliveTeam Village state