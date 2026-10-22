module Main (main) where

import Domain.Night (wolfVictim)
import Domain.Replay
import Domain.Types
import Domain.Validation (validateGameInvariant)
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

dayState8 :: GameState
dayState8 = activeState roles8 Day
dayState9 :: GameState
dayState9 = activeState roles9 Day

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
    it "invariant dung sau moi buoc cua chuoi Command" $
      property $ \(CommandTrace commands) ->
        let result = replayCommands dayState8 commands
            states = dayState8 : map replayState (replaySteps result)
        in counterexample (show result) $
             all ((== Right ()) . validateGameInvariant) states

    it "Command bi tu choi khong lam thay doi GameState" $
      property $ \(CommandTrace commands) ->
        rejectedStepsKeepState dayState8
          (replaySteps (replayCommands dayState8 commands))

    it "TV1 - invariant dung sau moi buoc cua van 9 nguoi" $
      property $ \(CommandTrace commands) ->
        let result = replayCommands dayState9 commands
            states = dayState9 : map replayState (replaySteps result)
        in counterexample (show result) $
             all ((== Right ()) . validateGameInvariant) states

    it "TV1 - Command bi tu choi khong doi state van 9 nguoi" $
      property $ \(CommandTrace commands) ->
        let result = replayCommands dayState9 commands
        in counterexample (show result) $
             rejectedStepsKeepState dayState9 (replaySteps result)

  describe "T11 - deterministic replay" $ do
    it "cung initial state va Command sequence cho ket qua giong nhau" $
      property $ \(CommandTrace commands) ->
        replayCommands dayState8 commands === replayCommands dayState8 commands

    it "TV1 - Night Action khong hop le giu nguyen GameState" $ do
      let initial = activeState roles9 Night
          commands =
            [ NightAction "p1" (WolfTarget "p2")
            , NightAction "p4" (SeerTarget "p4")
            , NightAction "p5" (GuardTarget "missing")
            , NightAction "missing" (WolfTarget "p8")
            ]
          result = replayCommands initial commands

      map replayOutcome (replaySteps result)
        `shouldSatisfy` all isRejected

      replayFinalState result `shouldBe` initial

      validateGameInvariant (replayFinalState result)
        `shouldBe` Right ()

    it "TV1 - replay Night Action van 9 nguoi cho cung state va events" $ do
      let initial = activeState roles9 Night
          commands =
            [ NightAction "p1" (WolfTarget "p8")
            , NightAction "p2" (WolfTarget "p8")
            , NightAction "p3" (WolfTarget "p9")
            , NightAction "p4" (SeerTarget "p1")
            , NightAction "p5" (GuardTarget "p8")
            ]
          first = replayCommands initial commands
          second = replayCommands initial commands
          final = replayFinalState first

      first `shouldBe` second

      map replayOutcome (replaySteps first)
        `shouldSatisfy` all isAccepted

      length (replaySteps first) `shouldBe` 5

      wolfVictim final `shouldBe` Just "p8"

      validateGameInvariant final `shouldBe` Right ()

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

  describe "T11 - TV1 Night Action Privacy" $ do
    it "TV1 - Replay Night Action giu dung quyen rieng tu" $ do
      let initial = activeState roles9 Night
          commands =
            [ NightAction "p1" (WolfTarget "p8")
            , NightAction "p4" (SeerTarget "p2")
            , NightAction "p5" (GuardTarget "p8")
            ]
          result = replayCommands initial commands
          events =
            concat
              [ es
              | step <- replaySteps result
              , Right es <- [replayOutcome step]
              ]

      map replayOutcome (replaySteps result)
        `shouldSatisfy` all isAccepted

      events `shouldContain` [WolfVoteUpdated 1 3]

      events `shouldContain` [SeerResult "p4" Wolves]

      all
        (\event ->
          case event of
            WolfVoteUpdated _ _ ->
              eventVisibility event == TeamOnly Wolves
            SeerResult pid _ ->
              eventVisibility event == Private pid
            NightActionAccepted pid ->
              eventVisibility event == Private pid
            _ -> True
        )
        events `shouldBe` True

      validateGameInvariant (replayFinalState result)
        `shouldBe` Right ()

  describe "T11 - bang phieu Soi" $ do
    it "A-A-B chon A" $
      wolfVictim (wolfState [("p1", "p8"), ("p2", "p8"), ("p3", "p9")])
        `shouldBe` Just "p8"

    it "A-B-C hoa nen khong co nan nhan" $
      wolfVictim (wolfState [("p1", "p7"), ("p2", "p8"), ("p3", "p9")])
        `shouldBe` Nothing

    it "hai Soi bo A-B hoa nen khong co nan nhan" $
      wolfVictim (wolfState [("p1", "p8"), ("p2", "p9")])
        `shouldBe` Nothing

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

isRejected :: Either GameError [DomainEvent] -> Bool
isRejected (Left _) = True
isRejected (Right _) = False