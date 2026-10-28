module Main (main) where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Concurrent.STM (atomically, writeTChan)
import Control.Exception (bracket)
import Domain.Types
  ( DomainEvent(..)
  , GameResult(..)
  , GameState(..)
  , LifeStatus(..)
  , Player(..)
  , Team(..)
  , defaultAppearance
  , emptyLobby
  )
import Protocol.Analytics (MatchSummary(..))
import Server.AnalyticsClient
  ( matchSummaryForUpdate
  , newAnalyticsPublisher
  , publishMatchSummary
  , subscribeRoomAnalyticsWithReplay
  )
import Server.ReplayStore
  ( newReplayStore
  , readReplay
  )
import Server.Room
  ( RoomRuntime(..)
  , RoomUpdate(..)
  , newRoomRuntime
  )
import System.Directory
  ( createDirectory
  , getTemporaryDirectory
  , removeFile
  , removePathForcibly
  )
import System.IO (hClose, openBinaryTempFile)
import Test.Hspec

withTempReplayDir :: (FilePath -> IO a) -> IO a
withTempReplayDir action =
  bracket create removePathForcibly action
  where
    create = do
      base <- getTemporaryDirectory
      (path, handle) <- openBinaryTempFile base "x02-replay-dir"
      hClose handle
      removeFile path
      createDirectory path
      pure path

main :: IO ()
main = hspec $ do
  describe "X02 - Game Server analytics client" $ do
    it "tao MatchSummary khi RoomUpdate co GameFinished" $ do
      room <- newRoomRuntime "ROOM-X02"
      let player = Player "p1" "Player 1" Nothing False Alive defaultAppearance
          state = emptyLobby {gameDay = 4, gamePlayers = [player], gameHost = "p1"}
          update = RoomUpdate
            { updateVersion = 12
            , updateState = state
            , updateEvents = [GameFinished Draw]
            , updateChatRecord = Nothing
            }
      case matchSummaryForUpdate room update of
        Nothing -> expectationFailure "Phai tao MatchSummary"
        Just actual -> do
          matchRoomId actual `shouldBe` "ROOM-X02"
          matchResult actual `shouldBe` Draw
          matchDayCount actual `shouldBe` 4
          matchPlayerCount actual `shouldBe` 1
          matchId actual `shouldBe`
            (roomId room <> "-" <> roomInstanceId room)

    it "khong gui analytics cho update chua ket thuc" $ do
      room <- newRoomRuntime "ROOM-X02"
      let update = RoomUpdate 1 emptyLobby [] Nothing
      matchSummaryForUpdate room update `shouldBe` Nothing

    it "Worker vang mat khong chan Game Server enqueue summary" $ do
      publisher <- newAnalyticsPublisher "127.0.0.1" "1"
      let summary = MatchSummary "m1" "R1" Draw 1 9
      publishMatchSummary publisher summary `shouldReturn` True

    it "hang doi day khi Worker tat lau tu choi ngay lap tuc ma khong treo GameLoop" $ do
      publisher <- newAnalyticsPublisher "127.0.0.1" "1"
      let mkSummary :: Int -> MatchSummary
          mkSummary idx = MatchSummary ("m-" ++ show idx) "R1" Draw 1 9
      accepted <- mapM (publishMatchSummary publisher . mkSummary) [1 :: Int .. 256]
      accepted `shouldBe` replicate 256 True
      overflow <- publishMatchSummary publisher (mkSummary 257)
      overflow `shouldBe` False

    it "subscribeRoomAnalyticsWithReplay tich hop xuyen suot tu RoomUpdate toi ReplayStore va Queue" $
      withTempReplayDir $ \dir -> do
        room <- newRoomRuntime "ROOM-INT"
        publisher <- newAnalyticsPublisher "127.0.0.1" "1"
        let store = newReplayStore dir
            player = Player "p1" "Player 1" Nothing False Alive defaultAppearance
            state = emptyLobby {gameDay = 3, gamePlayers = [player], gameHost = "p1"}
            update = RoomUpdate
              { updateVersion = 5
              , updateState = state
              , updateEvents = [GameFinished (Winner Village)]
              , updateChatRecord = Nothing
              }
            expectedId = roomId room <> "-" <> roomInstanceId room
        forwarder <- subscribeRoomAnalyticsWithReplay (Just store) publisher room
        bracket (forkIO forwarder) killThread $ \_ -> do
          atomically (writeTChan (roomUpdates room) update)
          threadDelay 50000
          stored <- readReplay store expectedId
          stored `shouldBe` Right MatchSummary
            { matchId = expectedId
            , matchRoomId = "ROOM-INT"
            , matchResult = Winner Village
            , matchDayCount = 3
            , matchPlayerCount = 1
            }
