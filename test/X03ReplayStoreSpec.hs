{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Concurrent.STM (atomically, writeTChan)
import Control.Exception (bracket)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString.Lazy.Char8 as BL8
import Data.Char (toLower)
import Domain.Types
  ( DomainEvent(GameFinished)
  , GameResult(..)
  , GameState(..)
  , LifeStatus(Alive)
  , Player(..)
  , Team(..)
  , defaultAppearance
  , emptyLobby
  )
import Protocol.Analytics (MatchSummary(..))
import Server.AnalyticsClient
  ( newAnalyticsPublisher
  , publishMatchSummary
  , subscribeRoomAnalyticsWithReplay
  )
import Server.ReplayStore
  ( ReplayWriteResult(..)
  , StorageError(..)
  , newReplayStore
  , readReplay
  , renderStorageError
  , replayFilePath
  , storageErrorFromIOException
  , writeReplay
  )
import Server.Room
  ( RoomRuntime(..)
  , RoomUpdate(..)
  , newRoomRuntime
  )
import Server.SafeLog (LogLevel(Warning), encodeSafeLogLine)
import System.Directory
  ( createDirectory
  , getTemporaryDirectory
  , removeFile
  , removePathForcibly
  )
import System.FilePath ((</>))
import System.IO (hClose, openBinaryTempFile)
import System.IO.Error (mkIOError, permissionErrorType)
import Test.Hspec

sampleReplay :: MatchSummary
sampleReplay = MatchSummary
  { matchId = "match-X03-001"
  , matchRoomId = "ROOM-X03"
  , matchResult = Winner Village
  , matchDayCount = 3
  , matchPlayerCount = 9
  }

withTempDirectory :: (FilePath -> IO a) -> IO a
withTempDirectory action =
  bracket create removePathForcibly action
  where
    create = do
      base <- getTemporaryDirectory
      (path, handle) <- openBinaryTempFile base "x03-replay-store"
      hClose handle
      removeFile path
      createDirectory path
      pure path

main :: IO ()
main = hspec $ do
  describe "X03 - shared ReplayStore" $ do
    it "Game Server va Analytics Worker doc cung mot replay" $
      withTempDirectory $ \directory -> do
        let serverStore = newReplayStore directory
            workerStore = newReplayStore directory
        result <- writeReplay serverStore sampleReplay
        result `shouldSatisfy` isCreated
        readReplay serverStore (matchId sampleReplay)
          `shouldReturn` Right sampleReplay
        readReplay workerStore (matchId sampleReplay)
          `shouldReturn` Right sampleReplay

    it "ghi lai cung matchId va noi dung la idempotent" $
      withTempDirectory $ \directory -> do
        let store = newReplayStore directory
        first <- writeReplay store sampleReplay
        first `shouldSatisfy` isCreated
        second <- writeReplay store sampleReplay
        second `shouldSatisfy` isAlreadyPresent

    it "cung matchId nhung noi dung khac bi tu choi" $
      withTempDirectory $ \directory -> do
        let store = newReplayStore directory
            changed = sampleReplay {matchDayCount = 4}
        _ <- writeReplay store sampleReplay
        result <- writeReplay store changed
        result `shouldSatisfy` isConflict

    it "matchId khong duoc thoat khoi shared/replays" $ do
      let store = newReplayStore "shared/replays"
          malicious = sampleReplay {matchId = "../secret"}
      writeReplay store malicious
        `shouldReturn` Left (StorageInvalidMatchId "../secret")

    it "file replay hong duoc tra ve thanh StorageCorrupt" $
      withTempDirectory $ \directory -> do
        let store = newReplayStore directory
        case replayFilePath store (matchId sampleReplay) of
          Left err -> expectationFailure (show err)
          Right path -> do
            BS.writeFile path "not-json"
            result <- readReplay store (matchId sampleReplay)
            result `shouldSatisfy` isCorrupt

    it "mount khong dung duoc tra StorageError thay vi nem exception" $
      withTempDirectory $ \directory -> do
        let mountFile = directory </> "not-a-directory"
        BS.writeFile mountFile "occupied"
        let store = newReplayStore mountFile
            replay = sampleReplay {matchId = "unavailable-mount"}
        result <- writeReplay store replay
        result `shouldSatisfy` isUnavailable

    it "permission denied duoc chuyen thanh StoragePermissionDenied" $ do
      let path = "shared/replays/denied.json"
          ioErrorValue = mkIOError permissionErrorType "denied" Nothing (Just path)
      storageErrorFromIOException path ioErrorValue
        `shouldBe` StoragePermissionDenied path

    it "replay khong chua role, ten, chat hoac night target" $
      withTempDirectory $ \directory -> do
        let store = newReplayStore directory
        _ <- writeReplay store sampleReplay
        case replayFilePath store (matchId sampleReplay) of
          Left err -> expectationFailure (show err)
          Right path -> do
            bytes <- BSC.map toLower <$> BS.readFile path
            mapM_ (assertSecretAbsent bytes)
              [ "role"
              , "displayname"
              , "chat"
              , "target"
              , "nightaction"
              ]

    it "loi mount NFS trong luc game van tiep tuc chay khong lam dung RoomRuntime va van day MatchSummary" $
      withTempDirectory $ \directory -> do
        let brokenMount = directory </> "broken-nfs-mount"
        BS.writeFile brokenMount "occupied-by-file"
        let brokenStore = newReplayStore brokenMount
        room <- newRoomRuntime "ROOM-NFS-ERR"
        publisher <- newAnalyticsPublisher "127.0.0.1" "1"
        let player = Player "p1" "Player 1" Nothing False Alive defaultAppearance
            state = emptyLobby {gameDay = 2, gamePlayers = [player], gameHost = "p1"}
            update = RoomUpdate
              { updateVersion = 9
              , updateState = state
              , updateEvents = [GameFinished (Winner Wolves)]
              , updateChatRecord = Nothing
              }
        forwarder <- subscribeRoomAnalyticsWithReplay (Just brokenStore) publisher room
        bracket (forkIO forwarder) killThread $ \_ -> do
          atomically (writeTChan (roomUpdates room) update)
          threadDelay 50000
          -- Subscriber khong bi crash va publisher van tiep tuc nhan them summary moi
          let followUp = sampleReplay { matchId = "match-X03-002" }
          publishMatchSummary publisher followUp `shouldReturn` True

    it "log loi StorageError va SafeLog khong lo role, ten, chat hoac night target" $ do
      let errs =
            [ StorageUnavailable "shared/replays/m1.json" "mount disconnected"
            , StoragePermissionDenied "shared/replays/m1.json"
            , StorageCorrupt "shared/replays/m1.json" "invalid json"
            , StorageConflict "shared/replays/m1.json"
            , StorageInvalidMatchId "../Werewolf"
            ]
          renderedLogs =
            [ BSC.map toLower $ BL8.toStrict $
                encodeSafeLogLine Warning "replay-store" "write_failed"
                  [ ("reason", renderStorageError err)
                  , ("secretRole", "Werewolf")
                  , ("wolfChat", "attack p2")
                  ]
            | err <- errs
            ]
      forM_ renderedLogs $ \bytes ->
        mapM_ (assertSecretAbsent bytes)
          [ "werewolf"
          , "seer"
          , "attack p2"
          , "displayname"
          , "nightaction"
          ]
  where
    forM_ = flip mapM_

isCreated :: Either StorageError ReplayWriteResult -> Bool
isCreated (Right (ReplayCreated _)) = True
isCreated _ = False

isAlreadyPresent :: Either StorageError ReplayWriteResult -> Bool
isAlreadyPresent (Right (ReplayAlreadyPresent _)) = True
isAlreadyPresent _ = False

isConflict :: Either StorageError ReplayWriteResult -> Bool
isConflict (Left (StorageConflict _)) = True
isConflict _ = False

isCorrupt :: Either StorageError MatchSummary -> Bool
isCorrupt (Left (StorageCorrupt _ _)) = True
isCorrupt _ = False

isUnavailable :: Either StorageError ReplayWriteResult -> Bool
isUnavailable (Left (StorageUnavailable _ _)) = True
isUnavailable _ = False

assertSecretAbsent :: BS.ByteString -> BS.ByteString -> Expectation
assertSecretAbsent bytes secret =
  BS.isInfixOf secret bytes `shouldBe` False
