{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import Data.Aeson (Value, encode, eitherDecode)
import Data.Either (isLeft)
import Protocol.Json
import Protocol.Types
import Test.Hspec (describe, hspec, it, shouldBe, shouldSatisfy)

main :: IO ()
main = hspec $ describe "Lobby JSON" $ do
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