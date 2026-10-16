-- Kiểm thử T06 tại queue STM: xác thực session, commit Vote và chống trùng.
module Main (main) where

import Control.Concurrent (forkIO, killThread)
import Control.Concurrent.STM
  ( atomically
  , check
  , dupTChan
  , isEmptyTChan
  , newEmptyTMVarIO
  , readTChan
  , readTVar
  , readTVarIO
  , takeTMVar
  , writeTBQueue
  , writeTVar
  )
import Control.Exception (bracket)
import Domain.Types
import Server.GameLoop (processNextLobbyCommand, runGameLoopWithPhaseTimeouts)
import Server.Room
  ( QueuedCommand(..)
  , RoomRuntime(..)
  , RoomUpdate(..)
  , newRoomRuntime
  )
import Test.Hspec
import System.Timeout (timeout)

roles8 :: [Role]
roles8 = [Werewolf, Werewolf, Seer, Guard, Witch, Hunter, Villager, Villager]

votingState :: GameState
votingState =
  emptyLobby
    { gamePlayers =
        [ Player pid ("Nguoi " ++ pid) (Just role) True Alive defaultAppearance
        | (pid, role) <- zip (map ("p" ++) (map show [1 :: Int .. 8])) roles8
        ]
    , gameHost = "p1"
    , gamePhase = Voting
    , gameDay = 1
    , gameConfiguredRoles = roles8
    }

submitVote :: RoomRuntime -> String -> String -> IO (Either GameError GameState)
submitVote room sessionActor commandActor = do
  reply <- newEmptyTMVarIO
  atomically $
    writeTBQueue (roomCommands room)
      QueuedCommand
        { queuedRequestId = "vote-request"
        , queuedActorId = sessionActor
        , queuedCommand = Vote commandActor "p7"
        , queuedReply = reply
        }
  processNextLobbyCommand room
  atomically (takeTMVar reply)

main :: IO ()
main = hspec $ describe "T06 GameLoop Vote" $ do
  it "Day tu dong chuyen sang Voting sau thoi gian thao luan" $ do
    room <- newRoomRuntime "ROOM-DAY"
    atomically (writeTVar (roomState room) votingState {gamePhase = Day})
    let waitForVoting = timeout 2000000 $ atomically $ do
          state <- readTVar (roomState room)
          check (gamePhase state == Voting)
    bracket
      (forkIO (runGameLoopWithPhaseTimeouts 50000 1000000 1000000 room))
      killThread
      (\_ -> waitForVoting `shouldReturn` Just ())

  it "Vote hop le duoc commit qua queue va phat event" $ do
    room <- newRoomRuntime "ROOM-01"
    updates <- atomically (dupTChan (roomUpdates room))
    atomically (writeTVar (roomState room) votingState)

    result <- submitVote room "p1" "p1"
    fmap gameVotes result `shouldBe` Right [("p1", "p7")]

    version <- readTVarIO (roomVersion room)
    version `shouldBe` 1
    update <- atomically (readTChan updates)
    updateEvents update `shouldBe` [VoteUpdated "p1" "p7"]

  it "Session khong duoc Vote thay PlayerId khac" $ do
    room <- newRoomRuntime "ROOM-01"
    updates <- atomically (dupTChan (roomUpdates room))
    atomically (writeTVar (roomState room) votingState)

    result <- submitVote room "p1" "p2"
    result `shouldBe` Left NotAuthorized
    readTVarIO (roomVersion room) `shouldReturn` 0
    atomically (isEmptyTChan updates) `shouldReturn` True

  it "Vote trung cung round bi tu choi va khong tang version" $ do
    room <- newRoomRuntime "ROOM-01"
    updates <- atomically (dupTChan (roomUpdates room))
    atomically (writeTVar (roomState room) votingState)

    _ <- submitVote room "p1" "p1"
    _ <- atomically (readTChan updates)
    result <- submitVote room "p1" "p1"

    result `shouldBe` Left DuplicateRequest
    readTVarIO (roomVersion room) `shouldReturn` 1
    atomically (isEmptyTChan updates) `shouldReturn` True
