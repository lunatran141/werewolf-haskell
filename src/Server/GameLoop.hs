
-- | Mot duong xu ly Command chung tu queue toi Pure Engine.
module Server.GameLoop
  ( processNextLobbyCommand
  , runLobbyLoop
  , CreateRoomError(..)
  , createRoomWithHost
  ) where

import Control.Concurrent.MVar (modifyMVar)

import Control.Concurrent.STM
  ( atomically
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
  ( applyLobbyCommand
  , applyNightCommand
  )

import Domain.Types
  ( Command(..)
  , DomainEvent
  , GameError(..)
  , GameState(..)
  , PlayerId
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

    -- Khong cho phep client tu goi lenh noi bo.
    _ ->
      False



-- T05: Dispatcher Lobby va NightAction

-- Chon Pure Engine theo loai command.
-- Khong cho client tu goi ResolveNight, StartGame,
-- AdvancePhase hoac cac lenh noi bo khac qua dispatcher nay.
dispatchPlayerCommand
  :: GameState
  -> Command
  -> Either GameError (GameState, [DomainEvent])
dispatchPlayerCommand state command =
  case command of
    -- T05: Xu ly hanh dong ban dem.
    NightAction _ _ ->
      applyNightCommand state command

    -- Giu nguyen xu ly Lobby.
    Join _ _ ->
      applyLobbyCommand state command

    Leave _ ->
      applyLobbyCommand state command

    SetReady _ _ ->
      applyLobbyCommand state command

    -- Lenh khong thuoc dispatcher nay bi tu choi.
    _ ->
      Left NotAuthorized



-- Xu ly Command Queue

-- Xu ly dung mot lenh; ham se cho neu hang doi dang rong.
-- Cap nhat state, version va event trong cung mot giao dich STM.
processNextLobbyCommand :: RoomRuntime -> IO ()
processNextLobbyCommand room = atomically $ do
  request <- readTBQueue (roomCommands room)
  currentState <- readTVar (roomState room)

  let result =
        if actorMatches request
          then dispatchPlayerCommand currentState (queuedCommand request)
          else Left NotAuthorized

  case result of
    Left err -> do
      -- Lenh loi: khong sua state, khong tang version,
      -- khong phat DomainEvent.
      putTMVar (queuedReply request) (Left err)

    Right (nextState, events) -> do
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
runLobbyLoop room = do
  processNextLobbyCommand room

  state <- readTVarIO (roomState room)

  if null (gamePlayers state)
    then pure ()
    else runLobbyLoop room



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
