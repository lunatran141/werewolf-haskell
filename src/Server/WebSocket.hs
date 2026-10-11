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
  , GameError(..)
  , GameState(..)
  , Player(..)
  , PlayerId
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
import Server.Broadcast (lobbyMessages, lobbyReply, lobbySnapshot)
import Server.GameLoop (CreateRoomError(..), createRoomWithHost)
import Server.Room
  ( QueuedCommand(..)
  , RoomRegistry(..)
  , RoomRuntime(..)
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

-- Xử lý Leave và xóa phòng rỗng dưới cùng khóa Registry.
-- Nhờ vậy Join mới không thể chen vào giữa hai thao tác.
leaveAndPrune
  :: RoomRegistry
  -> RoomRuntime
  -> RequestId
  -> PlayerId
  -> IO (Either GameError GameState)
leaveAndPrune registry room requestId actor =
  modifyMVar (registryRooms registry) $ \rooms -> do
    currentState <- atomically (readTVar (roomState room))

    -- Nếu người chơi đã rời, không gửi Leave vào worker có thể đã dừng.
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
    MsgPlayerJoined _ player -> viewPlayerId player /= actor
    MsgPlayerLeft _ pid      -> pid /= actor
    MsgReadyChanged _ pid _  -> pid /= actor
    _                       -> True

-- Đọc snapshot và đăng ký nhận cập nhật trong cùng một transaction.
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
    forM_
      (filter (forOtherPlayer actor)
        (lobbyMessages (roomId room) update))
      (sendToClient outbound)

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
      MsgRejected (Just requestId) "INVALID_ROOM_ID"
        "Mã phòng không hợp lệ."

    RoomAlreadyExists ->
      MsgRejected (Just requestId) "ROOM_ALREADY_EXISTS"
        "Mã phòng này đã được sử dụng."

    HostJoinRejected domainError ->
      lobbyReply rid requestId actor (Join actor name)
        (Left domainError)

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
            "Bạn đã ở trong một phòng."

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
            "Bạn đã ở trong một phòng."

        Nothing -> do
          let command = Join actor name

          -- Giữ khóa Registry trong lúc Join được xử lý.
          -- Leave của người cuối sẽ phải chờ Join này hoàn tất.
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
                "Không tìm thấy phòng."

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
            "Bạn chưa tham gia phòng."

        Just (room, broadcastThread)
          | rid /= roomId room ->
              reject outbound requestId "WRONG_ROOM"
                "Bạn không ở trong phòng này."

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
            "Bạn chưa tham gia phòng."

        Just (room, _)
          | rid /= roomId room ->
              reject outbound requestId "WRONG_ROOM"
                "Bạn không ở trong phòng này."

          | otherwise -> do
              let command = SetReady actor ready
              result <- submitCommand room requestId actor command

              sendToClient outbound
                (lobbyReply rid requestId actor command result)

webSocketApp
  :: RoomRegistry
  -> (RoomRuntime -> IO ())
  -> WS.ServerApp
webSocketApp registry startWorker pending = do
  connection <- WS.acceptRequest pending

  -- ID do Server cấp; Browser không gửi PlayerId.
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
                    "JSON không hợp lệ.")

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
                "Hãy gửi text frame JSON.")

      cleanup = do
        current <- readIORef sessionRef

        case current of
          Just (room, broadcastThread) -> do
            -- Đóng tab hoặc mất kết nối cũng xử lý như Leave.
            _ <- leaveAndPrune registry room "disconnect" actor
            killThread broadcastThread

          Nothing ->
            pure ()

        killThread writerThread

  receiveLoop `finally` cleanup