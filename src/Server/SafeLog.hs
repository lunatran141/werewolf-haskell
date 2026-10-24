{-# LANGUAGE OverloadedStrings #-}

-- | Structured logging with a small deny-list for private gameplay data.
-- Callers log event metadata, never raw commands or protocol payloads.
module Server.SafeLog
  ( LogLevel(..)
  , encodeSafeLogLine
  , logInfo
  , logWarning
  , logError
  ) where

import Data.Aeson (Value, encode, object, (.=))
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BL8
import Data.Char (toLower)
import Data.List (isInfixOf)
import System.IO (Handle, stderr, stdout)

data LogLevel = Info | Warning | Error
  deriving (Eq, Show)

encodeSafeLogLine
  :: LogLevel
  -> String
  -> String
  -> [(String, String)]
  -> BL.ByteString
encodeSafeLogLine level component event fields =
  encode $ object
    [ "level" .= renderLevel level
    , "component" .= component
    , "event" .= event
    , "fields" .= map renderField fields
    ]
  where
    renderField :: (String, String) -> Value
    renderField (key, value) = object
      [ "key" .= key
      , "value" .= if isSensitiveKey key then "[REDACTED]" else value
      ]

logInfo :: String -> String -> [(String, String)] -> IO ()
logInfo = emit stdout Info

logWarning :: String -> String -> [(String, String)] -> IO ()
logWarning = emit stderr Warning

logError :: String -> String -> [(String, String)] -> IO ()
logError = emit stderr Error

emit
  :: Handle
  -> LogLevel
  -> String
  -> String
  -> [(String, String)]
  -> IO ()
emit handle level component event fields =
  BL8.hPutStrLn handle (encodeSafeLogLine level component event fields)

renderLevel :: LogLevel -> String
renderLevel level =
  case level of
    Info -> "info"
    Warning -> "warning"
    Error -> "error"

-- Keep this deliberately broader than the current schema. If a future caller
-- accidentally adds a private field, the value is redacted by default.
isSensitiveKey :: String -> Bool
isSensitiveKey key =
  any (`isInfixOf` normalized)
    [ "role"
    , "chat"
    , "message"
    , "target"
    , "token"
    , "secret"
    , "password"
    , "payload"
    , "private"
    ]
  where
    normalized = map toLower key
