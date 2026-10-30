-- | Nhóm worker của một phòng, có Supervisor riêng để lỗi của phòng này
-- không hủy worker của phòng khác hay publisher toàn cục.
module Server.RoomWorker
  ( startRoomWorkerGroup
  ) where

import Control.Concurrent (killThread)
import Control.Exception (SomeException, catch, displayException, finally, throwIO)
import Control.Monad (unless)
import Server.Supervisor
  ( Supervisor
  , forkSupervised
  , isBenignSocketException
  , newSupervisor
  )

-- | Chạy analytics forwarder và game loop của một phòng dưới Supervisor riêng.
-- Lỗi bất ngờ của game loop được báo qua @onFailure@ rồi ném lại để Supervisor
-- hủy luồng anh em trong cùng phòng; các phòng khác không bị ảnh hưởng.
startRoomWorkerGroup
  :: String
  -> IO ()
  -> IO ()
  -> (String -> IO ())
  -> IO Supervisor
startRoomWorkerGroup roomLabel analyticsForwarder gameLoop onFailure = do
  roomSupervisor <- newSupervisor
  analyticsThread <-
    forkSupervised roomSupervisor ("analytics-room-" ++ roomLabel)
      analyticsForwarder
  _ <- forkSupervised roomSupervisor ("game-loop-" ++ roomLabel) $
    (gameLoop `catch` \err -> do
        unless (isBenignSocketException err) $
          onFailure (displayException (err :: SomeException))
        throwIO err)
      `finally` killThread analyticsThread
  pure roomSupervisor

