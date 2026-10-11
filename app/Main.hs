{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent (ThreadId, forkFinally, myThreadId)
import Control.Exception (displayException, throwTo)
import Network.HTTP.Types (status200)
import Network.Wai (Application, pathInfo, responseLBS)
import Network.Wai.Handler.Warp (run)
import Network.Wai.Handler.WebSockets (websocketsOr)
import qualified Network.WebSockets as WS
import Server.GameLoop (runLobbyLoop)
import Server.Room (RoomRegistry, RoomRuntime(..), newRoomRegistry)
import Server.WebSocket (webSocketApp)
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

main :: IO ()
main = do
  port <- maybe 8080 id . (>>= readMaybe) <$> lookupEnv "APP_PORT"
  mainThread <- myThreadId
  registry <- newRoomRegistry

  putStrLn ("werewolf-server listening on port " <> show port)
  run port (app registry (startRoomWorker mainThread))

startRoomWorker :: ThreadId -> RoomRuntime -> IO ()
startRoomWorker mainThread room = do
  _ <- forkFinally (runLobbyLoop room) $ \result ->
    case result of
      Left err -> do
        hPutStrLn stderr
          ("GameLoop " ++ roomId room ++ " stopped: " ++ displayException err)
        throwTo mainThread err
      Right () ->
        pure ()
  pure ()

app :: RoomRegistry -> (RoomRuntime -> IO ()) -> Application
app registry startWorker request respond
  | pathInfo request == ["ws"] =
      websocketsOr WS.defaultConnectionOptions
        (webSocketApp registry startWorker)
        healthApp
        request respond
  | otherwise =
      healthApp request respond

healthApp :: Application
healthApp _ respond =
  respond
    (responseLBS
      status200
      [("Content-Type", "application/json")]
      "{\"status\":\"ok\"}")