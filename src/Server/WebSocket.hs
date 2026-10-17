module Server.WebSocket (webSocketApp) where

import Control.Concurrent (ThreadId, forkIO, killThread)

import Control.Concurrent.MVar (modifyMVar, withMVar)

import Control.Concurrent.STM

  ( atomically

  , dupTChan

  , newEmptyTMVarIO

  , readTChan

  , readTVar

  , readTVarIO

  , takeTMVar

  , writeTBQueue

  , writeTVar

  , modifyTVar'

  )

import Control.Exception (finally)

import Control.Monad (forM_, forever, void)

import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Word (Word64)
import Numeric (showHex)
import GHC.Clock (getMonotonicTimeNSec)

import Domain.RoleShuffle (shuffleRoles)

import Domain.Types
  ( Command(..)
  , DomainEvent(..)
  , GameError(..)
  , GameState(..)
  , Player(..)
  , PlayerId
  , Phase(..)
  , NightChoice(..)
  )

import Domain.Validation (expectedRoles)

import qualified Network.WebSockets as WS

import Protocol.Json

  ( decodeClientMessage

  , encodeServerMessage

  )

import Protocol.Types

  ( ClientMessage(..)

  , PlayerView(..)

  , RequestId

  , RoomId

  , ServerMessage(..)

  )

import Server.Broadcast

  ( lobbyMessages

  , lobbyReply

  , lobbySnapshot

  , nightMessagesForState
  , votingSnapshot
  , chatHistorySnapshot
  , chatMessageForState
  , wolfTeamMessage
  , privateActionStateMessage
  , discussionSkipStateMessage
  )

import Server.Connection
  ( OutboundQueue
  , newOutboundQueue
  , readOutbound
  , writeBoundedDropOldest
  )

import Server.GameLoop
  ( CreateRoomError(..)
  , createRoomWithHost
  , createRoomWithHostAppearance
  )

import Server.Room

  ( QueuedCommand(..)

  , RoomRegistry(..)

  , RoomRuntime(..)

  , RoomUpdate(..)

  )

import Server.Supervisor (runIgnoringBenignSocketException)

import System.Random (newStdGen, randomIO)

-- Gui ServerMessage vao hang doi co gioi han cua mot ket noi.

sendToClient :: OutboundQueue -> ServerMessage -> IO ()

sendToClient outbound message =

  void (atomically (writeBoundedDropOldest outbound message))

isRoleAssignment :: DomainEvent -> Bool
isRoleAssignment event =
  case event of
    PlayerRoleAssigned _ _ -> True
    _ -> False

-- Gui CommandRejected cho ket noi da gui yeu cau.

reject

  :: OutboundQueue

  -> RequestId

  -> String

  -> String

  -> IO ()

reject outbound requestId code message =

  sendToClient outbound

    (MsgRejected (Just requestId) code message)

-- PlayerId do Server cap, khong lay tu Browser.

-- Command duoc xu ly boi Room Worker.

submitCommand

  :: RoomRuntime

  -> RequestId

  -> PlayerId

  -> Command

  -> IO (Either GameError GameState)

submitCommand room requestId actor command = do

  reply <- newEmptyTMVarIO

  atomically $

    writeTBQueue (roomCommands room)

      QueuedCommand

        { queuedRequestId = requestId

        , queuedActorId = actor

        , queuedCommand = command

        , queuedReply = reply

        }

  atomically (takeTMVar reply)

-- Xu ly Leave va xoa phong rong duoi cung khoa Registry.

leaveAndPrune

  :: RoomRegistry

  -> RoomRuntime

  -> RequestId

  -> PlayerId

  -> IO (Either GameError GameState)

leaveAndPrune registry room requestId actor =

  modifyMVar (registryRooms registry) $ \rooms -> do

    currentState <- readTVarIO (roomState room)

    if not (any ((== actor) . playerId) (gamePlayers currentState))

      then pure (rooms, Left PlayerNotFound)

      else do

        result <- submitCommand room requestId actor (Leave actor)

        let remainingRooms =

              case result of

                Right state | null (gamePlayers state) ->

                  filter ((/= roomId room) . fst) rooms

                _ ->

                  rooms

        pure (remainingRooms, result)

