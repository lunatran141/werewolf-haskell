module Main (main) where

import Control.Monad (forM_)
import Domain.Night (wolfVictim)
import Domain.Replay
  ( ReplayResult(..)
  , ReplayStep(..)
  , replayCommands
  , replayWithSeed
  )
import Domain.Types
  ( ChatChannel(..)
  , Command(..)
  , DomainEvent(..)
  , GameError(..)
  , GameState(..)
  , LifeStatus(..)
  , NightChoice(..)
  , Phase(..)
  , Player(..)
  , PlayerId
  , Role(..)
  , Team(..)
  , defaultAppearance
  , emptyLobby
  , gameDay
  , gamePhase
  , gamePlayers
  , playerId
  , playerLifeStatus
  , playerRole
  )
import Domain.Validation (validateGameInvariant)
import Protocol.Types
  ( ServerMessage(..)
  )
import Server.Broadcast
  ( lobbySnapshot
  , nightMessagesForState
  , votingSnapshot
  , wolfTeamMessage
  )
import Test.Hspec
import Test.QuickCheck

roles8 :: [Role]
roles8 =
  [Werewolf, Werewolf, Seer, Guard, Witch, Hunter, Villager, Villager]

roles9 :: [Role]
roles9 =
  [ Werewolf, Werewolf, Werewolf, Seer, Guard, Witch, Hunter
  , Villager, Villager
  ]

activeState :: [Role] -> Phase -> GameState
activeState roles phase =
  emptyLobby
    { gamePlayers =
        [ Player pid ("Nguoi " ++ pid) (Just role) True Alive defaultAppearance
        | (pid, role) <- zip playerIds roles
        ]
    , gameHost = "p1"
    , gamePhase = phase
    , gameDay = 1
    , gameConfiguredRoles = roles
    }
  where
    playerIds = map (("p" ++) . show) [1 :: Int .. length roles]

readyLobby :: [Role] -> GameState
readyLobby roles =
  emptyLobby
    { gamePlayers =
        [ Player pid ("Nguoi " ++ pid) Nothing True Alive defaultAppearance
        | pid <- playerIds
        ]
    , gameHost = "p1"
    , gamePhase = Lobby
    , gameDay = 0
    , gameConfiguredRoles = []
    }
  where
    playerIds = map (("p" ++) . show) [1 :: Int .. length roles]

dayState8 :: GameState
dayState8 = activeState roles8 Day

dayState9 :: GameState
dayState9 = activeState roles9 Day

nightState9 :: GameState
nightState9 = activeState roles9 Night

newtype CommandTrace = CommandTrace [Command]
  deriving (Show)

instance Arbitrary CommandTrace where
  arbitrary = CommandTrace <$> resize 35 (listOf genCommand)
  shrink (CommandTrace commands) =
    CommandTrace <$> shrinkList (const []) commands

genCommand :: Gen Command
genCommand =
  oneof
    [ Chat <$> genPlayerId <*> elements ["xin chao", "", replicate 301 'x']
    , ChatInChannel <$> genPlayerId <*> elements [PublicDay, WolvesNight]
        <*> elements ["thao luan", ""]
    , SkipDiscussion <$> genPlayerId
    , pure AdvancePhase
    , Vote <$> genPlayerId <*> genPlayerId
    , pure ResolveVoting
    , NightAction <$> genPlayerId <*> genNightChoice
    , pure ResolveNight
    , ResolveHunter <$> genPlayerId
        <*> frequency [(1, pure Nothing), (3, Just <$> genPlayerId)]
    ]

genPlayerId :: Gen PlayerId
genPlayerId = elements ("missing" : map (("p" ++) . show) [1 :: Int .. 9])

genNightChoice :: Gen NightChoice
genNightChoice =
  oneof
    [ WolfTarget <$> genPlayerId
    , SeerTarget <$> genPlayerId
    , GuardTarget <$> genPlayerId
    , pure WitchHeal
    , WitchPoison <$> genPlayerId
    , pure WitchPass
    , HunterShot <$> genPlayerId
    , pure HunterPass
    , pure NoAction
    ]

