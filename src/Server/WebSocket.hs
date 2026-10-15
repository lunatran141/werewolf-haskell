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

  , nightMessagesFor
  , votingSnapshot
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

import System.Random (newStdGen)

-- Gui ServerMessage vao hang doi cua mot ket noi.

sendToClient :: TQueue ServerMessage -> ServerMessage -> IO ()

sendToClient outbound message =

  atomically (writeTQueue outbound message)

-- Gui CommandRejected cho ket noi da gui yeu cau.

reject

  :: TQueue ServerMessage

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

-- Gui LobbySnapshot va dang ky nhan RoomUpdate.

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

    -- Giu nguyen luong Lobby.

    forM_

      (filter (forOtherPlayer actor)

        (lobbyMessages (roomId room) update))

      (sendToClient outbound)

    -- T05: Loc event theo quyen nhan cua PlayerId.

    let safeEvents = filter safeNightEvent (updateEvents update)

        nightMessages =

          nightMessagesFor (roomId room) actor safeEvents

    forM_ nightMessages (sendToClient outbound)

    -- Snapshot sau event giữ UI đồng bộ theo state đã commit; Lobby giữ contract cũ.
    if gamePhase (updateState update) /= Lobby
      then sendToClient outbound (votingSnapshot (roomId room) actor (updateState update))
      else pure ()

  writeIORef sessionRef (Just (room, broadcastThread))

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

  -> TQueue ServerMessage

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

  -> PlayerId

  -> IORef (Maybe (RoomRuntime, ThreadId))

  -> TQueue ServerMessage

  -> ClientMessage

  -> IO ()

handleClientMessage registry startWorker actor sessionRef outbound message =

  case message of

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

              beginSession room actor sessionRef outbound


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
              beginSession room actor sessionRef outbound


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

                  beginSession room actor sessionRef outbound


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
                  beginSession room actor sessionRef outbound


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
        HunterShot target -> handleVotingCommand requestId rid (ResolveHunter actor (Just target))
        HunterPass -> handleVotingCommand requestId rid (ResolveHunter actor Nothing)
        _ -> reject outbound requestId "INVALID_HUNTER_ACTION" "Lựa chọn Hunter không hợp lệ."

    -- Vote chỉ nhận mục tiêu; không nhận ID hoặc vai do Browser khai báo.
    ClientVote requestId rid target ->
      handleVotingCommand requestId rid (Vote actor target)
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

  -- Cap PlayerId tai Server.

  actor <- atomically $ do

    nextId <- readTVar (registryNextPlayerId registry)

    writeTVar (registryNextPlayerId registry) (nextId + 1)

    pure ("p" ++ show nextId)

  sessionRef <- newIORef Nothing

  outbound <- newTQueueIO

  -- Moi connection co mot writer rieng.

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

            -- Dong ket noi duoc xu ly nhu Leave.

            _ <- leaveAndPrune registry room "disconnect" actor

            killThread broadcastThread

          Nothing ->

            pure ()

        killThread writerThread

  receiveLoop `finally` cleanup
