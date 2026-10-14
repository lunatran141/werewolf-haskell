-- Bộ kiểm thử T06: Vote/Tally/Tie/Lynch end-to-end trong Pure Domain.
-- Các case lỗi đều kiểm tra state không bị thay đổi sau khi bị từ chối.
module DomainT06Spec (t06Spec) where

import Domain.Engine (applyCommand, resolveNightTurn, closeWolfVoting)
import Domain.Validation (validateGameInvariant)
import Domain.Rules
  ( checkWin
  , lynchTarget
  , tallyVotes
  , uniqueVoteWinner
  , voteWinners
  )
import Domain.Types
import Test.Hspec hiding (pending)

roles8 :: [Role]
roles8 = [Werewolf, Werewolf, Seer, Guard, Witch, Hunter, Villager, Villager]

startedVoting8 :: GameState
startedVoting8 =
  emptyLobby
    { gamePlayers =
        [ Player pid ("Nguoi " ++ pid) (Just role) True Alive
        | (pid, role) <- zip (map ("p" ++) (map show [1 :: Int .. 8])) roles8
        ]
    , gameHost = "p1"
    , gamePhase = Voting
    , gameDay = 1
    , gameConfiguredRoles = roles8
    }

mustRight :: Show errorType => Either errorType value -> value
mustRight result =
  case result of
    Right value -> value
    Left err -> error ("Khong tao duoc state test T06: " ++ show err)

castVote :: GameState -> PlayerId -> PlayerId -> GameState
castVote state voter target =
  fst (mustRight (applyCommand state (Vote voter target)))

withDead :: [PlayerId] -> GameState -> GameState
withDead pids state =
  state {gamePlayers = map mark (gamePlayers state)}
  where
    mark player
      | playerId player `elem` pids = player {playerLifeStatus = Dead}
      | otherwise = player

