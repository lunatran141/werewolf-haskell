{-# LANGUAGE ScopedTypeVariables #-}

-- | Validate va doc bien moi truong cho server va worker (fail-fast).
module Server.Config
  ( ServerConfig(..)
  , WorkerConfig(..)
  , AnalyticsClientConfig(..)
  , ConfigError(..)
  , parsePort
  , parseNonEmpty
  , loadServerConfig
  , loadWorkerConfig
  , loadAnalyticsClientConfig
  , renderConfigError
  ) where

import System.Environment (lookupEnv)
import Text.Read (readMaybe)

data ConfigError
  = InvalidPort !String !String
  | EmptyConfig !String
  | InvalidValue !String !String !String
  deriving (Eq, Show)

data ServerConfig = ServerConfig
  { serverPort :: !Int
  , serverReplayDir :: !(Maybe FilePath)
  , serverSpoolDir :: !FilePath
  } deriving (Eq, Show)

data WorkerConfig = WorkerConfig
  { workerPort :: !Int
  , workerOutputPath :: !FilePath
  , workerReplayDir :: !(Maybe FilePath)
  } deriving (Eq, Show)

data AnalyticsClientConfig = AnalyticsClientConfig
  { clientTargetHost :: !String
  , clientTargetPort :: !Int
  , clientSpoolDir :: !FilePath
  } deriving (Eq, Show)

parsePort :: String -> String -> Either ConfigError Int
parsePort varName raw =
  case readMaybe raw of
    Just p | p >= 1 && p <= 65535 -> Right p
    _ -> Left (InvalidPort varName raw)

parseNonEmpty :: String -> String -> Either ConfigError String
parseNonEmpty varName raw
  | null raw || all (`elem` " \t\r\n") raw =
      Left (EmptyConfig varName)
  | otherwise = Right raw

renderConfigError :: ConfigError -> String
renderConfigError (InvalidPort varName raw) =
  "Loi cau hinh bien moi truong " ++ varName ++ ": '" ++ raw
    ++ "' khong phai cong mang hop le (yeu cau so nguyen trong khoang 1..65535)."
renderConfigError (EmptyConfig varName) =
  "Loi cau hinh bien moi truong " ++ varName
    ++ ": gia tri khong duoc de trong."
renderConfigError (InvalidValue varName raw reason) =
  "Loi cau hinh bien moi truong " ++ varName ++ ": '" ++ raw
    ++ "' khong hop le (" ++ reason ++ ")."

loadServerConfig :: IO (Either ConfigError ServerConfig)
loadServerConfig = do
  portEnv <- lookupEnv "APP_PORT"
  replayEnv <- lookupEnv "REPLAY_DIR"
  spoolEnv <- lookupEnv "ANALYTICS_SPOOL_DIR"
  pure $ do
    port <- case portEnv of
      Nothing -> Right 8080
      Just raw -> parsePort "APP_PORT" raw
    spoolDir <- case spoolEnv of
      Nothing -> Right "analytics/spool"
      Just raw -> parseNonEmpty "ANALYTICS_SPOOL_DIR" raw
    let replayDir = case replayEnv of
          Just p | not (null p) -> Just p
          _ -> Nothing
    Right ServerConfig
      { serverPort = port
      , serverReplayDir = replayDir
      , serverSpoolDir = spoolDir
      }

loadWorkerConfig :: IO (Either ConfigError WorkerConfig)
loadWorkerConfig = do
  portEnv <- lookupEnv "ANALYTICS_PORT"
  outputEnv <- lookupEnv "ANALYTICS_OUTPUT"
  replayEnv <- lookupEnv "REPLAY_DIR"
  pure $ do
    port <- case portEnv of
      Nothing -> Right 9090
      Just raw -> parsePort "ANALYTICS_PORT" raw
    outPath <- case outputEnv of
      Nothing -> Right "analytics/matches.jsonl"
      Just raw -> parseNonEmpty "ANALYTICS_OUTPUT" raw
    let replayDir = case replayEnv of
          Just p | not (null p) -> Just p
          _ -> Nothing
    Right WorkerConfig
      { workerPort = port
      , workerOutputPath = outPath
      , workerReplayDir = replayDir
      }

loadAnalyticsClientConfig :: IO (Either ConfigError AnalyticsClientConfig)
loadAnalyticsClientConfig = do
  hostEnv <- lookupEnv "ANALYTICS_HOST"
  portEnv <- lookupEnv "ANALYTICS_PORT"
  spoolEnv <- lookupEnv "ANALYTICS_SPOOL_DIR"
  pure $ do
    host <- case hostEnv of
      Nothing -> Right "127.0.0.1"
      Just raw -> parseNonEmpty "ANALYTICS_HOST" raw
    port <- case portEnv of
      Nothing -> Right 9090
      Just raw -> parsePort "ANALYTICS_PORT" raw
    spoolDir <- case spoolEnv of
      Nothing -> Right "analytics/spool"
      Just raw -> parseNonEmpty "ANALYTICS_SPOOL_DIR" raw
    Right AnalyticsClientConfig
      { clientTargetHost = host
      , clientTargetPort = port
      , clientSpoolDir = spoolDir
      }
