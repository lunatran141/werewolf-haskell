{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (SomeException, catch, displayException)
import Network.HTTP.Types (status200)
import Network.Wai (Application, pathInfo, responseLBS)
import Network.Wai.Handler.Warp (run)
import Network.Wai.Handler.WebSockets (websocketsOr)
import Network.Wai.Application.Static
  (defaultFileServerSettings, staticApp)
import qualified Network.WebSockets as WS
import Server.GameLoop (runLobbyLoop)
import Server.Room (RoomRegistry, RoomRuntime(..), newRoomRegistry)
import Server.Supervisor (Supervisor, forkSupervised, newSupervisor)
import Server.WebSocket (webSocketApp)
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

main :: IO ()
main = do
  port <- maybe 8080 id . (>>= readMaybe) <$> lookupEnv "APP_PORT"
  registry <- newRoomRegistry
  supervisor <- newSupervisor

  putStrLn ("werewolf-server listening on port " <> show port)
  run port (app registry (startRoomWorker supervisor))

startRoomWorker :: Supervisor -> RoomRuntime -> IO ()
startRoomWorker supervisor room = do
  _ <- forkSupervised supervisor ("game-loop-" ++ roomId room) $
    runLobbyLoop room `catch` \(err :: SomeException) ->
      hPutStrLn stderr
        ("GameLoop " ++ roomId room ++ " stopped with error: " ++ displayException err)
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