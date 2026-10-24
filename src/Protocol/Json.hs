-- | JSON encode/decode cho Command, Event và Error.
{-# LANGUAGE OverloadedStrings #-}

module Protocol.Json
  ( decodeClientMessage
  , clientMessageWithinLimit
  , maxClientMessageBytes
  , encodeServerMessage
  ) where

import Data.Aeson (eitherDecode, encode)
import Data.ByteString.Lazy (ByteString)
import qualified Data.ByteString.Lazy as BL
import Protocol.Types

-- One player command is intentionally small. This guard rejects oversized
-- frames before JSON decoding so a client cannot use huge payloads to consume
-- unbounded parser work or memory.
maxClientMessageBytes :: Int
maxClientMessageBytes = 4096

clientMessageWithinLimit :: ByteString -> Bool
clientMessageWithinLimit bytes =
  BL.length bytes <= fromIntegral maxClientMessageBytes

decodeClientMessage :: ByteString -> Either String ClientMessage
decodeClientMessage bytes
  | clientMessageWithinLimit bytes = eitherDecode bytes
  | otherwise = Left "Client message exceeds 4096 bytes."

encodeServerMessage :: ServerMessage -> ByteString
encodeServerMessage = encode