-- Chi gui event Lobby cho cac nguoi choi khac khi can.

forOtherPlayer :: PlayerId -> ServerMessage -> Bool

forOtherPlayer actor message =

  case message of

    MsgPlayerJoined _ player ->

      viewPlayerId player /= actor

    MsgPlayerLeft _ pid ->

      pid /= actor

    MsgReadyChanged _ pid _ ->

      pid /= actor

    _ ->

      True

-- Khong cong khai NightResolved truoc khi xu ly Hunter.

safeNightEvent :: DomainEvent -> Bool

safeNightEvent event =

  case event of

    NightResolved _ ->

      False

    _ ->

      True

-- Chat đã lưu được phát bằng MsgStoredChatMessage để mang ID/sequence.
-- Không phát lại DomainEvent chat theo contract cũ trong cùng update.
isChatEvent :: DomainEvent -> Bool
isChatEvent event =
  case event of
    ChatMessage _ _ -> True
    ChatMessageInChannel _ _ _ -> True
    _ -> False

-- Gui LobbySnapshot va dang ky nhan RoomUpdate.

beginSession

  :: RoomRuntime

  -> PlayerId

  -> IORef (Maybe (RoomRuntime, ThreadId))

  -> OutboundQueue

  -> IO ()

beginSession room actor sessionRef outbound = do

  let enqueueSTM = void . writeBoundedDropOldest outbound

  updates <- atomically $ do

    channel <- dupTChan (roomUpdates room)

    state <- readTVar (roomState room)

    history <- readTVar (roomChatHistory room)

    enqueueSTM

      (lobbySnapshot (roomId room) actor state)

    -- Reconnect cần phục hồi dữ liệu riêng sau snapshot công khai.
    case filter ((== actor) . playerId) (gamePlayers state) of
      player : _ ->
        case playerRole player of
          Just role -> enqueueSTM (MsgYourRole (roomId room) role)
          Nothing -> pure ()
      [] -> pure ()

    forM_ (wolfTeamMessage (roomId room) actor state)
      enqueueSTM

    if gamePhase state /= Lobby
      then enqueueSTM
        (privateActionStateMessage (roomId room) actor state)
      else pure ()

    if gamePhase state /= Lobby
      then enqueueSTM (votingSnapshot (roomId room) actor state)
      else pure ()

    if gamePhase state == Day
      then enqueueSTM
        (discussionSkipStateMessage (roomId room) actor state)
      else pure ()

    case gameResult state of
      Just result -> do
        enqueueSTM (MsgGameFinished (roomId room) result)
        enqueueSTM
          (MsgGameRolesRevealed (roomId room)
            [ (playerId player, role)
            | player <- gamePlayers state
            , Just role <- [playerRole player]
            ])
      Nothing -> pure ()

    if null history
      then pure ()
      else enqueueSTM
        (chatHistorySnapshot (roomId room) actor state history)

    pure channel

  sendPhaseTimeRemaining outbound room

  broadcastThread <- forkIO $ runIgnoringBenignSocketException $ forever $ do

    update <- atomically (readTChan updates)

    -- Giu nguyen luong Lobby.

    forM_

      (filter (forOtherPlayer actor)

        (lobbyMessages (roomId room) update))

      (sendToClient outbound)

    -- T05: Loc event theo quyen nhan cua PlayerId.

    let safeEvents =
          filter safeNightEvent
            (if updateChatRecord update == Nothing
              then updateEvents update
              else filter (not . isChatEvent) (updateEvents update))

        nightMessages =

          nightMessagesForState
            (roomId room) actor (updateState update) safeEvents

    forM_ nightMessages (sendToClient outbound)

    -- StartGame vừa gán vai: gửi danh sách đồng đội riêng cho đúng phe Sói.
    -- Reconnect đã được phục hồi ở phần snapshot đầu phiên phía trên.
    if any isRoleAssignment (updateEvents update)
      then forM_
        (wolfTeamMessage (roomId room) actor (updateState update))
        (sendToClient outbound)
      else pure ()

    -- Luôn đồng bộ trạng thái riêng sau update để reconnect/UI không mở lại
    -- hành động hoặc bình thuốc đã dùng. Message này chỉ đi tới kết nối actor.
    if gamePhase (updateState update) /= Lobby
      then sendToClient outbound
        (privateActionStateMessage (roomId room) actor (updateState update))
      else pure ()

    -- Tin chat trực tiếp dùng chính record đã commit để ID/sequence khớp snapshot.
    forM_
      (updateChatRecord update >>= chatMessageForState
        (roomId room) actor (updateState update))
      (sendToClient outbound)

    -- Snapshot sau event giữ UI đồng bộ theo state đã commit; Lobby giữ contract cũ.
    if gamePhase (updateState update) /= Lobby
      then do
        sendToClient outbound (votingSnapshot (roomId room) actor (updateState update))
        if gamePhase (updateState update) == Day
          then sendToClient outbound
            (discussionSkipStateMessage (roomId room) actor (updateState update))
          else pure ()
        sendPhaseTimeRemaining outbound room
      else pure ()

  writeIORef sessionRef (Just (room, broadcastThread))

