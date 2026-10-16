
-- | Phan phoi public/private Event toi dung client.
module Server.Broadcast
  ( lobbySnapshot
  , lobbyMessages
  , lobbyReply
  , nightMessagesFor
  , nightMessagesForState
  , votingSnapshot
  , chatHistorySnapshot
  , chatMessageForState
  ) where

import Data.Maybe (mapMaybe)

import Domain.Types
  ( ChatChannel(..)
  , ChatRecord(..)
  , Command(..)
  , DomainEvent(..)
  , EventVisibility(..)
  , GameError(..)
  , GameState(..)
  , Player(..)
  , PlayerId
  , Role(..)
  , LifeStatus(..)
  , Team
  , eventVisibility
  , teamOfRole
  )

import Protocol.Types
  ( PlayerView(..)
  , VotingPlayerView(..)
  , RequestId
  , RoomId
  , ServerMessage(..)
  )

import Server.Room (RoomUpdate(..))

-- T07: Snapshot lịch sử được lọc riêng cho từng kết nối. Chat công khai có
-- thể xem lại; chat Sói chỉ được gửi cho Sói còn sống.
chatHistorySnapshot
  :: RoomId
  -> PlayerId
  -> GameState
  -> [ChatRecord]
  -> ServerMessage
chatHistorySnapshot rid recipient state records =
  MsgChatHistorySnapshot rid (filter canReceive records)
  where
    recipientIsLivingWolf =
      any
        (\player ->
          playerId player == recipient
            && playerLifeStatus player == Alive
            && playerRole player == Just Werewolf)
        (gamePlayers state)

    canReceive record =
      case chatChannel record of
        PublicDay -> True
        WolvesNight -> recipientIsLivingWolf

-- Cùng một bộ lọc quyền với snapshot, nhưng dành cho tin vừa được commit.
chatMessageForState
  :: RoomId
  -> PlayerId
  -> GameState
  -> ChatRecord
  -> Maybe ServerMessage
chatMessageForState rid recipient state record =
  case chatHistorySnapshot rid recipient state [record] of
    MsgChatHistorySnapshot _ [_] -> Just (MsgStoredChatMessage rid record)
    _ -> Nothing

-- T06: Người chết đang chờ Hunter vẫn hiển thị như trước batch với người khác.
-- Chỉ Hunter biết mình có quyền bắn; không lộ danh sách chết trước reveal.
votingSnapshot :: RoomId -> PlayerId -> GameState -> ServerMessage
votingSnapshot rid recipient state = MsgVotingSnapshot rid
  (gamePhase state) (gameDay state)
  [ VotingPlayerView (playerId p) (playerName p)
      (playerLifeStatus p == Alive || playerId p `elem` gamePendingReveals state)
  | p <- gamePlayers state ]
  (recipient `elem` map fst (gameVotes state))
  (gamePendingHunter state == Just recipient)
  (gameVotingResolved state)
  (gameResult state)

-- Lobby
-- Tao PlayerView chi chua thong tin cong khai.
-- Khong dua Role hoac Team cua Player vao snapshot.
playerView :: Player -> PlayerView
playerView player =
  PlayerView
    (playerId player)
    (playerName player)
    (playerReady player)
    (playerLifeStatus player == Alive)
    (playerAppearance player)

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

-- T05/T06 - Night, Vote va death event routing

-- Su kien Public duoc gui cho tat ca nguoi choi trong phong.
-- Su kien Private chi duoc gui cho nguoi choi co PlayerId tuong ung.
-- Su kien TeamOnly can kiem tra phe va trang thai song/chet.
-- Tam thoi tu choi TeamOnly cho den khi Server ho tro phan quyen day du.
canReceiveNightEvent :: PlayerId -> DomainEvent -> Bool
canReceiveNightEvent recipient event =
  case eventVisibility event of
    Public ->
      True

    Private pid ->
      recipient == pid

    TeamOnly _ ->
      False

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

        -- Tiến độ và kết quả khóa phiếu chỉ được TeamOnly Wolves nhận.
        -- Không gửi lựa chọn cá nhân của từng Sói để tránh lộ phiếu riêng.
        WolfVoteUpdated submitted total ->
          Just (MsgWolfVoteUpdated rid submitted total)

        WolfTargetLocked target ->
          Just (MsgWolfTargetLocked rid target)

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

        -- Khong cho phep tiet lo Role khi nguoi choi chet.
        -- Toan bo Role chi duoc cong khai tai GameOver.
        PlayerRoleRevealed _ _ _ ->
          Nothing

        -- T02: Cong khai nguoi chet, khong kem Role hoac Team.
        PlayerDied pid ->
          Just (MsgPlayerDied rid pid)

        -- T02: Chi cong khai toan bo Role khi GameOver.
        GameRolesRevealed roles ->
          Just (MsgGameRolesRevealed rid roles)

        -- Thong bao chuyen Phase.
        PhaseChanged phase ->
          Just (MsgPhaseChanged rid phase)

        -- Thong bao ket qua van choi.
        GameFinished result ->
          Just (MsgGameFinished rid result)

        -- VoteUpdated da duoc eventVisibility loc private theo voter.
        -- Message khong chua target de khong lo ro lua chon ca nhan.
        VoteUpdated _ _ ->
          Just (MsgVoteUpdated rid)

        VotingResolved tally target -> Just (MsgVotingResolved rid tally target)

        -- Ket qua lynch va reveal la public sau khi batch death da xong.
        PlayerEliminated pid ->
          Just (MsgPlayerEliminated rid pid)

        ChatMessage playerId messageText ->
          Just (MsgChatMessage rid playerId messageText)

        -- Khong gui event chua co JSON Contract.
        _ ->
          Nothing

-- T07: Phiên bản có GameState để kiểm TeamOnly ở phía server.
-- Không tin vai hoặc kênh do browser tự khai báo khi quyết định người nhận.
nightMessagesForState
  :: RoomId
  -> PlayerId
  -> GameState
  -> [DomainEvent]
  -> [ServerMessage]
nightMessagesForState rid recipient state events =
  mapMaybe convert (filter canReceive events)
  where
    canReceive event =
      case eventVisibility event of
        Public -> True
        Private pid -> recipient == pid
        TeamOnly team -> recipientIsAliveTeam team

    recipientIsAliveTeam :: Team -> Bool
    recipientIsAliveTeam team =
      any
        (\player ->
          playerId player == recipient
            && playerLifeStatus player == Alive
            && fmap teamOfRole (playerRole player) == Just team)
        (gamePlayers state)

    convert event =
      case event of
        ChatMessageInChannel channel playerId messageText ->
          Just
            (MsgChannelChatMessage
              rid (gameDay state) channel playerId messageText)
        -- Hai event TeamOnly đã được kiểm tra vai và trạng thái sống ở trên.
        -- Không gọi lại nightMessagesFor vì phiên bản không có GameState phải
        -- từ chối mọi TeamOnly để tránh tin dữ liệu vai từ client.
        WolfVoteUpdated submitted total ->
          Just (MsgWolfVoteUpdated rid submitted total)
        WolfTargetLocked target ->
          Just (MsgWolfTargetLocked rid target)
        _ ->
          case nightMessagesFor rid recipient [event] of
            message : _ -> Just message
            [] -> Nothing
