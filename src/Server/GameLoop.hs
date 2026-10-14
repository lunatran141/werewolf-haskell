
-- | Mot duong xu ly Command chung tu queue toi Pure Engine.
module Server.GameLoop
  ( processNextLobbyCommand
  , runLobbyLoop
  , runGameLoopWithTimeouts
  , applyInternalCommand
  , CreateRoomError(..)
  , createRoomWithHost
  ) where

import Control.Concurrent.MVar (modifyMVar)

import Control.Concurrent.STM
  ( STM, atomically, check, orElse, registerDelay
  , newEmptyTMVarIO
  , putTMVar
  , readTBQueue
  , readTVar
  , readTVarIO
  , takeTMVar
  , writeTBQueue
  , writeTChan
  , writeTVar
  )

import Data.Char (isSpace)

import Domain.Engine
  ( applyCommand
  )

import Domain.Types
  ( Command(..)
  , DomainEvent
  , GameError(..)
  , GameState(..)
  , PlayerId
  , Phase(..)
  )

import Protocol.Types (RequestId, RoomId)

import Server.Room
  ( QueuedCommand(..)
  , RoomRegistry(..)
  , RoomRuntime(..)
  , RoomUpdate(..)
  , newRoomRuntime
  )


-- Xac thuc nguoi gui command


-- Kiem tra ID trong lenh khop voi ID Server gan cho phien ket noi.
-- Lenh noi bo nhu ResolveNight khong duoc gui truc tiep tu Browser.
actorMatches :: QueuedCommand -> Bool
actorMatches request =
  case queuedCommand request of
    Join pid _ ->
      pid == queuedActorId request

    Leave pid ->
      pid == queuedActorId request

    SetReady pid _ ->
      pid == queuedActorId request

    -- T05: Chi cho phep gui NightAction voi dung PlayerId cua phien.
    NightAction pid _ ->
      pid == queuedActorId request

    -- T06: Vote cung phai dung PlayerId cua session, khong tin ID tu client.
    Vote pid _ ->
      pid == queuedActorId request

    -- Chỉ Handler đã xác thực mới tạo lệnh Hunter; Domain kiểm quyền pending.
    ResolveHunter pid _ -> pid == queuedActorId request

    -- Chat thuộc người chơi; ResolveVoting vẫn chỉ do bộ đếm giờ nội bộ gọi.
    -- HunterChoice được Handler đổi thành ResolveHunter với ID của session.
    Chat pid _ ->
      pid == queuedActorId request

    -- Khong cho phep client tu goi lenh noi bo.
    _ ->
      False



-- T05/T06: Dispatcher command public vao Pure Engine.

-- Chon Pure Engine theo loai command.
-- Khong cho client tu goi ResolveNight, StartGame,
-- AdvancePhase hoac cac lenh noi bo khac qua dispatcher nay.
dispatchPlayerCommand
  :: GameState
  -> Command
  -> Either GameError (GameState, [DomainEvent])
dispatchPlayerCommand state command =
  case command of
    -- Chi cho dispatcher public nhan cac command nguoi choi duoc gui.
    Join _ _ -> applyCommand state command
    Leave _ -> applyCommand state command
    SetReady _ _ -> applyCommand state command
    NightAction _ _ -> applyCommand state command
    Vote _ _ -> applyCommand state command
    ResolveHunter _ _ -> applyCommand state command
    Chat _ _ -> applyCommand state command
    -- Start/Resolve la luong noi bo, khong nhan truc tiep tu Browser.
    _ -> Left NotAuthorized



-- Xu ly Command Queue

-- Xu ly dung mot lenh; ham se cho neu hang doi dang rong.
-- Cap nhat state, version va event trong cung mot giao dich STM.
processNextLobbyCommand :: RoomRuntime -> IO ()
processNextLobbyCommand room = atomically (processPlayerCommand room)

-- T06: Dùng chung giao dịch cho worker và kiểm thử một lệnh.
processPlayerCommand :: RoomRuntime -> STM ()
processPlayerCommand room = do
  request <- readTBQueue (roomCommands room)
  currentState <- readTVar (roomState room)
  accepted <- readTVar (roomAcceptedRequests room)

  let key = (queuedActorId request, queuedRequestId request)
      tracked = case queuedCommand request of
        Vote _ _ -> True
        ResolveHunter _ _ -> True
        _ -> False
      result =
        if tracked && key `elem` accepted then Left DuplicateRequest
        else if actorMatches request
          then dispatchPlayerCommand currentState (queuedCommand request)
          else Left NotAuthorized

  case result of
    Left err -> do
      -- Lenh loi: khong sua state, khong tang version,
      -- khong phat DomainEvent.
      putTMVar (queuedReply request) (Left err)

    Right (nextState, events) -> do
      if tracked then writeTVar (roomAcceptedRequests room) (key : accepted) else pure ()
      currentVersion <- readTVar (roomVersion room)
      let nextVersion = currentVersion + 1

      -- Luu GameState moi.
      writeTVar (roomState room) nextState

      -- Tang version sau khi xu ly command thanh cong.
      writeTVar (roomVersion room) nextVersion

      -- Phat DomainEvent cho he thong Broadcast noi bo.
      writeTChan (roomUpdates room)
        RoomUpdate
          { updateVersion = nextVersion
          , updateState = nextState
          , updateEvents = events
          }

      -- Gui ket qua ve ket noi da gui command.
      putTMVar (queuedReply request) (Right nextState)



