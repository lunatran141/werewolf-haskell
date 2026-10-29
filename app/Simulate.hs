{-# LANGUAGE BangPatterns #-}

-- | X01: Executable chay mo phong nhieu van bang parMap/rdeepseq,
-- so sanh hieu nang voi ban tuan tu, va xuat report/balance.csv.
module Main (main) where

import Control.DeepSeq (deepseq)
import GHC.Clock (getMonotonicTimeNSec)
import GHC.Conc (getNumCapabilities)
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs)
import System.Exit (ExitCode(ExitFailure), exitSuccess, exitWith)
import System.FilePath (takeDirectory)
import System.IO (hPutStrLn, stderr)
import Text.Printf (printf)

import Domain.Simulation
  ( BalanceStats(..)
  , SimCliCommand(..)
  , SimCliOptions(..)
  , SimConfig(..)
  , parseSimulateArgs
  , renderSimCliError
  , roles8Preset
  , roles9Preset
  , runParallel
  , runSequential
  , simCliUsage
  )
import Domain.Types (Role)

data BenchmarkRow = BenchmarkRow
  { rowPresetName     :: String
  , rowPlayerCount    :: Int
  , rowWolfCount      :: Int
  , rowGames          :: Int
  , rowBaseSeed       :: Int
  , rowCores          :: Int
  , rowSeqTimeMs      :: Double
  , rowParTimeMs      :: Double
  , rowSpeedup        :: Double
  , rowVillageWins    :: Int
  , rowWolfWins       :: Int
  , rowDraws          :: Int
  , rowVillageWinRate :: Double
  , rowWolfWinRate    :: Double
  , rowDrawRate       :: Double
  , rowAvgRounds      :: Double
  , rowSeqEqPar       :: Bool
  } deriving (Show)

-- | Chay so sanh giua Sequential va Parallel cho mot cau hinh nhat dinh.
runBenchmark :: String -> [Role] -> Int -> Int -> Int -> Int -> IO BenchmarkRow
runBenchmark name roles pCount wCount count seed = do
  numCores <- getNumCapabilities
  let cfg = SimConfig
        { simPresetRoles = roles
        , simBaseSeed = seed
        , simGameCount = count
        }

  -- 1. Chay tuan tu (map)
  tSeqStart <- getMonotonicTimeNSec
  let (!seqOutcomes, !seqStats) = runSequential cfg
  seqOutcomes `deepseq` seqStats `deepseq` pure ()
  tSeqEnd <- getMonotonicTimeNSec
  let seqMs = fromIntegral (tSeqEnd - tSeqStart) / 1000000.0 :: Double

  -- 2. Chay song song (parMap rdeepseq)
  tParStart <- getMonotonicTimeNSec
  let (!parOutcomes, !parStats) = runParallel cfg
  parOutcomes `deepseq` parStats `deepseq` pure ()
  tParEnd <- getMonotonicTimeNSec
  let parMs = fromIntegral (tParEnd - tParStart) / 1000000.0 :: Double

  -- 3. Xac minh tinh dong nhat giua Sequential va Parallel (E19)
  let !isIdentical = (seqOutcomes == parOutcomes) && (seqStats == parStats)
      speedup = if parMs > 0 then seqMs / parMs else 1.0
      total = fromIntegral count :: Double
      vWinRate = (fromIntegral (statsVillageWins parStats) / total) * 100.0
      wWinRate = (fromIntegral (statsWolfWins parStats) / total) * 100.0
      dRate = (fromIntegral (statsDraws parStats) / total) * 100.0
      avgRounds = fromIntegral (statsTotalRounds parStats) / total

  pure BenchmarkRow
    { rowPresetName = name
    , rowPlayerCount = pCount
    , rowWolfCount = wCount
    , rowGames = count
    , rowBaseSeed = seed
    , rowCores = numCores
    , rowSeqTimeMs = seqMs
    , rowParTimeMs = parMs
    , rowSpeedup = speedup
    , rowVillageWins = statsVillageWins parStats
    , rowWolfWins = statsWolfWins parStats
    , rowDraws = statsDraws parStats
    , rowVillageWinRate = vWinRate
    , rowWolfWinRate = wWinRate
    , rowDrawRate = dRate
    , rowAvgRounds = avgRounds
    , rowSeqEqPar = isIdentical
    }

