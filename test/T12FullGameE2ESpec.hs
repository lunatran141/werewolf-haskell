{-# LANGUAGE OverloadedStrings #-}

-- | T12: full-game replay va 9 WebSocket client tren cung RoomRuntime.
module Main (main) where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Concurrent.MVar (modifyMVar_, newMVar, readMVar)
import Control.Concurrent.STM (readTVarIO)
import Control.Exception (bracket)
import Control.Monad (foldM, forM, forM_, void)
import Data.Aeson (eitherDecode, encode)
import qualified Data.ByteString.Lazy as BL
import Data.List (find, sort)
import qualified Network.WebSockets as WS
import System.IO
  ( BufferMode(LineBuffering)
  , hSetBuffering
  , hSetEncoding
  , stderr
  , stdout
  , utf8
  )
import System.Timeout (timeout)
import Test.Hspec

import Domain.Engine
  ( applyCommand
  , closeWolfVoting
  , completeNightTurn
  , resolveNightTurn
  )
import Domain.Types
import Domain.Validation (validateGameInvariant)
import Protocol.Types
import Server.GameLoop (runGameLoopWithPhaseTimeouts)
import Server.Room
import Server.WebSocket (webSocketApp)

port :: Int
port = 18767

roomCode :: String
roomCode = "T12-FULL-GAME"

roles9 :: [Role]
roles9 =
  [ Werewolf, Werewolf, Werewolf, Seer, Guard, Witch, Hunter
  , Villager, Villager
  ]

data ConnectedClient = ConnectedClient
  { clientPlayerId :: PlayerId
  , clientToken :: String
  , clientConnection :: WS.Connection
  , clientAppearance :: Appearance
  }

data AssignedClient = AssignedClient
  { assignedClient :: ConnectedClient
  , assignedRole :: Role
  }

data PureRun = PureRun
  { pureFinalState :: GameState
  , pureEvents :: [DomainEvent]
  } deriving (Eq, Show)

send :: WS.Connection -> ClientMessage -> IO ()
send connection = WS.sendTextData connection . encode

receiveUntil :: WS.Connection -> (ServerMessage -> Bool) -> IO ServerMessage
receiveUntil connection predicate = do
  result <- timeout 6000000 loop
  maybe (fail "T12: het thoi gian doi ServerMessage") pure result
  where
    loop = do
      bytes <- WS.receiveData connection :: IO BL.ByteString
      message <- either fail pure (eitherDecode bytes)
      if predicate message then pure message else loop

isRole :: ServerMessage -> Bool
isRole MsgYourRole {} = True
isRole _ = False

expectRejected :: WS.Connection -> String -> String -> IO ()
expectRejected connection requestId expectedCode = do
  message <- receiveUntil connection $ \current ->
    case current of
      MsgRejected (Just actualRequest) _ _ -> actualRequest == requestId
      _ -> False
  case message of
    MsgRejected _ actualCode _ -> actualCode `shouldBe` expectedCode
    _ -> expectationFailure "T12: thieu CommandRejected"

appearanceFor :: Int -> Appearance
appearanceFor number =
  defaultAppearance
    { appearanceHair = hairs !! index
    , appearanceAccessory = accessories !! index
    }
  where
    index = (number - 1) `mod` length hairs
    hairs = ["messy", "spiky", "curly", "bob", "long", "ponytail", "messy", "spiky", "curly"]
    accessories = ["none", "straw_hat", "cat_ears", "witch_hat", "sunglasses", "horns", "halo", "flower_crown", "none"]

withNineClients :: ([ConnectedClient] -> IO ()) -> IO ()
withNineClients action = connectNext 1 []
  where
    connectNext number clients
      | number > 9 = action (reverse clients)
      | otherwise =
          WS.runClient "127.0.0.1" port "/ws" $ \connection -> do
            let requestId = "join-" ++ show number
                playerName = "Nguoi " ++ show number
                appearance = appearanceFor number
                joinMessage =
                  if number == 1
                    then ClientCreateRoomWithAppearance requestId roomCode playerName appearance
                    else ClientJoinWithAppearance requestId roomCode playerName appearance
            send connection joinMessage
            established <- receiveUntil connection $ \message ->
              case message of
                MsgSessionEstablished actualRoom _ _ -> actualRoom == roomCode
                _ -> False
            (pid, token) <-
              case established of
                MsgSessionEstablished _ actualPlayer actualToken ->
                  pure (actualPlayer, actualToken)
                _ -> fail "T12: khong nhan duoc session"
            send connection (ClientSetReady ("ready-" ++ show number) roomCode True)
            readySnapshot <- receiveUntil connection $ \message ->
              case message of
                MsgLobbySnapshot _ _ _ players ->
                  any (\player -> viewPlayerId player == pid && viewReady player) players
                _ -> False
            readyPlayers <-
              case readySnapshot of
                MsgLobbySnapshot _ _ _ players -> pure players
                _ -> fail "T12: thieu snapshot Ready"
            any ((== pid) . viewPlayerId) readyPlayers `shouldBe` True
            putStrLn ("[T12] connected and ready client " ++ show number)
            connectNext (number + 1)
              (ConnectedClient pid token connection appearance : clients)

findClient :: PlayerId -> [ConnectedClient] -> ConnectedClient
findClient pid clients =
  case find ((== pid) . clientPlayerId) clients of
    Just client -> client
    Nothing -> error ("T12: khong tim thay client " ++ pid)

pureLobby9 :: GameState
pureLobby9 =
  emptyLobby
    { gamePlayers =
        [ Player pid ("Nguoi " ++ show number) Nothing True Alive defaultAppearance
        | number <- [1 :: Int .. 9]
        , let pid = "p" ++ show number
        ]
    , gameHost = "p1"
    }

applyPureCommand
  :: (GameState, [DomainEvent])
  -> Command
  -> Either GameError (GameState, [DomainEvent])
applyPureCommand (state, previousEvents) command = do
  (next, events) <- applyCommand state command
  pure (next, previousEvents ++ events)

applyPureTransition
  :: (GameState, [DomainEvent])
  -> (GameState -> Either GameError (GameState, [DomainEvent]))
  -> Either GameError (GameState, [DomainEvent])
applyPureTransition (state, previousEvents) transition = do
  (next, events) <- transition state
  pure (next, previousEvents ++ events)

runPureFullGame :: Either GameError PureRun
runPureFullGame = do
  started <- applyPureCommand (pureLobby9, []) (StartGame "p1" roles9)
  nightOneVotes <- foldM applyPureCommand started
    [ NightAction "p1" (WolfTarget "p8")
    , NightAction "p2" (WolfTarget "p8")
    , NightAction "p3" (WolfTarget "p8")
    ]
  lockedOne <- applyPureTransition nightOneVotes (\state -> closeWolfVoting state False)
  nightOneRoles <- foldM applyPureCommand lockedOne
    [ NightAction "p4" (SeerTarget "p1")
    , NightAction "p5" (GuardTarget "p5")
    , NightAction "p6" WitchPass
    ]
  resolvedOne <- applyPureTransition nightOneRoles resolveNightTurn
  dayOne <- applyPureTransition resolvedOne completeNightTurn
  votingOne <- applyPureCommand dayOne AdvancePhase
  nightTwo <- foldM applyPureCommand votingOne
    ([Vote pid "p9" | pid <- map (("p" ++) . show) [1 :: Int .. 7]]
      ++ [Vote "p9" "p1"])
  nightTwoVotes <- foldM applyPureCommand nightTwo
    [ NightAction "p1" (WolfTarget "p4")
    , NightAction "p2" (WolfTarget "p4")
    , NightAction "p3" (WolfTarget "p4")
    ]
  lockedTwo <- applyPureTransition nightTwoVotes (\state -> closeWolfVoting state False)
  nightTwoRoles <- foldM applyPureCommand lockedTwo
    [ NightAction "p4" (SeerTarget "p1")
    , NightAction "p5" (GuardTarget "p6")
    , NightAction "p6" WitchPass
    ]
  resolvedTwo <- applyPureTransition nightTwoRoles resolveNightTurn
  (finished, events) <- applyPureTransition resolvedTwo completeNightTurn
  pure (PureRun finished events)

main :: IO ()
main = do
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  hSetBuffering stdout LineBuffering
  registry <- newRoomRegistry
  workers <- newMVar []
  let startWorker room = do
        worker <- forkIO (runGameLoopWithPhaseTimeouts 120000000 120000000 120000000 room)
        modifyMVar_ workers (pure . (worker :))
      startServer = do
        server <- forkIO (WS.runServer "127.0.0.1" port (webSocketApp registry startWorker))
        threadDelay 250000
        pure server
      stopServer server = do
        workerIds <- readMVar workers
        forM_ (server : workerIds) (\thread -> void (forkIO (killThread thread)))

  bracket startServer stopServer $ \_ -> hspec $ do
    describe "T12 - deterministic full-game replay" $ do
      it "cung Lobby va input cho cung GameOver va event transcript" $ do
        let first = runPureFullGame
            second = runPureFullGame
        first `shouldBe` second
        case first of
          Left err -> expectationFailure ("T12 replay bi tu choi: " ++ show err)
          Right result -> do
            gamePhase (pureFinalState result) `shouldBe` GameOver
            gameDay (pureFinalState result) `shouldBe` 2
            gameResult (pureFinalState result) `shouldBe` Just (Winner Wolves)
            validateGameInvariant (pureFinalState result) `shouldBe` Right ()
            pureEvents result `shouldSatisfy` any isFullReveal

    describe "T12 - 9 WebSocket clients" $ do
      it "Create/Join -> role -> chat/reconnect -> Vote -> GameOver" $
        withNineClients $ \clients -> do
          putStrLn "[T12] all 9 clients connected"
          room <- findRoom registry roomCode >>= maybe (fail "T12: thieu RoomRuntime") pure
          lobbyState <- readTVarIO (roomState room)
          length (gamePlayers lobbyState) `shouldBe` 9
          all playerReady (gamePlayers lobbyState) `shouldBe` True
          forM_ clients $ \client -> do
            let own = find ((== clientPlayerId client) . playerId) (gamePlayers lobbyState)
            fmap playerAppearance own `shouldBe` Just (clientAppearance client)
          putStrLn "[T12] server holds the ready 9-player lobby and appearances"

          let host = head clients
          send (clientConnection host) (ClientStartGame "start-t12" roomCode)
          assigned <- forM clients $ \client -> do
            roleMessage <- receiveUntil (clientConnection client) isRole
            case roleMessage of
              MsgYourRole actualRoom role -> do
                actualRoom `shouldBe` roomCode
                pure (AssignedClient client role)
              _ -> fail "T12: thieu role rieng"
          sort (map assignedRole assigned) `shouldBe` sort roles9
          putStrLn "[T12] private roles assigned"

          let invalidActor = assignedClient (head assigned)
          send (clientConnection invalidActor)
            (ClientVote "vote-wrong-phase" roomCode (clientPlayerId (clients !! 1)))
          expectRejected (clientConnection invalidActor) "vote-wrong-phase" "WrongPhase"
          putStrLn "[T12] invalid Night vote rejected"

          let wolves = [item | item <- assigned, assignedRole item == Werewolf]
              wolfOne = assignedClient (head wolves)
          send (clientConnection wolfOne)
            (ClientChannelChat "wolf-chat" roomCode WolvesNight "T12 wolf private")
          void $ receiveUntil (clientConnection wolfOne)
            (== MsgActionAccepted "wolf-chat" roomCode)
          wolfHistory <- readTVarIO (roomChatHistory room)
          [ (chatChannel record, chatSenderId record, chatText record)
            | record <- wolfHistory
            ] `shouldContain`
              [(WolvesNight, clientPlayerId wolfOne, "T12 wolf private")]
          putStrLn "[T12] WolvesNight chat accepted and stored"

          let roleClient role =
                assignedClient (head [item | item <- assigned, assignedRole item == role])
              wolfClients = map assignedClient wolves
              seerClient = roleClient Seer
              guardClient = roleClient Guard
              witchClient = roleClient Witch
              villagerClients =
                map assignedClient [item | item <- assigned, assignedRole item == Villager]
              nonHostVillagers =
                filter ((/= clientPlayerId host) . clientPlayerId) villagerClients
              slowClient =
                case nonHostVillagers of
                  candidate : _ -> candidate
                  [] -> head villagerClients
              voteTargetClient =
                head (filter ((/= clientPlayerId slowClient) . clientPlayerId) villagerClients)
              observer = wolfOne
              submitNight request client choice = do
                send (clientConnection client)
                  (ClientNightAction request roomCode choice)
                void $ receiveUntil (clientConnection client)
                  (== MsgNightActionAccepted roomCode)

          submitNight "night1-seer" seerClient
            (SeerTarget (clientPlayerId wolfOne))
          void $ receiveUntil (clientConnection seerClient)
            (== MsgSeerResult roomCode Wolves)
          submitNight "night1-guard" guardClient
            (GuardTarget (clientPlayerId guardClient))
          forM_ (zip [1 :: Int ..] wolfClients) $ \(number, wolf) ->
            submitNight ("night1-wolf-" ++ show number) wolf
              (WolfTarget (clientPlayerId slowClient))
          void $ receiveUntil (clientConnection witchClient)
            (== MsgWitchVictimNotice roomCode (Just (clientPlayerId slowClient)))
          submitNight "night1-witch" witchClient WitchPass

          dayOne <- readTVarIO (roomState room)
          gamePhase dayOne `shouldBe` Day
          gameDay dayOne `shouldBe` 1
          fmap playerLifeStatus
            (find ((== clientPlayerId slowClient) . playerId) (gamePlayers dayOne))
            `shouldBe` Just Dead
          validateGameInvariant dayOne `shouldBe` Right ()
          putStrLn "[T12] Night 1 completed through WebSocket actions"

          let aliveIdsDayOne =
                [ playerId player
                | player <- gamePlayers dayOne
                , playerLifeStatus player == Alive
                ]
              aliveClientsDayOne = [findClient pid clients | pid <- aliveIdsDayOne]
              chatter = head aliveClientsDayOne
          send (clientConnection chatter)
            (ClientChannelChat "day1-chat" roomCode PublicDay "T12 Day 1 message")
          void $ receiveUntil (clientConnection chatter) $ \message ->
            case message of
              MsgStoredChatMessage actualRoom record ->
                actualRoom == roomCode && chatText record == "T12 Day 1 message"
              _ -> False
          send (clientConnection chatter)
            (ClientChannelChat "day1-chat" roomCode PublicDay "T12 Day 1 message")
          expectRejected (clientConnection chatter) "day1-chat" "DuplicateRequest"
          putStrLn "[T12] public chat stored once"

          forM_ (zip [1 :: Int ..] aliveClientsDayOne) $ \(number, client) -> do
            let request = "skip-" ++ show number
            send (clientConnection client) (ClientSkipDiscussion request roomCode)
            void $ receiveUntil (clientConnection client) (== MsgActionAccepted request roomCode)
          votingState <- readTVarIO (roomState room)
          gamePhase votingState `shouldBe` Voting
          putStrLn "[T12] unanimous skip opened Voting"

          let voteTarget = clientPlayerId voteTargetClient
          forM_ (zip [1 :: Int ..] aliveClientsDayOne) $ \(number, client) -> do
            let pid = clientPlayerId client
                target =
                  if pid == voteTarget
                    then clientPlayerId observer
                    else voteTarget
                request = "vote-" ++ show number
            send (clientConnection client) (ClientVote request roomCode target)
            void $ receiveUntil (clientConnection client) (== MsgActionAccepted request roomCode)
          putStrLn "[T12] all living clients voted"

          nightTwo <- readTVarIO (roomState room)
          (gamePhase nightTwo, gameDay nightTwo) `shouldBe` (Night, 2)
          fmap playerLifeStatus
            (find ((== voteTarget) . playerId) (gamePlayers nightTwo))
            `shouldBe` Just Dead
          putStrLn "[T12] Day 1 Vote completed and Night 2 started"

          let reconnectId = voteTarget
              reconnectClient = voteTargetClient
          WS.sendClose
            (clientConnection reconnectClient)
            ("T12 reconnect" :: BL.ByteString)
          threadDelay 150000
          WS.runClient "127.0.0.1" port "/ws" $ \reconnected -> do
            send reconnected
              (ClientReconnect "reconnect-t12" roomCode (clientToken reconnectClient))
            session <- receiveUntil reconnected $ \message ->
              case message of
                MsgSessionEstablished actualRoom actualPlayer _ ->
                  actualRoom == roomCode && actualPlayer == reconnectId
                _ -> False
            session `shouldBe`
              MsgSessionEstablished roomCode reconnectId (clientToken reconnectClient)
            void $ receiveUntil reconnected $ \message ->
              case message of
                MsgVotingSnapshot actualRoom Night 2 _ _ _ _ _ -> actualRoom == roomCode
                _ -> False
            history <- receiveUntil reconnected $ \message ->
              case message of
                MsgChatHistorySnapshot actualRoom _ -> actualRoom == roomCode
                _ -> False
            case history of
              MsgChatHistorySnapshot _ records -> do
                length (filter ((== "T12 Day 1 message") . chatText) records) `shouldBe` 1
                records `shouldSatisfy` any ((== "__system__") . chatSenderId)
              _ -> expectationFailure "T12: thieu chat history"
          putStrLn "[T12] reconnect restored Night 2 and Day 1 history"

          submitNight "night2-seer" seerClient
            (SeerTarget (clientPlayerId wolfOne))
          void $ receiveUntil (clientConnection seerClient)
            (== MsgSeerResult roomCode Wolves)
          submitNight "night2-guard" guardClient
            (GuardTarget (clientPlayerId witchClient))
          forM_ (zip [1 :: Int ..] wolfClients) $ \(number, wolf) ->
            submitNight ("night2-wolf-" ++ show number) wolf
              (WolfTarget (clientPlayerId seerClient))
          void $ receiveUntil (clientConnection witchClient)
            (== MsgWitchVictimNotice roomCode (Just (clientPlayerId seerClient)))
          submitNight "night2-witch" witchClient WitchPass

          gameOverState <- readTVarIO (roomState room)
          gamePhase gameOverState `shouldBe` GameOver
          gameResult gameOverState `shouldBe` Just (Winner Wolves)
          putStrLn "[T12] Night 2 completed and reached GameOver"

          WS.runClient "127.0.0.1" port "/ws" $ \gameOverClient -> do
            send gameOverClient
              (ClientReconnect "game-over-reconnect" roomCode (clientToken reconnectClient))
            void $ receiveUntil gameOverClient $ \message ->
              case message of
                MsgSessionEstablished actualRoom actualPlayer _ ->
                  actualRoom == roomCode && actualPlayer == reconnectId
                _ -> False
            void $ receiveUntil gameOverClient
              (== MsgGameFinished roomCode (Winner Wolves))
            rolesMessage <- receiveUntil gameOverClient isFullRevealMessage
            case rolesMessage of
              MsgGameRolesRevealed actualRoom revealed -> do
                actualRoom `shouldBe` roomCode
                length revealed `shouldBe` 9
              _ -> expectationFailure "T12: thieu GameRolesRevealed"
          finalState <- readTVarIO (roomState room)
          gamePhase finalState `shouldBe` GameOver
          gameResult finalState `shouldBe` Just (Winner Wolves)
          length (gamePlayers finalState) `shouldBe` 9
          history <- readTVarIO (roomChatHistory room)
          length (filter ((== "T12 Day 1 message") . chatText) history) `shouldBe` 1
          putStrLn "[T12] GameOver and full reveal verified"

isFullReveal :: DomainEvent -> Bool
isFullReveal GameRolesRevealed {} = True
isFullReveal _ = False

isFullRevealMessage :: ServerMessage -> Bool
isFullRevealMessage MsgGameRolesRevealed {} = True
isFullRevealMessage _ = False
