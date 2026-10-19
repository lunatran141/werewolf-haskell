-- | Vòng đời connection, hàng đợi gửi có giới hạn (backpressure),
-- timeout, disconnect và cleanup cho từng phiên WebSocket.
module Server.Connection
  ( OutboundQueue
  , defaultOutboundCapacity
  , newOutboundQueue
  , newOutboundQueueWithCapacity
  , readOutbound
  , readOutboundRecoverable
  , tryReadOutbound
  , sendBounded
  , writeBoundedDropOldest
  , enqueueOutbound
  , tryEnqueueRoomCommand
  , runSupervisedConnection
  ) where

import Control.Concurrent.STM
  ( STM
  , TBQueue
  , isFullTBQueue
  , newTBQueueIO
  , readTBQueue
  , newTVarIO
  , readTVar
  , writeTVar
  , TVar
  , tryReadTBQueue
  , writeTBQueue
  )
import Control.Exception (finally)
import Numeric.Natural (Natural)
import Protocol.Types (ServerMessage)
import Server.Room (QueuedCommand, RoomRuntime(..))
import Server.Supervisor
  ( Supervisor
  , forkSupervised
  , runIgnoringBenignSocketException
  , withSupervisedGroup
  )

-- | Hàng đợi thông điệp gửi ra WebSocket có giới hạn sức chứa (Bounded Queue)
-- để ngăn slow consumer làm tăng bộ nhớ vô hạn.
data OutboundQueue = OutboundQueue
  { outboundMessages :: TBQueue ServerMessage
  , outboundOverflowed :: TVar Bool
  }

-- | Sức chứa mặc định cho hàng đợi gửi của mỗi client.
defaultOutboundCapacity :: Natural
defaultOutboundCapacity = 256

-- | Tạo hàng đợi gửi với sức chứa mặc định.
newOutboundQueue :: IO OutboundQueue
newOutboundQueue = newOutboundQueueWithCapacity defaultOutboundCapacity

-- | Tạo hàng đợi gửi với sức chứa tùy chỉnh (tối thiểu 1).
newOutboundQueueWithCapacity :: Natural -> IO OutboundQueue
newOutboundQueueWithCapacity capacity =
  OutboundQueue
    <$> newTBQueueIO (max 1 capacity)
    <*> newTVarIO False

-- | Đọc một thông điệp từ hàng đợi gửi (chặn trong STM nếu rỗng).
readOutbound :: OutboundQueue -> STM ServerMessage
readOutbound = readTBQueue . outboundMessages

-- | Lấy message, hoặc báo worker gửi socket đóng nếu hàng đợi từng tràn.
-- Khi tràn, đóng kết nối buộc client reconnect và nhận snapshot đầy đủ.
readOutboundRecoverable :: OutboundQueue -> STM (Maybe ServerMessage)
readOutboundRecoverable queue = do
  overflowed <- readTVar (outboundOverflowed queue)
  if overflowed
    then pure Nothing
    else Just <$> readTBQueue (outboundMessages queue)

-- | Đọc không chặn một thông điệp từ hàng đợi gửi.
tryReadOutbound :: OutboundQueue -> STM (Maybe ServerMessage)
tryReadOutbound = tryReadTBQueue . outboundMessages

-- | Ghi thông điệp vào hàng đợi nếu chưa đầy.
-- Trả về True nếu ghi thành công, False nếu hàng đợi đã đầy (backpressure).
sendBounded :: OutboundQueue -> ServerMessage -> STM Bool
sendBounded queue message = do
  full <- isFullTBQueue (outboundMessages queue)
  if full
    then pure False
    else do
      writeTBQueue (outboundMessages queue) message
      pure True

-- | Ghi thông điệp vào hàng đợi có giới hạn:
-- Nếu hàng đợi đã đầy do client đọc quá chậm (slow consumer), bỏ thông điệp cũ nhất
-- để nhường chỗ cho thông điệp/snapshot mới nhất mà không bao giờ làm treo luồng gửi.
-- Trả về True nếu ghi bình thường, False nếu đã phải bỏ bớt 1 tin cũ.
writeBoundedDropOldest :: OutboundQueue -> ServerMessage -> STM Bool
writeBoundedDropOldest queue message = do
  full <- isFullTBQueue (outboundMessages queue)
  if full
    then do
      _ <- tryReadTBQueue (outboundMessages queue)
      writeTBQueue (outboundMessages queue) message
      pure False
    else do
      writeTBQueue (outboundMessages queue) message
      pure True

-- | Không âm thầm bỏ event: khi đầy, đánh dấu kết nối cần reconnect để lấy snapshot.
enqueueOutbound :: OutboundQueue -> ServerMessage -> STM Bool
enqueueOutbound queue message = do
  overflowed <- readTVar (outboundOverflowed queue)
  full <- isFullTBQueue (outboundMessages queue)
  if overflowed || full
    then writeTVar (outboundOverflowed queue) True >> pure False
    else writeTBQueue (outboundMessages queue) message >> pure True

-- | Đưa lệnh của người chơi vào hàng đợi lệnh của phòng nếu hàng đợi chưa đầy.
-- Trả về False ngay lập tức khi hàng đợi đầy (chống spam làm treo kết nối).
tryEnqueueRoomCommand :: RoomRuntime -> QueuedCommand -> STM Bool
tryEnqueueRoomCommand room command = do
  let queue = roomCommands room
  full <- isFullTBQueue queue
  if full
    then pure False
    else do
      writeTBQueue queue command
      pure True

-- | Chạy cặp writer và reader cho một kết nối WebSocket dưới sự quản lý của Supervisor,
-- đảm bảo khi kết nối đóng hoặc một luồng gặp lỗi thì mọi worker con đều được dọn sạch
-- và các lỗi đóng socket thông thường không văng ra ngoài.
runSupervisedConnection
  :: (Supervisor -> IO ())
  -> IO ()
  -> IO ()
  -> IO ()
runSupervisedConnection onStart writerAction readerAction =
  withSupervisedGroup $ \supervisor -> do
    onStart supervisor
    _ <- forkSupervised supervisor "ws-writer"
      (runIgnoringBenignSocketException writerAction)
    runIgnoringBenignSocketException readerAction
      `finally` pure ()
