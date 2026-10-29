{-# LANGUAGE DeriveGeneric #-}

-- | X01: Mo phong van choi thuan (Pure Simulation), phan tich tham so CLI
-- bang Parser Combinator (ReadP) va danh gia song song bang parMap rdeepseq.
module Domain.Simulation
  ( MatchOutcome(..)
  , BalanceStats(..)
  , SimConfig(..)
  , SimCliOptions(..)
  , SimCliCommand(..)
  , SimCliError(..)
  , defaultSimCliOptions
  , parseGamesSpec
  , parseSeedSpec
  , parseSimulateArgs
  , renderSimCliError
  , simCliUsage
  , roles8Preset
  , roles9Preset
  , simulateOneGame
  , runSequential
  , runParallel
  , aggregateStats
  ) where

import Control.DeepSeq (NFData)
import Control.Parallel.Strategies (parMap, rdeepseq)
import Data.Char (isDigit, isSpace)
import Data.List (foldl', isPrefixOf)
import GHC.Generics (Generic)
import System.Random (StdGen, mkStdGen, randomR)
import Text.ParserCombinators.ReadP
  ( ReadP
  , char
  , eof
  , many
  , munch1
  , option
  , pfail
  , readP_to_S
  , sepBy1
  , skipSpaces
  , (<++)
  )
import Text.Read (readMaybe)

import Domain.Engine
  ( applyCommand
  , closeWolfVoting
  , completeNightTurn
  , resolveNightTurn
  )
import Domain.Night (wolfVictim)
import Domain.RoleShuffle (shuffleRolesWithSeed)
import Domain.Types
  ( Command(..)
  , GameResult(..)
  , GameState
  , LifeStatus(..)
  , NightChoice(..)
  , Phase(..)
  , Player(..)
  , Role(..)
  , Team(..)
  , defaultAppearance
  , emptyLobby
  , gameConfiguredRoles
  , gameDay
  , gameHost
  , gameLastProtected
  , gamePendingHunter
  , gamePhase
  , gamePlayers
  , gameResult
  , gameWitchHealReady
  , gameWitchPoisonReady
  , playerId
  , playerLifeStatus
  , playerRole
  )
import Domain.Validation (validateGameInvariant)

-- | Ket qua dau ra cua mot van choi mo phong.
data MatchOutcome = MatchOutcome
  { outcomeSeed           :: !Int
  , outcomePlayerCount    :: !Int
  , outcomeWolfCount      :: !Int
  , outcomeResult         :: !GameResult
  , outcomeRounds         :: !Int
  , outcomeValidInvariant :: !Bool
  } deriving (Eq, Show, Generic)

instance NFData MatchOutcome

-- | Bang thong ke tong hop nhieu van choi.
data BalanceStats = BalanceStats
  { statsTotalGames         :: !Int
  , statsVillageWins        :: !Int
  , statsWolfWins           :: !Int
  , statsDraws              :: !Int
  , statsTotalRounds        :: !Int
  , statsAllInvariantsValid :: !Bool
  } deriving (Eq, Show, Generic)

instance NFData BalanceStats

-- | Cau hinh mo phong.
data SimConfig = SimConfig
  { simPresetRoles :: ![Role]
  , simBaseSeed    :: !Int
  , simGameCount   :: !Int
  } deriving (Eq, Show, Generic)

instance NFData SimConfig

-- | Tuy chon CLI da duoc kiem tra hop le cho executable werewolf-simulate.
data SimCliOptions = SimCliOptions
  { simOptGames  :: ![Int]
  , simOptSeed   :: !Int
  , simOptOutput :: !FilePath
  } deriving (Eq, Show, Generic)

instance NFData SimCliOptions

-- | Lenh CLI sau khi parse thanh cong.
data SimCliCommand
  = SimCliRun SimCliOptions
  | SimCliHelp
  deriving (Eq, Show, Generic)

instance NFData SimCliCommand

-- | Loi phan tich tham so CLI tuong minh (khong dung partial read).
data SimCliError
  = SimUnknownFlag String
  | SimMissingValue String
  | SimInvalidGames String
  | SimInvalidSeed String
  | SimInvalidOutput String
  deriving (Eq, Show, Generic)

instance NFData SimCliError

-- | Cau hinh CLI mac dinh khi khong truyen tham so.
defaultSimCliOptions :: SimCliOptions
defaultSimCliOptions = SimCliOptions
  { simOptGames  = [1000, 5000]
  , simOptSeed   = 2026
  , simOptOutput = "report/balance.csv"
  }

-- | Chay parser ReadP va lay ket qua khop toan bo chuoi dau vao.
runReadP :: ReadP a -> String -> Maybe a
runReadP parser input =
  case [result | (result, "") <- readP_to_S parser input] of
    result : _ -> Just result
    []         -> Nothing

-- | Parser combinator cho mot moc so van: ho tro so nguyen duong (1000),
-- dau cham phan nhom nghin (1.000, 10.000) va hau to k/K (1k, 5k, 10k).
-- Gioi han trong khoang [1 .. 1.000.000] de tranh tran bo nho.
gameCountTokenP :: ReadP Int
gameCountTokenP = do
  skipSpaces
  firstGroup <- munch1 isDigit
  restGroups <- many (char '.' >> munch1 isDigit)
  let digits = firstGroup ++ concat restGroups
  multiplier <- option (1 :: Integer) ((char 'k' <++ char 'K') >> pure 1000)
  skipSpaces
  case readMaybe digits :: Maybe Integer of
    Just n ->
      let total = n * multiplier
      in if total >= 1 && total <= 1000000
           then pure (fromIntegral total)
           else pfail
    Nothing -> pfail

-- | Parser combinator cho danh sach cac moc so van phan cach boi dau phay.
gamesListP :: ReadP [Int]
gamesListP = do
  counts <- sepBy1 gameCountTokenP (char ',')
  skipSpaces
  eof
  pure counts

-- | Parser combinator cho seed (so nguyen co dau trong khoang [-10^9 .. 10^9]).
seedSpecP :: ReadP Int
seedSpecP = do
  skipSpaces
  sign <- option (1 :: Integer) (char '-' >> pure (-1))
  digits <- munch1 isDigit
  skipSpaces
  eof
  case readMaybe digits :: Maybe Integer of
    Just n ->
      let val = sign * n
      in if val >= -1000000000 && val <= 1000000000
           then pure (fromIntegral val)
           else pfail
    Nothing -> pfail

-- | Phan tich chuoi danh sach so van (vi du "1000,5000,10000" hoac "1k,5k").
parseGamesSpec :: String -> Either SimCliError [Int]
parseGamesSpec raw =
  case runReadP gamesListP raw of
    Just counts | not (null counts) -> Right counts
    _ -> Left (SimInvalidGames raw)

-- | Phan tich chuoi seed.
parseSeedSpec :: String -> Either SimCliError Int
parseSeedSpec raw =
  case runReadP seedSpecP raw of
    Just seed -> Right seed
    Nothing   -> Left (SimInvalidSeed raw)

-- | Kiem tra duong dan file xuat CSV.
validateOutputSpec :: String -> Either SimCliError FilePath
validateOutputSpec raw =
  let trimmed = dropWhile isSpace raw
  in if null trimmed || "--" `isPrefixOf` trimmed
       then Left (SimInvalidOutput raw)
       else Right raw

-- | Phan tich danh sach tham so dong lenh bang de quy tren danh sach va ReadP.
-- Tu choi tuong minh co la, thieu gia tri hoac sai dinh dang so.
parseSimulateArgs :: [String] -> Either SimCliError SimCliCommand
parseSimulateArgs args
  | "--help" `elem` args || "-h" `elem` args = Right SimCliHelp
  | otherwise = SimCliRun <$> go defaultSimCliOptions args
  where
    isFlagLike :: String -> Bool
    isFlagLike s = "--" `isPrefixOf` s

    go :: SimCliOptions -> [String] -> Either SimCliError SimCliOptions
    go opts [] = Right opts
    go _ ["--games"] = Left (SimMissingValue "--games")
    go _ ("--games" : val : _)
      | isFlagLike val = Left (SimMissingValue "--games")
    go opts ("--games" : val : rest) = do
      counts <- parseGamesSpec val
      go (opts { simOptGames = counts }) rest
    go _ ["--seed"] = Left (SimMissingValue "--seed")
    go _ ("--seed" : val : _)
      | isFlagLike val = Left (SimMissingValue "--seed")
    go opts ("--seed" : val : rest) = do
      seed <- parseSeedSpec val
      go (opts { simOptSeed = seed }) rest
    go _ ["--output"] = Left (SimMissingValue "--output")
    go _ ("--output" : val : _)
      | isFlagLike val = Left (SimMissingValue "--output")
    go opts ("--output" : val : rest) = do
      outPath <- validateOutputSpec val
      go (opts { simOptOutput = outPath }) rest
    go opts (arg : rest)
      | "--games=" `isPrefixOf` arg = do
          let val = drop (length ("--games=" :: String)) arg
          if null val
            then Left (SimMissingValue "--games")
            else do
              counts <- parseGamesSpec val
              go (opts { simOptGames = counts }) rest
      | "--seed=" `isPrefixOf` arg = do
          let val = drop (length ("--seed=" :: String)) arg
          if null val
            then Left (SimMissingValue "--seed")
            else do
              seed <- parseSeedSpec val
              go (opts { simOptSeed = seed }) rest
      | "--output=" `isPrefixOf` arg = do
          let val = drop (length ("--output=" :: String)) arg
          if null val
            then Left (SimMissingValue "--output")
            else do
              outPath <- validateOutputSpec val
              go (opts { simOptOutput = outPath }) rest
      | otherwise = Left (SimUnknownFlag arg)

-- | Thong bao loi CLI ro rang cho nguoi dung.
renderSimCliError :: SimCliError -> String
renderSimCliError err =
  case err of
    SimUnknownFlag flag ->
      "Loi tham so: Khong nhan dien duoc co hoac tham so '" ++ flag ++ "'."
    SimMissingValue flag ->
      "Loi tham so: Co '" ++ flag ++ "' can mot gia tri di kem."
    SimInvalidGames raw ->
      "Loi tham so --games: '" ++ raw
        ++ "' khong hop le (yeu cau danh sach so nguyen 1..1000000, vi du: 1000,5000 hoac 1k,5k,10k)."
    SimInvalidSeed raw ->
      "Loi tham so --seed: '" ++ raw
        ++ "' khong hop le (yeu cau so nguyen trong khoang [-1000000000..1000000000])."
    SimInvalidOutput raw ->
      "Loi tham so --output: Duong dan file '" ++ raw ++ "' khong hop le."

-- | Huong dan su dung dong lenh werewolf-simulate.
simCliUsage :: String
simCliUsage = unlines
  [ "Su dung: werewolf-simulate [TUY CHON]"
  , "  --games <ds>     Danh sach so van mo phong (mac dinh: 1000,5000; ho tro 1k,5k,10k hoac 1.000,5.000)"
  , "  --seed <so>      Seed khoi tao RNG (mac dinh: 2026)"
  , "  --output <file>  Duong dan file CSV xuat ket qua (mac dinh: report/balance.csv)"
  , "  --help, -h       Hien thi huong dan su dung"
  ]

-- | Preset 8 nguoi: 2 Soi, 1 Tien Tri, 1 Bao Ve, 1 Phu Thuy, 1 Tho San, 2 Dan lang.
roles8Preset :: [Role]
roles8Preset =
  [ Werewolf, Werewolf, Seer, Guard, Witch, Hunter, Villager, Villager ]

-- | Preset 9 nguoi: 3 Soi, 1 Tien Tri, 1 Bao Ve, 1 Phu Thuy, 1 Tho San, 2 Dan lang.
roles9Preset :: [Role]
roles9Preset =
  [ Werewolf, Werewolf, Werewolf, Seer, Guard, Witch, Hunter, Villager, Villager ]

-- | Chon ngau nhien co xac dinh 1 phan tu trong danh sach bang StdGen.
pickRandom :: [a] -> StdGen -> Maybe (a, StdGen)
pickRandom [] _ = Nothing
pickRandom xs gen =
  let (idx, nextGen) = randomR (0, length xs - 1) gen
  in Just (xs !! idx, nextGen)

-- | Mo phong thuan mot van choi hoan chinh tu Lobby den GameOver bang seed.
simulateOneGame :: [Role] -> Int -> MatchOutcome
simulateOneGame roles seed =
  let initialGen = mkStdGen seed
      playerCount = length roles
      wolfCount = length (filter (== Werewolf) roles)
      playerIds = ["p" ++ show i | i <- [1 .. playerCount]]

      initialPlayers =
        [ Player pid ("Player " ++ pid) Nothing True Alive defaultAppearance
        | pid <- playerIds
        ]

      lobbyState =
        emptyLobby
          { gamePlayers = initialPlayers
          , gameHost = "p1"
          , gamePhase = Lobby
          , gameDay = 0
          , gameConfiguredRoles = roles
          }

      shuffledRoles = shuffleRolesWithSeed seed roles
      startRes = applyCommand lobbyState (StartGame "p1" shuffledRoles)
      night1State =
        case startRes of
          Right (st, _) -> st
          Left _        -> lobbyState

  in gameLoop night1State initialGen 0 playerCount wolfCount seed

-- | Vong lap cac pha cho den khi GameOver (gioi han toi da 30 vong de dam bao luon dung).
gameLoop :: GameState -> StdGen -> Int -> Int -> Int -> Int -> MatchOutcome
gameLoop state gen stepCount pCount wCount seed
  | gamePhase state == GameOver || stepCount >= 30 =
      let res = case gameResult state of
                  Just r  -> r
                  Nothing -> Draw
          valid = validateGameInvariant state == Right ()
      in MatchOutcome
          { outcomeSeed = seed
          , outcomePlayerCount = pCount
          , outcomeWolfCount = wCount
          , outcomeResult = res
          , outcomeRounds = gameDay state
          , outcomeValidInvariant = valid
          }

  -- 1. Neu co Hunter dang cho ban (co the xay ra sau Night hoac Voting)
  | Just hunterId <- gamePendingHunter state =
      let livingTargets =
            [ playerId p
            | p <- gamePlayers state
            , playerLifeStatus p == Alive
            , playerId p /= hunterId
            ]
      in case pickRandom livingTargets gen of
           Just (target, gen') ->
             let nextState =
                   case applyCommand state (ResolveHunter hunterId (Just target)) of
                     Right (st, _) -> st
                     Left _        -> state
             in gameLoop nextState gen' (stepCount + 1) pCount wCount seed
           Nothing ->
             let nextState =
                   case applyCommand state (ResolveHunter hunterId Nothing) of
                     Right (st, _) -> st
                     Left _        -> state
             in gameLoop nextState gen (stepCount + 1) pCount wCount seed

  -- 2. Pha Night: Soi, Tien Tri, Bao Ve, Phu Thuy thuc hien hanh dong
  | gamePhase state == Night =
      let (stateAfterNight, gen') = runNightTurn state gen
      in gameLoop stateAfterNight gen' (stepCount + 1) pCount wCount seed

  -- 3. Pha Day: Chuyen tiep sang Voting
  | gamePhase state == Day =
      let nextState =
            case applyCommand state AdvancePhase of
              Right (st, _) -> st
              Left _        -> state
      in gameLoop nextState gen (stepCount + 1) pCount wCount seed

  -- 4. Pha Voting: Moi nguoi con song bo phieu
  | gamePhase state == Voting =
      let (stateAfterVoting, gen') = runVotingTurn state gen
      in gameLoop stateAfterVoting gen' (stepCount + 1) pCount wCount seed

  | otherwise =
      gameLoop state gen 30 pCount wCount seed

-- | Thuc hien toan bo hanh dong ban dem va resolve sang Day.
runNightTurn :: GameState -> StdGen -> (GameState, StdGen)
runNightTurn state gen0 =
  let aliveNonWolves =
        [ playerId p
        | p <- gamePlayers state
        , playerLifeStatus p == Alive
        , playerRole p /= Just Werewolf
        ]
      aliveWolves =
        [ playerId p
        | p <- gamePlayers state
        , playerLifeStatus p == Alive
        , playerRole p == Just Werewolf
        ]

      -- Soi chon muc tieu
      (stAfterWolves, gen1) =
        case pickRandom aliveNonWolves gen0 of
          Just (wolfVictimTarget, g1) ->
            let applyWolfVotes st [] = st
                applyWolfVotes st (w : ws) =
                  case applyCommand st (NightAction w (WolfTarget wolfVictimTarget)) of
                    Right (nextSt, _) -> applyWolfVotes nextSt ws
                    Left _            -> applyWolfVotes st ws
                votedSt = applyWolfVotes state aliveWolves
                closedSt =
                  case closeWolfVoting votedSt True of
                    Right (cSt, _) -> cSt
                    Left _         -> votedSt
            in (closedSt, g1)
          Nothing ->
            case closeWolfVoting state True of
              Right (cSt, _) -> (cSt, gen0)
              Left _         -> (state, gen0)

      -- Tien Tri soi
      aliveOthersForSeer seerId =
        [ playerId p
        | p <- gamePlayers stAfterWolves
        , playerLifeStatus p == Alive
        , playerId p /= seerId
        ]
      livingSeer =
        [ playerId p
        | p <- gamePlayers stAfterWolves
        , playerLifeStatus p == Alive
        , playerRole p == Just Seer
        ]
      (stAfterSeer, gen2) =
        case livingSeer of
          (sId : _) ->
            case pickRandom (aliveOthersForSeer sId) gen1 of
              Just (target, g2) ->
                case applyCommand stAfterWolves (NightAction sId (SeerTarget target)) of
                  Right (nextSt, _) -> (nextSt, g2)
                  Left _            -> (stAfterWolves, g2)
              Nothing -> (stAfterWolves, gen1)
          [] -> (stAfterWolves, gen1)

      -- Bao Ve
      livingGuard =
        [ playerId p
        | p <- gamePlayers stAfterSeer
        , playerLifeStatus p == Alive
        , playerRole p == Just Guard
        ]
      validGuardTargets =
        [ playerId p
        | p <- gamePlayers stAfterSeer
        , playerLifeStatus p == Alive
        , Just (playerId p) /= gameLastProtected stAfterSeer
        ]
      (stAfterGuard, gen3) =
        case livingGuard of
          (gId : _) ->
            case pickRandom validGuardTargets gen2 of
              Just (target, g3) ->
                case applyCommand stAfterSeer (NightAction gId (GuardTarget target)) of
                  Right (nextSt, _) -> (nextSt, g3)
                  Left _            -> (stAfterSeer, g3)
              Nothing -> (stAfterSeer, gen2)
          [] -> (stAfterSeer, gen2)

      -- Phu Thuy
      livingWitch =
        [ playerId p
        | p <- gamePlayers stAfterGuard
        , playerLifeStatus p == Alive
        , playerRole p == Just Witch
        ]
      (stAfterWitch, gen4) =
        case livingWitch of
          (wId : _) ->
            let currentVictim = wolfVictim stAfterGuard
                healReady = gameWitchHealReady stAfterGuard
                poisonReady = gameWitchPoisonReady stAfterGuard
                (healRoll, g3a) = randomR (0 :: Int, 99) gen3
                (poisonRoll, g3b) = randomR (0 :: Int, 99) g3a
            in if healReady && currentVictim /= Nothing && healRoll < 75
                 then
                   case applyCommand stAfterGuard (NightAction wId WitchHeal) of
                     Right (nextSt, _) -> (nextSt, g3a)
                     Left _            -> (stAfterGuard, g3a)
                 else if poisonReady && poisonRoll < 20
                        then
                          let poisonTargets =
                                [ playerId p
                                | p <- gamePlayers stAfterGuard
                                , playerLifeStatus p == Alive
                                , playerId p /= wId
                                ]
                          in case pickRandom poisonTargets g3b of
                               Just (pTarget, g3c) ->
                                 case applyCommand stAfterGuard (NightAction wId (WitchPoison pTarget)) of
                                   Right (nextSt, _) -> (nextSt, g3c)
                                   Left _            -> (stAfterGuard, g3c)
                               Nothing ->
                                 case applyCommand stAfterGuard (NightAction wId WitchPass) of
                                   Right (nextSt, _) -> (nextSt, g3b)
                                   Left _            -> (stAfterGuard, g3b)
                        else
                          case applyCommand stAfterGuard (NightAction wId WitchPass) of
                            Right (nextSt, _) -> (nextSt, g3b)
                            Left _            -> (stAfterGuard, g3b)
          [] -> (stAfterGuard, gen3)

      -- Resolve Night Turn
      resolvedSt =
        case resolveNightTurn stAfterWitch of
          Right (st, _) ->
            if gamePendingHunter st /= Nothing
              then st
              else case completeNightTurn st of
                     Right (cSt, _) -> cSt
                     Left _         -> st
          Left _ -> stAfterWitch

  in (resolvedSt, gen4)

-- | Thuc hien toan bo phieu bau ban ngay.
runVotingTurn :: GameState -> StdGen -> (GameState, StdGen)
runVotingTurn state gen0 =
  let alivePlayers =
        [ playerId p
        | p <- gamePlayers state
        , playerLifeStatus p == Alive
        ]

      applyVotes currentSt [] gen = (currentSt, gen)
      applyVotes currentSt (voter : remaining) gen =
        if gamePhase currentSt /= Voting
          then (currentSt, gen)
          else
            let possibleTargets =
                  [ playerId p
                  | p <- gamePlayers currentSt
                  , playerLifeStatus p == Alive
                  , playerId p /= voter
                  ]
            in case pickRandom possibleTargets gen of
                 Just (target, gen') ->
                   let nextSt =
                         case applyCommand currentSt (Vote voter target) of
                           Right (st, _) -> st
                           Left _        -> currentSt
                   in applyVotes nextSt remaining gen'
                 Nothing -> applyVotes currentSt remaining gen

      (afterVotesSt, genFinal) = applyVotes state alivePlayers gen0

      -- Neu tat ca da vote nhung chua resolve vi ly do nao do
      finalVotingSt =
        if gamePhase afterVotesSt == Voting
          then case applyCommand afterVotesSt ResolveVoting of
                 Right (st, _) -> st
                 Left _        -> afterVotesSt
          else afterVotesSt

  in (finalVotingSt, genFinal)

-- | Tinh tong hop thong ke bang strict foldl'.
aggregateStats :: [MatchOutcome] -> BalanceStats
aggregateStats = foldl' add (BalanceStats 0 0 0 0 0 True)
  where
    add acc o =
      BalanceStats
        { statsTotalGames = statsTotalGames acc + 1
        , statsVillageWins = statsVillageWins acc + if isVillageWin (outcomeResult o) then 1 else 0
        , statsWolfWins = statsWolfWins acc + if isWolfWin (outcomeResult o) then 1 else 0
        , statsDraws = statsDraws acc + if isDraw (outcomeResult o) then 1 else 0
        , statsTotalRounds = statsTotalRounds acc + outcomeRounds o
        , statsAllInvariantsValid = statsAllInvariantsValid acc && outcomeValidInvariant o
        }
    isVillageWin (Winner Village) = True
    isVillageWin _ = False
    isWolfWin (Winner Wolves) = True
    isWolfWin _ = False
    isDraw Draw = True
    isDraw _ = False

-- | Chay mo phong tuan tu (Sequential) bang map.
runSequential :: SimConfig -> ([MatchOutcome], BalanceStats)
runSequential cfg =
  let seeds = [simBaseSeed cfg .. simBaseSeed cfg + simGameCount cfg - 1]
      outcomes = map (simulateOneGame (simPresetRoles cfg)) seeds
      stats = aggregateStats outcomes
  in (outcomes, stats)

-- | Chay mo phong song song (Parallel) bang parMap rdeepseq.
runParallel :: SimConfig -> ([MatchOutcome], BalanceStats)
runParallel cfg =
  let seeds = [simBaseSeed cfg .. simBaseSeed cfg + simGameCount cfg - 1]
      outcomes = parMap rdeepseq (simulateOneGame (simPresetRoles cfg)) seeds
      stats = aggregateStats outcomes
  in (outcomes, stats)
