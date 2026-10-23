module Main (main) where

import Domain.Types
  ( DomainEvent(..)
  , GameResult(..)
  , GameState(..)
  , LifeStatus(..)
  , Player(..)
  , defaultAppearance
  , emptyLobby
  )
import Protocol.Analytics (MatchSummary(..))
import Server.AnalyticsClient
  ( matchSummaryForUpdate
  , newAnalyticsPublisher
  , publishMatchSummary
  )
import Server.Room
  ( RoomRuntime(..)
  , RoomUpdate(..)
  , newRoomRuntime
  )
import Test.Hspec

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