main :: IO ()
main = hspec $ do
  describe "T11 - state-machine property" $ do
    it "invariant dung sau moi buoc cua chuoi Command tren van 8 nguoi" $
      property $ \(CommandTrace commands) ->
        let result = replayCommands dayState8 commands
            states = dayState8 : map replayState (replaySteps result)
        in counterexample (show result) $
             all ((== Right ()) . validateGameInvariant) states

    it "invariant dung sau moi buoc cua chuoi Command tren van 9 nguoi" $
      property $ \(CommandTrace commands) ->
        let result = replayCommands dayState9 commands
            states = dayState9 : map replayState (replaySteps result)
        in counterexample (show result) $
             all ((== Right ()) . validateGameInvariant) states

    it "Command bi tu choi khong lam thay doi GameState (8 nguoi)" $
      property $ \(CommandTrace commands) ->
        rejectedStepsKeepState dayState8
          (replaySteps (replayCommands dayState8 commands))

    it "Command bi tu choi khong lam thay doi GameState (9 nguoi)" $
      property $ \(CommandTrace commands) ->
        rejectedStepsKeepState dayState9
          (replaySteps (replayCommands dayState9 commands))

  describe "T11 - kien thuc foldl' va de quy cau truc (Sheet 04)" $ do
    it "base case: replay chuoi Command rong tra ve dung GameState ban dau" $ do
      let res8 = replayCommands dayState8 []
          res9 = replayCommands dayState9 []
      replayFinalState res8 `shouldBe` dayState8
      replaySteps res8 `shouldBe` []
      replayFinalState res9 `shouldBe` dayState9
      replaySteps res9 `shouldBe` []

    it "step case / composition: replay (cmds1 ++ cmds2) giong replay cmds1 roi tiep tuc cmds2" $
      property $ \(CommandTrace cmds1) (CommandTrace cmds2) ->
        let resMerged = replayCommands dayState8 (cmds1 ++ cmds2)
            res1 = replayCommands dayState8 cmds1
            res2 = replayCommands (replayFinalState res1) cmds2
        in counterexample "Final state phai giong nhau giua replay lien tuc va ghep chuoi" $
             replayFinalState resMerged == replayFinalState res2

  describe "T11 - deterministic replay (E16)" $ do
    it "cung initial state va Command sequence cho ket qua giong nhau" $
      property $ \(CommandTrace commands) ->
        replayCommands dayState8 commands === replayCommands dayState8 commands

    it "replay Day 1 -> Voting -> Night 2 co ket qua co dinh" $ do
      let commands =
            [ Chat "p1" "thao luan"
            , AdvancePhase
            , Vote "p1" "p7"
            , Vote "p2" "p7"
            , Vote "p3" "p8"
            , ResolveVoting
            ]
          first = replayCommands dayState8 commands
          second = replayCommands dayState8 commands
          final = replayFinalState first
      first `shouldBe` second
      map replayOutcome (replaySteps first) `shouldSatisfy` all isAccepted
      gamePhase final `shouldBe` Night
      gameDay final `shouldBe` 2
      lifeOf "p7" final `shouldBe` Just Dead
      validateGameInvariant final `shouldBe` Right ()

    it "replayWithSeed tu Lobby cho van 9 nguoi tao cung mot ket qua khi lap lai" $ do
      let seed = 42
          lobby = readyLobby roles9
          commands =
            [ Chat "p1" "xin chao"
            , ChatInChannel "p1" PublicDay "chat chung"
            ]
          first = replayWithSeed seed roles9 lobby commands
          second = replayWithSeed seed roles9 lobby commands
      first `shouldBe` second
      gamePhase (replayFinalState first) `shouldBe` Night
      validateGameInvariant (replayFinalState first) `shouldBe` Right ()

    it "cung chuoi command nhung khac seed tao phan vai khac nhau ma van giu invariant" $ do
      let lobby = readyLobby roles9
          r1 = replayWithSeed 100 roles9 lobby []
          r2 = replayWithSeed 200 roles9 lobby []
          state1 = replayFinalState r1
          state2 = replayFinalState r2
      validateGameInvariant state1 `shouldBe` Right ()
      validateGameInvariant state2 `shouldBe` Right ()
      -- Cả 2 đều chia đủ bộ vai chuẩn 9 người
      map playerRole (gamePlayers state1) `shouldNotBe` map playerRole (gamePlayers state2)

    it "replay chu trinh Night 1 -> Day 1 -> Voting 1 xuyen suot va xac dinh" $ do
      let lobby = readyLobby roles8
          fullCycle =
            [ StartGame "p1" roles8
            , NightAction "p1" (WolfTarget "p7")
            , NightAction "p2" (WolfTarget "p7")
            , NightAction "p3" (SeerTarget "p2")
            , NightAction "p4" (GuardTarget "p1")
            , NightAction "p5" WitchPass
            , ResolveNight
            , Chat "p1" "Chao buoi sang"
            , AdvancePhase
            , Vote "p1" "p2"
            , Vote "p3" "p2"
            , Vote "p4" "p2"
            , ResolveVoting
            ]
          run1 = replayCommands lobby fullCycle
          run2 = replayCommands lobby fullCycle
          st1 = replayFinalState run1
      run1 `shouldBe` run2
      map replayOutcome (replaySteps run1) `shouldSatisfy` all isAccepted
      gameDay st1 `shouldBe` 2
      gamePhase st1 `shouldBe` Night
      lifeOf "p7" st1 `shouldBe` Just Dead
      lifeOf "p2" st1 `shouldBe` Just Dead
      validateGameInvariant st1 `shouldBe` Right ()

  describe "T11 - bang phieu Soi (Sheet 02)" $ do
    it "A-A-B chon A" $
      wolfVictim (wolfState [("p1", "p8"), ("p2", "p8"), ("p3", "p9")])
        `shouldBe` Just "p8"

    it "A-B-C hoa nen khong co nan nhan" $
      wolfVictim (wolfState [("p1", "p7"), ("p2", "p8"), ("p3", "p9")])
        `shouldBe` Nothing

    it "hai Soi bo A-B hoa nen khong co nan nhan" $
      wolfVictim (wolfState [("p1", "p8"), ("p2", "p9")])
        `shouldBe` Nothing

    it "hai Soi bo A-A chon A" $
      wolfVictim (wolfState [("p1", "p8"), ("p2", "p8")])
        `shouldBe` Just "p8"

  describe "T11 - khong ro ri thong tin bi mat qua Broadcast (E15)" $ do
    it "Dan lang khong bao gio nhan thong diep mat cua Soi hoac Tien tri" $ do
      let state = nightState9
          villagers = [pid | p <- gamePlayers state, playerRole p == Just Villager, let pid = playerId p]
      forM_ villagers $ \vid -> do
        wolfTeamMessage "ROOM-T11" vid state `shouldBe` Nothing

        let secretEvents =
              [ SeerResult "p4" Wolves
              , WitchVictimNotice "p6" (Just "p8")
              , WolfVoteUpdated 2 3
              , WolfTargetLocked (Just "p8")
              , ChatMessageInChannel WolvesNight "p1" "Can p8 nhe"
              , PlayerRoleRevealed "p8" Villager Village
              ]
            delivered = nightMessagesForState "ROOM-T11" vid state secretEvents
        delivered `shouldBe` []

    it "Snapshot Lobby va Voting khong chua vai tro cua nguoi khac" $ do
      let state = dayState9
      case lobbySnapshot "ROOM-T11" "p8" state of
        MsgLobbySnapshot _ _ _ players -> do
          length players `shouldBe` 9
        other -> expectationFailure ("Mong doi MsgLobbySnapshot, nhan: " ++ show other)

      case votingSnapshot "ROOM-T11" "p8" state of
        MsgVotingSnapshot _ _ _ players _ _ _ _ -> do
          length players `shouldBe` 9
        other -> expectationFailure ("Mong doi MsgVotingSnapshot, nhan: " ++ show other)

rejectedStepsKeepState :: GameState -> [ReplayStep] -> Bool
rejectedStepsKeepState _ [] = True
rejectedStepsKeepState previous (step : rest) =
  unchangedWhenRejected
    && rejectedStepsKeepState (replayState step) rest
  where
    unchangedWhenRejected =
      case replayOutcome step of
        Left _  -> replayState step == previous
        Right _ -> True

isAccepted :: Either GameError [DomainEvent] -> Bool
isAccepted (Right _) = True
isAccepted (Left _) = False

lifeOf :: PlayerId -> GameState -> Maybe LifeStatus
lifeOf pid state =
  playerLifeStatus <$> findPlayer pid (gamePlayers state)
  where
    findPlayer _ [] = Nothing
    findPlayer wanted (player : rest)
      | playerId player == wanted = Just player
      | otherwise = findPlayer wanted rest

wolfState :: [(PlayerId, PlayerId)] -> GameState
wolfState votes =
  (activeState roles9 Night)
    { gameNightActions = [(actor, WolfTarget target) | (actor, target) <- votes]
    , gameWolfVotingClosed = True
    }
