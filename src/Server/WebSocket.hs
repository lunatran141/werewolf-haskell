
module Server.WebSocket (webSocketApp) where

import Control.Concurrent (ThreadId, forkIO, killThread)
import Control.Concurrent.MVar (modifyMVar, withMVar)
import Control.Concurrent.STM
  ( TQueue
  , atomically
  , dupTChan
  , newEmptyTMVarIO
  , newTQueueIO
  , readTChan
  , readTQueue
  , readTVar
  , readTVarIO
  , takeTMVar
  , writeTBQueue
  , writeTQueue
  , writeTVar
  )
import Control.Exception (finally)
import Control.Monad (forM_, forever)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Domain.Types
  ( Command(..)
  , DomainEvent(..)
  , GameError(..)
  , GameState(..)
  , Player(..)
  , PlayerId
  , Phase(..)
  )
import qualified Network.WebSockets as WS
import Protocol.Json (decodeClientMessage, encodeServerMessage)
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
  , nightMessagesFor
  , votingSnapshot
  )
import Server.GameLoop (CreateRoomError(..), createRoomWithHost)
import Server.Room
  ( QueuedCommand(..)
  , RoomRegistry(..)
  , RoomRuntime(..)
  , RoomUpdate(..)
  )

sendToClient :: TQueue ServerMessage -> ServerMessage -> IO ()
sendToClient outbound message =
  atomically (writeTQueue outbound message)

reject
  :: TQueue ServerMessage
  -> RequestId
  -> String
  -> String
  -> IO ()
reject outbound requestId code message =
  sendToClient outbound
    (MsgRejected (Just requestId) code message)

-- PlayerId duoc gan boi Server, khong lay tu JSON Browser.
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
-- Nho vay Join moi khong the chen vao giua hai thao tac.
leaveAndPrune
  :: RoomRegistry
  -> RoomRuntime
  -> RequestId
  -> PlayerId
  -> IO (Either GameError GameState)
leaveAndPrune registry room requestId actor =
  modifyMVar (registryRooms registry) $ \rooms -> do
    currentState <- readTVarIO (roomState room)

    -- Neu nguoi choi da roi, khong gui Leave vao worker da dung.
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

-- NightResolved co the xuat hien khi Hunter chua xu ly xong.
-- Khong cong khai danh sach nguoi chet tu event nay.
-- PlayerRoleRevealed duoc phat khi Engine hoan tat death effects.
safeNightEvent :: DomainEvent -> Bool
safeNightEvent event =
  case event of
    NightResolved _ ->
      False
    _ ->
      True

-- Doc snapshot va dang ky nhan cap nhat trong cung transaction.
beginSession
  :: RoomRuntime
  -> PlayerId
  -> IORef (Maybe (RoomRuntime, ThreadId))
  -> TQueue ServerMessage
  -> IO ()
beginSession room actor sessionRef outbound = do
  updates <- atomically $ do
    channel <- dupTChan (roomUpdates room)
    state <- readTVar (roomState room)

    writeTQueue outbound
      (lobbySnapshot (roomId room) actor state)

    pure channel

  broadcastThread <- forkIO $ forever $ do
    update <- atomically (readTChan updates)

    -- Gui cac event Lobby nhu truoc day.
    forM_
      (filter (forOtherPlayer actor)
        (lobbyMessages (roomId room) update))
      (sendToClient outbound)

    -- T05: Loc Night Event theo PlayerId cua phien ket noi.
    -- Khong broadcast thong tin rieng tu cho ca phong.
    let safeEvents = filter safeNightEvent (updateEvents update)
        nightMessages =
          nightMessagesFor (roomId room) actor safeEvents

    forM_ nightMessages (sendToClient outbound)

    -- Snapshot sau event giữ UI đồng bộ theo state đã commit; Lobby giữ contract cũ.
    if gamePhase (updateState update) /= Lobby
      then sendToClient outbound (votingSnapshot (roomId room) actor (updateState update))
      else pure ()

  writeIORef sessionRef (Just (room, broadcastThread))

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

-- Chi gui loi cho client da gui command.
-- NightAction thanh cong duoc xac nhan bang NightActionAccepted.
nightActionErrorReply
  :: RequestId
  -> GameError
  -> ServerMessage
nightActionErrorReply requestId err =
  MsgRejected
    (Just requestId)
    (show err)
    ("NightAction bi tu choi: " ++ show err)

handleClientMessage
  :: RoomRegistry
  -> (RoomRuntime -> IO ())
  -> PlayerId
  -> IORef (Maybe (RoomRuntime, ThreadId))
  -> TQueue ServerMessage
  -> ClientMessage
  -> IO ()
handleClientMessage registry startWorker actor sessionRef outbound message =
  case message of
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
              beginSession room actor sessionRef outbound

    ClientJoin requestId rid name -> do
      current <- readIORef sessionRef

      case current of
        Just _ ->
          reject outbound requestId "ALREADY_JOINED"
            "Ban da o trong mot phong."

        Nothing -> do
          let command = Join actor name

          -- Giu khoa Registry trong khi Join duoc xu ly.
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
                  beginSession room actor sessionRef outbound

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
                  killThread broadcastThread
                  writeIORef sessionRef Nothing

                Left _ ->
                  pure ()

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

    -- T05: Dua NightAction vao queue bang PlayerId cua Server.
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
                  -- Ack duoc gui qua DomainEvent, tranh gui trung.
                  pure ()

    -- T06: Browser chi gui targetId; actor duoc gan tu session hien tai.
    -- ActionAccepted xác nhận đúng request; VoteUpdated là receipt riêng của voter.
    ClientVote requestId rid targetId -> do
      handleVotingCommand requestId rid (Vote actor targetId)

    -- Lựa chọn từ client được chuyển thành lệnh Domain sau khi gắn actor của phiên.
    ClientHunterChoice requestId rid targetId ->
      handleVotingCommand requestId rid (ResolveHunter actor targetId)
  where
    handleVotingCommand requestId rid command = do
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
              result <- submitCommand room requestId actor command

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

webSocketApp
  :: RoomRegistry
  -> (RoomRuntime -> IO ())
  -> WS.ServerApp
webSocketApp registry startWorker pending = do
  connection <- WS.acceptRequest pending

  -- ID do Server cap; Browser khong gui PlayerId.
  actor <- atomically $ do
    nextId <- readTVar (registryNextPlayerId registry)
    writeTVar (registryNextPlayerId registry) (nextId + 1)
    pure ("p" ++ show nextId)

  sessionRef <- newIORef Nothing
  outbound <- newTQueueIO

  writerThread <- forkIO $ forever $ do
    message <- atomically (readTQueue outbound)
    WS.sendTextData connection (encodeServerMessage message)

  let receiveLoop = forever $ do
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
                  actor
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
          Just (room, broadcastThread) -> do
            -- Dong tab hoac mat ket noi xu ly nhu Leave.
            _ <- leaveAndPrune registry room "disconnect" actor
            killThread broadcastThread

          Nothing ->
            pure ()

        killThread writerThread

  receiveLoop `finally` cleanup