-- Chuyển deadline monotonic nội bộ thành thời lượng còn lại. Browser không cần
-- dùng cùng đồng hồ với Server và reconnect không làm cửa sổ chạy lại từ đầu.
sendPhaseTimeRemaining :: OutboundQueue -> RoomRuntime -> IO ()
sendPhaseTimeRemaining outbound room = do
  phaseDeadline <- readTVarIO (roomPhaseDeadline room)
  case phaseDeadline of
    Nothing -> pure ()
    Just (phase, day, deadlineNs) -> do
      now <- getMonotonicTimeNSec
      let remainingMs = fromIntegral ((deadlineNs - min deadlineNs now) `div` 1000000)
      sendToClient outbound
        (MsgPhaseTimeRemaining (roomId room) phase day remainingMs)

-- Token ngẫu nhiên không mang thông tin vai trò hay trạng thái ván.
newSessionToken :: IO String
newSessionToken = do
  first <- randomIO :: IO Word64
  second <- randomIO :: IO Word64
  pure (showHex first "" ++ showHex second "")

establishNewSession
  :: RoomRuntime
  -> PlayerId
  -> IORef (Maybe (RoomRuntime, ThreadId))
  -> OutboundQueue
  -> IO ()
establishNewSession room actor sessionRef outbound = do
  token <- newSessionToken
  atomically $
    modifyTVar' (roomReconnectTokens room)
      (((token, actor) :) . filter ((/= actor) . snd))
  sendToClient outbound (MsgSessionEstablished (roomId room) actor token)
  beginSession room actor sessionRef outbound

-- Tra loi khi tao phong that bai.

createErrorReply

  :: RequestId

  -> RoomId

  -> PlayerId

  -> String

  -> CreateRoomError

  -> ServerMessage

createErrorReply requestId rid actor name createError =

  case createError of

    InvalidRoomId ->

      MsgRejected

        (Just requestId)

        "INVALID_ROOM_ID"

        "Ma phong khong hop le."

    RoomAlreadyExists ->

      MsgRejected

        (Just requestId)

        "ROOM_ALREADY_EXISTS"

        "Ma phong nay da duoc su dung."

    HostJoinRejected domainError ->

      lobbyReply rid requestId actor (Join actor name)

        (Left domainError)

-- Loi cua NightAction.

nightActionErrorReply

  :: RequestId

  -> GameError

  -> ServerMessage

nightActionErrorReply requestId err =

  MsgRejected

    (Just requestId)

    (show err)

    ("NightAction bi tu choi: " ++ show err)

-- Loi cua StartGame.

startGameErrorReply

  :: RequestId

  -> GameError

  -> ServerMessage

startGameErrorReply requestId err =

  MsgRejected

    (Just requestId)

    (show err)

    ("StartGame bi tu choi: " ++ show err)

-- Xu ly StartGame bang preset va RNG do Server quan ly.

-- Browser khong duoc gui danh sach Role hay seed.

