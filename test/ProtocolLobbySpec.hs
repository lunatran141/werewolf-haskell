
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Aeson (Value, encode, eitherDecode)
import Data.Either (isLeft)


import Domain.Types
  ( NightChoice(..)
  , Role(..)
  , Team(..)
  , Phase(..)
  , GameResult(..)
  , DomainEvent(..)
  )

import Server.Broadcast (nightMessagesFor)

import Protocol.Json
import Protocol.Types

import Test.Hspec
  ( describe, hspec, it, shouldBe, shouldSatisfy )


main :: IO ()
main = hspec $ do

  -- Lobby JSON - Giu nguyen 11 bai test cu.

  describe "Lobby JSON" $ do

    it "doc JoinGame" $
      decodeClientMessage
        "{\"type\":\"JoinGame\",\"requestId\":\"r1\",\"roomId\":\"ROOM-01\",\"playerName\":\"Van\"}"
        `shouldBe` Right (ClientJoin "r1" "ROOM-01" "Van")

    it "doc SetReady" $
      decodeClientMessage
        "{\"type\":\"SetReady\",\"requestId\":\"r2\",\"roomId\":\"ROOM-01\",\"ready\":true}"
        `shouldBe` Right (ClientSetReady "r2" "ROOM-01" True)

    it "doc LeaveGame" $
      decodeClientMessage
        "{\"type\":\"LeaveGame\",\"requestId\":\"r3\",\"roomId\":\"ROOM-01\"}"
        `shouldBe` Right (ClientLeave "r3" "ROOM-01")

    it "tu choi khi thieu requestId" $
      decodeClientMessage
        "{\"type\":\"JoinGame\",\"roomId\":\"ROOM-01\",\"playerName\":\"Van\"}"
        `shouldSatisfy` isLeft

    it "tu choi ready sai kieu" $
      decodeClientMessage
        "{\"type\":\"SetReady\",\"requestId\":\"r2\",\"roomId\":\"ROOM-01\",\"ready\":\"yes\"}"
        `shouldSatisfy` isLeft

    it "tu choi command khong ho tro" $
      decodeClientMessage
        "{\"type\":\"DeleteRoom\",\"requestId\":\"r4\",\"roomId\":\"ROOM-01\"}"
        `shouldSatisfy` isLeft

    it "ghi LobbySnapshot dung cau truc" $ do
      let actual =
            eitherDecode
              (encodeServerMessage
                (MsgLobbySnapshot "ROOM-01" "p1" "p1"
                  [PlayerView "p1" "Van" False]))
              :: Either String Value

          expected =
            eitherDecode
              "{\"type\":\"LobbySnapshot\",\"roomId\":\"ROOM-01\",\"selfPlayerId\":\"p1\",\"hostPlayerId\":\"p1\",\"players\":[{\"playerId\":\"p1\",\"displayName\":\"Van\",\"ready\":false}]}"
              :: Either String Value

      actual `shouldBe` expected

    it "ghi CommandRejected kem requestId" $ do
      let actual =
            eitherDecode
              (encodeServerMessage
                (MsgRejected (Just "r2") "PLAYER_NOT_FOUND" "Khong tim thay"))
              :: Either String Value

          expected =
            eitherDecode
              "{\"type\":\"CommandRejected\",\"requestId\":\"r2\",\"code\":\"PLAYER_NOT_FOUND\",\"message\":\"Khong tim thay\"}"
              :: Either String Value

      actual `shouldBe` expected

    it "doc CreateRoom" $
      decodeClientMessage
        "{\"type\":\"CreateRoom\",\"requestId\":\"r0\",\"roomId\":\"ROOM-02\",\"playerName\":\"Khanh\"}"
        `shouldBe` Right (ClientCreateRoom "r0" "ROOM-02" "Khanh")

    it "round-trip tat ca ClientMessage" $ do
      let commands =
            [ ClientCreateRoom "r0" "ROOM-01" "Van"
            , ClientJoin "r1" "ROOM-01" "Binh"
            , ClientLeave "r2" "ROOM-01"
            , ClientSetReady "r3" "ROOM-01" True
            , ClientSetReady "r4" "ROOM-01" False
            ]

      map (decodeClientMessage . encode) commands
        `shouldBe` map Right commands

    it "round-trip tat ca ServerMessage" $ do
      let player = PlayerView "p1" "Van" False
          messages =
            [ MsgLobbySnapshot "ROOM-01" "p1" "p1" [player]
            , MsgPlayerJoined "ROOM-01" player
            , MsgPlayerLeft "ROOM-01" "p1"
            , MsgHostChanged "ROOM-01" "p2"
            , MsgReadyChanged "ROOM-01" "p1" True
            , MsgRejected (Just "r5") "ROOM_FULL" "Phong da day"
            , MsgRejected Nothing "INVALID_JSON" "JSON khong hop le"
            ]

          decodeBack message =
            eitherDecode (encodeServerMessage message)
              :: Either String ServerMessage

      map decodeBack messages `shouldBe` map Right messages

  -- T05 - Protocol NightAction JSON - 10 bai test.

  describe "T05 - Protocol NightAction JSON" $ do

    it "N01 - Doc JSON WolfTarget" $
      decodeClientMessage
        "{\"type\":\"NightAction\",\"requestId\":\"r1\",\"roomId\":\"ROOM-01\",\"choice\":{\"action\":\"WolfTarget\",\"targetId\":\"7\"}}"
        `shouldBe`
          Right (ClientNightAction "r1" "ROOM-01" (WolfTarget "7"))

    it "N02 - Doc JSON SeerTarget" $
      decodeClientMessage
        "{\"type\":\"NightAction\",\"requestId\":\"r2\",\"roomId\":\"ROOM-01\",\"choice\":{\"action\":\"SeerTarget\",\"targetId\":\"1\"}}"
        `shouldBe`
          Right (ClientNightAction "r2" "ROOM-01" (SeerTarget "1"))

    it "N03 - Doc JSON GuardTarget" $
      decodeClientMessage
        "{\"type\":\"NightAction\",\"requestId\":\"r3\",\"roomId\":\"ROOM-01\",\"choice\":{\"action\":\"GuardTarget\",\"targetId\":\"4\"}}"
        `shouldBe`
          Right (ClientNightAction "r3" "ROOM-01" (GuardTarget "4"))

    it "N04 - Doc JSON WitchHeal" $
      decodeClientMessage
        "{\"type\":\"NightAction\",\"requestId\":\"r4\",\"roomId\":\"ROOM-01\",\"choice\":{\"action\":\"WitchHeal\"}}"
        `shouldBe`
          Right (ClientNightAction "r4" "ROOM-01" WitchHeal)

    it "N05 - Doc JSON WitchPoison" $
      decodeClientMessage
        "{\"type\":\"NightAction\",\"requestId\":\"r5\",\"roomId\":\"ROOM-01\",\"choice\":{\"action\":\"WitchPoison\",\"targetId\":\"8\"}}"
        `shouldBe`
          Right (ClientNightAction "r5" "ROOM-01" (WitchPoison "8"))

    it "N06 - Doc JSON WitchPass" $
      decodeClientMessage
        "{\"type\":\"NightAction\",\"requestId\":\"r6\",\"roomId\":\"ROOM-01\",\"choice\":{\"action\":\"WitchPass\"}}"
        `shouldBe`
          Right (ClientNightAction "r6" "ROOM-01" WitchPass)

    it "N07 - Round-trip NightAction" $ do
      let commands =
            [ ClientNightAction "r7" "ROOM-01" (WolfTarget "7")
            , ClientNightAction "r8" "ROOM-01" (SeerTarget "1")
            , ClientNightAction "r9" "ROOM-01" (GuardTarget "4")
            , ClientNightAction "r10" "ROOM-01" WitchHeal
            , ClientNightAction "r11" "ROOM-01" (WitchPoison "8")
            , ClientNightAction "r12" "ROOM-01" WitchPass
            ]

      map (decodeClientMessage . encode) commands
        `shouldBe` map Right commands

    it "N08 - Tu choi NightAction khong hop le" $
      decodeClientMessage
        "{\"type\":\"NightAction\",\"requestId\":\"r13\",\"roomId\":\"ROOM-01\",\"choice\":{\"action\":\"InvalidAction\"}}"
        `shouldSatisfy` isLeft

    it "N09 - Tu choi WolfTarget thieu targetId" $
      decodeClientMessage
        "{\"type\":\"NightAction\",\"requestId\":\"r14\",\"roomId\":\"ROOM-01\",\"choice\":{\"action\":\"WolfTarget\"}}"
        `shouldSatisfy` isLeft

    it "N10 - Tu choi NightAction thieu requestId" $
      decodeClientMessage
        "{\"type\":\"NightAction\",\"roomId\":\"ROOM-01\",\"choice\":{\"action\":\"WitchPass\"}}"
        `shouldSatisfy` isLeft

  -- T05 - Night Server Events JSON - 7 bai test moi.

  describe "T05 - Night Server Events JSON" $ do

    it "E01 - NightActionAccepted round-trip" $ do
      let message = MsgNightActionAccepted "ROOM-01"

      eitherDecode (encodeServerMessage message)
        `shouldBe` Right message

    it "E02 - SeerResult round-trip" $ do
      let message = MsgSeerResult "ROOM-01" Wolves

      eitherDecode (encodeServerMessage message)
        `shouldBe` Right message

    it "E03 - WitchVictimNotice round-trip" $ do
      let messages =
            [ MsgWitchVictimNotice "ROOM-01" (Just "p7")
            , MsgWitchVictimNotice "ROOM-01" Nothing
            ]

      map (eitherDecode . encodeServerMessage) messages
        `shouldBe` map Right messages

    it "E04 - NightResolved round-trip" $ do
      let message = MsgNightResolved "ROOM-01" ["p7", "p8"]

      eitherDecode (encodeServerMessage message)
        `shouldBe` Right message

    it "E05 - PlayerRoleRevealed round-trip" $ do
      let message =
            MsgPlayerRoleRevealed "ROOM-01" "p7" Villager Village

      eitherDecode (encodeServerMessage message)
        `shouldBe` Right message

    it "E06 - PhaseChanged round-trip" $ do
      let messages =
            [ MsgPhaseChanged "ROOM-01" Night
            , MsgPhaseChanged "ROOM-01" Day
            , MsgPhaseChanged "ROOM-01" Voting
            , MsgPhaseChanged "ROOM-01" GameOver
            ]

      map (eitherDecode . encodeServerMessage) messages
        `shouldBe` map Right messages

    it "E07 - GameFinished round-trip" $ do
      let messages =
            [ MsgGameFinished "ROOM-01" (Winner Village)
            , MsgGameFinished "ROOM-01" (Winner Wolves)
            , MsgGameFinished "ROOM-01" Draw
            ]

      map (eitherDecode . encodeServerMessage) messages
        `shouldBe` map Right messages



  -- T05 - Kiem thu phan quyen Night Events.

  describe "T05 - Night Event Routing" $ do

    it "V01 - Seer chi nhan ket qua soi cua minh" $ do
      let events = [SeerResult "p3" Wolves]

      nightMessagesFor "ROOM-01" "p3" events
        `shouldBe` [MsgSeerResult "ROOM-01" Wolves]

      nightMessagesFor "ROOM-01" "p5" events
        `shouldBe` []

    it "V02 - Witch chi nhan thong bao nan nhan cua minh" $ do
      let events = [WitchVictimNotice "p5" (Just "p7")]

      nightMessagesFor "ROOM-01" "p5" events
        `shouldBe`
          [MsgWitchVictimNotice "ROOM-01" (Just "p7")]

      nightMessagesFor "ROOM-01" "p3" events
        `shouldBe` []

    it "V03 - NightActionAccepted chi gui cho actor" $ do
      let events = [NightActionAccepted "p2"]

      nightMessagesFor "ROOM-01" "p2" events
        `shouldBe` [MsgNightActionAccepted "ROOM-01"]

      nightMessagesFor "ROOM-01" "p4" events
        `shouldBe` []

    it "V04 - PhaseChanged duoc gui cho moi nguoi" $ do
      let events = [PhaseChanged Day]
          expected = [MsgPhaseChanged "ROOM-01" Day]

      nightMessagesFor "ROOM-01" "p1" events
        `shouldBe` expected

      nightMessagesFor "ROOM-01" "p8" events
        `shouldBe` expected

    it "V05 - PlayerRoleRevealed la public" $ do
      let events =
            [PlayerRoleRevealed "p7" Villager Village]

          expected =
            [MsgPlayerRoleRevealed "ROOM-01" "p7" Villager Village]

      nightMessagesFor "ROOM-01" "p1" events
        `shouldBe` expected

      nightMessagesFor "ROOM-01" "p8" events
        `shouldBe` expected

    it "V06 - GameFinished la public" $ do
      let events = [GameFinished (Winner Village)]
          expected = [MsgGameFinished "ROOM-01" (Winner Village)]

      nightMessagesFor "ROOM-01" "p1" events
        `shouldBe` expected

      nightMessagesFor "ROOM-01" "p8" events
        `shouldBe` expected

    it "V07 - Khong ro ri event private khi tron voi public" $ do
      let events =
            [ SeerResult "p3" Wolves
            , WitchVictimNotice "p5" (Just "p7")
            , PhaseChanged Day
            ]

      nightMessagesFor "ROOM-01" "p3" events
        `shouldBe`
          [ MsgSeerResult "ROOM-01" Wolves
          , MsgPhaseChanged "ROOM-01" Day
          ]

      nightMessagesFor "ROOM-01" "p5" events
        `shouldBe`
          [ MsgWitchVictimNotice "ROOM-01" (Just "p7")
          , MsgPhaseChanged "ROOM-01" Day
          ]

      nightMessagesFor "ROOM-01" "p8" events
        `shouldBe`
          [MsgPhaseChanged "ROOM-01" Day]

    it "V08 - Khong chuyen event private chua co JSON contract" $ do
      let events =
            [ PlayerRoleAssigned "p3" Seer
            , PhaseChanged Night
            ]

      nightMessagesFor "ROOM-01" "p3" events
        `shouldBe`
          [MsgPhaseChanged "ROOM-01" Night]

      nightMessagesFor "ROOM-01" "p8" events
        `shouldBe`
          [MsgPhaseChanged "ROOM-01" Night]
