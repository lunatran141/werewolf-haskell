{-# LANGUAGE OverloadedStrings #-}

-- | Giao thuc noi bo giua Game Server va Analytics Worker.
-- Moi 'MatchSummary' duoc gui tren mot dong JSON (JSON Lines).
-- DTO nay co chu y khong chua ten, vai tro hay noi dung chat cua nguoi choi.
module Protocol.Analytics
  ( MatchSummary(..)
  , encodeMatchSummaryLine
  , decodeMatchSummaryLine
  ) where

import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , eitherDecodeStrict'
  , encode
  , object
  , withObject
  , (.:)
  , (.=)
  )
import Control.Monad (when)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS

import Domain.Types (GameResult(..), Team(..))
import Protocol.Types (RoomId)

-- | Du lieu tong hop toi thieu cua mot van da ket thuc.
-- 'matchId' la khoa idempotency: Worker chi duoc ghi mot lan cho moi ID.
data MatchSummary = MatchSummary
  { matchId :: String
  , matchRoomId :: RoomId
  , matchResult :: GameResult
  , matchDayCount :: Int
  , matchPlayerCount :: Int
  } deriving (Eq, Show)

instance ToJSON MatchSummary where
  toJSON summary =
    object
      [ "matchId" .= matchId summary
      , "roomId" .= matchRoomId summary
      , "result" .= resultText (matchResult summary)
      , "dayCount" .= matchDayCount summary
      , "playerCount" .= matchPlayerCount summary
      ]

instance FromJSON MatchSummary where
  parseJSON = withObject "MatchSummary" $ \value -> do
    encodedResult <- value .: "result"
    decodedResult <- either fail pure (parseResultText encodedResult)
    summary <- MatchSummary
      <$> value .: "matchId"
      <*> value .: "roomId"
      <*> pure decodedResult
      <*> value .: "dayCount"
      <*> value .: "playerCount"
    when (null (matchId summary)) (fail "matchId must not be empty")
    when (null (matchRoomId summary)) (fail "roomId must not be empty")
    when (matchDayCount summary < 1) (fail "dayCount must be positive")
    when (matchPlayerCount summary < 1) (fail "playerCount must be positive")
    pure summary

-- | Ma hoa dung mot record JSON Lines, luon ket thuc bang LF.
encodeMatchSummaryLine :: MatchSummary -> BS.ByteString
encodeMatchSummaryLine summary =
  LBS.toStrict (encode summary) <> "\n"

-- | Giai ma mot dong JSON. Ky tu xuong dong cuoi la tuy chon.
decodeMatchSummaryLine :: BS.ByteString -> Either String MatchSummary
decodeMatchSummaryLine = eitherDecodeStrict'

resultText :: GameResult -> String
resultText (Winner Wolves) = "Wolves"
resultText (Winner Village) = "Village"
resultText Draw = "Draw"

parseResultText :: String -> Either String GameResult
parseResultText "Wolves" = Right (Winner Wolves)
parseResultText "Village" = Right (Winner Village)
parseResultText "Draw" = Right Draw
parseResultText value = Left ("Unknown match result: " <> value)
