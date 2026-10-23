{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Exception (bracket)
import qualified Data.ByteString as BS
import Domain.Types (GameResult(..), Team(..))
import System.Directory (removeFile)
import System.IO (hClose, openBinaryTempFile)
import Test.Hspec

import Analytics.Store
  ( StoreResult(..)
  , newAnalyticsStore
  , recordMatchSummary
  )
import Protocol.Analytics (MatchSummary(..), decodeMatchSummaryLine)

summary :: MatchSummary
summary = MatchSummary
  { matchId = "match-001"
  , matchRoomId = "ROOM-01"
  , matchResult = Winner Wolves
  , matchDayCount = 2
  , matchPlayerCount = 9
  }

withTempStore :: (FilePath -> IO a) -> IO a
withTempStore action =
  bracket create cleanup action
  where
    create = do
      (path, handle) <- openBinaryTempFile "." "x02-analytics.jsonl"
      hClose handle
      pure path
    cleanup path = removeFile path

main :: IO ()
main = hspec $ do
  describe "X02 - duplicate-safe analytics store" $ do
    it "ghi MatchSummary moi dung mot dong JSON" $
      withTempStore $ \path -> do
        store <- newAnalyticsStore path
        recordMatchSummary store summary `shouldReturn` SummaryStored
        content <- BS.readFile path
        length (filter (not . BS.null) (BS.split 10 content)) `shouldBe` 1
        decodeMatchSummaryLine (head (BS.split 10 content))
          `shouldBe` Right summary

    it "bo qua summary trung matchId trong cung process" $
      withTempStore $ \path -> do
        store <- newAnalyticsStore path
        recordMatchSummary store summary `shouldReturn` SummaryStored
        recordMatchSummary store summary `shouldReturn` SummaryDuplicate
        content <- BS.readFile path
        length (filter (not . BS.null) (BS.split 10 content)) `shouldBe` 1

    it "restart Worker van nho matchId da ghi" $
      withTempStore $ \path -> do
        firstStore <- newAnalyticsStore path
        recordMatchSummary firstStore summary `shouldReturn` SummaryStored
        restartedStore <- newAnalyticsStore path
        recordMatchSummary restartedStore summary `shouldReturn` SummaryDuplicate
        content <- BS.readFile path
        length (filter (not . BS.null) (BS.split 10 content)) `shouldBe` 1
