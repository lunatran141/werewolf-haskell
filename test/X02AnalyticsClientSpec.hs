module Main (main) where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Concurrent.STM (atomically, writeTChan)
import Control.Exception (bracket)
import qualified Data.ByteString as BS
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
import Protocol.Analytics (MatchSummary(..), encodeMatchSummaryLine)
import Server.AnalyticsClient
  ( matchSummaryForUpdate
  , newAnalyticsPublisher
  , newAnalyticsPublisherWithSpool
  , publishMatchSummary
  , recoverSpoolToQueue
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
  , doesFileExist
  , getTemporaryDirectory
  , removeFile
  , removePathForcibly
  )
import System.FilePath ((</>))
import System.IO (BufferMode(LineBuffering), hClose, hSetBuffering, hSetEncoding, openBinaryTempFile, stderr, stdout, utf8)
import Test.Hspec

withTempDir :: String -> (FilePath -> IO a) -> IO a
withTempDir prefix action =
  bracket create removePathForcibly action
  where
    create = do
      base <- getTemporaryDirectory
      (path, handle) <- openBinaryTempFile base prefix
      hClose handle
      removeFile path
      createDirectory path
      pure path

main :: IO ()
main = do
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  hSetBuffering stdout LineBuffering
  hspec $ do
    describe "X02 - Game Server analytics client & Persistent Spool" $ do
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

      it "Spooling: ghi summary xuong file disk ngay ca khi TBQueue day" $
        withTempDir "x02-spool-overflow" $ \spoolDir -> do
          publisher <- newAnalyticsPublisherWithSpool "127.0.0.1" "1" spoolDir
          let mkSummary :: Int -> MatchSummary
              mkSummary idx = MatchSummary ("spool-" ++ show idx) "R1" Draw 1 9
          _ <- mapM (publishMatchSummary publisher . mkSummary) [1 :: Int .. 256]
          overflow <- publishMatchSummary publisher (mkSummary 257)
          overflow `shouldBe` False
          -- Dù bị overflow khỏi TBQueue, file spool vẫn tồn tại an toàn trên đĩa
          doesFileExist (spoolDir </> "spool-257.json") `shouldReturn` True

      it "Recovery: khoi dong lai server doc cac file spool chua gui vao hang doi" $
        withTempDir "x02-spool-recover" $ \spoolDir -> do
          let s1 = MatchSummary "recover-1" "R1" Draw 1 9
              s2 = MatchSummary "recover-2" "R1" Draw 2 9
          BS.writeFile (spoolDir </> "recover-1.json") (encodeMatchSummaryLine s1)
          BS.writeFile (spoolDir </> "recover-2.json") (encodeMatchSummaryLine s2)
          publisher <- newAnalyticsPublisherWithSpool "127.0.0.1" "1" spoolDir
          count <- recoverSpoolToQueue publisher
          count `shouldBe` 2

      it "subscribeRoomAnalyticsWithReplay tich hop xuyen suot tu RoomUpdate toi ReplayStore va Queue" $
        withTempDir "x02-replay-dir" $ \dir -> do
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