t06Spec :: Spec
t06Spec = do
  describe "T06 - Tally va tie/lynch" $ do
    it "Tally dem dung so phieu theo target" $ do
      tallyVotes [("p1", "p7"), ("p2", "p7"), ("p3", "p8")]
        `shouldBe` [("p7", 2), ("p8", 1)]

    it "Target co nhieu phieu nhat duy nhat la nguoi bi lynch" $ do
      voteWinners [("p1", "p7"), ("p2", "p7"), ("p3", "p8")]
        `shouldBe` ["p7"]
      uniqueVoteWinner [("p1", "p7"), ("p2", "p7"), ("p3", "p8")]
        `shouldBe` Just "p7"
      lynchTarget [("p1", "p7"), ("p2", "p7"), ("p3", "p8")]
        `shouldBe` Just "p7"

    it "Hoa phieu cao nhat khong co lynch target" $ do
      voteWinners [("p1", "p7"), ("p2", "p8")]
        `shouldBe` ["p7", "p8"]
      lynchTarget [("p1", "p7"), ("p2", "p8")]
        `shouldBe` Nothing

    it "Khong co phieu thi khong co lynch target" $
      lynchTarget [] `shouldBe` Nothing

  describe "T06 - Validate Vote" $ do
    it "Vote hop le duoc luu va phat VoteUpdated rieng cho voter" $ do
      let (state, events) =
            mustRight (applyCommand startedVoting8 (Vote "p1" "p7"))
      gameVotes state `shouldBe` [("p1", "p7")]
      events `shouldBe` [VoteUpdated "p1" "p7"]
      eventVisibility (head events) `shouldBe` Private "p1"

    it "Khong cho phep self-vote" $ do
      applyCommand startedVoting8 (Vote "p1" "p1")
        `shouldBe` Left InvalidTarget

    it "Khong cho phep voter da chet" $ do
      applyCommand (withDead ["p1"] startedVoting8) (Vote "p1" "p7")
        `shouldBe` Left DeadPlayer

    it "Khong cho phep target da chet" $ do
      applyCommand (withDead ["p7"] startedVoting8) (Vote "p1" "p7")
        `shouldBe` Left DeadPlayer

    it "Khong cho phep target khong ton tai" $ do
      applyCommand startedVoting8 (Vote "p1" "missing")
        `shouldBe` Left PlayerNotFound

    it "Vote lan hai cua cung voter bi tu choi va state giu nguyen" $ do
      let voted = castVote startedVoting8 "p1" "p7"
      applyCommand voted (Vote "p1" "p8") `shouldBe` Left AlreadyVoted
      gameVotes voted `shouldBe` [("p1", "p7")]

    it "Vote ngoai phase Voting bi tu choi" $ do
      applyCommand (startedVoting8 {gamePhase = Day}) (Vote "p1" "p7")
        `shouldBe` Left WrongPhase

  describe "T06 - Resolve Voting va tie/no-vote" $ do
    it "Lynch target duy nhat bi loai va chuyen sang Night ke tiep" $ do
      let voted =
            castVote
              (castVote startedVoting8 "p1" "p7")
              "p2"
              "p7"
          (resolved, events) = mustRight (applyCommand voted ResolveVoting)
          target = head (filter ((== "p7") . playerId) (gamePlayers resolved))
      playerLifeStatus target `shouldBe` Dead
      gamePhase resolved `shouldBe` Night
      gameDay resolved `shouldBe` 2
      gameVotes resolved `shouldBe` []
      gameVotingResolved resolved `shouldBe` False
      events `shouldBe`
        [ VotingResolved [("p7", 2)] (Just "p7")
        , PlayerEliminated "p7"
        , PlayerRoleRevealed "p7" Villager Village
        , PhaseChanged Night
        ]

    it "Hoa phieu khong ai chet va khong duoc vote lai" $ do
      let voted =
            castVote
              (castVote startedVoting8 "p1" "p7")
              "p2"
              "p8"
          (resolved, events) = mustRight (applyCommand voted ResolveVoting)
      map playerLifeStatus (gamePlayers resolved) `shouldBe` replicate 8 Alive
      gamePhase resolved `shouldBe` Night
      gameDay resolved `shouldBe` 2
      events `shouldBe` [VotingResolved [("p7", 1), ("p8", 1)] Nothing, PhaseChanged Night]

    it "Khong co phieu cung chuyen sang Night ma khong tao fake vote" $ do
      let (resolved, events) =
            mustRight (applyCommand startedVoting8 ResolveVoting)
      gameVotes resolved `shouldBe` []
      gamePhase resolved `shouldBe` Night
      events `shouldBe` [VotingResolved [] Nothing, PhaseChanged Night]

  describe "T06 - Hunter chain va checkWin" $ do
    it "Lynch Hunter tao pending shot va chua checkWin som" $ do
      let voted = castVote startedVoting8 "p1" "p6"
          (pending, events) = mustRight (applyCommand voted ResolveVoting)
      gamePhase pending `shouldBe` Voting
      gamePendingHunter pending `shouldBe` Just "p6"
      gameVotingResolved pending `shouldBe` True
      gameResult pending `shouldBe` Nothing
      events `shouldBe` [VotingResolved [("p6", 1)] (Just "p6"), HunterShotPending "p6"]

    it "Hunter ban target roi moi reveal va chuyen phase" $ do
      let voted = castVote startedVoting8 "p1" "p6"
          (pending, _) = mustRight (applyCommand voted ResolveVoting)
          (resolved, events) =
            mustRight (applyCommand pending (ResolveHunter "p6" (Just "p1")))
      gamePendingHunter resolved `shouldBe` Nothing
      gamePhase resolved `shouldBe` Night
      playerLifeStatus (findById "p1" resolved) `shouldBe` Dead
      events `shouldBe`
        [ HunterShotResolved "p6" (Just "p1")
        , PlayerEliminated "p6"
        , PlayerEliminated "p1"
        , PlayerRoleRevealed "p6" Hunter Village
        , PlayerRoleRevealed "p1" Werewolf Wolves
        , PhaseChanged Night
        ]

    it "Hunter va Soi cuoi cung cung chet thi Draw" $ do
      let state =
            (withDead ["p2", "p3", "p4", "p5", "p7", "p8"] startedVoting8)
              {gameVotes = [("p1", "p6")]}
          (pending, _) = mustRight (applyCommand state ResolveVoting)
          (finished, events) =
            mustRight (applyCommand pending (ResolveHunter "p6" (Just "p1")))
      gamePhase finished `shouldBe` GameOver
      gameResult finished `shouldBe` Just Draw
      last events `shouldBe` GameFinished Draw

    it "Khong con Soi song thi ket qua la Winner Village" $ do
      let state =
            castVote
              (withDead ["p1", "p2"] startedVoting8)
              "p3"
              "p4"
          (finished, _) = mustRight (applyCommand state ResolveVoting)
      gameResult finished `shouldBe` Just (Winner Village)
      checkWin finished `shouldBe` Just (Winner Village)

    it "Chi con Soi song thi ket qua la Winner Wolves" $ do
      let state =
            castVote
              (withDead ["p3", "p4", "p5", "p6", "p7", "p8"] startedVoting8)
              "p1"
              "p2"
          (finished, _) = mustRight (applyCommand state ResolveVoting)
      gameResult finished `shouldBe` Just (Winner Wolves)

    -- Ghép thực sự với resolver T05: Hunter chết trong Night vẫn được bắn.
    it "Hunter chet ban dem ban xong moi sang Day" $ do
      let night = startedVoting8 {gamePhase = Night, gameNightActions = [("p5", WitchPoison "p6")]}
          (locked, _) = mustRight (closeWolfVoting night True)
          (pending, _) = mustRight (resolveNightTurn locked)
          (finished, _) = mustRight (applyCommand pending (ResolveHunter "p6" (Just "p1")))
      gamePhase finished `shouldBe` Day
      gameDay finished `shouldBe` 1
      playerLifeStatus (findById "p1" finished) `shouldBe` Dead
      validateGameInvariant finished `shouldBe` Right ()

    it "Hunter pass, self/dead/missing target va ban lap duoc xu ly" $ do
      let (pending, _) = mustRight (applyCommand (castVote startedVoting8 "p1" "p6") ResolveVoting)
          (passed, _) = mustRight (applyCommand pending (ResolveHunter "p6" Nothing))
      applyCommand pending (ResolveHunter "p6" (Just "p6")) `shouldBe` Left InvalidTarget
      applyCommand pending (ResolveHunter "p6" (Just "missing")) `shouldBe` Left PlayerNotFound
      applyCommand (withDead ["p7"] pending) (ResolveHunter "p6" (Just "p7")) `shouldBe` Left DeadPlayer
      gamePhase passed `shouldBe` Night
      applyCommand passed (ResolveHunter "p6" Nothing) `shouldSatisfy` either (const True) (const False)

    it "Van 9 nguoi van dung luat duy nhat cao nhat va invariant" $ do
      let roles = Werewolf : roles8
          nine = startedVoting8 {gamePlayers = zipWith (\n role -> Player ("p" ++ show n) (show n) (Just role) True Alive) [1 :: Int .. 9] roles,
                                 gameConfiguredRoles = roles}
          (finished, _) = mustRight (applyCommand (castVote nine "p1" "p9") ResolveVoting)
      playerLifeStatus (findById "p9" finished) `shouldBe` Dead
      validateGameInvariant finished `shouldBe` Right ()

    it "Khong cho resolve lai, vote muon hoac tally state sai" $ do
      let (finished, _) = mustRight (applyCommand startedVoting8 ResolveVoting)
      applyCommand finished ResolveVoting `shouldBe` Left WrongPhase
      applyCommand finished (Vote "p1" "p7") `shouldBe` Left WrongPhase
      applyCommand (startedVoting8 {gameVotes = [("p1", "p1")]}) ResolveVoting `shouldBe` Left InvalidGameState

  describe "T06 - Chat khong lam doi gameplay" $ do
    it "Chat trong Day phat event nhung giu nguyen state" $ do
      let dayState = startedVoting8 {gamePhase = Day}
          result = applyCommand dayState (Chat "p1" "Xin chao")
      result `shouldBe` Right (dayState, [ChatMessage "p1" "Xin chao"])

findById :: PlayerId -> GameState -> Player
findById pid state =
  case filter ((== pid) . playerId) (gamePlayers state) of
    player : _ -> player
    [] -> error "Khong tim thay Player trong fixture T06"
