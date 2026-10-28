{-# LANGUAGE OverloadedStrings #-}

-- | Structured logging with a small deny-list for private gameplay data.
-- Callers log event metadata, never raw commands or protocol payloads.
module Server.SafeLog
  ( LogLevel(..)
  , CorrelationLog(..)
  , encodeSafeLogLine
  , encodeCorrelationLogLine
  , logInfo
  , logWarning
  , logError
  , logCorrelation
  ) where

import Data.Aeson (Value, encode, object, (.=))
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BL8
import Data.Char (toLower)
import Data.List (isInfixOf)
import System.IO (Handle, stderr, stdout)

data LogLevel = Info | Warning | Error
  deriving (Eq, Show)

-- | Bo 5 truong correlation ID thong nhat theo Sheet 03 Dong 70 & Sheet 04 Dong 35.
data CorrelationLog = CorrelationLog
  { corrRequestId :: String
  , corrGameId    :: String
  , corrPlayerId  :: String
  , corrEventType :: String
  , corrErrorCode :: Maybe String
  } deriving (Eq, Show)

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

encodeCorrelationLogLine
  :: LogLevel
  -> String
  -> CorrelationLog
  -> [(String, String)]
  -> BL.ByteString
encodeCorrelationLogLine level component corr extraFields =
  encode $ object
    [ "level" .= renderLevel level
    , "component" .= component
    , "event" .= corrEventType corr
    , "requestId" .= sanitizeCorrelationValue (corrRequestId corr)
    , "gameId" .= sanitizeCorrelationValue (corrGameId corr)
    , "playerId" .= sanitizeCorrelationValue (corrPlayerId corr)
    , "eventType" .= sanitizeCorrelationValue (corrEventType corr)
    , "errorCode" .= fmap sanitizeCorrelationValue (corrErrorCode corr)
    , "fields" .= map renderField (correlationFields ++ extraFields)
    ]
  where
    correlationFields =
      [ ("requestId", corrRequestId corr)
      , ("gameId", corrGameId corr)
      , ("playerId", corrPlayerId corr)
      , ("eventType", corrEventType corr)
      , ("errorCode", maybe "NONE" id (corrErrorCode corr))
      ]

renderField :: (String, String) -> Value
renderField (key, value) = object
  [ "key" .= key
  , "value" .=
      if isSensitiveKey key || containsSecretRoleValue value
        then "[REDACTED]"
        else value
  ]

sanitizeCorrelationValue :: String -> String
sanitizeCorrelationValue value =
  if containsSecretRoleValue value then "[REDACTED]" else value

logInfo :: String -> String -> [(String, String)] -> IO ()
logInfo = emit stdout Info

logWarning :: String -> String -> [(String, String)] -> IO ()
logWarning = emit stderr Warning

logError :: String -> String -> [(String, String)] -> IO ()
logError = emit stderr Error

logCorrelation
  :: LogLevel
  -> String
  -> CorrelationLog
  -> [(String, String)]
  -> IO ()
logCorrelation level component corr extraFields =
  BL8.hPutStrLn handle (encodeCorrelationLogLine level component corr extraFields)
  where
    handle =
      case level of
        Info -> stdout
        Warning -> stderr
        Error -> stderr

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
    , "seer"
    , "witch"
    , "wolf"
    ]
  where
    normalized = map toLower key

containsSecretRoleValue :: String -> Bool
containsSecretRoleValue value =
  any (`isInfixOf` normalized)
    [ "werewolf"
    , "villager"
    , "seer"
    , "witch"
    , "guard"
    , "hunter"
    , "wolvesnight"
    ]
  where
    normalized = map toLower value
