{-# LANGUAGE ScopedTypeVariables #-}

-- | Kenh gui bat dong bo tu Game Server sang Analytics Worker voi persistent spool.
module Server.AnalyticsClient
  ( AnalyticsPublisher
  , publisherSpoolDir
  , newAnalyticsPublisher
  , newAnalyticsPublisherWithSpool
  , newAnalyticsPublisherFromEnv
  , publishMatchSummary
  , runAnalyticsPublisher
  , recoverSpoolToQueue
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
import Control.Monad (forM, forever, void)
import qualified Data.ByteString as BS
import Data.Maybe (catMaybes)
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
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , listDirectory
  , removeFile
  )
import System.FilePath ((</>), takeExtension)

import Domain.Types (DomainEvent(..), GameState(..))
import Protocol.Analytics
  ( MatchSummary(..)
  , decodeMatchSummaryLine
  , encodeMatchSummaryLine
  )
import Server.Config
  ( AnalyticsClientConfig(..)
  , loadAnalyticsClientConfig
  )
import Server.ReplayStore
  ( ReplayStore
  , readReplay
  , renderStorageError
  , writeReplay
  )
import Server.Room (RoomRuntime(..), RoomUpdate(..))
import Server.SafeLog (logWarning)

data AnalyticsPublisher = AnalyticsPublisher
  { publisherHost :: !String
  , publisherPort :: !String
  , publisherQueue :: !(TBQueue MatchSummary)
  , publisherSpoolDir :: !FilePath
  }

newAnalyticsPublisher :: String -> String -> IO AnalyticsPublisher
newAnalyticsPublisher host port =
  newAnalyticsPublisherWithSpool host port "analytics/spool"

newAnalyticsPublisherWithSpool :: String -> String -> FilePath -> IO AnalyticsPublisher
newAnalyticsPublisherWithSpool host port spoolDir = do
  createDirectoryIfMissing True spoolDir
  AnalyticsPublisher host port <$> newTBQueueIO 256 <*> pure spoolDir

newAnalyticsPublisherFromEnv :: IO AnalyticsPublisher
newAnalyticsPublisherFromEnv = do
  configResult <- loadAnalyticsClientConfig
  case configResult of
    Right cfg ->
      newAnalyticsPublisherWithSpool
        (clientTargetHost cfg)
        (show (clientTargetPort cfg))
        (clientSpoolDir cfg)
    Left _ ->
      newAnalyticsPublisherWithSpool "127.0.0.1" "9090" "analytics/spool"

spoolFilePath :: FilePath -> String -> FilePath
spoolFilePath dir mId =
  dir </> (map safeChar mId ++ ".json")
  where
    safeChar c
      | c `elem` ['a'..'z'] ++ ['A'..'Z'] ++ ['0'..'9'] ++ "-_" = c
      | otherwise = '_'

writeSpoolSummary :: FilePath -> MatchSummary -> IO ()
writeSpoolSummary dir summary = do
  createDirectoryIfMissing True dir
  let path = spoolFilePath dir (matchId summary)
  BS.writeFile path (encodeMatchSummaryLine summary)
    `catch` \(_ :: IOException) -> pure ()

deleteSpoolSummary :: FilePath -> String -> IO ()
deleteSpoolSummary dir mId = do
  let path = spoolFilePath dir mId
  removeFile path `catch` \(_ :: IOException) -> pure ()

recoverSpoolToQueue :: AnalyticsPublisher -> IO Int
recoverSpoolToQueue publisher = do
  let dir = publisherSpoolDir publisher
  exists <- doesDirectoryExist dir
  if not exists
    then pure 0
    else do
      entries <- listDirectory dir `catch` \(_ :: IOException) -> pure []
      let jsonFiles = filter (\f -> takeExtension f == ".json") entries
      recovered <- fmap catMaybes $ forM jsonFiles $ \f -> do
        let path = dir </> f
        content <- (BS.readFile path >>= pure . decodeMatchSummaryLine)
          `catch` \(_ :: IOException) -> pure (Left "read error")
        case content of
          Right summary -> pure (Just summary)
          Left _ -> pure Nothing
      enqueuedList <- atomically $ do
        let queue = publisherQueue publisher
        forM recovered $ \summary -> do
          full <- isFullTBQueue queue
          if full
            then pure False
            else writeTBQueue queue summary >> pure True
      pure (length (filter id enqueuedList))

-- | Non-blocking: luu spool truoc, sau do enqueue.
publishMatchSummary :: AnalyticsPublisher -> MatchSummary -> IO Bool
publishMatchSummary publisher summary = do
  writeSpoolSummary (publisherSpoolDir publisher) summary
  atomically $ do
    let queue = publisherQueue publisher
    full <- isFullTBQueue queue
    if full
      then pure False
      else writeTBQueue queue summary >> pure True

-- | Gui theo thu tu; xoa spool khi da nhan thanh cong.
runAnalyticsPublisher :: AnalyticsPublisher -> IO ()
runAnalyticsPublisher publisher = do
  void (recoverSpoolToQueue publisher)
  forever $ do
    summary <- atomically (readTBQueue (publisherQueue publisher))
    retryUntilDelivered summary
    deleteSpoolSummary (publisherSpoolDir publisher) (matchId summary)
    void (recoverSpoolToQueue publisher)
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

subscribeRoomAnalytics
  :: AnalyticsPublisher
  -> RoomRuntime
  -> IO (IO ())
subscribeRoomAnalytics publisher room = do
  subscribeRoomAnalyticsWithReplay Nothing publisher room

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
            [("action", "summary_spooled")]

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
