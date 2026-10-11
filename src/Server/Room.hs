-- | Runtime của một phòng chơi và GameState được bảo vệ bằng STM.
module Server.Room where


import Control.Concurrent.STM
  ( TBQueue
  , TChan
  , TMVar
  , TVar
  , newBroadcastTChanIO
  , newTBQueueIO
  , newTVarIO
  )
import Domain.Types
  ( Command
  , DomainEvent
  , GameError
  , GameState
  , PlayerId
  , emptyLobby
  )
import Protocol.Types (RequestId, RoomId)
import Control.Concurrent.MVar (MVar, newMVar, withMVar)

-- Lệnh đã được Server gắn thông tin người gửi.
-- PlayerId phải lấy từ phiên kết nối, không lấy từ JSON của Browser.
data QueuedCommand = QueuedCommand
  { queuedRequestId :: RequestId
  , queuedActorId   :: PlayerId
  , queuedCommand   :: Command
  , queuedReply     :: TMVar (Either GameError GameState)
  }

-- Một lần cập nhật thành công, dành cho bộ phận Broadcast nội bộ.
data RoomUpdate = RoomUpdate
  { updateVersion :: Int
  , updateState   :: GameState
  , updateEvents  :: [DomainEvent]
  }

data RoomRuntime = RoomRuntime
  { roomId       :: RoomId
  , roomState    :: TVar GameState
  , roomVersion  :: TVar Int
  , roomCommands :: TBQueue QueuedCommand
  , roomUpdates  :: TChan RoomUpdate
  , roomNextPlayerId :: TVar Int
  }

newRoomRuntime :: RoomId -> IO RoomRuntime
newRoomRuntime rid = do
  stateVar <- newTVarIO emptyLobby
  versionVar <- newTVarIO 0
  commandQueue <- newTBQueueIO 128
  updateChannel <- newBroadcastTChanIO
  playerIdCounter <- newTVarIO 1
  pure RoomRuntime
    { roomId = rid
    , roomState = stateVar
    , roomVersion = versionVar
    , roomCommands = commandQueue
    , roomUpdates = updateChannel
    , roomNextPlayerId = playerIdCounter
    }

-- Danh sách các phòng đã tạo. MVar bảo vệ thao tác kiểm tra mã trùng
-- và thêm phòng khi nhiều kết nối CreateRoom cùng lúc.
data RoomRegistry = RoomRegistry
  { registryRooms :: MVar [(RoomId, RoomRuntime)]
  , registryNextPlayerId :: TVar Int
  }

newRoomRegistry :: IO RoomRegistry
newRoomRegistry = do
  rooms <- newMVar []
  nextPlayerId <- newTVarIO 1
  pure RoomRegistry
    { registryRooms = rooms
    , registryNextPlayerId = nextPlayerId
    }

findRoom :: RoomRegistry -> RoomId -> IO (Maybe RoomRuntime)
findRoom registry rid =
  withMVar (registryRooms registry) (pure . lookup rid)