handleStartGame

  :: RoomRuntime

  -> RequestId

  -> PlayerId

  -> OutboundQueue

  -> IO ()

handleStartGame room requestId actor outbound = do

  currentState <- readTVarIO (roomState room)

  let playerCount = length (gamePlayers currentState)

  case expectedRoles playerCount of

    Nothing ->

      reject outbound requestId

        "INVALID_PLAYER_COUNT"

        "StartGame yeu cau du 8 hoac 9 nguoi."

    Just preset -> do

      -- Generator duoc tao o Server.

      generator <- newStdGen

      let (shuffledRoles, _) = shuffleRoles generator preset

          command = StartGame actor shuffledRoles

      -- Pure Engine kiem tra Host, Ready, Phase va preset.

      -- State, version va events duoc cap nhat trong STM.

      result <- submitCommand room requestId actor command

      case result of

        Left err ->

          sendToClient outbound

            (startGameErrorReply requestId err)

        Right _ ->

          -- PhaseChanged duoc gui qua RoomUpdate.

          -- Role rieng tu se duoc bo sung trong Broadcast.

          pure ()

-- Xu ly cac command tu Browser.

handleClientMessage

  :: RoomRegistry

  -> (RoomRuntime -> IO ())

  -> IORef PlayerId

  -> IORef (Maybe (RoomRuntime, ThreadId))

  -> OutboundQueue

  -> ClientMessage

  -> IO ()

