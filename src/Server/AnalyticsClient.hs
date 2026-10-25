{-# LANGUAGE ScopedTypeVariables #-}

-- | Kenh gui bat dong bo tu Game Server sang Analytics Worker.
-- Loi mang chi lam giu summary trong queue khong bao gio lam dung GameLoop.
module Server.AnalyticsClient
  ( AnalyticsPublisher
  , newAnalyticsPublisher
  , newAnalyticsPublisherFromEnv
  , publishMatchSummary
  , runAnalyticsPublisher
  , subscribeRoomAnalytics
  , subscribeRoomAnalyticsWithReplay
  , matchSummaryForUpdate
  ) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.STM
  ( TBQueue
  , atomically
  , dupTChan
  , isFullTBQueue
  , newTBQueueIO
  , readTBQueue
  , readTChan
  , writeTBQueue
  )
import Control.Exception (IOException, bracket, catch)
import Control.Monad (forever)
import Network.Socket
  ( AddrInfo(..)
  , SocketType(Stream)
  , addrAddress
  , close
  , connect
  , defaultHints
  , getAddrInfo
  , socket
  )
import qualified Network.Socket.ByteString as SocketBS
import System.Environment (lookupEnv)

import Domain.Types (DomainEvent(..), GameState(..))
import Protocol.Analytics (MatchSummary(..), encodeMatchSummaryLine)
import Server.Room (RoomRuntime(..), RoomUpdate(..))
import Server.ReplayStore
  ( ReplayStore
  , readReplay
  , renderStorageError
  , writeReplay
  )
import Server.SafeLog (logWarning)

data AnalyticsPublisher = AnalyticsPublisher
  { publisherHost :: String
  , publisherPort :: String
  , publisherQueue :: TBQueue MatchSummary
  }

newAnalyticsPublisher :: String -> String -> IO AnalyticsPublisher
newAnalyticsPublisher host port =
  AnalyticsPublisher host port <$> newTBQueueIO 256

newAnalyticsPublisherFromEnv :: IO AnalyticsPublisher
newAnalyticsPublisherFromEnv = do
  host <- maybe "127.0.0.1" id <$> lookupEnv "ANALYTICS_HOST"
  port <- maybe "9090" id <$> lookupEnv "ANALYTICS_PORT"
  newAnalyticsPublisher host port

-- | Non-blocking: queue day thi bo qua analytics, Game Server van tiep tuc.
publishMatchSummary :: AnalyticsPublisher -> MatchSummary -> IO Bool
publishMatchSummary publisher summary =
  atomically $ do
    let queue = publisherQueue publisher
    full <- isFullTBQueue queue
    if full
      then pure False
      else writeTBQueue queue summary >> pure True

-- | Gui theo thu tu. Neu Worker vang mat, thu lai summary dau queue sau 2 giay.
runAnalyticsPublisher :: AnalyticsPublisher -> IO ()
runAnalyticsPublisher publisher = forever $ do
  summary <- atomically (readTBQueue (publisherQueue publisher))
  retryUntilDelivered summary
  where
    retryUntilDelivered summary = do
      delivered <-
        (sendSummary publisher summary >> pure True)
          `catch` \(_ :: IOException) -> pure False
      if delivered
        then pure ()
        else do
          logWarning "analytics-publisher" "delivery_retry"
            [("reason", "worker_unavailable")]
          threadDelay 2000000
          retryUntilDelivered summary

sendSummary :: AnalyticsPublisher -> MatchSummary -> IO ()
sendSummary publisher summary = do
  addresses <- getAddrInfo
    (Just defaultHints {addrSocketType = Stream})
    (Just (publisherHost publisher))
    (Just (publisherPort publisher))
  case addresses of
    [] -> ioError (userError "Cannot resolve analytics worker")
    address : _ -> bracket (open address) close $ \connection ->
      SocketBS.sendAll connection (encodeMatchSummaryLine summary)
  where
    open address = do
      connection <- socket
        (addrFamily address)
        (addrSocketType address)
        (addrProtocol address)
      connect connection (addrAddress address)
      pure connection

-- | Dang ky TChan truoc khi GameLoop bat dau de khong bo lo GameFinished.
subscribeRoomAnalytics
  :: AnalyticsPublisher
  -> RoomRuntime
  -> IO (IO ())
subscribeRoomAnalytics publisher room = do
  subscribeRoomAnalyticsWithReplay Nothing publisher room

-- | Ban X03 ghi replay da lam sach len shared storage truoc khi gui summary
-- cho Worker. Moi loi storage chi duoc log va khong chan GameLoop.
subscribeRoomAnalyticsWithReplay
  :: Maybe ReplayStore
  -> AnalyticsPublisher
  -> RoomRuntime
  -> IO (IO ())
subscribeRoomAnalyticsWithReplay replayStore publisher room = do
  updates <- atomically (dupTChan (roomUpdates room))
  pure $ forever $ do
    update <- atomically (readTChan updates)
    case matchSummaryForUpdate room update of
      Nothing -> pure ()
      Just summary -> do
        persistSharedReplay replayStore summary
        accepted <- publishMatchSummary publisher summary
        if accepted
          then pure ()
          else logWarning "analytics-publisher" "queue_full"
            [("action", "summary_skipped")]

persistSharedReplay :: Maybe ReplayStore -> MatchSummary -> IO ()
persistSharedReplay Nothing _ = pure ()
persistSharedReplay (Just store) summary = do
  written <- writeReplay store summary
  case written of
    Left err ->
      logWarning "replay-store" "write_failed"
        [("reason", renderStorageError err)]
    Right _ -> do
      verified <- readReplay store (matchId summary)
      case verified of
        Right replay
          | replay == summary -> pure ()
          | otherwise -> logWarning "replay-store" "verification_failed"
              [("reason", "StorageConflict")]
        Left err ->
          logWarning "replay-store" "read_failed"
            [("reason", renderStorageError err)]

matchSummaryForUpdate :: RoomRuntime -> RoomUpdate -> Maybe MatchSummary
matchSummaryForUpdate room update =
  case [result | GameFinished result <- updateEvents update] of
    [] -> Nothing
    result : _ ->
      let state = updateState update
      in Just MatchSummary
        { matchId = roomId room <> "-" <> roomInstanceId room
        , matchRoomId = roomId room
        , matchResult = result
        , matchDayCount = gameDay state
        , matchPlayerCount = length (gamePlayers state)
        }
