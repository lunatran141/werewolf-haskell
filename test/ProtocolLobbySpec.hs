
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Aeson
  ( Value, encode, eitherDecode, object, (.=) )
import Data.Either (isLeft)

import Domain.Types
  ( Appearance(..)
  , defaultAppearance
  , RoleAbilityInfo(..)
  , roleAbilityInfo
  , NightChoice(..)
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

-- Appearance tuy chinh hop le theo preset T07.
customAppearance :: Appearance
customAppearance =
  Appearance
    { appearanceHair = "ponytail"
    , appearanceHairColor = "#8B5CF6"
    , appearanceSkin = "#C28865"
    , appearanceOutfit = "#064E3B"
    , appearanceAccessory = "flower_crown"
    }

-- PlayerView cong khai khong co Role hoac Team.
samplePlayerView :: PlayerView
samplePlayerView =
  PlayerView "p1" "Van" False True defaultAppearance

-- Tao JSON Appearance de doi chieu contract frontend.
appearanceJSON :: Appearance -> Value
appearanceJSON appearance =
  object
    [ "hair" .= appearanceHair appearance
    , "hairColor" .= appearanceHairColor appearance
    , "skin" .= appearanceSkin appearance
    , "outfit" .= appearanceOutfit appearance
    , "accessory" .= appearanceAccessory appearance
    ]

main :: IO ()
main = hspec $ do

  describe "T02 - Role Ability JSON" $ do

    -- YourRole phai chua thong tin kha nang cho chu so huu.
    it "A16 - YourRole JSON chua Ability cua Seer" $ do
      let actual = encode (MsgYourRole "ROOM-01" Seer)
          expected = object
            [ "type" .= ("YourRole" :: String)
            , "roomId" .= ("ROOM-01" :: String)
            , "role" .= ("Seer" :: String)
            , "ability" .= object
                [ "description" .= abilityDescription (roleAbilityInfo Seer)
                , "phase" .= ("Night" :: String)
                , "targetRules" .= abilityTargetRules (roleAbilityInfo Seer)
                ]
            ]

      eitherDecode actual `shouldBe` Right expected

    -- JSON moi van phai giai ma ve constructor YourRole hien tai.
    it "A17 - YourRole co Ability van round-trip" $ do
      let message = MsgYourRole "ROOM-01" Witch

      eitherDecode (encode message) `shouldBe` Right message

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
                  [samplePlayerView]))
              :: Either String Value

          expected =
            eitherDecode
              "{\"type\":\"LobbySnapshot\",\"roomId\":\"ROOM-01\",\"selfPlayerId\":\"p1\",\"hostPlayerId\":\"p1\",\"players\":[{\"playerId\":\"p1\",\"displayName\":\"Van\",\"ready\":false,\"alive\":true,\"appearance\":{\"hair\":\"messy\",\"hairColor\":\"#1E293B\",\"skin\":\"#FDE2D0\",\"outfit\":\"#1E1B4B\",\"accessory\":\"none\"}}]}"
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
      let player = samplePlayerView

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

  -- T02 - Appearance va PlayerView JSON.
  describe "T02 - Appearance va PlayerView JSON" $ do

    it "A10 - Appearance tuy chinh round-trip qua PlayerView" $ do
      let player =
            PlayerView "p2" "Binh" True True customAppearance

          encoded =
            encodeServerMessage
              (MsgPlayerJoined "ROOM-01" player)

          decoded =
            eitherDecode encoded :: Either String ServerMessage

      decoded `shouldBe`
        Right (MsgPlayerJoined "ROOM-01" player)

    it "A11 - JSON PlayerView co alive va appearance" $ do
      let player =
            PlayerView "p2" "Binh" True False customAppearance

          actual =
            eitherDecode
              (encodeServerMessage
                (MsgPlayerJoined "ROOM-01" player))
              :: Either String Value

          expected =
            Right $
              object
                [ "type" .= ("PlayerJoined" :: String)
                , "roomId" .= ("ROOM-01" :: String)
                , "player" .=
                    object
                      [ "playerId" .= ("p2" :: String)
                      , "displayName" .= ("Binh" :: String)
                      , "ready" .= True
                      , "alive" .= False
                      , "appearance" .= appearanceJSON customAppearance
                      ]
                ]

      actual `shouldBe` expected

    it "A12 - LobbySnapshot khong chua Role hoac Team" $ do
      let actual =
            eitherDecode
              (encodeServerMessage
                (MsgLobbySnapshot "ROOM-01" "p1" "p1"
                  [samplePlayerView]))
              :: Either String Value

          expected =
            Right $
              object
                [ "type" .= ("LobbySnapshot" :: String)
                , "roomId" .= ("ROOM-01" :: String)
                , "selfPlayerId" .= ("p1" :: String)
                , "hostPlayerId" .= ("p1" :: String)
                , "players" .=
                    [ object
                        [ "playerId" .= ("p1" :: String)
                        , "displayName" .= ("Van" :: String)
                        , "ready" .= False
                        , "alive" .= True
                        , "appearance" .= appearanceJSON defaultAppearance
                        ]
                    ]
                ]

      actual `shouldBe` expected

    it "A13 - Tu choi PlayerView thieu appearance" $ do
      let json =
            "{\"playerId\":\"p1\",\"displayName\":\"Van\",\"ready\":false,\"alive\":true}"
          decoded = eitherDecode json :: Either String PlayerView

      decoded `shouldSatisfy` isLeft

    it "A14 - CreateRoom co Appearance round-trip" $ do
      let command =
            ClientCreateRoomWithAppearance
              "r1" "ROOM-01" "Van" customAppearance

      decodeClientMessage (encode command)
        `shouldBe` Right command

    it "A15 - JoinGame co Appearance round-trip" $ do
      let command =
            ClientJoinWithAppearance
              "r2" "ROOM-01" "Binh" customAppearance

      decodeClientMessage (encode command)
        `shouldBe` Right command

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

  -- T05 - Night Server Events JSON - 7 bai test.
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

    it "E03b - Tien do va ket qua khoa phieu Soi round-trip" $ do
      let messages =
            [ MsgWolfTeam "ROOM-01" ["p1", "p3", "p5"]
            , MsgWolfVoteUpdated "ROOM-01" 2 3
            , MsgWolfTargetLocked "ROOM-01" (Just "p7")
            , MsgWolfTargetLocked "ROOM-01" Nothing
            ]
      map (eitherDecode . encodeServerMessage) messages
        `shouldBe` map Right messages

    it "E03c - Trang thai action rieng khi reconnect round-trip" $ do
      let messages =
            [ MsgPrivateActionState "ROOM-01" True (Just False) (Just True) Nothing
            , MsgPrivateActionState "ROOM-01" False Nothing Nothing (Just "p4")
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

    it "E08 - PlayerDied JSON round-trip" $ do
      let message = MsgPlayerDied "ROOM-01" "p7"

      eitherDecode (encodeServerMessage message)
        `shouldBe` Right message

    it "E09 - GameRolesRevealed JSON round-trip" $ do
      let message =
            MsgGameRolesRevealed
              "ROOM-01"
              [ ("p1", Werewolf)
              , ("p2", Seer)
              , ("p7", Villager)
              ]

      eitherDecode (encodeServerMessage message)
        `shouldBe` Right message


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
        `shouldBe` [MsgWitchVictimNotice "ROOM-01" (Just "p7")]
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


    it "V05 - Khong cong khai Role khi nguoi choi chet" $ do
      let events =
            [PlayerRoleRevealed "p7" Villager Village]

      nightMessagesFor "ROOM-01" "p1" events
        `shouldBe` []

      nightMessagesFor "ROOM-01" "p7" events
        `shouldBe` []


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
        `shouldBe` [MsgPhaseChanged "ROOM-01" Day]

    it "V08 - Chi gui YourRole cho dung nguoi nhan" $ do
      let events =
            [ PlayerRoleAssigned "p3" Seer
            , PhaseChanged Night
            ]
      nightMessagesFor "ROOM-01" "p3" events
        `shouldBe`
          [ MsgYourRole "ROOM-01" Seer
          , MsgPhaseChanged "ROOM-01" Night
          ]
      nightMessagesFor "ROOM-01" "p8" events
        `shouldBe` [MsgPhaseChanged "ROOM-01" Night]

  describe "T11 - Cross-Review Protocol JSON & Sync Messages" $ do

    it "MsgRoomVersion round-trip JSON va format dung schema" $ do
      let msg = MsgRoomVersion "ROOM-01" 42
          encoded = encodeServerMessage msg
          expected =
            object
              [ "type" .= ("RoomVersion" :: String)
              , "roomId" .= ("ROOM-01" :: String)
              , "version" .= (42 :: Int)
              ]
      eitherDecode encoded `shouldBe` Right expected
      (eitherDecode encoded :: Either String ServerMessage) `shouldBe` Right msg

    it "MsgDiscussionSkipState round-trip JSON va format dung schema" $ do
      let msg = MsgDiscussionSkipState "ROOM-01" 5 8 True
          encoded = encodeServerMessage msg
          expected =
            object
              [ "type" .= ("DiscussionSkipState" :: String)
              , "roomId" .= ("ROOM-01" :: String)
              , "submitted" .= (5 :: Int)
              , "total" .= (8 :: Int)
              , "hasSkipped" .= True
              ]
      eitherDecode encoded `shouldBe` Right expected
      (eitherDecode encoded :: Either String ServerMessage) `shouldBe` Right msg

    it "MsgValidTargetsSnapshot round-trip JSON va format dung schema" $ do
      let targets = [("WolfTarget", ["p2", "p3"]), ("SeerTarget", ["p1"])]
          msg = MsgValidTargetsSnapshot "ROOM-01" Night 1 3 targets
          encoded = encodeServerMessage msg
      (eitherDecode encoded :: Either String ServerMessage) `shouldBe` Right msg

    it "MsgPrivateActionState round-trip JSON va format dung schema" $ do
      let msg = MsgPrivateActionState "ROOM-01" True (Just True) (Just False) (Just "p4")
          encoded = encodeServerMessage msg
          expected =
            object
              [ "type" .= ("PrivateActionState" :: String)
              , "roomId" .= ("ROOM-01" :: String)
              , "nightActionSubmitted" .= True
              , "witchHealReady" .= True
              , "witchPoisonReady" .= False
              , "lastProtectedId" .= ("p4" :: String)
              ]
      eitherDecode encoded `shouldBe` Right expected
      (eitherDecode encoded :: Either String ServerMessage) `shouldBe` Right msg

    it "ClientSkipDiscussion round-trip JSON" $ do
      let clientMsg = ClientSkipDiscussion "req-skip-1" "ROOM-01"
          jsonVal =
            object
              [ "type" .= ("SkipDiscussion" :: String)
              , "requestId" .= ("req-skip-1" :: String)
              , "roomId" .= ("ROOM-01" :: String)
              ]
      eitherDecode (encode clientMsg) `shouldBe` Right jsonVal
      decodeClientMessage (encode clientMsg) `shouldBe` Right clientMsg
