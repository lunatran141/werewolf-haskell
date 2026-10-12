
-- | Phan phoi public/private Event toi dung client.
module Server.Broadcast
  ( lobbySnapshot
  , lobbyMessages
  , lobbyReply
  , nightMessagesFor
  ) where

import Data.Maybe (mapMaybe)

import Domain.Types
  ( Command(..)
  , DomainEvent(..)
  , EventVisibility(..)
  , GameError(..)
  , GameState(..)
  , Player(..)
  , PlayerId
  , eventVisibility
  )

import Protocol.Types
  ( PlayerView(..)
  , RequestId
  , RoomId
  , ServerMessage(..)
  )

import Server.Room (RoomUpdate(..))

-- Lobby

playerView :: Player -> PlayerView
playerView player =
  PlayerView
    (playerId player)
    (playerName player)
    (playerReady player)


-- Gui rieng cho nguoi vua Join de biet ID, Host va danh sach phong.
lobbySnapshot :: RoomId -> PlayerId -> GameState -> ServerMessage
lobbySnapshot rid selfId state =
  MsgLobbySnapshot
    rid
    selfId
    (gameHost state)
    (map playerView (gamePlayers state))


-- Chuyen cac event Lobby cong khai thanh thong diep JSON.
-- Event ve vai hoac thong tin bi mat khong duoc chuyen o day.
lobbyMessages :: RoomId -> RoomUpdate -> [ServerMessage]
lobbyMessages rid update =
  mapMaybe convert (updateEvents update)
  where
    state = updateState update

    convert event =
      case event of
        PlayerJoined pid ->
          case filter ((== pid) . playerId) (gamePlayers state) of
            player : _ ->
              Just (MsgPlayerJoined rid (playerView player))

            [] ->
              Nothing

        PlayerLeft pid ->
          Just (MsgPlayerLeft rid pid)

        HostChanged pid ->
          Just (MsgHostChanged rid pid)

        ReadyChanged pid ready ->
          Just (MsgReadyChanged rid pid ready)

        _ ->
          Nothing


-- Phan hoi rieng cho ket noi da gui lenh.
-- GameLoop tra ve ket qua truoc khi gui phan hoi nay.
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

        -- Snapshot cung xac nhan SetReady khong doi gia tri.
        SetReady _ _ ->
          lobbySnapshot rid actor state

        -- Nguoi roi phong nhan phan hoi de UI xoa phien.
        Leave pid ->
          MsgPlayerLeft rid pid

        _ ->
          MsgRejected
            (Just requestId)
            "INVALID_COMMAND"
            "Lenh khong thuoc Lobby."


lobbyError :: GameError -> (String, String)
lobbyError err =
  case err of
    InvalidPlayerName ->
      ("INVALID_PLAYER_NAME", "Ten nguoi choi khong hop le.")

    DuplicatePlayerName ->
      ("DUPLICATE_PLAYER_NAME", "Ten nay da co trong phong.")

    DuplicatePlayerId ->
      ("DUPLICATE_PLAYER_ID", "ID nguoi choi da ton tai.")

    RoomFull ->
      ("ROOM_FULL", "Phong da du nguoi.")

    PlayerNotFound ->
      ("PLAYER_NOT_FOUND", "Nguoi choi khong co trong phong.")

    WrongPhase ->
      ("WRONG_PHASE", "Khong the thuc hien lenh o giai doan nay.")

    NotAuthorized ->
      ("NOT_AUTHORIZED", "Ban khong co quyen thuc hien lenh.")

    _ ->
      ("COMMAND_REJECTED", "Khong the thuc hien lenh.")

-- T05 - Night Event Routing

-- Kiem tra mot DomainEvent co duoc gui cho client hay khong.
-- Public: moi client trong phong duoc nhan.
-- Private pid: chi client co PlayerId trung pid duoc nhan.
canReceiveNightEvent :: PlayerId -> DomainEvent -> Bool
canReceiveNightEvent recipient event =
  case eventVisibility event of
    Public ->
      True

    Private pid ->
      recipient == pid


-- Chuyen DomainEvent thanh ServerMessage sau khi kiem tra
-- quyen nhan cua tung client.
--
-- Ham nay chi ho tro cac Night Event da co trong Protocol.
-- Nhung event chua co JSON contract se khong duoc gui.
--
-- Khong duoc truyen ket qua cua ham nay vao broadcast
-- chung cho toan bo client.
nightMessagesFor
  :: RoomId
  -> PlayerId
  -> [DomainEvent]
  -> [ServerMessage]
nightMessagesFor rid recipient events =
  mapMaybe convert
    (filter (canReceiveNightEvent recipient) events)
  where
    convert event =
      case event of
        -- Xac nhan hanh dong, chi gui cho actor.
        NightActionAccepted _ ->
          Just (MsgNightActionAccepted rid)

        -- Ket qua soi, chi gui rieng cho Tien Tri.
        SeerResult _ team ->
          Just (MsgSeerResult rid team)

        -- Nan nhan Soi, chi gui rieng cho Phu Thuy.
        WitchVictimNotice _ victim ->
          Just (MsgWitchVictimNotice rid victim)

        -- Ket qua dem: event cong khai theo contract hien tai.
        NightResolved deaths ->
          Just (MsgNightResolved rid deaths)

        -- Cong khai Role/Team cua nguoi da chet.
        PlayerRoleRevealed pid role team ->
          Just (MsgPlayerRoleRevealed rid pid role team)

        -- Chuyen Phase.
        PhaseChanged phase ->
          Just (MsgPhaseChanged rid phase)

        -- Ket thuc van.
        GameFinished result ->
          Just (MsgGameFinished rid result)

        -- Khong chuyen event khac trong T05 router.
        _ ->
          Nothing
