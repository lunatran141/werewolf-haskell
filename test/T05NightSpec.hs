
module Main (main) where

import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck (Positive(..))

import Domain.Engine
  ( startGame, submitNightAction, applyNightCommand
  , resolveNightTurn, closeWolfVoting
  , nightGameResult, completeNightTurn
  )
import Domain.Night
import Domain.Types
import Domain.Validation (expectedRoles , validNightTargets)

-- Tao van dung preset 8 hoac 9 nguoi bang StartGame cua T04.
mkGame :: Int -> GameState
mkGame count =
  case startGame lobby "1" roles of
    Right (state, _) -> state
    Left err -> error ("Khong tao duoc van kiem thu: " ++ show err)
  where
    roles = case expectedRoles count of
      Just preset -> preset
      Nothing -> error "So nguoi khong duoc ho tro"

    -- Moi Player can co Appearance sau khi T02 mo rong Domain.Types.
    players =
      [ Player (show n) ("Player" ++ show n)
          Nothing True Alive defaultAppearance
      | n <- [1 .. count]
      ]

    lobby = emptyLobby
      { gamePlayers = players
      , gameHost = "1"
      }

-- Van 8 nguoi: 1,2 Soi; 3 Tien Tri; 4 Bao Ve; 5 Phu Thuy; 6 Tho San; 7,8 Dan.
game8 :: GameState
game8 = mkGame 8

-- Van 9 nguoi: 1,2,3 Soi; 4 Tien Tri; 5 Bao Ve; 6 Phu Thuy; 7 Tho San; 8,9 Dan.
game9 :: GameState
game9 = mkGame 9

-- Gan cac hanh dong da duoc chap nhan vao trang thai kiem thu.
withActions :: GameState -> [(PlayerId, NightChoice)] -> GameState
withActions state actions =
  state { gameNightActions = actions }

-- Danh dau mot nguoi chet de kiem tra viec tu choi hanh dong.
withDeadPlayer :: GameState -> PlayerId -> GameState
withDeadPlayer state pid =
  state { gamePlayers = map update (gamePlayers state) }
  where
    update player
      | playerId player == pid =
          player { playerLifeStatus = Dead }
      | otherwise = player

