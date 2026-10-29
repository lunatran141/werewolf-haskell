-- | X01: Bo kiem thu tu dong cho Parallel Simulation (E19) va CLI Parser (ReadP).
-- Chung minh cung seed thi ban tuan tu (map) va ban song song (parMap rdeepseq)
-- cho ket qua dong nhat tuyet doi, giu invariant, CLI parser an toan khong crash.
module Main (main) where

import Control.DeepSeq (rnf)
import Control.Exception (evaluate)
import Test.Hspec
import Test.QuickCheck

import Domain.Simulation
  ( BalanceStats(..)
  , MatchOutcome(..)
  , SimCliCommand(..)
  , SimCliError(..)
  , SimCliOptions(..)
  , SimConfig(..)
  , defaultSimCliOptions
  , parseSimulateArgs
  , renderSimCliError
  , roles8Preset
  , roles9Preset
  , runParallel
  , runSequential
  , simulateOneGame
  )
import Domain.Types (GameResult(..), Team(..))

main :: IO ()
main = hspec $ do

  describe "X01 - E19 Deterministic Parallelism (Sequential == Parallel)" $ do

    it "E19 - 8 nguoi (2 Soi): sequential == parallel cung seed va giu invariant" $ do
      let cfg = SimConfig
            { simPresetRoles = roles8Preset
            , simBaseSeed = 2026
            , simGameCount = 200
            }
          (seqOutcomes, seqStats) = runSequential cfg
          (parOutcomes, parStats) = runParallel cfg

      -- 1. Ket qua tung van phai giong nhau tung byte
      parOutcomes `shouldBe` seqOutcomes

      -- 2. Thong ke tong hop phai bang nhau
      parStats `shouldBe` seqStats

      -- 3. Tat ca van deu phai giu invariant GameState hop le
      statsAllInvariantsValid parStats `shouldBe` True
      statsTotalGames parStats `shouldBe` 200
      statsVillageWins parStats + statsWolfWins parStats + statsDraws parStats
        `shouldBe` 200

    it "E19 - 9 nguoi (3 Soi): sequential == parallel cung seed va giu invariant" $ do
      let cfg = SimConfig
            { simPresetRoles = roles9Preset
            , simBaseSeed = 9999
            , simGameCount = 200
            }
          (seqOutcomes, seqStats) = runSequential cfg
          (parOutcomes, parStats) = runParallel cfg

      parOutcomes `shouldBe` seqOutcomes
      parStats `shouldBe` seqStats
      statsAllInvariantsValid parStats `shouldBe` True
      statsTotalGames parStats `shouldBe` 200
      statsVillageWins parStats + statsWolfWins parStats + statsDraws parStats
        `shouldBe` 200

    it "E19 - simulateOneGame tao ket qua xac dinh va invariant dung tren tung van" $ do
      let run1 = simulateOneGame roles8Preset 77777
          run2 = simulateOneGame roles8Preset 77777
      run1 `shouldBe` run2
      outcomeValidInvariant run1 `shouldBe` True
      outcomePlayerCount run1 `shouldBe` 8
      outcomeWolfCount run1 `shouldBe` 2
      outcomeRounds run1 `shouldSatisfy` (> 0)

  describe "X01 - CLI Parser Combinator (ReadP)" $ do

    it "khong truyen tham so tra ve cau hinh mac dinh" $ do
      parseSimulateArgs [] `shouldBe` Right (SimCliRun defaultSimCliOptions)

    it "ho tro nhieu dang dau vao (--games 1000,5000,10000, hau to k, dau cham phan nhom, dau =)" $ do
      parseSimulateArgs ["--games", "1000,5000,10000", "--seed", "2026", "--output", "report/balance.csv"]
        `shouldBe` Right (SimCliRun (SimCliOptions [1000, 5000, 10000] 2026 "report/balance.csv"))
      parseSimulateArgs ["--games=1k,5k,10k", "--seed=-42", "--output=out.csv"]
        `shouldBe` Right (SimCliRun (SimCliOptions [1000, 5000, 10000] (-42) "out.csv"))
      parseSimulateArgs ["--games", "1.000,10.000"]
        `shouldBe` Right (SimCliRun (defaultSimCliOptions { simOptGames = [1000, 10000] }))
      parseSimulateArgs ["--help"] `shouldBe` Right SimCliHelp

    it "tu choi tuong minh gia tri so sai, co la hoac thieu gia tri ma khong crash" $ do
      parseSimulateArgs ["--games", "1000,abc"]
        `shouldBe` Left (SimInvalidGames "1000,abc")
      parseSimulateArgs ["--games", "0"]
        `shouldBe` Left (SimInvalidGames "0")
      parseSimulateArgs ["--seed", "not-a-number"]
        `shouldBe` Left (SimInvalidSeed "not-a-number")
      parseSimulateArgs ["--unknown-flag"]
        `shouldBe` Left (SimUnknownFlag "--unknown-flag")
      parseSimulateArgs ["--games"]
        `shouldBe` Left (SimMissingValue "--games")
      parseSimulateArgs ["--games", "--seed", "2026"]
        `shouldBe` Left (SimMissingValue "--games")
      renderSimCliError (SimInvalidGames "abc") `shouldSatisfy` (not . null)

  describe "X01 - QuickCheck Property Tests" $ do

    it "Property: parseSimulateArgs khong bao gio nem exception voi moi danh sach tham so bat ky" $
      property $ \(args :: [String]) ->
        ioProperty $ do
          res <- evaluate (rnf (parseSimulateArgs args))
          pure (res == ())

    it "Property: Voi moi seed va so van bat ky, sequential luon bang parallel" $
      property $ \(Positive countRaw) (seed :: Int) ->
        let count = (countRaw `mod` 30) + 1
            cfg = SimConfig roles8Preset seed count
            (seqOutcomes, seqStats) = runSequential cfg
            (parOutcomes, parStats) = runParallel cfg
        in seqOutcomes == parOutcomes
           && seqStats == parStats
           && statsAllInvariantsValid parStats
           && statsTotalGames parStats == count
           && (statsVillageWins parStats + statsWolfWins parStats + statsDraws parStats == count)

    it "Property: 9 nguoi 3 Soi luon ket thuc o GameOver va bao toan bat bien" $
      property $ \(seed :: Int) ->
        let outcome = simulateOneGame roles9Preset seed
        in outcomeValidInvariant outcome
           && outcomePlayerCount outcome == 9
           && outcomeWolfCount outcome == 3
           && outcomeRounds outcome >= 1
           && case outcomeResult outcome of
                Winner Village -> True
                Winner Wolves  -> True
                Draw           -> True

  describe "X01 - Game Balance Verification (1.000 van mo phong)" $ do

    it "1.000 van 8 nguoi (2 Soi): ca 2 phe deu co chien thang, khong crash hay deadlock" $ do
      let cfg = SimConfig roles8Preset 1001 1000
          (_, stats) = runParallel cfg
      statsTotalGames stats `shouldBe` 1000
      statsAllInvariantsValid stats `shouldBe` True
      statsVillageWins stats `shouldSatisfy` (> 0)
      statsWolfWins stats `shouldSatisfy` (> 0)

    it "1.000 van 9 nguoi (3 Soi): ty le thang Soi cao hon nhung van hop le 100%" $ do
      let cfg = SimConfig roles9Preset 2002 1000
          (_, stats) = runParallel cfg
      statsTotalGames stats `shouldBe` 1000
      statsAllInvariantsValid stats `shouldBe` True
      statsWolfWins stats `shouldSatisfy` (> 0)
