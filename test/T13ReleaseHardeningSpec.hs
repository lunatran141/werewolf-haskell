{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import qualified Data.ByteString.Lazy.Char8 as BL8
import Data.List (isInfixOf)
import Test.Hspec

import Domain.Types
  ( ChatChannel(PublicDay)
  , GameError(ChatTooLong, InvalidPlayerName)
  , GameState(..)
  , LifeStatus(Alive)
  , Phase(Day)
  , Player(..)
  , Role(Villager)
  , defaultAppearance
  , emptyLobby
  )
import Domain.Validation
  ( validateChatInChannel
  , validatePlayerName
  )
import Protocol.Json
  ( clientMessageWithinLimit
  , decodeClientMessage
  , maxClientMessageBytes
  )
import Server.SafeLog (LogLevel(Info), encodeSafeLogLine)

main :: IO ()
main = hspec $ do
  describe "T13 - input limits" $ do
    it "accepts a 30-character player name and rejects 31 characters" $ do
      validatePlayerName (replicate 30 'a') `shouldBe` Right (replicate 30 'a')
      validatePlayerName (replicate 31 'a') `shouldBe` Left InvalidPlayerName

    it "accepts 300 chat characters and rejects 301 on the server" $ do
      validateChatInChannel dayState "p1" PublicDay (replicate 300 'a')
        `shouldBe` Right ()
      validateChatInChannel dayState "p1" PublicDay (replicate 301 'a')
        `shouldBe` Left ChatTooLong

    it "rejects an oversized client frame before JSON decoding" $ do
      let boundary = BL8.replicate (fromIntegral maxClientMessageBytes) 'x'
          oversized = BL8.snoc boundary 'x'
      clientMessageWithinLimit boundary `shouldBe` True
      clientMessageWithinLimit oversized `shouldBe` False
      decodeClientMessage oversized `shouldSatisfy` isLeft

  describe "T13 - structured safe logging" $ do
    it "emits JSON metadata and redacts private gameplay fields" $ do
      let encoded = encodeSafeLogLine Info "game-server" "privacy_check"
            [ ("roomId", "ROOM-1")
            , ("role", "Werewolf")
            , ("chatMessage", "attack p8")
            , ("sessionToken", "secret-token")
            ]
          rendered = BL8.unpack encoded
      encoded `shouldSatisfy` BL8.isPrefixOf "{"
      rendered `shouldSatisfy` isInfixOf "\"event\":\"privacy_check\""
      rendered `shouldSatisfy` isInfixOf "ROOM-1"
      rendered `shouldSatisfy` isInfixOf "[REDACTED]"
      rendered `shouldSatisfy` (not . isInfixOf "Werewolf")
      rendered `shouldSatisfy` (not . isInfixOf "attack p8")
      rendered `shouldSatisfy` (not . isInfixOf "secret-token")

isLeft :: Either a b -> Bool
isLeft value =
  case value of
    Left _ -> True
    Right _ -> False

dayState :: GameState
dayState = emptyLobby
  { gamePhase = Day
  , gamePlayers =
      [ Player
          { playerId = "p1"
          , playerName = "Player One"
          , playerRole = Just Villager
          , playerReady = True
          , playerLifeStatus = Alive
          , playerAppearance = defaultAppearance
          }
      ]
  }
