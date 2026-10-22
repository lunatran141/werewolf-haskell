-- | Replay thuan cho T11: cung state ban dau va cung chuoi Command
-- luon tao cung ket qua. Command bi tu choi khong lam thay doi state.
module Domain.Replay
  ( ReplayStep(..)
  , ReplayResult(..)
  , replayCommands
  ) where

import Data.List (foldl')
import Domain.Engine (applyCommand)
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
      case applyCommand current command of
        Left err ->
          (current, ReplayStep command (Left err) current : steps)
        Right (next, events) ->
          (next, ReplayStep command (Right events) next : steps)