-- Vong lap xu ly Command Queue


-- Worker dung khi nguoi cuoi cung roi phong.
-- Giu nguyen ten ham de khong anh huong code Server hien tai.
runLobbyLoop :: RoomRuntime -> IO ()
runLobbyLoop = runGameLoopWithTimeouts 60000000 30000000

-- T06: Điểm nối cho bộ điều phối T04/T05. Không được gọi từ JSON client.
-- Cập nhật phase và phát sự kiện trong cùng STM với queue người chơi.
applyInternalCommand :: RoomRuntime -> Command -> STM (Either GameError GameState)
applyInternalCommand room command = do
  state <- readTVar (roomState room)
  case applyCommand state command of
    Left err -> pure (Left err)
    Right (nextState, events) -> do
      version <- readTVar (roomVersion room)
      writeTVar (roomState room) nextState
      writeTVar (roomVersion room) (version + 1)
      writeTChan (roomUpdates room) (RoomUpdate (version + 1) nextState events)
      pure (Right nextState)

-- Khóa cửa sổ bằng phase/vòng/Hunter: phiếu mới không gia hạn timer.
votingWindow :: GameState -> Maybe (Phase, Int, Maybe PlayerId)
votingWindow state
  | gamePhase state `elem` [Night, Voting], Just hunter <- gamePendingHunter state =
      Just (gamePhase state, gameDay state, Just hunter)
  | gamePhase state == Voting && not (gameVotingResolved state) =
      Just (Voting, gameDay state, Nothing)
  | otherwise = Nothing

-- Thời gian tính bằng microsecond, truyền vào để test nhanh mà không đổi luật.
-- Timer và Vote tranh chấp trên cùng TVar: sau khi chốt, phiếu đến muộn bị từ chối.
runGameLoopWithTimeouts :: Int -> Int -> RoomRuntime -> IO ()
runGameLoopWithTimeouts voteMicros hunterMicros room = startWindow
  where
    startWindow = do
      state <- readTVarIO (roomState room)
      let window = votingWindow state
          duration = case window of
            Just (_, _, Just _) -> hunterMicros
            _ -> voteMicros
      timer <- registerDelay (max 1 duration)
      let loop = do
            restart <- atomically $
              (do current <- readTVar (roomState room)
                  check (votingWindow current /= window || null (gamePlayers current))
                  pure True)
              `orElse`
              (do check (window /= Nothing)
                  expired <- readTVar timer
                  check expired
                  let command = case window of
                        Just (_, _, Just hunter) -> ResolveHunter hunter Nothing
                        _ -> ResolveVoting
                  result <- applyInternalCommand room command
                  case result of
                    Left err -> error ("T06: trạng thái timer không hợp lệ: " ++ show err)
                    Right _ -> pure True)
              `orElse`
              (processPlayerCommand room >> pure False)
            if restart then do
              current <- readTVarIO (roomState room)
              if null (gamePlayers current) then pure () else startWindow
            else loop
      loop



-- Tao Room va Host


data CreateRoomError
  = InvalidRoomId
  | RoomAlreadyExists
  | HostJoinRejected GameError
  deriving (Eq, Show)


-- Chi dua phong vao Registry sau khi Host Join thanh cong.
createRoomWithHost
  :: RoomRegistry
  -> RoomId
  -> RequestId
  -> PlayerId
  -> String
  -> (RoomRuntime -> IO ())
  -> IO (Either CreateRoomError (RoomRuntime, GameState))
createRoomWithHost registry rid requestId actor name startWorker
  | null rid || length rid > 32 || any isSpace rid =
      pure (Left InvalidRoomId)

  | otherwise =
      modifyMVar (registryRooms registry) $ \rooms ->
        case lookup rid rooms of
          Just _ ->
            pure (rooms, Left RoomAlreadyExists)

          Nothing -> do
            room <- newRoomRuntime rid
            reply <- newEmptyTMVarIO

            atomically $
              writeTBQueue (roomCommands room)
                QueuedCommand
                  { queuedRequestId = requestId
                  , queuedActorId = actor
                  , queuedCommand = Join actor name
                  , queuedReply = reply
                  }

            -- Phong chua duoc cong bo.
            -- Xu ly Join dau tien ngay tai day.
            processNextLobbyCommand room

            result <- atomically (takeTMVar reply)

            case result of
              Left err ->
                pure (rooms, Left (HostJoinRejected err))

              Right state -> do
                startWorker room

                pure
                  ( (rid, room) : rooms
                  , Right (room, state)
                  )
