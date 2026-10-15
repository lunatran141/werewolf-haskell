module Main (main) where

import Domain.Rules
  ( checkWin
  , countAliveTeam
  )
import Domain.Types
import Domain.Engine (applyChatCommand, applyCommand)
import Protocol.Types (ClientMessage(..), ServerMessage(..))
import Data.Aeson (decode, encode)
import Test.Hspec

-- Tạo một Player phục vụ unit test.
-- ID được tạo theo số thứ tự: p1, p2, p3...
testPlayer :: Int -> Role -> LifeStatus -> Player
testPlayer number role lifeStatus =
  Player
    { playerId = "p" ++ show number
    , playerName = "Player " ++ show number
    , playerRole = Just role
    , playerReady = True
    , playerLifeStatus = lifeStatus
    , playerAppearance = defaultAppearance
    }

-- Tạo GameState nhỏ gọn cho test.
-- Mỗi phần tử trong roster gồm (Role, LifeStatus).
testState
  :: Phase
  -> Maybe PlayerId
  -> [(Role, LifeStatus)]
  -> GameState
testState phase pendingHunter roster =
  emptyLobby
    { gamePlayers =
        zipWith
          (\number (role, lifeStatus) ->
              testPlayer number role lifeStatus
          )
          [1 ..]
          roster
    , gameHost =
        if null roster
          then ""
          else "p1"
    , gamePhase = phase
    , gameDay = 1
    , gamePendingHunter = pendingHunter
    }

main :: IO ()
main =
  hspec $ do
    describe "T07 - countAliveTeam" $ do
      it "chi dem Werewolf con song" $ do
        let state =
              testState
                Night
                Nothing
                [ (Werewolf, Alive)
                , (Werewolf, Dead)
                , (Villager, Alive)
                ]
        countAliveTeam Wolves state `shouldBe` 1

      it "dem tat ca role Village con song" $ do
        let state =
              testState
                Night
                Nothing
                [ (Villager, Alive)
                , (Seer, Alive)
                , (Guard, Alive)
                , (Witch, Dead)
                , (Werewolf, Alive)
                ]
        countAliveTeam Village state `shouldBe` 3

    describe "T07 - checkWin" $ do
      it "khong con ai song thi Draw" $ do
        let state =
              testState
                Night
                Nothing
                [ (Werewolf, Dead)
                , (Villager, Dead)
                ]
        checkWin state `shouldBe` Just Draw

      it "het Soi va con Dan thi Village thang" $ do
        let state =
              testState
                Night
                Nothing
                [ (Werewolf, Dead)
                , (Villager, Alive)
                ]
        checkWin state `shouldBe` Just (Winner Village)

      it "con Soi nhung khong con Dan thi Wolves thang" $ do
        let state =
              testState
                Night
                Nothing
                [ (Werewolf, Alive)
                , (Villager, Dead)
                ]
        checkWin state `shouldBe` Just (Winner Wolves)

      it "so Soi bang so Dan thi Wolves thang" $ do
        let state =
              testState
                Night
                Nothing
                [ (Werewolf, Alive)
                , (Villager, Alive)
                ]
        checkWin state `shouldBe` Just (Winner Wolves)

      it "so Soi it hon so Dan thi tiep tuc" $ do
        let state =
              testState
                Night
                Nothing
                [ (Werewolf, Alive)
                , (Werewolf, Alive)
                , (Villager, Alive)
                , (Seer, Alive)
                , (Guard, Alive)
                ]
        checkWin state `shouldBe` Nothing

      it "khong tinh thang khi dang Lobby" $ do
        checkWin emptyLobby `shouldBe` Nothing

      it "khong tinh thang khi Hunter con pending" $ do
        let state =
              testState
                Night
                (Just "p2")
                [ (Werewolf, Alive)
                , (Hunter, Dead)
                ]
        checkWin state `shouldBe` Nothing

    describe "T07 - Day Chat" $ do
      let dayState = testState Day Nothing
            [ (Werewolf, Alive), (Villager, Alive) ]

      it "nguoi con song duoc chat trong Day" $ do
        applyChatCommand dayState (Chat "p1" "  xin   chao  ")
          `shouldBe` Right
            (dayState, [ChatMessage "p1" "xin chao"])

      it "nguoi da chet khong duoc chat" $ do
        let deadState = testState Day Nothing
              [ (Werewolf, Dead), (Villager, Alive) ]
        applyChatCommand deadState (Chat "p1" "xin chao")
          `shouldBe` Left DeadPlayer

      it "khong duoc chat ngoai Day" $ do
        let nightState = testState Night Nothing
              [ (Werewolf, Alive), (Villager, Alive) ]
        applyChatCommand nightState (Chat "p1" "xin chao")
          `shouldBe` Left WrongPhase

      it "tu choi chat rong" $ do
        applyChatCommand dayState (Chat "p1" "   ")
          `shouldBe` Left EmptyChat

      it "server tu choi tin nhan dai hon 300 ky tu" $ do
        applyCommand dayState (Chat "p1" (replicate 301 'a'))
          `shouldBe` Left ChatTooLong

      it "dispatcher chat dung cung mot noi dung da chuan hoa" $ do
        applyCommand dayState (Chat "p1" "  xin   chao  ")
          `shouldBe` applyChatCommand dayState (Chat "p1" "  xin   chao  ")

    describe "T07 - Chat Protocol" $ do
      it "ClientChat JSON round-trip" $ do
        let message = ClientChat "r1" "ROOM-01" "xin chao"
        decode (encode message) `shouldBe` Just message

      it "MsgChatMessage JSON round-trip" $ do
        let message = MsgChatMessage "ROOM-01" "p1" "xin chao"
        decode (encode message) `shouldBe` Just message
