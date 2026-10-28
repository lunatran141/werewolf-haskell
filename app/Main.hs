{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent (killThread)
import Control.Exception (SomeException, catch, finally)
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
import Server.Room (RoomRegistry, RoomRuntime(..), newRoomRegistry)
import Server.SafeLog (logError, logInfo)
import Server.Supervisor (Supervisor, forkSupervised, newSupervisor)
import Server.WebSocket (webSocketApp)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

main :: IO ()
main = do
  port <- maybe 8080 id . (>>= readMaybe) <$> lookupEnv "APP_PORT"
  registry <- newRoomRegistry
  supervisor <- newSupervisor
  analyticsPublisher <- newAnalyticsPublisherFromEnv
  replayDirectory <- lookupEnv "REPLAY_DIR"
  let replayStore = replayStoreFromDirectory replayDirectory
  _ <- forkSupervised supervisor "analytics-publisher" $
    runAnalyticsPublisher analyticsPublisher

  logInfo "game-server" "server_listening" [("port", show port)]
  run port
    (app registry
      (startRoomWorker registry supervisor analyticsPublisher replayStore))

replayStoreFromDirectory :: Maybe FilePath -> Maybe ReplayStore
replayStoreFromDirectory (Just path)
  | not (null path) = Just (newReplayStore path)
replayStoreFromDirectory _ = Nothing

startRoomWorker
  :: RoomRegistry
  -> Supervisor
  -> AnalyticsPublisher
  -> Maybe ReplayStore
  -> RoomRuntime
  -> IO ()
startRoomWorker registry supervisor analyticsPublisher replayStore room = do
  analyticsForwarder <-
    subscribeRoomAnalyticsWithReplay replayStore analyticsPublisher room
  analyticsThread <- forkSupervised supervisor ("analytics-room-" ++ roomId room)
    analyticsForwarder
  _ <- forkSupervised supervisor ("game-loop-" ++ roomId room) $
    (runRegisteredLobbyLoop registry room `catch` \(_ :: SomeException) ->
      logError "game-server" "game_loop_stopped"
        [("roomId", roomId room), ("errorClass", "unexpected_exception")])
      `finally` killThread analyticsThread
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
