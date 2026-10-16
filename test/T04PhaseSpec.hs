module Main (main) where

import Data.List (sort)
import Domain.Engine
  ( advancePhase
  , applyLobbyCommand
  , applyPhaseCommand
  , finishResolvedNight
  , finishResolvedVoting
  , startGame
  )
import Domain.Types
import Domain.Validation (expectedRoles, validateGameInvariant)
import Test.Hspec (Spec, describe, hspec, it, shouldBe)
import Test.QuickCheck (counterexample, elements, forAll, property, shuffle)

-- Lấy giá trị Right; nếu chuẩn bị test lỗi thì báo rõ nguyên nhân.
mustRight :: Show e => Either e a -> a
mustRight result =
  case result of
    Right value -> value
    Left err -> error ("Khong tao duoc du lieu test: " ++ show err)

-- Lấy bộ vai chuẩn cho 8 hoặc 9 người.
mustRoles :: Int -> [Role]
mustRoles count =
  case expectedRoles count of
    Just roles -> roles
    Nothing -> error "So nguoi test phai la 8 hoac 9"

-- Tạo Lobby có n người bằng hàm Join.
lobbyWith :: Int -> GameState
lobbyWith count =
  foldl addPlayer emptyLobby [1 .. count]
  where
    addPlayer state number =
      fst
        (mustRight
          (applyLobbyCommand state
            (Join ("p" ++ show number) ("Nguoi " ++ show number))))

-- Cho toàn bộ người trong phòng Ready.
allReady :: GameState -> GameState
allReady state =
  foldl setReady state (map playerId (gamePlayers state))
  where
    setReady current pid =
      fst (mustRight (applyLobbyCommand current (SetReady pid True)))

ready8 :: GameState
ready8 = allReady (lobbyWith 8)

ready9 :: GameState
ready9 = allReady (lobbyWith 9)

-- Đảo thứ tự để chứng minh Engine dùng thứ tự vai được truyền vào.
roles8 :: [Role]
roles8 = reverse (mustRoles 8)

roles9 :: [Role]
roles9 = reverse (mustRoles 9)

main :: IO ()
main = hspec lobbyStartTests