main :: IO ()
main = hspec $ do

  describe "T05 - Van 8 nguoi: Soi" $ do

    -- Soi chi duoc chon Player con song thuoc Village.
    it "validNightTargets - Soi khong duoc chon dong doi" $ do
      let targets = validNightTargets game8 "1" WolfTarget

      targets `shouldBe` ["3", "4", "5", "6", "7", "8"]

    it "Co dung 2 Soi con song" $
      livingWolves game8 `shouldBe` ["1", "2"]

    it "Hai Soi cung can mot nguoi thi nguoi do chet" $ do
      let state = withActions game8
            [("1", WolfTarget "7"), ("2", WolfTarget "7")]
      wolfVotingComplete state `shouldBe` True
      wolfTally state `shouldBe` [("7", 2)]
      wolfVictim state `shouldBe` Just "7"
      nightDeaths state `shouldBe` ["7"]

    it "Hai Soi chia phieu 1-1 thi khong ai bi can" $ do
      let state = withActions game8
            [("1", WolfTarget "7"), ("2", WolfTarget "8")]
      wolfVictim state `shouldBe` Nothing
      nightDeaths state `shouldBe` []

    it "Khong co phieu thi khong co nan nhan" $ do
      wolfVictim game8 `shouldBe` Nothing
      nightDeaths game8 `shouldBe` []

    it "Chi mot Soi bo phieu thi chua du phieu" $ do
      let state = withActions game8 [("1", WolfTarget "7")]
      wolfVotingComplete state `shouldBe` False

    it "Soi khong duoc chon dong doi" $
      nightActionPrivateEvents game8 "1" (WolfTarget "2")
        `shouldBe` Left InvalidTarget

  describe "T05 - Van 8 nguoi: Tien Tri" $ do

    -- Tien Tri duoc soi nguoi song khac, khong duoc soi chinh minh.
    it "validNightTargets - Tien Tri khong duoc tu soi" $ do
      let targets = validNightTargets game8 "3" SeerTarget

      targets `shouldBe` ["1", "2", "4", "5", "6", "7", "8"]

    it "Tien Tri soi Soi nhan Wolves" $
      seerInspection game8 "3" "1" `shouldBe` Right Wolves

    it "Tien Tri soi Dan nhan Village" $
      seerInspection game8 "3" "7" `shouldBe` Right Village

    it "Tien Tri khong duoc tu soi" $
      seerInspection game8 "3" "3" `shouldBe` Left InvalidTarget

    it "Ket qua soi chi duoc gui rieng cho Tien Tri" $ do
      let result = nightActionPrivateEvents game8 "3" (SeerTarget "1")
      result `shouldBe`
        Right [NightActionAccepted "3", SeerResult "3" Wolves]
      fmap (map eventVisibility) result
        `shouldBe` Right [Private "3", Private "3"]

  describe "T05 - Van 8 nguoi: Bao Ve" $ do

    -- Guard duoc tu bao ve, nhung khong duoc lap muc tieu dem truoc.
    it "validNightTargets - Guard khong bao ve lap muc tieu" $ do
      let state = game8 { gameLastProtected = Just "7" }
          targets = validNightTargets state "4" GuardTarget

      -- Guard co the chon chinh minh.
      "4" `shouldSatisfy` (`elem` targets)

      -- Muc tieu da bao ve dem truoc bi loai.
      "7" `shouldNotSatisfy` (`elem` targets)

      -- Van con 7 muc tieu hop le.
      length targets `shouldBe` 7

    it "Bao Ve duoc tu bao ve va chan Soi" $ do
      let state = withActions game8
            [ ("1", WolfTarget "4")
            , ("2", WolfTarget "4")
            , ("4", GuardTarget "4")
            ]
      guardedTarget state `shouldBe` Just "4"
      nightDeaths state `shouldBe` []

    it "Bao Ve cuu duoc Dan bi Soi can" $ do
      let state = withActions game8
            [ ("1", WolfTarget "7")
            , ("2", WolfTarget "7")
            , ("4", GuardTarget "7")
            ]
      nightDeaths state `shouldBe` []

    it "Bao Ve khong duoc bao ve cung muc tieu hai dem lien tiep" $ do
      let state = game8 { gameLastProtected = Just "7" }
      nightActionPrivateEvents state "4" (GuardTarget "7")
        `shouldBe` Left InvalidTarget

    it "Bao Ve khong ngan duoc Poison" $ do
      let state = withActions game8
            [("4", GuardTarget "7"), ("5", WitchPoison "7")]
      nightDeaths state `shouldBe` ["7"]

  describe "T05 - Van 8 nguoi: Phu Thuy" $ do

    -- Witch het binh Poison thi khong con muc tieu hop le.
    it "validNightTargets - Witch het Poison khong co muc tieu" $ do
      let state = game8 { gameWitchPoisonReady = False }
          targets = validNightTargets state "5" WitchPoison

      targets `shouldBe` []

    -- Witch Poison chi duoc chon nguoi song khac ban than.
    it "validNightTargets - Witch Poison chon dung muc tieu" $ do
      let targets = validNightTargets game8 "5" WitchPoison

      targets `shouldBe` ["1", "2", "3", "4", "6", "7", "8"]

    it "Heal cuu nan nhan Soi va tieu hao binh cuu" $ do
      let state = withActions game8
            [ ("1", WolfTarget "7")
            , ("2", WolfTarget "7")
            , ("5", WitchHeal)
            ]
          outcome = resolveNightEffects state
      outcomeDeaths outcome `shouldBe` []
      outcomeHealReadyAfter outcome `shouldBe` False

    it "Poison giet muc tieu va tieu hao binh doc" $ do
      let state = withActions game8 [("5", WitchPoison "8")]
          outcome = resolveNightEffects state
      outcomeDeaths outcome `shouldBe` ["8"]
      outcomePoisonReadyAfter outcome `shouldBe` False

    it "Pass khong tieu hao hai binh thuoc" $ do
      let state = withActions game8 [("5", WitchPass)]
          outcome = resolveNightEffects state
      outcomeHealReadyAfter outcome `shouldBe` True
      outcomePoisonReadyAfter outcome `shouldBe` True

    it "Heal bi tu choi khi Soi chua xac dinh nan nhan" $
      nightActionPrivateEvents game8 "5" WitchHeal
        `shouldBe` Left InvalidNightAction

    it "Phu Thuy khong duoc Poison ban than" $
      nightActionPrivateEvents game8 "5" (WitchPoison "5")
        `shouldBe` Left InvalidTarget

  describe "T05 - Van 9 nguoi: Soi" $ do

    it "Co dung 3 Soi con song" $
      livingWolves game9 `shouldBe` ["1", "2", "3"]

    it "Ba Soi dong long can mot Dan" $ do
      let state = withActions game9
            [ ("1", WolfTarget "8")
            , ("2", WolfTarget "8")
            , ("3", WolfTarget "8")
            ]
      wolfVotingComplete state `shouldBe` True
      wolfTally state `shouldBe` [("8", 3)]
      wolfVictim state `shouldBe` Just "8"
      nightDeaths state `shouldBe` ["8"]

    it "Phieu 2-1 thi muc tieu co 2 phieu bi can" $ do
      let state = withActions game9
            [ ("1", WolfTarget "8")
            , ("2", WolfTarget "8")
            , ("3", WolfTarget "9")
            ]
      wolfTally state `shouldBe` [("8", 2), ("9", 1)]
      wolfVictim state `shouldBe` Just "8"
      nightDeaths state `shouldBe` ["8"]

    it "Phieu 1-1-1 thi hoa, khong ai bi can" $ do
      let state = withActions game9
            [ ("1", WolfTarget "7")
            , ("2", WolfTarget "8")
            , ("3", WolfTarget "9")
            ]
      wolfVictim state `shouldBe` Nothing
      nightDeaths state `shouldBe` []

    it "Mot Soi chet thi chi can hai Soi con lai bo phieu" $ do
      let state = withActions (withDeadPlayer game9 "3")
            [("1", WolfTarget "8"), ("2", WolfTarget "8")]
      livingWolves state `shouldBe` ["1", "2"]
      wolfVotingComplete state `shouldBe` True
      wolfVictim state `shouldBe` Just "8"

    it "Soi khong duoc chon Soi cung phe" $
      nightActionPrivateEvents game9 "1" (WolfTarget "3")
        `shouldBe` Left InvalidTarget

  describe "T05 - Van 9 nguoi: Tien Tri" $ do

    it "Tien Tri soi Soi nhan Wolves" $
      seerInspection game9 "4" "3" `shouldBe` Right Wolves

    it "Tien Tri soi Bao Ve nhan Village" $
      seerInspection game9 "4" "5" `shouldBe` Right Village

    it "Tien Tri khong duoc tu soi" $
      seerInspection game9 "4" "4" `shouldBe` Left InvalidTarget

    it "Khong cong khai ket qua soi cua Tien Tri" $ do
      let result = nightActionPrivateEvents game9 "4" (SeerTarget "2")
      fmap (map eventVisibility) result
        `shouldBe` Right [Private "4", Private "4"]

  describe "T05 - Van 9 nguoi: Bao Ve va Phu Thuy" $ do

    it "Bao Ve chan muc tieu bi 3 Soi can" $ do
      let state = withActions game9
            [ ("1", WolfTarget "8")
            , ("2", WolfTarget "8")
            , ("3", WolfTarget "8")
            , ("5", GuardTarget "8")
            ]
      nightDeaths state `shouldBe` []

    it "Witch Heal cuu muc tieu bi 2 tren 3 Soi chon" $ do
      let state = withActions game9
            [ ("1", WolfTarget "8")
            , ("2", WolfTarget "8")
            , ("3", WolfTarget "9")
            , ("6", WitchHeal)
            ]
      nightDeaths state `shouldBe` []
      outcomeHealReadyAfter (resolveNightEffects state)
        `shouldBe` False

    it "Guard khong cuu duoc nguoi bi Witch Poison" $ do
      let state = withActions game9
            [("5", GuardTarget "9"), ("6", WitchPoison "9")]
      nightDeaths state `shouldBe` ["9"]

    it "Soi can mot nguoi va Witch Poison nguoi khac thi ca hai chet" $ do
      let state = withActions game9
            [ ("1", WolfTarget "8")
            , ("2", WolfTarget "8")
            , ("3", WolfTarget "8")
            , ("6", WitchPoison "9")
            ]
      nightDeaths state `shouldBe` ["8", "9"]

    it "Bao Ve chan Soi nhung Poison van co hieu luc" $ do
      let state = withActions game9
            [ ("1", WolfTarget "8")
            , ("2", WolfTarget "8")
            , ("3", WolfTarget "8")
            , ("5", GuardTarget "8")
            , ("6", WitchPoison "8")
            ]
      nightDeaths state `shouldBe` ["8"]

    it "Witch Pass giu nguyen thuoc" $ do
      let state = withActions game9 [("6", WitchPass)]
          outcome = resolveNightEffects state
      outcomeHealReadyAfter outcome `shouldBe` True
      outcomePoisonReadyAfter outcome `shouldBe` True

  describe "T05 - Kiem tra loi cho ca 8 va 9 nguoi" $ do

    -- Khong cho chon muc tieu Night khi dang o Day.
    it "validNightTargets - Sai Phase khong co muc tieu" $ do
      let state = game8 { gamePhase = Day }
          targets = validNightTargets state "1" WolfTarget

      targets `shouldBe` []

    -- Soi da bo phieu thi khong duoc chon lai trong cung dem.
    it "validNightTargets - Da dung luot khong co muc tieu" $ do
      let state = withActions game8 [("1", WolfTarget "7")]
          targets = validNightTargets state "1" WolfTarget

      targets `shouldBe` []

    -- Soi da chet khong duoc chon bat ky muc tieu nao.
    it "validNightTargets - Soi chet khong co muc tieu" $ do
      let state = withDeadPlayer game9 "1"
          targets = validNightTargets state "1" WolfTarget

      targets `shouldBe` []

    it "Van 8: sai Phase bi tu choi" $ do
      let state = game8 { gamePhase = Day }
      nightActionPrivateEvents state "1" (WolfTarget "7")
        `shouldBe` Left WrongPhase

    it "Van 9: sai Phase bi tu choi" $ do
      let state = game9 { gamePhase = Voting }
      nightActionPrivateEvents state "1" (WolfTarget "8")
        `shouldBe` Left WrongPhase

    it "Van 8: Soi chet khong duoc hanh dong" $
      nightActionPrivateEvents
        (withDeadPlayer game8 "1") "1" (WolfTarget "7")
        `shouldBe` Left DeadPlayer

    it "Van 9: Soi chet khong duoc hanh dong" $
      nightActionPrivateEvents
        (withDeadPlayer game9 "1") "1" (WolfTarget "8")
        `shouldBe` Left DeadPlayer

    it "Van 8: muc tieu khong ton tai bi tu choi" $
      nightActionPrivateEvents game8 "1" (WolfTarget "99")
        `shouldBe` Left PlayerNotFound

    it "Van 9: muc tieu khong ton tai bi tu choi" $
      nightActionPrivateEvents game9 "1" (WolfTarget "99")
        `shouldBe` Left PlayerNotFound

    it "Van 9: khong duoc gui hai hanh dong trong mot dem" $ do
      let state = withActions game9 [("1", WolfTarget "8")]
      nightActionPrivateEvents state "1" (WolfTarget "9")
        `shouldBe` Left DuplicateNightAction

  describe "T05 - Property Tests cho 8 va 9 nguoi" $ do

    prop "Wrong Phase luon tu choi NightAction" $
      \(Positive n) ->
        let game = if even (n :: Int) then game8 else game9
            target = if even n then "7" else "8"
            state = game { gamePhase = Day }
        in nightActionPrivateEvents state "1" (WolfTarget target)
             == Left WrongPhase

    prop "Soi da chet khong the gui NightAction" $
      \(Positive n) ->
        let game = if even (n :: Int) then game8 else game9
            target = if even n then "7" else "8"
        in nightActionPrivateEvents
             (withDeadPlayer game "1") "1" (WolfTarget target)
             == Left DeadPlayer

    prop "Soi khong duoc chon dong doi" $
      \(Positive n) ->
        let game = if even (n :: Int) then game8 else game9
        in nightActionPrivateEvents game "1" (WolfTarget "2")
             == Left InvalidTarget

    prop "Cung cac phieu Soi thi ket qua khong phu thuoc thu tu phieu" $
      \(Positive n) ->
        let game = if even (n :: Int) then game8 else game9
            votes =
              if even n
                then
                  [ ("1", WolfTarget "7")
                  , ("2", WolfTarget "8")
                  ]
                else
                  [ ("1", WolfTarget "8")
                  , ("2", WolfTarget "8")
                  , ("3", WolfTarget "9")
                  ]
        in wolfVictim (withActions game votes)
             == wolfVictim (withActions game (reverse votes))

  describe "T05 - Engine NightAction 8 nguoi" $ do
    it "Soi gui action hop le va cap nhat tien do bo phieu" $ do
      case submitNightAction game8 "1" (WolfTarget "7") of
        Left err -> expectationFailure (show err)
        Right (state, events) -> do
          gameNightActions state `shouldBe` [("1", WolfTarget "7")]

          events `shouldBe`
            [ NightActionAccepted "1"
            , WolfVoteUpdated 1 2
            ]

          map eventVisibility events `shouldBe`
            [ Private "1"
            , TeamOnly Wolves
            ]
    it "Tien Tri soi Soi va nhan ket qua rieng" $ do
      case submitNightAction game8 "3" (SeerTarget "1") of
        Left err -> expectationFailure (show err)
        Right (state, events) -> do
          gameNightActions state `shouldBe` [("3", SeerTarget "1")]
          events `shouldBe`
            [NightActionAccepted "3", SeerResult "3" Wolves]
          map eventVisibility events
            `shouldBe` [Private "3", Private "3"]

    it "Bao Ve gui action va khong cong khai muc tieu" $ do
      case submitNightAction game8 "4" (GuardTarget "7") of
        Left err -> expectationFailure (show err)
        Right (state, events) -> do
          gameNightActions state `shouldBe` [("4", GuardTarget "7")]
          events `shouldBe` [NightActionAccepted "4"]
          map eventVisibility events `shouldBe` [Private "4"]

    it "Phu Thuy Poison va khong cong khai muc tieu" $ do
      case submitNightAction game8 "5" (WitchPoison "7") of
        Left err -> expectationFailure (show err)
        Right (state, events) -> do
          gameNightActions state `shouldBe` [("5", WitchPoison "7")]
          events `shouldBe` [NightActionAccepted "5"]
          map eventVisibility events `shouldBe` [Private "5"]

    it "Phu Thuy Pass duoc luu va khong mat Potion" $ do
      case submitNightAction game8 "5" WitchPass of
        Left err -> expectationFailure (show err)
        Right (state, events) -> do
          gameNightActions state `shouldBe` [("5", WitchPass)]
          gameWitchHealReady state `shouldBe` True
          gameWitchPoisonReady state `shouldBe` True
          events `shouldBe` [NightActionAccepted "5"]

  describe "T05 - Engine NightAction 9 nguoi" $ do

    it "Ba Soi gui action va duoc luu day du" $ do
      let result = do
            (s1, _) <- submitNightAction game9 "1" (WolfTarget "8")
            (s2, _) <- submitNightAction s1 "2" (WolfTarget "8")
            submitNightAction s2 "3" (WolfTarget "9")
      case result of
        Left err -> expectationFailure (show err)
        Right (state, events) -> do
          gameNightActions state `shouldBe`
            [ ("1", WolfTarget "8")
            , ("2", WolfTarget "8")
            , ("3", WolfTarget "9")
            ]
          wolfVictim state `shouldBe` Just "8"
          events `shouldBe`
            [ NightActionAccepted "3"
            , WolfVoteUpdated 3 3
            ]

          map eventVisibility events `shouldBe`
            [ Private "3"
            , TeamOnly Wolves
            ]

    it "Tien Tri van 9 nguoi soi dung Team" $ do
      case submitNightAction game9 "4" (SeerTarget "2") of
        Left err -> expectationFailure (show err)
        Right (_, events) -> do
          events `shouldBe`
            [NightActionAccepted "4", SeerResult "4" Wolves]
          map eventVisibility events
            `shouldBe` [Private "4", Private "4"]

    it "Bao Ve va Phu Thuy gui action doc lap" $ do
      let result = do
            (s1, _) <- submitNightAction game9 "5" (GuardTarget "8")
            submitNightAction s1 "6" (WitchPoison "9")
      case result of
        Left err -> expectationFailure (show err)
        Right (state, _) ->
          gameNightActions state `shouldBe`
            [("5", GuardTarget "8"), ("6", WitchPoison "9")]

  describe "T05 - Engine Validation va Command" $ do

    -- Hanh dong khong hop le khong duoc cap nhat phieu hoac phat event.
    it "WolfVoteUpdated - Khong phat event khi Soi chon dong doi" $ do
      let result = submitNightAction game8 "1" (WolfTarget "2")

      result `shouldBe` Left InvalidTarget

    it "Sai Phase bi tu choi" $ do
      let state = game8 { gamePhase = Day }
      submitNightAction state "1" (WolfTarget "7")
        `shouldBe` Left WrongPhase

    it "Nguoi chet khong duoc gui action" $
      submitNightAction
        (withDeadPlayer game9 "1") "1" (WolfTarget "8")
        `shouldBe` Left DeadPlayer

    it "Soi khong duoc chon dong doi" $
      submitNightAction game8 "1" (WolfTarget "2")
        `shouldBe` Left InvalidTarget

    it "Sai Role bi tu choi" $
      submitNightAction game8 "7" (SeerTarget "1")
        `shouldBe` Left InvalidNightAction

    it "Khong duoc gui hai action trong cung dem" $ do
      let result = do
            (state, _) <- submitNightAction game8 "1" (WolfTarget "7")
            submitNightAction state "1" (WolfTarget "8")
      result `shouldBe` Left DuplicateNightAction

    it "Command NightAction duoc dispatcher xu ly" $ do
      let command = NightAction "1" (WolfTarget "7")
      applyNightCommand game8 command
        `shouldBe` submitNightAction game8 "1" (WolfTarget "7")

    it "Dispatcher tu choi command khong thuoc Night" $
      applyNightCommand game8 AdvancePhase
        `shouldBe` Left InvalidCommand

    it "Cung State va Command cho cung ket qua" $ do
      let command = NightAction "3" (SeerTarget "1")
      applyNightCommand game8 command
        `shouldBe` applyNightCommand game8 command

  describe "T05 - ResolveNight 8 va 9 nguoi" $ do

    it "Van 8: Soi can Dan, Dan chet va action duoc xoa" $ do
      let state = withActions game8
            [("1", WolfTarget "7"), ("2", WolfTarget "7")]
      case resolveNightTurn state of
        Left err -> expectationFailure (show err)
        Right (next, events) -> do
          playerLifeStatus (gamePlayers next !! 6) `shouldBe` Dead
          gameNightActions next `shouldBe` []
          gameNightResolved next `shouldBe` True
          gamePhase next `shouldBe` Night
          gamePendingReveals next `shouldBe` ["7"]
          events `shouldBe` [NightResolved ["7"]]

    it "Van 8: Bao Ve chan Soi, khong co nguoi chet" $ do
      let state = withActions game8
            [ ("1", WolfTarget "7")
            , ("2", WolfTarget "7")
            , ("4", GuardTarget "7")
            ]
      case resolveNightTurn state of
        Left err -> expectationFailure (show err)
        Right (next, events) -> do
          gamePendingReveals next `shouldBe` []
          gameLastProtected next `shouldBe` Just "7"
          events `shouldBe` [NightResolved []]

    it "Van 8: Chua du phieu Soi thi khong duoc resolve" $ do
      let state = withActions game8 [("1", WolfTarget "7")]
      resolveNightTurn state `shouldBe` Left InvalidGameState

    it "Van 9: Witch Poison giet Hunter, cho Hunter ban" $ do
      let state = withActions game9
            [ ("1", WolfTarget "8")
            , ("2", WolfTarget "8")
            , ("3", WolfTarget "8")
            , ("6", WitchPoison "7")
            ]
      case resolveNightTurn state of
        Left err -> expectationFailure (show err)
        Right (next, events) -> do
          gamePendingHunter next `shouldBe` Just "7"
          gamePendingReveals next `shouldBe` ["8", "7"]
          gameWitchPoisonReady next `shouldBe` False
          gamePhase next `shouldBe` Night
          events `shouldBe`
            [NightResolved ["8", "7"], HunterShotPending "7"]
          map eventVisibility events
            `shouldBe` [Public, Private "7"]

    it "Van 9: Witch Heal cuu nan nhan va mat binh cuu" $ do
      let state = withActions game9
            [ ("1", WolfTarget "8")
            , ("2", WolfTarget "8")
            , ("3", WolfTarget "9")
            , ("6", WitchHeal)
            ]
      case resolveNightTurn state of
        Left err -> expectationFailure (show err)
        Right (next, _) -> do
          gamePendingReveals next `shouldBe` []
          gameWitchHealReady next `shouldBe` False

    it "ResolveNight khong duoc chay hai lan" $ do
      let state = withActions game8
            [("1", WolfTarget "7"), ("2", WolfTarget "7")]
      case resolveNightTurn state of
        Left err -> expectationFailure (show err)
        Right (next, _) ->
          resolveNightTurn next `shouldBe` Left InvalidGameState

    it "Command ResolveNight duoc dispatcher xu ly" $ do
      let state = withActions game8
            [("1", WolfTarget "7"), ("2", WolfTarget "7")]
      applyNightCommand state ResolveNight
        `shouldBe` resolveNightTurn state

  describe "T05 - Wolf Voting Lock va Witch Notice" $ do

    -- Moi lan khoa phieu hop le chi tao mot WolfTargetLocked.
    it "WolfTargetLocked - Chi phat mot lan khi khoa phieu" $ do
      let state = withActions game8
            [ ("1", WolfTarget "7")
            , ("2", WolfTarget "7")
            ]

      case closeWolfVoting state False of
        Left err ->
          expectationFailure (show err)

        Right (lockedState, events) -> do
          let lockedEvents =
                [ target
                | WolfTargetLocked target <- events
                ]

          lockedEvents `shouldBe` [Just "7"]

          closeWolfVoting lockedState False
            `shouldBe` Left InvalidGameState

    it "Van 8: khoa phieu Soi khi du 2 phieu" $ do
      let state = withActions game8
            [("1", WolfTarget "7"), ("2", WolfTarget "7")]
      case closeWolfVoting state False of
        Left err -> expectationFailure (show err)
        Right (next, events) -> do
          gameWolfVotingClosed next `shouldBe` True
          events `shouldBe`
            [ WolfTargetLocked (Just "7")
            , WitchVictimNotice "5" (Just "7")
            ]

          map eventVisibility events `shouldBe`
            [ TeamOnly Wolves
            , Private "5"
            ]

    it "Van 8: khong khoa som khi moi co 1 phieu" $ do
      let state = withActions game8 [("1", WolfTarget "7")]
      closeWolfVoting state False `shouldBe` Left InvalidGameState

    it "Van 8: khoa do het gio khi thieu phieu" $ do
      let state = withActions game8 [("1", WolfTarget "7")]
      case closeWolfVoting state True of
        Left err -> expectationFailure (show err)
        Right (next, events) -> do
          gameWolfVotingClosed next `shouldBe` True
          events `shouldBe`
            [ WolfTargetLocked (Just "7")
            , WitchVictimNotice "5" (Just "7")
            ]

          map eventVisibility events `shouldBe`
            [ TeamOnly Wolves
            , Private "5"
            ]

    it "Van 8: Soi khong duoc bo phieu sau khi khoa" $ do
      let state = game8 { gameWolfVotingClosed = True }
      submitNightAction state "1" (WolfTarget "7")
        `shouldBe` Left InvalidNightAction

    it "Van 8: Soi hoa 1-1 thi Witch nhan Nothing" $ do
      let state = withActions game8
            [("1", WolfTarget "7"), ("2", WolfTarget "8")]

      case closeWolfVoting state False of
        Left err -> expectationFailure (show err)

        Right (_, events) -> do
          events `shouldBe`
            [ WolfTargetLocked Nothing
            , WitchVictimNotice "5" Nothing
            ]

          map eventVisibility events `shouldBe`
            [ TeamOnly Wolves
            , Private "5"
            ]

    it "Van 9: khoa phieu 2-1 va thong bao dung nan nhan" $ do
      let state = withActions game9
            [ ("1", WolfTarget "8")
            , ("2", WolfTarget "8")
            , ("3", WolfTarget "9")
            ]
      case closeWolfVoting state False of
        Left err -> expectationFailure (show err)
        Right (_, events) -> do
          events `shouldBe`
            [ WolfTargetLocked (Just "8")
            , WitchVictimNotice "6" (Just "8")
            ]

          map eventVisibility events `shouldBe`
            [ TeamOnly Wolves
            , Private "6"
            ]

    it "Van 9: khoa luot hai lan bi tu choi" $ do
      let state = withActions game9
            [ ("1", WolfTarget "8")
            , ("2", WolfTarget "8")
            , ("3", WolfTarget "9")
            ]
      case closeWolfVoting state False of
        Left err -> expectationFailure (show err)
        Right (next, _) ->
          closeWolfVoting next False `shouldBe` Left InvalidGameState

    it "Van 9: Witch Heal chi duoc gui sau khi khoa" $ do
      let state = withActions game9
            [ ("1", WolfTarget "8")
            , ("2", WolfTarget "8")
            , ("3", WolfTarget "8")
            ]
      submitNightAction state "6" WitchHeal
        `shouldBe` Left InvalidNightAction

      case closeWolfVoting state False of
        Left err -> expectationFailure (show err)
        Right (next, _) ->
          case submitNightAction next "6" WitchHeal of
            Left err -> expectationFailure (show err)
            Right (finalState, _) ->
              gameNightActions finalState
                `shouldSatisfy` elem ("6", WitchHeal)

  describe "T05 - Complete Night va Win Condition" $ do

    it "Van 8: thong bao Dan chet khong lo Role va chuyen sang Day" $ do
      let state = withActions game8
            [("1", WolfTarget "7"), ("2", WolfTarget "7")]

      case resolveNightTurn state >>= (completeNightTurn . fst) of
        Left err -> expectationFailure (show err)
        Right (next, events) -> do
          gamePhase next `shouldBe` Day
          gamePendingReveals next `shouldBe` []
          events `shouldBe`
            [ PlayerDied "7"
            , PhaseChanged Day
            ]


    it "Van 8: khong co nguoi chet thi chuyen Day" $ do
      let state = withActions game8
            [("1", WolfTarget "7"), ("2", WolfTarget "8")]

      case resolveNightTurn state >>= (completeNightTurn . fst) of
        Left err -> expectationFailure (show err)
        Right (next, events) -> do
          gamePhase next `shouldBe` Day
          events `shouldBe` [PhaseChanged Day]

    it "Van 9: Hunter pending thi khong duoc ket thuc Night" $ do
      let state = withActions game9
            [ ("1", WolfTarget "8")
            , ("2", WolfTarget "8")
            , ("3", WolfTarget "8")
            , ("6", WitchPoison "7")
            ]

      case resolveNightTurn state of
        Left err -> expectationFailure (show err)
        Right (next, _) ->
          completeNightTurn next `shouldBe` Left HunterNotPending

    it "Het Soi thi Village thang" $ do
      let state = withDeadPlayer
            (withDeadPlayer game8 "1") "2"
      nightGameResult state `shouldBe` Just (Winner Village)

    it "So Soi bang so Dan thi Wolves thang" $ do
      let state = foldl withDeadPlayer game8 ["3", "4", "5", "6"]
      nightGameResult state `shouldBe` Just (Winner Wolves)

    it "Tat ca chet thi Draw uu tien" $ do
      let state =
            foldl withDeadPlayer game8
              (map playerId (gamePlayers game8))
      nightGameResult state `shouldBe` Just Draw

    it "Chua resolve Night thi khong duoc complete" $
      completeNightTurn game8
        `shouldBe` Left InvalidGameState
