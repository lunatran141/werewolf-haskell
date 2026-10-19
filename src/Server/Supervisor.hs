-- | Quản lý vòng đời worker (reader, writer, broadcast, game-loop) có cấu trúc.
-- Cô lập ngoại lệ theo phòng/phiên, hủy sạch nhóm thread con và tránh orphan thread.
module Server.Supervisor
  ( Supervisor(..)
  , SupervisorEvent(..)
  , newSupervisor
  , forkSupervised
  , shutdownSupervisor
  , withSupervisedGroup
  , activeWorkerCount
  , supervisorEvents
  , isBenignSocketException
  , runIgnoringBenignSocketException
  ) where

import Control.Concurrent (ThreadId, forkFinally, killThread, myThreadId)
import Control.Concurrent.STM
  ( TVar
  , atomically
  , check
  , modifyTVar'
  , newTVarIO
  , readTVar
  , readTVarIO
  )
import Control.Exception
  ( AsyncException(ThreadKilled)
  , IOException
  , SomeException
  , bracket
  , catch
  , displayException
  , fromException
  , mask_
  , throwIO
  )
import Data.List (isInfixOf)
import qualified Network.WebSockets as WS

-- | Sự kiện vòng đời của một worker được quản lý bởi Supervisor.
data SupervisorEvent
  = WorkerStarted String
  | WorkerStopped String
  | WorkerCancelled String
  | WorkerFailed String String
  deriving (Eq, Show)

-- | Bộ giám sát quản lý một nhóm worker con (ví dụ: các worker của một phòng hoặc một kết nối).
data Supervisor = Supervisor
  { supervisorThreads :: TVar [(ThreadId, String)]
  , supervisorHistory :: TVar [SupervisorEvent]
  , supervisorShuttingDown :: TVar Bool
  }

-- | Khởi tạo một Supervisor mới với danh sách worker rỗng.
newSupervisor :: IO Supervisor
newSupervisor = do
  threadsVar <- newTVarIO []
  historyVar <- newTVarIO []
  shuttingDownVar <- newTVarIO False
  pure Supervisor
    { supervisorThreads = threadsVar
    , supervisorHistory = historyVar
    , supervisorShuttingDown = shuttingDownVar
    }

-- | Tạo một worker con được giám sát.
-- Khi worker kết thúc (bình thường hoặc lỗi), ThreadId tự động được gỡ khỏi danh sách active.
-- Nếu worker gặp lỗi bất ngờ (không phải ThreadKilled hay lỗi đóng socket thông thường),
-- toàn bộ các worker anh em trong cùng nhóm Supervisor sẽ được hủy để tránh orphan thread.
forkSupervised :: Supervisor -> String -> IO () -> IO ThreadId
forkSupervised supervisor label action =
  mask_ $ do
    registeredVar <- newTVarIO False
    tid <- forkFinally
      ( do
          atomically $ do
            done <- readTVar registeredVar
            check done
          action
      )
      ( \outcome -> do
          selfTid <- myThreadId
          let event = classifyOutcome label outcome
          shouldCancelSiblings <- atomically $ do
            modifyTVar' (supervisorThreads supervisor) (filter ((/= selfTid) . fst))
            history <- readTVar (supervisorHistory supervisor)
            modifyTVar' (supervisorHistory supervisor) (const (history ++ [event]))
            shuttingDown <- readTVar (supervisorShuttingDown supervisor)
            case event of
              WorkerFailed _ _ | not shuttingDown -> do
                modifyTVar' (supervisorShuttingDown supervisor) (const True)
                pure True
              _ -> pure False
          if shouldCancelSiblings
            then cancelRemainingThreads supervisor
            else pure ()
      )
    atomically $ do
      modifyTVar' (supervisorThreads supervisor) ((tid, label) :)
      history <- readTVar (supervisorHistory supervisor)
      modifyTVar' (supervisorHistory supervisor) (const (history ++ [WorkerStarted label]))
      modifyTVar' registeredVar (const True)
    pure tid

classifyOutcome :: String -> Either SomeException () -> SupervisorEvent
classifyOutcome label outcome =
  case outcome of
    Right () -> WorkerStopped label
    Left err
      | Just ThreadKilled <- fromException err ->
          WorkerCancelled label
      | isBenignSocketException err ->
          WorkerStopped label
      | otherwise ->
          WorkerFailed label (displayException err)

cancelRemainingThreads :: Supervisor -> IO ()
cancelRemainingThreads supervisor = do
  entries <- readTVarIO (supervisorThreads supervisor)
  mapM_ (killThread . fst) entries

-- | Dừng toàn bộ worker trong Supervisor và chờ cho tới khi không còn thread con nào chạy.
shutdownSupervisor :: Supervisor -> IO ()
shutdownSupervisor supervisor = do
  atomically $ modifyTVar' (supervisorShuttingDown supervisor) (const True)
  cancelRemainingThreads supervisor
  atomically $ do
    remaining <- readTVar (supervisorThreads supervisor)
    check (null remaining)

-- | Chạy một tác vụ có sử dụng Supervisor; khi khối lệnh thoát (bình thường hoặc exception),
-- đảm bảo toàn bộ worker con đã sinh ra trong nhóm đều bị hủy sạch.
withSupervisedGroup :: (Supervisor -> IO a) -> IO a
withSupervisedGroup =
  bracket newSupervisor shutdownSupervisor

-- | Số lượng worker đang hoạt động trong Supervisor.
activeWorkerCount :: Supervisor -> IO Int
activeWorkerCount supervisor =
  length <$> readTVarIO (supervisorThreads supervisor)

-- | Đọc lịch sử sự kiện của Supervisor.
supervisorEvents :: Supervisor -> IO [SupervisorEvent]
supervisorEvents supervisor =
  readTVarIO (supervisorHistory supervisor)

-- | Kiểm tra một ngoại lệ có phải là sự kiện đóng kết nối WebSocket/socket bình thường hay không.
isBenignSocketException :: SomeException -> Bool
isBenignSocketException err
  | Just WS.ConnectionClosed <- fromException err = True
  | Just (WS.CloseRequest _ _) <- fromException err = True
  | Just ThreadKilled <- fromException err = True
  | Just ioErr <- fromException err = isBenignIOException ioErr
  | otherwise = False
  where
    isBenignIOException :: IOException -> Bool
    isBenignIOException ioErr =
      let msg = displayException ioErr
      in any (`isInfixOf` msg)
           [ "Invalid argument"
           , "Broken pipe"
           , "Connection reset"
           , "forcibly closed"
           , "vanished"
           , " end of file"
           , "EOF"
           ]

-- | Chạy một tác vụ mạng và bỏ qua các ngoại lệ đóng socket thông thường,
-- nhưng vẫn ném lại các ngoại lệ hệ thống/logic khác.
runIgnoringBenignSocketException :: IO () -> IO ()
runIgnoringBenignSocketException action =
  action `catch` \err ->
    if isBenignSocketException err
      then pure ()
      else throwIO err