lobbyStartTests :: Spec
lobbyStartTests =
  describe "T04 StartGame" $ do

    it "Host bat dau van 8 nguoi va vao Night 1" $ do
      let (state, events) =
            mustRight (startGame ready8 "p1" roles8)

      gamePhase state `shouldBe` Night
      gameDay state `shouldBe` 1
      gameHost state `shouldBe` "p1"
      gameNightResolved state `shouldBe` False
      map playerRole (gamePlayers state)
        `shouldBe` map Just roles8
      map playerLifeStatus (gamePlayers state)
        `shouldBe` replicate 8 Alive
      events
        `shouldBe`
          [GameStarted, PhaseChanged Night]
            ++ zipWith PlayerRoleAssigned
                 (map playerId (gamePlayers state))
                 roles8
      validateGameInvariant state `shouldBe` Right ()

    it "Host bat dau van 9 nguoi voi dung bo vai" $ do
      let (state, _) =
            mustRight (startGame ready9 "p1" roles9)

      gamePhase state `shouldBe` Night
      gameDay state `shouldBe` 1
      sort [role | player <- gamePlayers state,
                   Just role <- [playerRole player]]
        `shouldBe` sort (mustRoles 9)
      validateGameInvariant state `shouldBe` Right ()

    it "Cung state va cung danh sach vai cho cung ket qua" $
      startGame ready8 "p1" roles8
        `shouldBe` startGame ready8 "p1" roles8

    it "Nguoi khong phai Host khong duoc Start" $
      startGame ready8 "p2" roles8
        `shouldBe` Left NotAuthorized

    it "Khong duoc Start khi chua ai Ready" $
      startGame (lobbyWith 8) "p1" roles8
        `shouldBe` Left NotAllReady

    it "Bay nguoi khong duoc Start" $
      startGame (allReady (lobbyWith 7)) "p1" roles8
        `shouldBe` Left InvalidPlayerCount

    it "Danh sach vai sai preset bi tu choi" $
      startGame ready8 "p1" (replicate 8 Villager)
        `shouldBe` Left InvalidRoleConfiguration

    it "Danh sach vai thieu mot vai bi tu choi" $
      startGame ready8 "p1" (take 7 roles8)
        `shouldBe` Left InvalidRoleConfiguration

    it "Khong duoc Start lan thu hai" $ do
      let (startedState, _) =
            mustRight (startGame ready8 "p1" roles8)

      startGame startedState "p1" roles8
        `shouldBe` Left WrongPhase

    it "Event chia vai la Private cho tung nguoi" $ do
      let (state, events) =
            mustRight (startGame ready8 "p1" roles8)
          roleEvents = drop 2 events
          pids = map playerId (gamePlayers state)

      map eventVisibility roleEvents
        `shouldBe` map Private pids

    it "Day 1 chuyen sang Voting 1" $ do
      let (nightState, _) =
            mustRight (startGame ready8 "p1" roles8)
          dayState =
            nightState { gamePhase = Day }
          (votingState, events) =
            mustRight (advancePhase dayState)

      gamePhase votingState `shouldBe` Voting
      gameDay votingState `shouldBe` 1
      gameVotes votingState `shouldBe` []
      gameVotingResolved votingState `shouldBe` False
      events `shouldBe` [PhaseChanged Voting]
      validateGameInvariant votingState `shouldBe` Right ()

    it "AdvancePhase khong duoc bo qua ResolveNight" $ do
      let (nightState, _) =
            mustRight (startGame ready8 "p1" roles8)

      advancePhase nightState `shouldBe` Left WrongPhase

    it "AdvancePhase khong duoc bo qua ResolveVoting" $ do
      let (nightState, _) =
            mustRight (startGame ready8 "p1" roles8)
          votingState =
            nightState { gamePhase = Voting }

      advancePhase votingState `shouldBe` Left WrongPhase

    it "Lenh AdvancePhase di qua applyPhaseCommand" $ do
      let (nightState, _) =
            mustRight (startGame ready8 "p1" roles8)
          dayState =
            nightState { gamePhase = Day }

      applyPhaseCommand dayState AdvancePhase
        `shouldBe` advancePhase dayState

    it "Chua resolve Night thi khong duoc sang Day" $ do
      let (nightState, _) =
            mustRight (startGame ready8 "p1" roles8)

      finishResolvedNight nightState Nothing
        `shouldBe` Left InvalidGameState

    it "Night 1 da resolve chuyen sang Day 1" $ do
      let (nightState, _) =
            mustRight (startGame ready8 "p1" roles8)
          resolvedNight =
            nightState { gameNightResolved = True }
          (dayState, events) =
            mustRight (finishResolvedNight resolvedNight Nothing)

      gamePhase dayState `shouldBe` Day
      gameDay dayState `shouldBe` 1
      gameNightResolved dayState `shouldBe` False
      events `shouldBe` [PhaseChanged Day]
      validateGameInvariant dayState `shouldBe` Right ()

    it "Chua resolve Voting thi khong duoc sang Night" $ do
      let (night1, _) =
            mustRight (startGame ready8 "p1" roles8)
          resolvedNight =
            night1 { gameNightResolved = True }
          (day1, _) =
            mustRight (finishResolvedNight resolvedNight Nothing)
          (voting1, _) =
            mustRight (advancePhase day1)

      finishResolvedVoting voting1 Nothing
        `shouldBe` Left InvalidGameState

    it "Voting 1 da resolve chuyen sang Night 2" $ do
      let (night1, _) =
            mustRight (startGame ready8 "p1" roles8)
          resolvedNight =
            night1 { gameNightResolved = True }
          (day1, _) =
            mustRight (finishResolvedNight resolvedNight Nothing)
          (voting1, _) =
            mustRight (advancePhase day1)
          resolvedVoting =
            voting1 { gameVotingResolved = True }
          (night2, events) =
            mustRight (finishResolvedVoting resolvedVoting Nothing)

      gamePhase night2 `shouldBe` Night
      gameDay night2 `shouldBe` 2
      gameNightResolved night2 `shouldBe` False
      gameVotingResolved night2 `shouldBe` False
      events `shouldBe` [PhaseChanged Night]
      validateGameInvariant night2 `shouldBe` Right ()

    it "Night resolve ra hoa thi vao GameOver" $ do
      let (nightState, _) =
            mustRight (startGame ready8 "p1" roles8)
          resolvedNight =
            nightState { gameNightResolved = True }
          (endedState, events) =
            mustRight (finishResolvedNight resolvedNight (Just Draw))

      gamePhase endedState `shouldBe` GameOver
      gameResult endedState `shouldBe` Just Draw
      gameDay endedState `shouldBe` 1
      gameNightResolved endedState `shouldBe` False
      events `shouldBe`
        [ PhaseChanged GameOver
        , GameFinished Draw
        , GameRolesRevealed
            [ (playerId p, role)
            | p <- gamePlayers endedState
            , Just role <- [playerRole p]
            ]
        ]
      validateGameInvariant endedState `shouldBe` Right ()

    it "Khong chuyen pha khi con role reveal dang cho" $ do
      let (nightState, _) =
            mustRight (startGame ready8 "p1" roles8)
          pendingState =
            nightState
              { gameNightResolved = True
              , gamePendingReveals = ["p1"]
              }

      finishResolvedNight pendingState Nothing
        `shouldBe` Left InvalidGameState

    it "GameOver khong duoc chuyen pha lan nua" $ do
      let (nightState, _) =
            mustRight (startGame ready8 "p1" roles8)
          resolvedNight =
            nightState { gameNightResolved = True }
          (endedState, _) =
            mustRight (finishResolvedNight resolvedNight (Just Draw))

      finishResolvedNight endedState Nothing
        `shouldBe` Left GameAlreadyOver

    it "QuickCheck: StartGame luon tao Night state hop le" $
      property $
        forAll (elements [8, 9]) $ \count ->
          forAll (shuffle (mustRoles count)) $ \roles ->
            let lobby = allReady (lobbyWith count)
            in case startGame lobby "p1" roles of
                 Left err ->
                   counterexample
                     ("StartGame bi tu choi: " ++ show err)
                     False

                 Right (state, events) ->
                   counterexample
                     ("State: " ++ show state ++ "\nEvents: " ++ show events)
                     ( gamePhase state == Night
                       && gameDay state == 1
                       && not (gameNightResolved state)
                       && validateGameInvariant state == Right ()
                       && map playerRole (gamePlayers state) == map Just roles
                       && take 2 events == [GameStarted, PhaseChanged Night]
                     )
    it "QuickCheck: moi buoc chuyen Phase giu GameState hop le" $
      property $
        forAll (elements [8, 9]) $ \count ->
          forAll (shuffle (mustRoles count)) $ \roles ->
            let runCycle = do
                  (night1, startEvents) <-
                    startGame (allReady (lobbyWith count)) "p1" roles
                  (day1, nightEvents) <-
                    finishResolvedNight
                      (night1 { gameNightResolved = True })
                      Nothing
                  (voting1, dayEvents) <-
                    advancePhase day1
                  (night2, votingEvents) <-
                    finishResolvedVoting
                      (voting1 { gameVotingResolved = True })
                      Nothing
                  pure (night1, day1, voting1, night2,
                        startEvents, nightEvents, dayEvents, votingEvents)

            in case runCycle of
                 Left err ->
                   counterexample ("Chuyen Phase loi: " ++ show err) False

                 Right (night1, day1, voting1, night2,
                        startEvents, nightEvents, dayEvents, votingEvents) ->
                   counterexample "Phase hoac invariant khong dung" $
                     and
                       [ map validateGameInvariant
                           [night1, day1, voting1, night2]
                           == replicate 4 (Right ())
                       , map gamePhase
                           [night1, day1, voting1, night2]
                           == [Night, Day, Voting, Night]
                       , map gameDay
                           [night1, day1, voting1, night2]
                           == [1, 1, 1, 2]
                       , take 2 startEvents
                           == [GameStarted, PhaseChanged Night]
                       , nightEvents == [PhaseChanged Day]
                       , dayEvents == [PhaseChanged Voting]
                       , votingEvents == [PhaseChanged Night]
                       , not (gameNightResolved night2)
                       , not (gameVotingResolved night2)
                       ]