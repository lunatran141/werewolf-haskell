
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
-- Khong gui thong tin vai tro bi mat trong Lobby.
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

-- T05: Night Event Routing

-- Public: moi client trong phong duoc nhan.
-- Private pid: chi client co PlayerId trung pid duoc nhan.
canReceiveNightEvent :: PlayerId -> DomainEvent -> Bool
canReceiveNightEvent recipient event =
  case eventVisibility event of
    Public ->
      True

    Private pid ->
      recipient == pid

-- Chuyen DomainEvent thanh ServerMessage cho tung client.
-- Khong broadcast event Private cho toan bo phong.
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
        -- Role chi gui cho nguoi choi duoc phan vai.
        PlayerRoleAssigned pid role
          | pid == recipient ->
              Just (MsgYourRole rid role)

          | otherwise ->
              Nothing

        -- Xac nhan NightAction cho nguoi thuc hien.
        NightActionAccepted _ ->
          Just (MsgNightActionAccepted rid)

        -- Ket qua soi chi gui rieng cho Tien Tri.
        SeerResult _ team ->
          Just (MsgSeerResult rid team)

        -- Nan nhan Soi chi gui rieng cho Phu Thuy.
        WitchVictimNotice _ victim ->
          Just (MsgWitchVictimNotice rid victim)

        -- Ket qua dem theo Domain Contract.
        NightResolved deaths ->
          Just (MsgNightResolved rid deaths)

        -- T06: chi Hunter dang pending nhan quyen ban.
        -- EventVisibility cua HunterShotPending la Private.
        HunterShotPending _ ->
          Just (MsgHunterShotPending rid)

        -- T06: chi phat khi Engine da xu ly Hunter thanh cong.
        -- Event nay la Public theo Domain Contract hien tai.
        HunterShotResolved hunterId targetId ->
          Just (MsgHunterShotResolved rid hunterId targetId)

        -- Cong khai Role va Team cua nguoi da chet.
        PlayerRoleRevealed pid role team ->
          Just (MsgPlayerRoleRevealed rid pid role team)

        -- Thong bao chuyen Phase.
        PhaseChanged phase ->
          Just (MsgPhaseChanged rid phase)

        -- Thong bao ket qua van choi.
        GameFinished result ->
          Just (MsgGameFinished rid result)

        -- Khong gui event chua co JSON Contract.
        _ ->
          Nothing
