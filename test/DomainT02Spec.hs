
-- | Bo kiem thu Task T02 - Domain Types va Validation.
--
-- Pham vi:
-- - Smart Constructor
-- - Validation
-- - Role Preset
-- - GameState Invariant
-- - Event Visibility
-- - Appearance Validation
-- - JoinWithAppearance
-- - Property Testing
--
-- Khong thay doi logic T03/T06.
-- Cac ham kiem thu su dung Hspec va QuickCheck.

module DomainT02Spec (spec) where

import Domain.Types
import Domain.Validation
import Domain.Engine
  ( applyLobbyCommand
  , finishResolvedNight
  )

import Test.Hspec
import Test.QuickCheck

-- Tao Player mau de su dung trong Unit Test.
-- Player da Ready nhung chua duoc phan Role.
player :: Int -> Player
player i =
  Player
    ("p" ++ show i)
    ("Ten " ++ show i)
    Nothing
    True
    Alive
    defaultAppearance

-- Tao Lobby gom 8 nguoi choi.
-- p1 la Host, tat ca Player deu Ready.
lobby8 :: GameState
lobby8 =
  emptyLobby
    { gamePlayers = map player [1..8]
    , gameHost = "p1"
    , gameConfiguredRoles =
        maybe [] id (expectedRoles 8)
    }

-- Tao GameState da bat dau.
-- Role duoc gan theo preset 8 nguoi.
-- Ham nay chi dung de tao du lieu kiem thu.
started8 :: GameState
started8 =
  lobby8
    { gamePlayers =
        zipWith
          (\p role -> p { playerRole = Just role })
          (gamePlayers lobby8)
          (maybe [] id (expectedRoles 8))
    , gamePhase = Night
    , gameDay = 1
    }

-- Appearance tuy chinh hop le theo preset T07.
customAppearance :: Appearance
customAppearance =
  Appearance
    "ponytail"
    "#8B5CF6"
    "#C28865"
    "#064E3B"
    "flower_crown"

