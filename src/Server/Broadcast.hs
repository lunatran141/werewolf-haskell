-- | Phân phối public/private Event tới đúng client.
module Server.Broadcast
  ( lobbySnapshot
  , lobbyMessages
  , lobbyReply
  ) where

import Data.Maybe (mapMaybe)
import Domain.Types
  ( Command(..)
  , DomainEvent(..)
  , GameError(..)
  , GameState(..)
  , Player(..)
  , PlayerId
  )
import Protocol.Types
  ( PlayerView(..)
  , RequestId
  , RoomId
  , ServerMessage(..)
  )
import Server.Room (RoomUpdate(..))

playerView :: Player -> PlayerView
playerView player =
  PlayerView
    (playerId player)
    (playerName player)
    (playerReady player)

-- Gửi riêng cho người vừa Join để họ biết ID, Host và danh sách phòng.
lobbySnapshot :: RoomId -> PlayerId -> GameState -> ServerMessage
lobbySnapshot rid selfId state =
  MsgLobbySnapshot
    rid
    selfId
    (gameHost state)
    (map playerView (gamePlayers state))

-- Chuyển các event Lobby công khai thành thông điệp JSON.
-- Event về vai hoặc thông tin bí mật không được chuyển ở đây.
lobbyMessages :: RoomId -> RoomUpdate -> [ServerMessage]
lobbyMessages rid update =
  mapMaybe convert (updateEvents update)
  where
    state = updateState update

    convert event =
      case event of
        PlayerJoined pid ->
          case filter ((== pid) . playerId) (gamePlayers state) of
            player : _ -> Just (MsgPlayerJoined rid (playerView player))
            []         -> Nothing

        PlayerLeft pid ->
          Just (MsgPlayerLeft rid pid)

        HostChanged pid ->
          Just (MsgHostChanged rid pid)

        ReadyChanged pid ready ->
          Just (MsgReadyChanged rid pid ready)

        _ ->
          Nothing

-- Phản hồi riêng cho kết nối đã gửi lệnh, sau khi GameLoop trả kết quả.
lobbyReply
  :: RoomId
  -> RequestId
  -> PlayerId
  -> Command
  -> Either GameError GameState
  -> ServerMessage
lobbyReply rid requestId actor command result =
  case result of
    Left err ->
      let (code, message) = lobbyError err
      in MsgRejected (Just requestId) code message

    Right state ->
      case command of
        Join _ _ ->
          lobbySnapshot rid actor state

        -- Snapshot cũng xác nhận SetReady không làm thay đổi giá trị.
        SetReady _ _ ->
          lobbySnapshot rid actor state

        -- Người rời phòng phải nhận được phản hồi để UI tự xóa phiên.
        Leave pid ->
          MsgPlayerLeft rid pid

        _ ->
          MsgRejected
            (Just requestId)
            "INVALID_COMMAND"
            "Lệnh không thuộc Lobby."

lobbyError :: GameError -> (String, String)
lobbyError err =
  case err of
    InvalidPlayerName   -> ("INVALID_PLAYER_NAME", "Tên người chơi không hợp lệ.")
    DuplicatePlayerName -> ("DUPLICATE_PLAYER_NAME", "Tên này đã có trong phòng.")
    DuplicatePlayerId   -> ("DUPLICATE_PLAYER_ID", "ID người chơi đã tồn tại.")
    RoomFull            -> ("ROOM_FULL", "Phòng đã đủ người.")
    PlayerNotFound      -> ("PLAYER_NOT_FOUND", "Người chơi không có trong phòng.")
    WrongPhase          -> ("WRONG_PHASE", "Không thể thực hiện lệnh ở giai đoạn này.")
    NotAuthorized       -> ("NOT_AUTHORIZED", "Bạn không có quyền thực hiện lệnh.")
    _                   -> ("COMMAND_REJECTED", "Không thể thực hiện lệnh.")
