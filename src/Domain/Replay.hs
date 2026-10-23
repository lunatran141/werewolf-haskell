-- | Replay thuan cho T11: cung state ban dau va cung chuoi Command
-- luon tao cung ket qua. Command bi tu choi khong lam thay doi state.
module Domain.Replay
  ( ReplayStep(..)
  , ReplayResult(..)
  , replayCommands
  , replayWithSeed
  , applyReplayCommand
  ) where

import Data.List (foldl')
import Domain.Engine (applyCommand, completeNightTurn)
import Domain.RoleShuffle (shuffleRolesWithSeed)
import Domain.Types

data ReplayStep = ReplayStep
  { replayCommand :: Command
  , replayOutcome :: Either GameError [DomainEvent]
  , replayState   :: GameState
  } deriving (Eq, Show)

data ReplayResult = ReplayResult
  { replayInitialState :: GameState
  , replayFinalState   :: GameState
  , replaySteps        :: [ReplayStep]
  } deriving (Eq, Show)

-- | Ap dung 1 command trong replay. Khi ResolveNight thanh cong va
-- khong co Hunter cho ban, tu dong hoan tat chuyen sang Day/GameOver
-- de chuoi Command co the di xuyen suot cac Phase ma khong bi tac o Night.
applyReplayCommand :: GameState -> Command -> Either GameError (GameState, [DomainEvent])
applyReplayCommand current command =
  case applyCommand current command of
    Left err -> Left err
    Right (next, events) ->
      case command of
        ResolveNight
          | gamePhase next == Night
          , gameNightResolved next
          , gamePendingHunter next == Nothing ->
              case completeNightTurn next of
                Left err -> Left err
                Right (completedState, completeEvents) ->
                  Right (completedState, events ++ completeEvents)
        _ -> Right (next, events)

-- | Chay mot chuoi Command tu GameState ban dau bang foldl'.
replayCommands :: GameState -> [Command] -> ReplayResult
replayCommands initial commands =
  ReplayResult
    { replayInitialState = initial
    , replayFinalState = finalState
    , replaySteps = reverse reversedSteps
    }
  where
    (finalState, reversedSteps) =
      foldl' applyOne (initial, []) commands

    applyOne (current, steps) command =
      case applyReplayCommand current command of
        Left err ->
          (current, ReplayStep command (Left err) current : steps)
        Right (next, events) ->
          (next, ReplayStep command (Right events) next : steps)

-- | Replay van choi ket hop phan vai ngau nhien co kiem soat bang seed.
replayWithSeed :: Int -> [Role] -> GameState -> [Command] -> ReplayResult
replayWithSeed seed roles initial commands =
  let shuffled = shuffleRolesWithSeed seed roles
      prepared =
        case gamePhase initial of
          Lobby ->
            case applyCommand initial (StartGame (gameHost initial) shuffled) of
              Right (started, _) -> started
              Left _             -> initial
          _ -> initial
  in replayCommands prepared commands
