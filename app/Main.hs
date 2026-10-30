{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent.MVar (modifyMVar_)
import Network.HTTP.Types (status200)
import Network.Wai (Application, pathInfo, responseLBS)
import Network.Wai.Handler.Warp (run)
import Network.Wai.Handler.WebSockets (websocketsOr)
import Network.Wai.Application.Static
  (defaultFileServerSettings, staticApp)
import qualified Network.WebSockets as WS
import Server.GameLoop (runRegisteredLobbyLoop)
import Server.AnalyticsClient
  ( AnalyticsPublisher
  , newAnalyticsPublisherFromEnv
  , runAnalyticsPublisher
  , subscribeRoomAnalyticsWithReplay
  )
import Server.ReplayStore (ReplayStore, newReplayStore)
import Server.Room (RoomRegistry(..), RoomRuntime(..), newRoomRegistry)
import Server.RoomWorker (startRoomWorkerGroup)
import Server.SafeLog (logError, logInfo)
import Server.Supervisor (forkSupervised, newSupervisor)
import Server.Config (ServerConfig(..), loadServerConfig, renderConfigError)
import Server.WebSocket (webSocketApp)
import System.Exit (ExitCode(ExitFailure), exitWith)
import System.IO (hPutStrLn, stderr)

main :: IO ()
main = do
  configResult <- loadServerConfig
  serverConfig <- case configResult of
    Left err -> do
      let msg = renderConfigError err
      hPutStrLn stderr msg
      logError "game-server" "config_error" [("error", msg)]
      exitWith (ExitFailure 1)
    Right cfg -> pure cfg
  let port = serverPort serverConfig
  registry <- newRoomRegistry
  supervisor <- newSupervisor
  analyticsPublisher <- newAnalyticsPublisherFromEnv

  let replayStore = replayStoreFromDirectory (serverReplayDir serverConfig)
  _ <- forkSupervised supervisor "analytics-publisher" $
    runAnalyticsPublisher analyticsPublisher

  logInfo "game-server" "server_listening" [("port", show port)]
  run port
    (app registry
      (startRoomWorker registry analyticsPublisher replayStore))

replayStoreFromDirectory :: Maybe FilePath -> Maybe ReplayStore
replayStoreFromDirectory (Just path)
  | not (null path) = Just (newReplayStore path)
replayStoreFromDirectory _ = Nothing

startRoomWorker
  :: RoomRegistry
  -> AnalyticsPublisher
  -> Maybe ReplayStore
  -> RoomRuntime
  -> IO ()
startRoomWorker registry analyticsPublisher replayStore room = do
  analyticsForwarder <-
    subscribeRoomAnalyticsWithReplay replayStore analyticsPublisher room
  _ <- startRoomWorkerGroup (roomId room) analyticsForwarder
    (runRegisteredLobbyLoop registry room)
    (\_ -> do
      logError "game-server" "game_loop_stopped"
        [("roomId", roomId room), ("errorClass", "unexpected_exception")]
      modifyMVar_ (registryRooms registry) $
        pure . filter ((/= roomId room) . fst))
  pure ()

app :: RoomRegistry -> (RoomRuntime -> IO ()) -> Application
app registry startWorker request respond
  | pathInfo request == ["health"] =
      healthApp request respond
  | pathInfo request == ["ws"] =
      websocketsOr WS.defaultConnectionOptions
        (webSocketApp registry startWorker)
        healthApp
        request respond
  | otherwise =
      staticApp (defaultFileServerSettings "web") request respond

healthApp :: Application
healthApp _ respond =
  respond
    (responseLBS
      status200
      [("Content-Type", "application/json")]
      "{\"status\":\"ok\"}")