formatRowCSV :: BenchmarkRow -> String
formatRowCSV r =
  printf "%s,%d,%d,%d,%d,%d,%.2f,%.2f,%.2fx,%d,%d,%d,%.2f%%,%.2f%%,%.2f%%,%.2f,%s"
    (rowPresetName r)
    (rowPlayerCount r)
    (rowWolfCount r)
    (rowGames r)
    (rowBaseSeed r)
    (rowCores r)
    (rowSeqTimeMs r)
    (rowParTimeMs r)
    (rowSpeedup r)
    (rowVillageWins r)
    (rowWolfWins r)
    (rowDraws r)
    (rowVillageWinRate r)
    (rowWolfWinRate r)
    (rowDrawRate r)
    (rowAvgRounds r)
    (if rowSeqEqPar r then "TRUE" else "FALSE")

printConsoleRow :: BenchmarkRow -> IO ()
printConsoleRow r =
  printf "%-10s %7d %7d %9.1f%% %8.1f%% %6.1f%% %7.2f %9.1f %9.1f %7.2fx   %s\n"
    (rowPresetName r)
    (rowGames r)
    (rowBaseSeed r)
    (rowVillageWinRate r)
    (rowWolfWinRate r)
    (rowDrawRate r)
    (rowAvgRounds r)
    (rowSeqTimeMs r)
    (rowParTimeMs r)
    (rowSpeedup r)
    (if rowSeqEqPar r then "PASS (identical)" else "FAIL (mismatch)")

main :: IO ()
main = do
  args <- getArgs
  case parseSimulateArgs args of
    Left err -> do
      hPutStrLn stderr (renderSimCliError err)
      hPutStrLn stderr simCliUsage
      exitWith (ExitFailure 2)
    Right SimCliHelp -> do
      putStr simCliUsage
      exitSuccess
    Right (SimCliRun opts) -> runWithOptions opts

runWithOptions :: SimCliOptions -> IO ()
runWithOptions opts = do
  cores <- getNumCapabilities
  let counts = simOptGames opts
      seed = simOptSeed opts
      outPath = simOptOutput opts

  putStrLn "=========================================================================================="
  putStrLn "                  WEREWOLF HASKELL - X01 PARALLEL SIMULATION BENCHMARK                   "
  printf   "                   Evaluation Strategies: parMap rdeepseq | Cores: %d                     \n" cores
  putStrLn "=========================================================================================="
  printf "%-10s %7s %7s %10s %9s %7s %7s %9s %9s %8s   %s\n"
    ("Preset" :: String) ("Games" :: String) ("Seed" :: String)
    ("Village%" :: String) ("Wolf%" :: String) ("Draw%" :: String) ("AvgDay" :: String)
    ("Seq(ms)" :: String) ("Par(ms)" :: String) ("Speedup" :: String) ("E19 (Seq==Par)" :: String)
  putStrLn "------------------------------------------------------------------------------------------"

  rows <- sequence
    [ do
        r8 <- runBenchmark "8p (2 Soi)" roles8Preset 8 2 cnt seed
        printConsoleRow r8
        r9 <- runBenchmark "9p (3 Soi)" roles9Preset 9 3 cnt seed
        printConsoleRow r9
        pure [r8, r9]
    | cnt <- counts
    ]

  let allRows = concat rows

  putStrLn "=========================================================================================="
  printf "Writing balance report to: %s\n" outPath

  let csvHeader = "preset,players,wolves,games,base_seed,cores,seq_ms,par_ms,speedup,village_wins,wolf_wins,draws,village_win_rate_pct,wolf_win_rate_pct,draw_rate_pct,avg_rounds,seq_eq_par\n"
      csvBody = unlines (map formatRowCSV allRows)

  createDirectoryIfMissing True (takeDirectory outPath)
  writeFile outPath (csvHeader ++ csvBody)
  putStrLn "Done! Parallel simulation completed successfully."
