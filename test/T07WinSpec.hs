module Main (main) where

import Domain.Rules
  ( checkWin
  , countAliveTeam
  )
import Domain.Types
import Domain.Engine (applyChatCommand, applyCommand)
import Domain.Validation (validateChatInChannel)
import Control.Concurrent.STM
  ( atomically
  , newEmptyTMVarIO
  , readTVarIO
  , takeTMVar
  , writeTBQueue
  , writeTVar
  )
import Protocol.Types (ClientMessage(..), ServerMessage(..))
import Server.Broadcast
  ( chatHistorySnapshot
  , chatMessageForState
  , nightMessagesForState
  )
import Server.GameLoop (processNextLobbyCommand)
import Server.Room
  ( QueuedCommand(..)
  , RoomRuntime(..)
  , newRoomRuntime
  )
import Data.Aeson (decode, encode)
import Data.List (isInfixOf)
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
    describe "T07 - bo nho lich su chat cua phong" $ do
      it "phong moi co lich su rong va sequence bat dau tu 1" $ do
        room <- newRoomRuntime "ROOM-CHAT"
        readTVarIO (roomChatHistory room) `shouldReturn` []
        readTVarIO (roomNextChatSequence room) `shouldReturn` 1
        readTVarIO (roomReconnectTokens room) `shouldReturn` []

      it "luu tin hop le voi noi dung chuan hoa va khong luu trung request" $ do
        room <- newRoomRuntime "ROOM-CHAT"
        let dayState =
              testState Day Nothing
                [ (Werewolf, Alive)
                , (Villager, Alive)
                ]

        atomically $ writeTVar (roomState room) dayState

        firstReply <- newEmptyTMVarIO
        atomically $
          writeTBQueue (roomCommands room)
            QueuedCommand
              { queuedRequestId = "chat-1"
              , queuedActorId = "p1"
              , queuedCommand =
                  ChatInChannel "p1" PublicDay "  xin   chào  "
              , queuedReply = firstReply
              }

        processNextLobbyCommand room
        atomically (takeTMVar firstReply) `shouldReturn` Right dayState

        readTVarIO (roomChatHistory room)
          `shouldReturn`
            [ ChatRecord
                { chatRoomId = "ROOM-CHAT"
                , chatDay = 1
                , chatChannel = PublicDay
                , chatMessageId = "ROOM-CHAT-chat-1"
                , chatSequence = 1
                , chatSenderId = "p1"
                , chatText = "xin chào"
                }
            ]
        readTVarIO (roomNextChatSequence room) `shouldReturn` 2

        duplicateReply <- newEmptyTMVarIO
        atomically $
          writeTBQueue (roomCommands room)
            QueuedCommand
              { queuedRequestId = "chat-1"
              , queuedActorId = "p1"
              , queuedCommand = ChatInChannel "p1" PublicDay "tin bị lặp"
              , queuedReply = duplicateReply
              }

        processNextLobbyCommand room
        atomically (takeTMVar duplicateReply)
          `shouldReturn` Left DuplicateRequest
        length <$> readTVarIO (roomChatHistory room) `shouldReturn` 1
        readTVarIO (roomNextChatSequence room) `shouldReturn` 2

      it "khong luu chat bi validation tu choi" $ do
        room <- newRoomRuntime "ROOM-CHAT"
        let nightState =
              testState Night Nothing
                [ (Werewolf, Alive)
                , (Villager, Alive)
                ]

        atomically $ writeTVar (roomState room) nightState
        reply <- newEmptyTMVarIO
        atomically $
          writeTBQueue (roomCommands room)
            QueuedCommand
              { queuedRequestId = "chat-invalid"
              , queuedActorId = "p2"
              , queuedCommand = ChatInChannel "p2" WolvesNight "xin vào chat Sói"
              , queuedReply = reply
              }

        processNextLobbyCommand room
        atomically (takeTMVar reply) `shouldReturn` Left InvalidRole
        readTVarIO (roomChatHistory room) `shouldReturn` []
        readTVarIO (roomNextChatSequence room) `shouldReturn` 1

      it "snapshot chi gui chat Soi cho Soi con song" $ do
        let state =
              testState Night Nothing
                [ (Werewolf, Alive)
                , (Villager, Alive)
                , (Werewolf, Dead)
                ]
            publicRecord =
              ChatRecord "ROOM-CHAT" 1 PublicDay "m1" 1 "p2" "chat chung"
            wolfRecord =
              ChatRecord "ROOM-CHAT" 1 WolvesNight "m2" 2 "p1" "chat Sói"
            history = [publicRecord, wolfRecord]

        chatHistorySnapshot "ROOM-CHAT" "p1" state history
          `shouldBe` MsgChatHistorySnapshot "ROOM-CHAT" history
        chatHistorySnapshot "ROOM-CHAT" "p2" state history
          `shouldBe` MsgChatHistorySnapshot "ROOM-CHAT" [publicRecord]
        chatHistorySnapshot "ROOM-CHAT" "p3" state history
          `shouldBe` MsgChatHistorySnapshot "ROOM-CHAT" [publicRecord]

        chatMessageForState "ROOM-CHAT" "p1" state wolfRecord
          `shouldBe` Just (MsgStoredChatMessage "ROOM-CHAT" wolfRecord)
        chatMessageForState "ROOM-CHAT" "p2" state wolfRecord
          `shouldBe` Nothing

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

    describe "T07 - quyen chat theo luat moi" $ do
      let nightState = testState Night Nothing
            [ (Werewolf, Alive), (Villager, Alive), (Werewolf, Dead) ]

      it "Soi con song duoc chat kenh rieng trong Night" $ do
        validateChatInChannel nightState "p1" WolvesNight "chon p2"
          `shouldBe` Right ()

      it "Dan khong duoc chat kenh Soi" $ do
        validateChatInChannel nightState "p2" WolvesNight "xin chao"
          `shouldBe` Left InvalidRole

      it "Soi da chet khong duoc chat kenh Soi" $ do
        validateChatInChannel nightState "p3" WolvesNight "chon p2"
          `shouldBe` Left DeadPlayer

      it "kenh Soi chi mo trong Night" $ do
        let dayState = nightState {gamePhase = Day}
        validateChatInChannel dayState "p1" WolvesNight "chon p2"
          `shouldBe` Left WrongPhase

      it "chat chung chi mo trong Day" $ do
        validateChatInChannel nightState "p1" PublicDay "xin chao"
          `shouldBe` Left WrongPhase

      it "gioi han 300 ky tu ap dung ca kenh Soi" $ do
        validateChatInChannel nightState "p1" WolvesNight (replicate 301 'a')
          `shouldBe` Left ChatTooLong

      it "Engine phat chat Soi voi dung kenh va khong doi state" $ do
        applyCommand nightState
          (ChatInChannel "p1" WolvesNight "  chọn   p2  ")
          `shouldBe` Right
            (nightState, [ChatMessageInChannel WolvesNight "p1" "chọn p2"])

      it "Server chi chuyen chat Soi cho Soi con song" $ do
        let event = ChatMessageInChannel WolvesNight "p1" "chọn p2"
            expected = [MsgChannelChatMessage "ROOM-01" 1 WolvesNight "p1" "chọn p2"]
        nightMessagesForState "ROOM-01" "p1" nightState [event]
          `shouldBe` expected
        nightMessagesForState "ROOM-01" "p2" nightState [event]
          `shouldBe` []
        nightMessagesForState "ROOM-01" "p3" nightState [event]
          `shouldBe` []

      it "Server chi gui tien do va ket qua khoa phieu cho Soi con song" $ do
        let events = [WolfVoteUpdated 1 2, WolfTargetLocked (Just "p2")]
            expected =
              [ MsgWolfVoteUpdated "ROOM-01" 1 2
              , MsgWolfTargetLocked "ROOM-01" (Just "p2")
              ]
        nightMessagesForState "ROOM-01" "p1" nightState events
          `shouldBe` expected
        nightMessagesForState "ROOM-01" "p2" nightState events
          `shouldBe` []
        nightMessagesForState "ROOM-01" "p3" nightState events
          `shouldBe` []

    describe "T07 - Chat Protocol" $ do
      it "ClientChat JSON round-trip" $ do
        let message = ClientChat "r1" "ROOM-01" "xin chao"
        decode (encode message) `shouldBe` Just message

      it "MsgChatMessage JSON round-trip" $ do
        let message = MsgChatMessage "ROOM-01" "p1" "xin chao"
        decode (encode message) `shouldBe` Just message

      it "ClientChannelChat WolvesNight JSON round-trip" $ do
        let message = ClientChannelChat "r2" "ROOM-01" WolvesNight "chọn p2"
        decode (encode message) `shouldBe` Just message

      it "MsgChannelChatMessage JSON round-trip" $ do
        let message = MsgChannelChatMessage "ROOM-01" 2 WolvesNight "p1" "chọn p2"
        decode (encode message) `shouldBe` Just message

      it "MsgChatHistorySnapshot JSON round-trip" $ do
        let records =
              [ ChatRecord "ROOM-01" 1 PublicDay "m1" 1 "p1" "xin chào"
              , ChatRecord "ROOM-01" 1 WolvesNight "m2" 2 "p2" "chọn p3"
              ]
            message = MsgChatHistorySnapshot "ROOM-01" records
        decode (encode message) `shouldBe` Just message

      it "tin chat truc tiep co ID va sequence JSON round-trip" $ do
        let record =
              ChatRecord "ROOM-01" 2 PublicDay "m7" 7 "p1" "tin mới"
            message = MsgStoredChatMessage "ROOM-01" record
        decode (encode message) `shouldBe` Just message

      it "Reconnect va SessionEstablished JSON round-trip" $ do
        let client = ClientReconnect "r3" "ROOM-01" "token-bi-mat"
            server = MsgSessionEstablished "ROOM-01" "p1" "token-bi-mat"
        decode (encode client) `shouldBe` Just client
        decode (encode server) `shouldBe` Just server

      it "SkipDiscussion va tien do xac nhan JSON round-trip" $ do
        let client = ClientSkipDiscussion "skip-1" "ROOM-01"
            server = MsgDiscussionSkipState "ROOM-01" 3 7 True
        decode (encode client) `shouldBe` Just client
        decode (encode server) `shouldBe` Just server

    describe "T07 - bo qua thoi gian thao luan" $ do
      let roster =
            [ (Werewolf, Alive), (Werewolf, Alive), (Seer, Alive)
            , (Guard, Alive), (Witch, Alive), (Hunter, Alive)
            , (Villager, Alive), (Villager, Alive)
            ]
          dayState = (testState Day Nothing roster)
            { gameConfiguredRoles = map fst roster }

      it "chua du tat ca nguoi song thi van o Day" $ do
        let Right (next, events) = applyCommand dayState (SkipDiscussion "p1")
        gamePhase next `shouldBe` Day
        gameDiscussionSkips next `shouldBe` ["p1"]
        events `shouldBe` []

      it "du tat ca nguoi song thi chuyen ngay sang Voting" $ do
        let beforeLast = dayState
              { gameDiscussionSkips = ["p1", "p2", "p3", "p4", "p5", "p6", "p7"] }
            Right (next, events) = applyCommand beforeLast (SkipDiscussion "p8")
        gamePhase next `shouldBe` Voting
        gameDiscussionSkips next `shouldBe` []
        events `shouldBe` [PhaseChanged Voting]

      it "khong cho bam hai lan hoac bam khi da chet" $ do
        let already = dayState {gameDiscussionSkips = ["p1"]}
            dead = dayState
              { gamePlayers =
                  map (\p -> if playerId p == "p1"
                    then p {playerLifeStatus = Dead} else p) (gamePlayers dayState) }
        applyCommand already (SkipDiscussion "p1")
          `shouldBe` Left AlreadySkippedDiscussion
        applyCommand dead (SkipDiscussion "p1")
          `shouldBe` Left DeadPlayer

    describe "T07 - huong dan vai tro" $ do
      it "mo ta cua tat ca vai duoc gui bang tieng Viet co dau" $ do
        let roles = [Werewolf, Seer, Guard, Witch, Hunter, Villager]
        map (any (> '\x7f') . abilityDescription . roleAbilityInfo) roles
          `shouldBe` replicate (length roles) True

      it "dan lang co huong dan bo phieu ro rang" $ do
        let info = roleAbilityInfo Villager
        abilityDescription info `shouldSatisfy` isInfixOf "thảo luận ban ngày"
        abilityTargetRules info `shouldSatisfy` isInfixOf "chọn một người còn sống khác bản thân"