handleClientMessage registry startWorker actorRef sessionRef outbound message = do

  actor <- readIORef actorRef

  case message of

    ClientReconnect requestId rid token -> do
      current <- readIORef sessionRef
      case current of
        Just _ ->
          reject outbound requestId "ALREADY_JOINED" "Ban da o trong mot phong."
        Nothing -> do
          found <- withMVar (registryRooms registry) $ \rooms ->
            case lookup rid rooms of
              Nothing -> pure Nothing
              Just room -> do
                tokens <- readTVarIO (roomReconnectTokens room)
                state <- readTVarIO (roomState room)
                pure $ case lookup token tokens of
                  Just restoredActor
                    | any ((== restoredActor) . playerId) (gamePlayers state) ->
                        Just (room, restoredActor)
                  _ -> Nothing
          case found of
            Nothing ->
              reject outbound requestId "INVALID_SESSION"
                "Phien choi khong con hop le. Hay tham gia lai."
            Just (room, restoredActor) -> do
              writeIORef actorRef restoredActor
              sendToClient outbound (MsgSessionEstablished rid restoredActor token)
              beginSession room restoredActor sessionRef outbound

    -- Tao phong.

    ClientCreateRoom requestId rid name -> do

      current <- readIORef sessionRef

      case current of

        Just _ ->

          reject outbound requestId "ALREADY_JOINED"

            "Ban da o trong mot phong."

        Nothing -> do

          result <-

            createRoomWithHost registry rid requestId actor name startWorker

          case result of

            Left err ->

              sendToClient outbound

                (createErrorReply requestId rid actor name err)

            Right (room, _) ->

              establishNewSession room actor sessionRef outbound


    -- Tao phong voi Appearance do nguoi choi chon.
    ClientCreateRoomWithAppearance requestId rid name appearance -> do
      current <- readIORef sessionRef

      case current of
        Just _ ->
          reject outbound requestId "ALREADY_JOINED"
            "Ban da o trong mot phong."

        Nothing -> do
          result <-
            createRoomWithHostAppearance
              registry rid requestId actor name appearance startWorker

          case result of
            Left err ->
              sendToClient outbound
                (createErrorReply requestId rid actor name err)

            Right (room, _) ->
              establishNewSession room actor sessionRef outbound


    -- Tham gia phong.

    ClientJoin requestId rid name -> do

      current <- readIORef sessionRef

      case current of

        Just _ ->

          reject outbound requestId "ALREADY_JOINED"

            "Ban da o trong mot phong."

        Nothing -> do

          let command = Join actor name

          found <- withMVar (registryRooms registry) $ \rooms ->

            case lookup rid rooms of

              Nothing ->

                pure Nothing

              Just room -> do

                result <- submitCommand room requestId actor command

                pure (Just (room, result))

          case found of

            Nothing ->

              reject outbound requestId "ROOM_NOT_FOUND"

                "Khong tim thay phong."

            Just (room, result) ->

              case result of

                Left _ ->

                  sendToClient outbound

                    (lobbyReply rid requestId actor command result)

                Right _ ->

                  establishNewSession room actor sessionRef outbound


    -- Tham gia phong voi Appearance do nguoi choi chon.
    ClientJoinWithAppearance requestId rid name appearance -> do
      current <- readIORef sessionRef

      case current of
        Just _ ->
          reject outbound requestId "ALREADY_JOINED"
            "Ban da o trong mot phong."

        Nothing -> do
          let command = JoinWithAppearance actor name appearance

          found <- withMVar (registryRooms registry) $ \rooms ->
            case lookup rid rooms of
              Nothing ->
                pure Nothing

              Just room -> do
                result <- submitCommand room requestId actor command
                pure (Just (room, result))

          case found of
            Nothing ->
              reject outbound requestId "ROOM_NOT_FOUND"
                "Khong tim thay phong."

            Just (room, result) ->
              case result of
                Left _ ->
                  sendToClient outbound
                    (lobbyReply rid requestId actor command result)

                Right _ ->
                  establishNewSession room actor sessionRef outbound


    -- Roi phong.

    ClientLeave requestId rid -> do

      current <- readIORef sessionRef

      case current of

        Nothing ->

          reject outbound requestId "NOT_JOINED"

            "Ban chua tham gia phong."

        Just (room, broadcastThread)

          | rid /= roomId room ->

              reject outbound requestId "WRONG_ROOM"

                "Ban khong o trong phong nay."

          | otherwise -> do

              let command = Leave actor

              result <- leaveAndPrune registry room requestId actor

              sendToClient outbound

                (lobbyReply rid requestId actor command result)

              case result of

                Right _ -> do

                  atomically $
                    modifyTVar' (roomReconnectTokens room)
                      (filter ((/= actor) . snd))

                  killThread broadcastThread

                  writeIORef sessionRef Nothing

                Left _ ->

                  pure ()

    -- Thay doi trang thai Ready.

    ClientSetReady requestId rid ready -> do

      current <- readIORef sessionRef

      case current of

        Nothing ->

          reject outbound requestId "NOT_JOINED"

            "Ban chua tham gia phong."

        Just (room, _)

          | rid /= roomId room ->

              reject outbound requestId "WRONG_ROOM"

                "Ban khong o trong phong nay."

          | otherwise -> do

              let command = SetReady actor ready

              result <- submitCommand room requestId actor command

              sendToClient outbound

                (lobbyReply rid requestId actor command result)

    -- T04/T05: Host yeu cau bat dau van.

    ClientStartGame requestId rid -> do

      current <- readIORef sessionRef

      case current of

        Nothing ->

          reject outbound requestId "NOT_JOINED"

            "Ban chua tham gia phong."

        Just (room, _)

          | rid /= roomId room ->

              reject outbound requestId "WRONG_ROOM"

                "Ban khong o trong phong nay."

          | otherwise ->

              handleStartGame room requestId actor outbound

    -- T05: Gui NightAction vao Room Command Queue.

    ClientNightAction requestId rid choice -> do

      current <- readIORef sessionRef

      case current of

        Nothing ->

          reject outbound requestId "NOT_JOINED"

            "Ban chua tham gia phong."

        Just (room, _)

          | rid /= roomId room ->

              reject outbound requestId "WRONG_ROOM"

                "Ban khong o trong phong nay."

          | otherwise -> do

              let command = NightAction actor choice

              result <- submitCommand room requestId actor command

              case result of

                Left err ->

                  sendToClient outbound

                    (nightActionErrorReply requestId err)

                Right _ ->

                  -- NightActionAccepted duoc gui qua DomainEvent.

                  pure ()

    -- T05/T06: Giữ contract HunterAction của develop, gắn actor từ session.
    -- NightChoice chỉ là payload; Domain ResolveHunter kiểm tra quyền pending.
    ClientHunterAction requestId rid choice ->
      case choice of
        HunterShot target -> handlePlayerCommand requestId rid (ResolveHunter actor (Just target))
        HunterPass -> handlePlayerCommand requestId rid (ResolveHunter actor Nothing)
        _ -> reject outbound requestId "INVALID_HUNTER_ACTION" "Lựa chọn Hunter không hợp lệ."

    -- Vote chỉ nhận mục tiêu; không nhận ID hoặc vai do Browser khai báo.
    ClientVote requestId rid target ->
      handlePlayerCommand requestId rid (Vote actor target)

    -- T07: Chat chi hop le trong Day va voi nguoi con song.
    ClientChat requestId rid messageText ->
      handlePlayerCommand requestId rid (Chat actor messageText)

    -- T07: Kênh do client yêu cầu vẫn được Domain xác thực theo phase/vai/life.
    ClientChannelChat requestId rid channel messageText ->
      handlePlayerCommand requestId rid
        (ChatInChannel actor channel messageText)

    -- Mỗi người còn sống xác nhận một lần; Engine chỉ chuyển sang Voting
    -- khi toàn bộ người còn sống trong phòng đã đồng ý.
    ClientSkipDiscussion requestId rid ->
      handlePlayerCommand requestId rid (SkipDiscussion actor)
  where
    handlePlayerCommand requestId rid command = do
      currentActor <- readIORef actorRef
      current <- readIORef sessionRef

      case current of
        Nothing ->
          reject outbound requestId "NOT_JOINED"
            "Ban chua tham gia phong."

        Just (room, _)
          | rid /= roomId room ->
              reject outbound requestId "WRONG_ROOM"
                "Ban khong o trong phong nay."

          | otherwise -> do
              result <- submitCommand room requestId currentActor command

              case result of
                Left err ->
                  sendToClient outbound
                    (MsgRejected
                      (Just requestId)
                      (show err)
                      ("Yêu cầu bị từ chối: " ++ show err))

                Right _ ->
                  -- Receipt theo requestId để UI chỉ kết thúc đúng yêu cầu đang chờ.
                  sendToClient outbound (MsgActionAccepted requestId rid)

