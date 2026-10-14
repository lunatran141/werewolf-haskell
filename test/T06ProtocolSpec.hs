{-# LANGUAGE OverloadedStrings #-}

-- Kiểm thử T06 ở lớp Protocol và routing private/public của Vote event.
module Main (main) where

import Data.Aeson (eitherDecode, encode)
import Domain.Types
import Protocol.Json (decodeClientMessage, encodeServerMessage)
import Protocol.Types
import Server.Broadcast (nightMessagesFor, votingSnapshot)
import Test.Hspec

main :: IO ()
main = hspec $ do
  describe "T06 - Vote JSON" $ do
    it "Decode Vote chi nhan targetId tu Browser" $
      decodeClientMessage
        "{\"type\":\"Vote\",\"requestId\":\"r1\",\"roomId\":\"ROOM-01\",\"targetId\":\"p7\"}"
        `shouldBe`
          Right (ClientVote "r1" "ROOM-01" "p7")

    it "Vote JSON round-trip giu nguyen request/room/target" $ do
      let command = ClientVote "r2" "ROOM-01" "p8"
      decodeClientMessage (encode command) `shouldBe` Right command

    it "Vote thieu targetId bi tu choi" $
      decodeClientMessage
        "{\"type\":\"Vote\",\"requestId\":\"r3\",\"roomId\":\"ROOM-01\"}"
        `shouldSatisfy` isLeft

    -- null là chủ động bỏ qua; thiếu trường là thông điệp chưa hợp lệ.
    it "HunterChoice round-trip ca ban va bo qua" $ do
      let choices = [ClientHunterChoice "h1" "R" (Just "p2"), ClientHunterChoice "h2" "R" Nothing]
      map (decodeClientMessage . encode) choices `shouldBe` map Right choices

    it "HunterChoice thieu targetId bi tu choi" $
      decodeClientMessage "{\"type\":\"HunterChoice\",\"requestId\":\"h\",\"roomId\":\"R\"}" `shouldSatisfy` isLeft

    it "Snapshot, tally va phan hoi request round-trip" $ do
      let messages =
            [ MsgActionAccepted "v1" "R"
            , MsgVotingResolved "R" [("p2", 1)] (Just "p2")
            , MsgVotingResolved "R" [] Nothing
            , MsgVotingSnapshot "R" Voting 1 [VotingPlayerView "p1" "Một" True] True False False Nothing
            ]
      map (eitherDecode . encodeServerMessage) messages `shouldBe` map Right messages

  describe "T06 - Vote event routing" $ do
    -- Snapshot được tạo riêng cho từng recipient, không chứa Role trong kiểu dữ liệu.
    it "Snapshot khong lo phieu hay quyen Hunter cua nguoi khac" $ do
      let state = emptyLobby
            { gamePhase = Voting, gameDay = 1
            , gamePlayers = [Player "p1" "Một" (Just Hunter) True Dead, Player "p2" "Hai" (Just Werewolf) True Alive]
            , gamePendingHunter = Just "p1", gamePendingReveals = ["p1"]
            , gameVotes = [("p1", "p2")], gameVotingResolved = True
            }
          players = [VotingPlayerView "p1" "Một" True, VotingPlayerView "p2" "Hai" True]
      votingSnapshot "R" "p2" state `shouldBe` MsgVotingSnapshot "R" Voting 1 players False False True Nothing
      votingSnapshot "R" "p1" state `shouldBe` MsgVotingSnapshot "R" Voting 1 players True True True Nothing

    it "VoteUpdated chi gui receipt cho voter va khong leak target" $ do
      let event = VoteUpdated "p1" "p7"
      nightMessagesFor "ROOM-01" "p1" [event]
        `shouldBe` [MsgVoteUpdated "ROOM-01"]
      nightMessagesFor "ROOM-01" "p2" [event]
        `shouldBe` []

    it "PlayerEliminated la public" $ do
      let event = PlayerEliminated "p7"
          expected = [MsgPlayerEliminated "ROOM-01" "p7"]
      nightMessagesFor "ROOM-01" "p1" [event] `shouldBe` expected
      nightMessagesFor "ROOM-01" "p8" [event] `shouldBe` expected

    it "Hunter prompt private va Hunter result public round-trip JSON" $ do
      let messages =
            [ MsgHunterShotPending "ROOM-01"
            , MsgHunterShotResolved "ROOM-01" (Just "p1")
            , MsgHunterShotResolved "ROOM-01" Nothing
            ]
      map (eitherDecode . encodeServerMessage) messages
        `shouldBe` map Right messages

    it "Vote va Hunter event giu dung visibility" $ do
      eventVisibility (VoteUpdated "p1" "p7") `shouldBe` Private "p1"
      eventVisibility (HunterShotPending "p6") `shouldBe` Private "p6"
      eventVisibility (PlayerEliminated "p7") `shouldBe` Public

isLeft :: Either errorType value -> Bool
isLeft result =
  case result of
    Left _ -> True
    Right _ -> False
