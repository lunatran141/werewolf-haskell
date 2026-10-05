{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Network.HTTP.Types (status200)
import Network.Wai (Application, responseLBS)
import Network.Wai.Handler.Warp (run)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

main :: IO ()
main = do
  port <- maybe 8080 id . (>>= readMaybe) <$> lookupEnv "APP_PORT"
  putStrLn ("werewolf-server listening on port " <> show port)
  run port app

app :: Application
app _ respond =
  respond (responseLBS status200 [("Content-Type", "application/json")] "{\"status\":\"ok\"}")
