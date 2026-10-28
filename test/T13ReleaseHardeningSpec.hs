{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent.STM (atomically, newEmptyTMVarIO)
import qualified Data.ByteString.Lazy.Char8 as BL8
import Data.Char (toLower)
import Data.List (isInfixOf)
import Test.Hspec
import Test.QuickCheck

import Domain.Types
  ( ChatChannel(PublicDay)
  , Command(Chat)
  , GameError(ChatTooLong, InvalidPlayerName)
  , GameState(..)
  , LifeStatus(Alive)
  , Phase(Day)
  , Player(..)
  , Role(..)
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
import Protocol.Types (ServerMessage(MsgRoomVersion))
import Server.Connection
  ( enqueueOutbound
  , newOutboundQueueWithCapacity
  , readOutboundRecoverable
  , tryEnqueueRoomCommand
  )
import Server.Room
  ( QueuedCommand(..)
  , newRoomRuntime
  )
import Server.SafeLog
  ( CorrelationLog(..)
  , LogLevel(Info, Warning)
  , encodeCorrelationLogLine
  , encodeSafeLogLine
  )

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

  describe "T13 - structured safe logging & correlation IDs" $ do
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

    it "emits unified correlation fields (requestId, gameId, playerId, eventType, errorCode)" $ do
      let corr = CorrelationLog
            { corrRequestId = "req-42"
            , corrGameId    = "ROOM-99"
            , corrPlayerId  = "p3"
            , corrEventType = "CommandRejected"
            , corrErrorCode = Just "WrongPhase"
            }
          encoded = encodeCorrelationLogLine Warning "game-server" corr
            [ ("phase", "Night")
            , ("secretRole", "Seer")
            ]
          rendered = BL8.unpack encoded
      rendered `shouldSatisfy` isInfixOf "\"requestId\":\"req-42\""
      rendered `shouldSatisfy` isInfixOf "\"gameId\":\"ROOM-99\""
      rendered `shouldSatisfy` isInfixOf "\"playerId\":\"p3\""
      rendered `shouldSatisfy` isInfixOf "\"eventType\":\"CommandRejected\""
      rendered `shouldSatisfy` isInfixOf "\"errorCode\":\"WrongPhase\""
      rendered `shouldSatisfy` (not . isInfixOf "Seer")

    it "E15 QuickCheck Property: structured logs never leak secret roles or private chat/tokens" $
      property $ forAll genRole $ \role ->
        forAll genSafeId $ \reqId ->
          forAll genSafeId $ \roomIdVal ->
            forAll genSafeId $ \pid ->
              let corr = CorrelationLog
                    { corrRequestId = reqId
                    , corrGameId    = roomIdVal
                    , corrPlayerId  = pid
                    , corrEventType = "NightActionProcessed"
                    , corrErrorCode = Nothing
                    }
                  encoded = encodeCorrelationLogLine Info "game-server" corr
                    [ ("assignedRole", show role)
                    , ("accidentalField", show role)
                    , ("nightChat", "wolves-secret-plan")
                    , ("nightTarget", "p8")
                    , ("reconnectToken", "tok-999999")
                    ]
                  lowerRendered = map toLower (BL8.unpack encoded)
              in not ("werewolf" `isInfixOf` lowerRendered)
                 && not ("seer" `isInfixOf` lowerRendered)
                 && not ("witch" `isInfixOf` lowerRendered)
                 && not ("guard" `isInfixOf` lowerRendered)
                 && not ("hunter" `isInfixOf` lowerRendered)
                 && not ("villager" `isInfixOf` lowerRendered)
                 && not ("wolves-secret-plan" `isInfixOf` lowerRendered)
                 && not ("tok-999999" `isInfixOf` lowerRendered)

  describe "T13 - spam & backpressure protection (E14)" $ do
    it "rejects command spam immediately when room TBQueue is full and marks slow consumer overflow" $ do
      room <- newRoomRuntime "ROOM-SPAM"
      replyVar <- newEmptyTMVarIO
      let cmd = QueuedCommand
            { queuedRequestId = "spam-req"
            , queuedActorId = "p1"
            , queuedCommand = Chat "p1" "hello"
            , queuedReply = replyVar
            }
      results <- mapM (\_ -> atomically (tryEnqueueRoomCommand room cmd)) [1 :: Int .. 134]
      take 128 results `shouldBe` replicate 128 True
      drop 128 results `shouldBe` replicate 6 False

      outbound <- newOutboundQueueWithCapacity 3
      r1 <- atomically (enqueueOutbound outbound (MsgRoomVersion "ROOM-SPAM" 1))
      r2 <- atomically (enqueueOutbound outbound (MsgRoomVersion "ROOM-SPAM" 2))
      r3 <- atomically (enqueueOutbound outbound (MsgRoomVersion "ROOM-SPAM" 3))
      r4 <- atomically (enqueueOutbound outbound (MsgRoomVersion "ROOM-SPAM" 4))
      [r1, r2, r3, r4] `shouldBe` [True, True, True, False]
      recoverable <- atomically (readOutboundRecoverable outbound)
      recoverable `shouldBe` Nothing

genRole :: Gen Role
genRole = elements [Werewolf, Seer, Witch, Guard, Hunter, Villager]

genSafeId :: Gen String
genSafeId = do
  n <- chooseInt (1, 9999)
  pure ("id-" ++ show n)

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
