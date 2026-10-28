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
  ( ChatRecord
  , Command
  , DomainEvent
  , GameError
  , GameState
  , Phase
  , PlayerId
  , emptyLobby
  )
import Protocol.Types (RequestId, RoomId)
import Control.Concurrent.MVar (MVar, newMVar, withMVar)
import Data.Word (Word64)
import Numeric (showHex)
import Numeric.Natural (Natural)
import System.Random (randomIO)

-- | Sức chứa mặc định của hàng đợi lệnh cho mỗi phòng.
defaultCommandQueueCapacity :: Natural
defaultCommandQueueCapacity = 128

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
  , updateChatRecord :: Maybe ChatRecord
  }

data RoomRuntime = RoomRuntime
  { roomId       :: RoomId
  -- ID rieng cho moi lan tao phong, tranh trung matchId khi tai su dung roomId.
  , roomInstanceId :: String
  , roomState    :: TVar GameState
  , roomVersion  :: TVar Int
  , roomCommands :: TBQueue QueuedCommand
  , roomUpdates  :: TChan RoomUpdate
  , roomNextPlayerId :: TVar Int
  -- Request Vote/Hunter/Chat đã thành công, lưu theo actor suốt vòng đời phòng.
  , roomAcceptedRequests :: TVar [(PlayerId, RequestId)]
  -- T07: Lịch sử chat thuộc về phòng, không phụ thuộc vòng đời kết nối.
  , roomChatHistory :: TVar [ChatRecord]
  -- Sequence tăng dần giúp mọi client sắp xếp và khử tin trùng ổn định.
  , roomNextChatSequence :: TVar Int
  -- Token chỉ dùng để nối lại đúng PlayerId sau khi WebSocket bị ngắt.
  , roomReconnectTokens :: TVar [(String, PlayerId)]
  -- Mốc monotonic của từng lượt; stage phân biệt Sói và vai Dân trong đêm.
  , roomPhaseDeadline :: TVar (Maybe (Phase, Int, Maybe String, Word64))
  }

newRoomRuntime :: RoomId -> IO RoomRuntime
newRoomRuntime = newRoomRuntimeWithCapacity defaultCommandQueueCapacity

newRoomRuntimeWithCapacity :: Natural -> RoomId -> IO RoomRuntime
newRoomRuntimeWithCapacity capacity rid = do
  instanceNumber <- randomIO :: IO Word64
  stateVar <- newTVarIO emptyLobby
  versionVar <- newTVarIO 0
  commandQueue <- newTBQueueIO (max 1 capacity)
  updateChannel <- newBroadcastTChanIO
  playerIdCounter <- newTVarIO 1
  acceptedRequests <- newTVarIO []
  chatHistory <- newTVarIO []
  nextChatSequence <- newTVarIO 1
  reconnectTokens <- newTVarIO []
  phaseDeadline <- newTVarIO Nothing
  pure RoomRuntime
    { roomId = rid
    , roomInstanceId = showHex instanceNumber ""
    , roomState = stateVar
    , roomVersion = versionVar
    , roomCommands = commandQueue
    , roomUpdates = updateChannel
    , roomNextPlayerId = playerIdCounter
    , roomAcceptedRequests = acceptedRequests
    , roomChatHistory = chatHistory
    , roomNextChatSequence = nextChatSequence
    , roomReconnectTokens = reconnectTokens
    , roomPhaseDeadline = phaseDeadline
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
