{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Data.Aeson (eitherDecode)
import Domain.Engine (applyCommand)
import Domain.Types
import Protocol.Types (ClientMessage(..))
import Test.Hspec

lobbyPlayer :: String -> Player
lobbyPlayer pid =
  Player pid pid Nothing False Alive defaultAppearance

roles8 :: [Role]
roles8 =
  [ Werewolf, Werewolf, Seer, Guard
  , Witch, Hunter, Villager, Villager
  ]

runningGame :: GameState
runningGame =
  emptyLobby
    { gamePlayers =
        zipWith
          (\number role ->
            Player ("p" ++ show number) ("Player " ++ show number)
              (Just role) True Alive defaultAppearance)
          [1 :: Int ..]
          roles8
    , gameHost = "p1"
    , gamePhase = Day
    , gameDay = 1
    , gameConfiguredRoles = roles8
    }

main :: IO ()
main = hspec $ do
  describe "Host controls" $ do
    it "Host co the kick thanh vien khac trong Lobby" $ do
      let lobby = emptyLobby
            { gamePlayers = map lobbyPlayer ["p1", "p2", "p3"]
            , gameHost = "p1"
            }
          result = applyCommand lobby (KickPlayer "p1" "p2")
      fmap (map playerId . gamePlayers . fst) result
        `shouldBe` Right ["p1", "p3"]
      fmap snd result `shouldBe` Right [PlayerLeft "p2"]

    it "thanh vien thuong khong the kick nguoi khac" $ do
      let lobby = emptyLobby
            { gamePlayers = map lobbyPlayer ["p1", "p2", "p3"]
            , gameHost = "p1"
            }
      applyCommand lobby (KickPlayer "p2" "p3")
        `shouldBe` Left NotAuthorized

    it "khong kick thanh vien khi van da bat dau" $ do
      applyCommand runningGame (KickPlayer "p1" "p2")
        `shouldBe` Left WrongPhase

    it "Host ket thuc van thanh GameOver va cong khai vai" $ do
      let result = applyCommand runningGame (EndGame "p1")
      fmap (gamePhase . fst) result `shouldBe` Right GameOver
      fmap (gameResult . fst) result `shouldBe` Right (Just Draw)
      fmap snd result `shouldSatisfy` either (const False) (elem (GameFinished Draw))

    it "thanh vien thuong khong the ket thuc van" $ do
      applyCommand runningGame (EndGame "p2")
        `shouldBe` Left NotAuthorized

  describe "Host control protocol" $ do
    it "doc KickPlayer va chi nhan targetId" $ do
      eitherDecode
        "{\"type\":\"KickPlayer\",\"requestId\":\"kick-1\",\"roomId\":\"R1\",\"targetId\":\"p2\"}"
        `shouldBe` Right (ClientKickPlayer "kick-1" "R1" "p2")

    it "doc EndGame khong nhan ket qua tu Browser" $ do
      eitherDecode
        "{\"type\":\"EndGame\",\"requestId\":\"end-1\",\"roomId\":\"R1\"}"
        `shouldBe` Right (ClientEndGame "end-1" "R1")
