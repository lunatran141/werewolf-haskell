-- | Một đường xử lý Command chung từ queue tới Pure Engine.
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
  , takeTMVar
  , writeTBQueue
  , writeTChan
  , writeTVar
  )
import Data.Char (isSpace)
import Domain.Engine (applyLobbyCommand)
import Domain.Types
  ( Command(..)
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

-- Kiểm tra ID trong lệnh khớp với ID Server gắn cho phiên kết nối.
-- Lệnh đổi pha và chia vai chưa đi qua luồng Lobby này.
actorMatches :: QueuedCommand -> Bool
actorMatches request =
  case queuedCommand request of
    Join pid _     -> pid == queuedActorId request
    Leave pid      -> pid == queuedActorId request
    SetReady pid _ -> pid == queuedActorId request
    _              -> False

-- Xử lý đúng một lệnh; hàm sẽ chờ nếu hàng đợi đang rỗng.
processNextLobbyCommand :: RoomRuntime -> IO ()
processNextLobbyCommand room = atomically $ do
  request <- readTBQueue (roomCommands room)
  currentState <- readTVar (roomState room)

  let result =
        if actorMatches request
          then applyLobbyCommand currentState (queuedCommand request)
          else Left NotAuthorized

  case result of
    Left err ->
      -- Lệnh lỗi: không sửa state, không phát event.
      putTMVar (queuedReply request) (Left err)

    Right (nextState, events) -> do
      currentVersion <- readTVar (roomVersion room)
      let nextVersion = currentVersion + 1

      writeTVar (roomState room) nextState
      writeTVar (roomVersion room) nextVersion
      writeTChan (roomUpdates room)
        RoomUpdate
          { updateVersion = nextVersion
          , updateState = nextState
          , updateEvents = events
          }
      putTMVar (queuedReply request) (Right nextState)

-- Worker dừng khi người cuối cùng rời phòng.
runLobbyLoop :: RoomRuntime -> IO ()
runLobbyLoop room = do
  processNextLobbyCommand room
  state <- atomically (readTVar (roomState room))
  if null (gamePlayers state)
    then pure ()
    else runLobbyLoop room

data CreateRoomError
  = InvalidRoomId
  | RoomAlreadyExists
  | HostJoinRejected GameError
  deriving (Eq, Show)

-- Chỉ đưa phòng vào Registry sau khi Host Join thành công.
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

            -- Phòng chưa được công bố; xử lý Join đầu tiên ngay tại đây.
            processNextLobbyCommand room
            result <- atomically (takeTMVar reply)

            case result of
              Left err ->
                pure (rooms, Left (HostJoinRejected err))

              Right state -> do
                startWorker room
                pure ((rid, room) : rooms, Right (room, state))