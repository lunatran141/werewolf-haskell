-- | Pure Engine nhận state và command, rồi trả state cùng domain event.
module Domain.Engine where

import Domain.Types
import Domain.Validation
  ( validateGameInvariant
  , validateJoin
  , validateLeave
  , validateSetReady
  )

-- Thêm người chơi vào Lobby.
-- PlayerId do Server cấp; validateJoin tạo Player với tên đã chuẩn hóa.
joinPlayer
  :: GameState
  -> PlayerId
  -> String
  -> Either GameError (GameState, [DomainEvent])
joinPlayer state pid name = do
  player <- validateJoin state pid name

  let isFirst = null (gamePlayers state)
      newState = state
        { gamePlayers = gamePlayers state ++ [player]
        , gameHost = if isFirst then pid else gameHost state
        }

  validateGameInvariant newState
  pure (newState, [PlayerJoined pid])

-- Xóa người chơi khỏi Lobby.
-- Nếu Host rời, người còn lại Join sớm nhất trở thành Host.
leavePlayer
  :: GameState
  -> PlayerId
  -> Either GameError (GameState, [DomainEvent])
leavePlayer state pid = do
  _ <- validateLeave state pid

  let remaining = filter ((/= pid) . playerId) (gamePlayers state)
      hostLeft = gameHost state == pid
      newHost =
        if hostLeft
          then case remaining of
            []    -> ""
            p : _ -> playerId p
          else gameHost state
      newState = state
        { gamePlayers = remaining
        , gameHost = newHost
        }
      events =
        [PlayerLeft pid] ++
        [HostChanged newHost | hostLeft && not (null remaining)]

  validateGameInvariant newState
  pure (newState, events)

-- Đổi trạng thái Ready của một người chơi.
-- Nếu giá trị không đổi thì không phát ReadyChanged.
setPlayerReady
  :: GameState
  -> PlayerId
  -> Bool
  -> Either GameError (GameState, [DomainEvent])
setPlayerReady state pid ready = do
  currentPlayer <- validateSetReady state pid

  let changed = playerReady currentPlayer /= ready
      updatePlayer player
        | playerId player == pid = player { playerReady = ready }
        | otherwise = player
      newState = state
        { gamePlayers =
            if changed
              then map updatePlayer (gamePlayers state)
              else gamePlayers state
        }
      events =
        if changed
          then [ReadyChanged pid ready]
          else []

  validateGameInvariant newState
  pure (newState, events)


-- Xử lý riêng các command thuộc Lobby.
-- TV2 có thể gọi hàm này từ GameLoop khi tích hợp Server.
applyLobbyCommand
  :: GameState
  -> Command
  -> Either GameError (GameState, [DomainEvent])
applyLobbyCommand state command =
  case command of
    Join pid name       -> joinPlayer state pid name
    Leave pid           -> leavePlayer state pid
    SetReady pid ready  -> setPlayerReady state pid ready
    _                   -> Left InvalidCommand