-- Tao WebSocket connection va session.

webSocketApp

  :: RoomRegistry

  -> (RoomRuntime -> IO ())

  -> WS.ServerApp

webSocketApp registry startWorker pending = do

  connection <- WS.acceptRequest pending

  -- Cap PlayerId tai Server.

  actor <- atomically $ do

    nextId <- readTVar (registryNextPlayerId registry)

    writeTVar (registryNextPlayerId registry) (nextId + 1)

    pure ("p" ++ show nextId)

  sessionRef <- newIORef Nothing

  actorRef <- newIORef actor

  outbound <- newOutboundQueue

  -- Moi connection co mot writer rieng, bo qua ngoai le dong socket thong thuong.

  writerThread <- forkIO $ runIgnoringBenignSocketException $ forever $ do

    message <- atomically (readOutbound outbound)

    WS.sendTextData connection (encodeServerMessage message)

  let receiveLoop = runIgnoringBenignSocketException $ forever $ do

        frame <- WS.receiveDataMessage connection

        case frame of

          WS.Text payload _ ->

            case decodeClientMessage payload of

              Left _ ->

                sendToClient outbound

                  (MsgRejected Nothing "INVALID_JSON"

                    "JSON khong hop le.")

              Right clientMessage ->

                handleClientMessage

                  registry

                  startWorker

                  actorRef

                  sessionRef

                  outbound

                  clientMessage

          WS.Binary _ ->

            sendToClient outbound

              (MsgRejected Nothing "TEXT_REQUIRED"

                "Hay gui text frame JSON.")

      cleanup = do

        current <- readIORef sessionRef

        case current of

          Just (_, broadcastThread) -> do

            -- Mất kết nối không xóa Player; token cho phép nối lại đúng phiên.
            killThread broadcastThread

          Nothing ->

            pure ()

        killThread writerThread

  receiveLoop `finally` cleanup