-- Ham spec chua toan bo Unit Test va Property Test.
-- T02Main.hs se goi ham nay bang hspec.
spec :: Spec
spec = do

  describe "T02 - ChatChannel Validation" $ do

    it "C01 - Alive duoc chat PublicDay trong Day" $ do
      let state = started8 { gamePhase = Day }
      validateChatInChannel state "p7" PublicDay "Xin chao"
        `shouldBe` Right ()

    it "C02 - Werewolf duoc chat WolvesNight trong Night" $ do
      validateChatInChannel started8 "p1" WolvesNight "Chon p7"
        `shouldBe` Right ()

    it "C03 - Villager khong duoc chat WolvesNight" $ do
      validateChatInChannel started8 "p7" WolvesNight "Xin chao"
        `shouldBe` Left InvalidRole

    it "C04 - WolvesNight khong duoc chat trong Day" $ do
      let state = started8 { gamePhase = Day }
      validateChatInChannel state "p1" WolvesNight "Chon p7"
        `shouldBe` Left WrongPhase

    it "C05 - PublicDay khong duoc chat trong Night" $ do
      validateChatInChannel started8 "p7" PublicDay "Xin chao"
        `shouldBe` Left WrongPhase

    it "C06 - Chat rong bi tu choi" $ do
      validateChatInChannel started8 "p1" WolvesNight "   "
        `shouldBe` Left EmptyChat

    it "C07 - Soi da chet khong duoc chat" $ do
      let state = started8
            { gamePlayers =
                [ if playerId p == "p1"
                    then p { playerLifeStatus = Dead }
                    else p
                | p <- gamePlayers started8
                ]
            }

      validateChatInChannel state "p1" WolvesNight "Xin chao"
        `shouldBe` Left DeadPlayer

  describe "T02 - Smart Constructor" $ do

    it "U01 - Tao Player mac dinh hop le" $
      mkPlayer "a" "Alice"
        `shouldBe`
          Right
            (Player "a" "Alice" Nothing False Alive defaultAppearance)

    it "U02 - Tu choi PlayerId rong" $
      mkPlayer "   " "Alice"
        `shouldBe` Left InvalidPlayerId

    it "U03 - Tu choi ten rong" $
      mkPlayer "a" "  "
        `shouldBe` Left InvalidPlayerName

    it "U04 - Chuan hoa khoang trang trong ten" $
      mkPlayer "a" "  Van   Nguyen "
        `shouldBe`
          Right
            (Player "a" "Van Nguyen" Nothing False Alive defaultAppearance)

  describe "T02 - Validation dinh danh" $ do

    it "U05 - Tu choi PlayerId trung" $
      validateUniquePlayerIds
        [player 1, player 1]
        `shouldBe` Left DuplicatePlayerId

    it "U06 - Tu choi ten trung du khac khoang trang" $
      validateUniquePlayerNames
        [ Player "a" "Van" Nothing False Alive defaultAppearance
        , Player "b" " Van " Nothing False Alive defaultAppearance
        ]
        `shouldBe` Left DuplicatePlayerName

    it "U07 - Tu choi ten trung du khac hoa thuong" $
      validateUniquePlayerNames
        [ Player "a" "Van" Nothing False Alive defaultAppearance
        , Player "b" "vAn" Nothing False Alive defaultAppearance
        ]
        `shouldBe` Left DuplicatePlayerName

  describe "T02 - Role Preset" $ do

    it "U08 - Preset 8 nguoi co dung 2 Soi" $
      fmap
        (length . filter (== Werewolf))
        (expectedRoles 8)
        `shouldBe` Just 2

    it "U09 - Preset 9 nguoi co dung 3 Soi" $
      fmap
        (length . filter (== Werewolf))
        (expectedRoles 9)
        `shouldBe` Just 3

    it "U10 - Preset khong phu thuoc thu tu Role" $
      validateRolePreset
        8
        (reverse (maybe [] id (expectedRoles 8)))
        `shouldBe` Right ()

    it "U11 - Tu choi preset 8 nguoi co 3 Soi" $
      validateRolePreset
        8
        [ Werewolf, Werewolf, Werewolf
        , Seer, Guard, Witch, Hunter, Villager
        ]
        `shouldBe` Left InvalidRoleConfiguration

  describe "T02 - Validation StartGame" $ do

    it "U12 - Nguoi khong phai Host khong duoc Start" $
      validateStartGame "p2" lobby8
        `shouldBe` Left NotAuthorized

    it "U13 - Host duoc Start khi du dieu kien" $
      validateStartGame "p1" lobby8
        `shouldBe` Right ()

    it "U14 - Tu choi Start khi chua Ready het" $
      let
        players = gamePlayers lobby8

        notReady =
          (head players) { playerReady = False }
          : tail players
      in
        validateStartGame
          "p1"
          (lobby8 { gamePlayers = notReady })
          `shouldBe` Left NotAllReady

  describe "T02 - Validation cho T03" $ do

    it "U15 - Join voi PlayerId trung bi tu choi" $
      validateJoin lobby8 "p1" "New"
        `shouldBe` Left DuplicatePlayerId

    it "U16 - Join voi ten trung bi tu choi" $
      validateJoin lobby8 "p9" " ten 1 "
        `shouldBe` Left DuplicatePlayerName

    it "U17 - Join khi phong co 9 nguoi bi tu choi" $
      validateJoin
        (lobby8 { gamePlayers = map player [1..9] })
        "p10"
        "New"
        `shouldBe` Left RoomFull

  describe "T02 - GameState Invariant" $ do

    it "U18 - Lobby rong la trang thai hop le" $
      validateGameInvariant emptyLobby
        `shouldBe` Right ()

    it "U19 - Host khong ton tai bi tu choi" $
      validateGameInvariant
        (lobby8 { gameHost = "missing" })
        `shouldBe` Left InvalidGameState

    it "U20 - Khong chap nhan LowestPlayerId" $
      validateGameInvariant
        (lobby8 { gameVoteTiePolicy = LowestPlayerId })
        `shouldBe` Left InvalidTiePolicy

    it "U21 - GameOver bat buoc co GameResult" $
      validateGameInvariant
        (started8 { gamePhase = GameOver })
        `shouldBe` Left InvalidGameState

  describe "T02 - Event Visibility" $ do

    it "U22 - SeerResult la Private" $
      eventVisibility
        (SeerResult "p3" Wolves)
        `shouldBe` Private "p3"

    -- Khi chet chi cong khai PlayerId, khong tiet lo Role.
    it "U23 - PlayerDied la Public" $
      eventVisibility
        (PlayerDied "p3")
        `shouldBe` Public

    -- Chi cong khai danh sach Role khi GameOver.
    it "U23b - GameRolesRevealed la Public" $
      eventVisibility
        (GameRolesRevealed [("p3", Seer)])
        `shouldBe` Public
    -- Chua GameOver thi khong duoc cong khai Role.
    it "U23c - Night sang Day khong reveal Role" $ do
      let resolvedState =
            started8 { gameNightResolved = True }

      case finishResolvedNight resolvedState Nothing of
        Left err ->
          expectationFailure (show err)

        Right (newState, events) -> do
          gamePhase newState `shouldBe` Day

          let revealedRoles =
                [ roles | GameRolesRevealed roles <- events ]

          revealedRoles `shouldBe` []

    -- GameOver phai cong khai day du Role cua 8 Player.
    it "U23d - GameOver reveal du 8 Role" $ do
      let resolvedState =
            started8 { gameNightResolved = True }

      case finishResolvedNight resolvedState (Just (Winner Village)) of
        Left err ->
          expectationFailure (show err)
        Right (newState, events) -> do
          gamePhase newState `shouldBe` GameOver

          let expectedRolesList =
                [ (playerId p, role)
                | p <- gamePlayers newState
                , Just role <- [playerRole p]
                ]

          let revealedRoles =
                [ roles | GameRolesRevealed roles <- events ]

          revealedRoles `shouldBe` [expectedRolesList]

          length expectedRolesList `shouldBe` 8

    -- GameOver roi thi khong duoc reveal them lan nua.
    it "U23e - Khong reveal Role lap lai" $ do
      let resolvedState =
            started8 { gameNightResolved = True }

      case finishResolvedNight resolvedState (Just (Winner Village)) of
        Left err ->
          expectationFailure (show err)

        Right (endedState, _) ->
          finishResolvedNight endedState (Just (Winner Village))
            `shouldBe` Left GameAlreadyOver

  describe "T02 - Night Action Validation" $ do

    it "U24 - Seer khong duoc soi chinh minh" $
      validateNightAction
        started8
        "p3"
        (SeerTarget "p3")
        `shouldBe` Left InvalidTarget

    it "U25 - Guard duoc tu bao ve" $
      validateNightAction
        started8
        "p4"
        (GuardTarget "p4")
        `shouldBe` Right ()

    it "U26 - Guard khong bao ve lap muc tieu" $
      validateNightAction
        (started8 { gameLastProtected = Just "p4" })
        "p4"
        (GuardTarget "p4")
        `shouldBe` Left InvalidTarget

    it "U27 - Witch khong duoc Poison chinh minh" $
      validateNightAction
        started8
        "p5"
        (WitchPoison "p5")
        `shouldBe` Left InvalidTarget

    it "U28 - Witch Heal khong co nan nhan bi tu choi" $
      validateNightAction
        started8
        "p5"
        WitchHeal
        `shouldBe` Left InvalidNightAction

  describe "T02 - Vote va Chat Validation" $ do

    it "U29 - Mot Player khong duoc Vote hai lan" $
      validateVote
        (started8
          { gamePhase = Voting
          , gameVotes = [("p3", "p1")]
          })
        "p3"
        "p2"
        `shouldBe` Left AlreadyVoted

    it "U30 - Chat chi co khoang trang bi tu choi" $
      validateChat
        (started8 { gamePhase = Day })
        "p3"
        "  \n  "
        `shouldBe` Left EmptyChat

    it "U31 - NightActionAccepted la Private" $
      eventVisibility (NightActionAccepted "p1")
        `shouldBe` Private "p1"

    it "U32 - VoteUpdated la Private" $
      eventVisibility (VoteUpdated "p2" "p5")
        `shouldBe` Private "p2"

    it "U33 - HunterShotPending la Private" $
      eventVisibility (HunterShotPending "p6")
        `shouldBe` Private "p6"

    it "U34 - PhaseChanged la Public" $
      eventVisibility (PhaseChanged Day)
        `shouldBe` Public

  describe "T02 - Appearance Validation (T07)" $ do

    it "A01 - Appearance mac dinh hop le" $
      validateAppearance defaultAppearance
        `shouldBe` Right defaultAppearance

    it "A02 - Appearance tuy chinh hop le" $
      validateAppearance customAppearance
        `shouldBe` Right customAppearance

    it "A03 - Tat ca kieu toc cua T07 hop le" $
      let
        hairs =
          ["messy", "spiky", "curly", "bob", "long", "ponytail"]

        appearances =
          [ defaultAppearance { appearanceHair = hair }
          | hair <- hairs
          ]
      in
        map validateAppearance appearances
          `shouldBe` map Right appearances

    it "A04 - Tu choi kieu toc khong hop le" $
      validateAppearance
        (defaultAppearance { appearanceHair = "unknown" })
        `shouldBe` Left InvalidAppearance

    it "A05 - Tu choi mau toc ngoai danh sach" $
      validateAppearance
        (defaultAppearance { appearanceHairColor = "#ABCDEF" })
        `shouldBe` Left InvalidAppearance

    it "A06 - Tu choi mau da ngoai danh sach" $
      validateAppearance
        (defaultAppearance { appearanceSkin = "#ABCDEF" })
        `shouldBe` Left InvalidAppearance

    it "A07 - Tu choi mau trang phuc ngoai danh sach" $
      validateAppearance
        (defaultAppearance { appearanceOutfit = "#ABCDEF" })
        `shouldBe` Left InvalidAppearance

    it "A08 - Tu choi phu kien ngoai danh sach" $
      validateAppearance
        (defaultAppearance { appearanceAccessory = "unknown" })
        `shouldBe` Left InvalidAppearance

    it "A09 - Tu choi chuoi mau co ky tu SVG" $
      validateAppearance
        (defaultAppearance
          { appearanceHairColor = "\" onload=\"alert(1)" })
        `shouldBe` Left InvalidAppearance

  -- Test moi: Kiem tra JoinWithAppearance trong Pure Engine.
  describe "T02 - JoinWithAppearance" $ do

    it "A10 - Host tao phong voi Appearance tuy chinh" $ do
      let result =
            applyLobbyCommand
              emptyLobby
              (JoinWithAppearance "p1" "Van" customAppearance)

      case result of
        Left err ->
          expectationFailure
            ("Host Join that bai: " ++ show err)

        Right (state, events) -> do
          gameHost state `shouldBe` "p1"
          length (gamePlayers state) `shouldBe` 1
          playerAppearance (head (gamePlayers state))
            `shouldBe` customAppearance
          events `shouldBe` [PlayerJoined "p1"]
          validateGameInvariant state `shouldBe` Right ()

    it "A11 - Nguoi thu hai Join va luu Appearance rieng" $ do
      let hostResult =
            applyLobbyCommand
              emptyLobby
              (Join "p1" "Van")

      case hostResult of
        Left err ->
          expectationFailure
            ("Khong tao duoc Host: " ++ show err)

        Right (hostState, _) ->
          case applyLobbyCommand
            hostState
            (JoinWithAppearance "p2" "Binh" customAppearance) of

            Left err ->
              expectationFailure
                ("Join Appearance that bai: " ++ show err)

            Right (state, events) -> do
              gameHost state `shouldBe` "p1"
              length (gamePlayers state) `shouldBe` 2

              map playerAppearance (gamePlayers state)
                `shouldBe`
                  [defaultAppearance, customAppearance]

              events `shouldBe` [PlayerJoined "p2"]
              validateGameInvariant state `shouldBe` Right ()

    it "A12 - Appearance khong hop le bi tu choi" $ do
      let invalidAppearance =
            defaultAppearance
              { appearanceHair = "unknown" }

          result =
            applyLobbyCommand
              emptyLobby
              (JoinWithAppearance "p1" "Van" invalidAppearance)

      result `shouldBe` Left InvalidAppearance

      -- Pure Engine tra Left, khong tao GameState moi.
      validateGameInvariant emptyLobby `shouldBe` Right ()
      gamePlayers emptyLobby `shouldBe` []

    it "A13 - Join cu van dung Appearance mac dinh" $ do
      let result =
            applyLobbyCommand
              emptyLobby
              (Join "p1" "Van")

      case result of
        Left err ->
          expectationFailure
            ("Join cu that bai: " ++ show err)

        Right (state, events) -> do
          gameHost state `shouldBe` "p1"
          length (gamePlayers state) `shouldBe` 1

          playerAppearance (head (gamePlayers state))
            `shouldBe` defaultAppearance

          events `shouldBe` [PlayerJoined "p1"]
          validateGameInvariant state `shouldBe` Right ()

  describe "T02 - Property Tests" $ do

    it "P01 - Hoan vi Role Preset luon hop le" $
      withNumTests 100 $
        forAll (elements [8, 9]) $ \n ->
          forAll
            (shuffle (maybe [] id (expectedRoles n)))
            $ \roles ->
              validateRolePreset n roles == Right ()

    it "P02 - mkPlayer tao Player hop le" $
      withNumTests 100 $
        forAll
          (listOf1 (elements ['a'..'z']))
          $ \pid ->
            forAll
              (listOf1 (elements ['A'..'Z']))
              $ \name ->
                case mkPlayer pid ("  " ++ name ++ "  ") of
                  Right p ->
                    playerId p == pid
                    && playerName p == name
                    && playerRole p == Nothing
                    && not (playerReady p)
                    && playerLifeStatus p == Alive
                    && playerAppearance p == defaultAppearance

                  Left _ -> False

    it "P03 - PlayerId trung luon bi tu choi" $
      withNumTests 100 $
        forAll
          (listOf1 (elements ['a'..'z']))
          $ \pid ->
            let p =
                  Player pid "Alice" Nothing False Alive defaultAppearance
            in validateUniquePlayerIds [p, p]
                 == Left DuplicatePlayerId

    it "P04 - Host khong ton tai vi pham Invariant" $
      withNumTests 100 $
        forAll
          (listOf1 (elements ['a'..'z']))
          $ \suffix ->
            let
              invalidHost = "missing-" ++ suffix

              invalidGame =
                lobby8 { gameHost = invalidHost }
            in
              validateGameInvariant invalidGame
                == Left InvalidGameState
