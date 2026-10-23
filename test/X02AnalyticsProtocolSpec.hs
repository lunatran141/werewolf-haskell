{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Aeson (Value, eitherDecodeStrict')
import qualified Data.ByteString.Char8 as BS8
import Domain.Types (GameResult(..), Team(..))
import Protocol.Analytics
  ( MatchSummary(..)
  , decodeMatchSummaryLine
  , encodeMatchSummaryLine
  )
import Test.Hspec
  ( describe
  , hspec
  , it
  , shouldBe
  , shouldSatisfy
  )

sampleSummary :: MatchSummary
sampleSummary =
  MatchSummary
    { matchId = "ROOM-01-instance-7"
    , matchRoomId = "ROOM-01"
    , matchResult = Winner Village
    , matchDayCount = 3
    , matchPlayerCount = 9
    }

main :: IO ()
main = hspec $ do
  describe "X02 - Analytics protocol" $ do
    it "JSON Lines round-trip giu nguyen MatchSummary" $ do
      decodeMatchSummaryLine (encodeMatchSummaryLine sampleSummary)
        `shouldBe` Right sampleSummary

    it "moi MatchSummary duoc ma hoa tren dung mot dong" $ do
      let encoded = encodeMatchSummaryLine sampleSummary
      BS8.last encoded `shouldBe` '\n'
      BS8.count '\n' encoded `shouldBe` 1

    it "payload chi chua du lieu tong hop, khong tiet lo ten, role hoac chat" $ do
      let encoded = encodeMatchSummaryLine sampleSummary
          decoded = eitherDecodeStrict' encoded :: Either String Value
      decoded `shouldSatisfy` either (const False) (const True)
      encoded `shouldSatisfy` (not . BS8.isInfixOf "playerName")
      encoded `shouldSatisfy` (not . BS8.isInfixOf "playerRole")
      encoded `shouldSatisfy` (not . BS8.isInfixOf "chat")

    it "tu choi ket qua tran khong nam trong contract" $ do
      let invalid =
            "{\"matchId\":\"m1\",\"roomId\":\"R1\",\"result\":\"Unknown\",\"dayCount\":1,\"playerCount\":9}"
      (decodeMatchSummaryLine invalid :: Either String MatchSummary)
        `shouldSatisfy` either (const True) (const False)
