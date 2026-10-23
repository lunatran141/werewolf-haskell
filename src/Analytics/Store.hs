-- | Kho JSON Lines duplicate-safe cua Analytics Worker.
module Analytics.Store
  ( AnalyticsStore
  , StoreResult(..)
  , newAnalyticsStore
  , recordMatchSummary
  ) where

import Control.Concurrent.MVar (MVar, modifyMVar, newMVar)
import qualified Data.ByteString as BS
import Data.List (nub)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath (takeDirectory)

import Protocol.Analytics
  ( MatchSummary(..)
  , decodeMatchSummaryLine
  , encodeMatchSummaryLine
  )

data AnalyticsStore = AnalyticsStore
  { analyticsPath :: FilePath
  , analyticsKnownIds :: MVar [String]
  }

data StoreResult = SummaryStored | SummaryDuplicate
  deriving (Eq, Show)

-- | Khoi dong lai Worker se doc cac matchId da ghi de tiep tuc khu trung.
newAnalyticsStore :: FilePath -> IO AnalyticsStore
newAnalyticsStore path = do
  createDirectoryIfMissing True (takeDirectory path)
  exists <- doesFileExist path
  content <- if exists then BS.readFile path else pure BS.empty
  let summaries =
        [ summary
        | line <- BS.split 10 content
        , not (BS.null line)
        , Right summary <- [decodeMatchSummaryLine line]
        ]
  knownIds <- newMVar (nub (map matchId summaries))
  pure AnalyticsStore
    { analyticsPath = path
    , analyticsKnownIds = knownIds
    }

-- | Cung mot matchId chi duoc append mot lan, ke ca khi gui lai hoac restart.
recordMatchSummary :: AnalyticsStore -> MatchSummary -> IO StoreResult
recordMatchSummary store summary =
  modifyMVar (analyticsKnownIds store) $ \knownIds ->
    if matchId summary `elem` knownIds
      then pure (knownIds, SummaryDuplicate)
      else do
        BS.appendFile (analyticsPath store) (encodeMatchSummaryLine summary)
        pure (matchId summary : knownIds, SummaryStored)
