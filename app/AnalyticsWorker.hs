{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import Control.Concurrent (forkFinally)
import Control.Exception (SomeException, bracket, displayException)
import Control.Monad (forever, void)
import qualified Data.ByteString as BS
import Network.Socket
  ( AddrInfo(..)
  , AddrInfoFlag(..)
  , Family(AF_INET)
  , Socket
  , SocketOption(..)
  , SocketType(..)
  , accept
  , addrAddress
  , bind
  , close
  , defaultHints
  , getAddrInfo
  , listen
  , setSocketOption
  , socket
  , withSocketsDo
  )
import qualified Network.Socket.ByteString as SocketBS
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)

import Analytics.Store
  ( AnalyticsStore
  , StoreResult(..)
  , newAnalyticsStore
  , recordMatchSummary
  )
import Protocol.Analytics (decodeMatchSummaryLine)

main :: IO ()
main = withSocketsDo $ do
  port <- maybe "9090" id <$> lookupEnv "ANALYTICS_PORT"
  outputPath <- maybe "analytics/matches.jsonl" id
    <$> lookupEnv "ANALYTICS_OUTPUT"
  store <- newAnalyticsStore outputPath
  address <- resolveAddress port
  bracket (openSocket address) close $ \listener -> do
    putStrLn ("analytics-worker listening on TCP port " <> port)
    putStrLn ("analytics-worker output: " <> outputPath)
    forever $ do
      (connection, _) <- accept listener
      void $ forkFinally
        (serveConnection store connection)
        (\result -> do
          close connection
          case result of
            Left err -> hPutStrLn stderr
              ("analytics connection stopped: " <> displayException err)
            Right () -> pure ())

resolveAddress :: String -> IO AddrInfo
resolveAddress port = do
  addresses <- getAddrInfo
    (Just defaultHints
      { addrFlags = [AI_PASSIVE]
      , addrSocketType = Stream
      })
    Nothing
    (Just port)
  case filter ((== AF_INET) . addrFamily) addresses of
    address : _ -> pure address
    [] -> ioError (userError "Cannot resolve analytics listen address")

openSocket :: AddrInfo -> IO Socket
openSocket address = do
  listener <- socket (addrFamily address) Stream (addrProtocol address)
  setSocketOption listener ReuseAddr 1
  bind listener (addrAddress address)
  listen listener 32
  pure listener

serveConnection :: AnalyticsStore -> Socket -> IO ()
serveConnection store connection = receiveLoop BS.empty
  where
    receiveLoop buffered = do
      chunk <- SocketBS.recv connection 4096
      if BS.null chunk
        then processFinal buffered
        else do
          remaining <- processCompleteLines (buffered <> chunk)
          receiveLoop remaining

    processFinal bytes
      | BS.null bytes = pure ()
      | otherwise = processLine bytes

    processCompleteLines bytes =
      case BS.break (== 10) bytes of
        (line, rest)
          | BS.null rest -> pure line
          | otherwise -> do
              processLine line
              processCompleteLines (BS.drop 1 rest)

    processLine line
      | BS.null line = pure ()
      | otherwise =
          case decodeMatchSummaryLine line of
            Left err -> hPutStrLn stderr
              ("analytics rejected invalid JSON line: " <> err)
            Right summary -> do
              result <- recordMatchSummary store summary
              case result of
                SummaryStored -> putStrLn "analytics stored match summary"
                SummaryDuplicate -> putStrLn "analytics ignored duplicate matchId"
