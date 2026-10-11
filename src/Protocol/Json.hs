-- | JSON encode/decode cho Command, Event và Error.
{-# LANGUAGE OverloadedStrings #-}

module Protocol.Json
  ( decodeClientMessage
  , encodeServerMessage
  ) where

import Data.Aeson (eitherDecode, encode)
import Data.ByteString.Lazy (ByteString)
import Protocol.Types

decodeClientMessage :: ByteString -> Either String ClientMessage
decodeClientMessage = eitherDecode

encodeServerMessage :: ServerMessage -> ByteString
encodeServerMessage = encode