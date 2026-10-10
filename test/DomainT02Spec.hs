
-- | Bo kiem thu Task T02 - Domain Types va Validation.
--
-- Pham vi:
-- - Smart Constructor
-- - Validation
-- - Role Preset
-- - GameState Invariant
-- - Event Visibility
-- - Property Testing
--
-- Khong kiem thu logic cap nhat GameState cua T03.
-- Cac ham kiem thu su dung Hspec va QuickCheck.

module DomainT02Spec (spec) where

import Domain.Types
import Domain.Validation

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

-- Ham spec chua toan bo Unit Test va Property Test.
-- T02Main.hs se goi ham nay bang hspec.
spec :: Spec
spec = do

  describe "T02 - Smart Constructor" $ do

    -- Kiem tra tao Player voi cac gia tri mac dinh.
    it "U01 - Tao Player mac dinh hop le" $
      mkPlayer "a" "Alice"
        `shouldBe`
          Right
            (Player "a" "Alice" Nothing False Alive)

    -- PlayerId khong duoc rong.
    it "U02 - Tu choi PlayerId rong" $
      mkPlayer "   " "Alice"
        `shouldBe` Left InvalidPlayerId

    -- Ten nguoi choi khong duoc rong.
    it "U03 - Tu choi ten rong" $
      mkPlayer "a" "  "
        `shouldBe` Left InvalidPlayerName

    -- Ten phai duoc loai bo khoang trang thua.
    it "U04 - Chuan hoa khoang trang trong ten" $
      mkPlayer "a" "  Van   Nguyen "
        `shouldBe`
          Right
            (Player "a" "Van Nguyen" Nothing False Alive)

  describe "T02 - Validation dinh danh" $ do

    -- Hai Player khong duoc trung ID.
    it "U05 - Tu choi PlayerId trung" $
      validateUniquePlayerIds
        [player 1, player 1]
        `shouldBe` Left DuplicatePlayerId

    -- Khoang trang thua khong lam ten thanh khac nhau.
    it "U06 - Tu choi ten trung du khac khoang trang" $
      validateUniquePlayerNames
        [ Player "a" "Van" Nothing False Alive
        , Player "b" " Van " Nothing False Alive
        ]
        `shouldBe` Left DuplicatePlayerName

    -- So sanh ten khong phan biet chu hoa va chu thuong.
    it "U07 - Tu choi ten trung du khac hoa thuong" $
      validateUniquePlayerNames
        [ Player "a" "Van" Nothing False Alive
        , Player "b" "vAn" Nothing False Alive
        ]
        `shouldBe` Left DuplicatePlayerName

  describe "T02 - Role Preset" $ do

    -- Van 8 nguoi phai co dung 2 Werewolf.
    it "U08 - Preset 8 nguoi co dung 2 Soi" $
      fmap
        (length . filter (== Werewolf))
        (expectedRoles 8)
        `shouldBe` Just 2

    -- Van 9 nguoi phai co dung 3 Werewolf.
    it "U09 - Preset 9 nguoi co dung 3 Soi" $
      fmap
        (length . filter (== Werewolf))
        (expectedRoles 9)
        `shouldBe` Just 3

    -- Thu tu Role khong anh huong den preset.
    it "U10 - Preset khong phu thuoc thu tu Role" $
      validateRolePreset
        8
        (reverse (maybe [] id (expectedRoles 8)))
        `shouldBe` Right ()

    -- Van 8 nguoi khong duoc chua 3 Werewolf.
    it "U11 - Tu choi preset 8 nguoi co 3 Soi" $
      validateRolePreset
        8
        [ Werewolf, Werewolf, Werewolf
        , Seer, Guard, Witch, Hunter, Villager
        ]
        `shouldBe` Left InvalidRoleConfiguration

  describe "T02 - Validation StartGame" $ do

    -- Chi Host moi co quyen bat dau van choi.
    it "U12 - Nguoi khong phai Host khong duoc Start" $
      validateStartGame "p2" lobby8
        `shouldBe` Left NotAuthorized

    -- Lobby hop le duoc phep bat dau.
    it "U13 - Host duoc Start khi du dieu kien" $
      validateStartGame "p1" lobby8
        `shouldBe` Right ()

    -- Neu con mot Player chua Ready thi khong duoc Start.
    it "U14 - Tu choi Start khi chua Ready het" $
      let
        players = gamePlayers lobby8

        notReady =
          (head players) { playerReady = False }
          : tail players

      in validateStartGame
           "p1"
           (lobby8 { gamePlayers = notReady })
           `shouldBe` Left NotAllReady

  describe "T02 - Validation cho T03" $ do

    -- T02 chi kiem tra Join, khong them Player vao GameState.
    it "U15 - Join voi PlayerId trung bi tu choi" $
      validateJoin lobby8 "p1" "New"
        `shouldBe` Left DuplicatePlayerId

    -- Join voi ten da ton tai phai bi tu choi.
    it "U16 - Join voi ten trung bi tu choi" $
      validateJoin lobby8 "p9" " ten 1 "
        `shouldBe` Left DuplicatePlayerName

    -- Phong toi da 9 nguoi.
    it "U17 - Join khi phong co 9 nguoi bi tu choi" $
      validateJoin
        (lobby8 { gamePlayers = map player [1..9] })
        "p10"
        "New"
        `shouldBe` Left RoomFull

  describe "T02 - GameState Invariant" $ do

    -- Lobby rong ban dau phai hop le.
    it "U18 - Lobby rong la trang thai hop le" $
      validateGameInvariant emptyLobby
        `shouldBe` Right ()

    -- Host phai nam trong danh sach Player.
    it "U19 - Host khong ton tai bi tu choi" $
      validateGameInvariant
        (lobby8 { gameHost = "missing" })
        `shouldBe` Left InvalidGameState

    -- Khong duoc dung chinh sach pha hoa theo ID.
    it "U20 - Khong chap nhan LowestPlayerId" $
      validateGameInvariant
        (lobby8 { gameVoteTiePolicy = LowestPlayerId })
        `shouldBe` Left InvalidTiePolicy

    -- GameOver phai chua ket qua cuoi cung.
    it "U21 - GameOver bat buoc co GameResult" $
      validateGameInvariant
        (started8 { gamePhase = GameOver })
        `shouldBe` Left InvalidGameState

  describe "T02 - Event Visibility" $ do

    -- Ket qua soi cua Seer phai duoc gui rieng.
    it "U22 - SeerResult la Private" $
      eventVisibility
        (SeerResult "p3" Wolves)
        `shouldBe` Private "p3"

    -- Role Reveal khi chet duoc cong khai.
    it "U23 - Role Reveal khi chet la Public" $
      eventVisibility
        (PlayerRoleRevealed "p3" Seer Village)
        `shouldBe` Public

  describe "T02 - Night Action Validation" $ do

    -- Seer khong duoc soi chinh minh.
    it "U24 - Seer khong duoc soi chinh minh" $
      validateNightAction
        started8
        "p3"
        (SeerTarget "p3")
        `shouldBe` Left InvalidTarget

    -- Guard co the tu bao ve.
    it "U25 - Guard duoc tu bao ve" $
      validateNightAction
        started8
        "p4"
        (GuardTarget "p4")
        `shouldBe` Right ()

    -- Guard khong duoc bao ve cung muc tieu
    -- trong hai dem lien tiep.
    it "U26 - Guard khong bao ve lap muc tieu" $
      validateNightAction
        (started8 { gameLastProtected = Just "p4" })
        "p4"
        (GuardTarget "p4")
        `shouldBe` Left InvalidTarget

    -- Witch khong duoc Poison chinh minh.
    it "U27 - Witch khong duoc Poison chinh minh" $
      validateNightAction
        started8
        "p5"
        (WitchPoison "p5")
        `shouldBe` Left InvalidTarget

    -- Witch Heal chi hop le khi co nan nhan do Soi tan cong.
    it "U28 - Witch Heal khong co nan nhan bi tu choi" $
      validateNightAction
        started8
        "p5"
        WitchHeal
        `shouldBe` Left InvalidNightAction

  describe "T02 - Vote va Chat Validation" $ do

    -- Moi nguoi chi duoc Vote mot lan trong moi luot.
    it "U29 - Mot Player khong duoc Vote hai lan" $
      validateVote
        (started8
          { gamePhase = Voting
          , gameVotes = [("p3", "p1")]
          })
        "p3"
        "p2"
        `shouldBe` Left AlreadyVoted

    -- Tin nhan rong hoac chi co khoang trang bi tu choi.
    it "U30 - Chat chi co khoang trang bi tu choi" $
      validateChat
        (started8 { gamePhase = Day })
        "p3"
        "  \n  "
        `shouldBe` Left EmptyChat
    
        -- Kiem tra Night Action chi duoc gui rieng.
    it "U31 - NightActionAccepted la Private" $
      eventVisibility (NightActionAccepted "p1")
        `shouldBe` Private "p1"

    -- Khong cong khai lua chon bo phieu.
    it "U32 - VoteUpdated la Private" $
      eventVisibility (VoteUpdated "p2" "p5")
        `shouldBe` Private "p2"

    -- Chi Hunter duoc nhan yeu cau ban.
    it "U33 - HunterShotPending la Private" $
      eventVisibility (HunterShotPending "p6")
        `shouldBe` Private "p6"

    -- Chuyen Phase la thong tin cong khai.
    it "U34 - PhaseChanged la Public" $
      eventVisibility (PhaseChanged Day)
        `shouldBe` Public

  describe "T02 - Property Tests" $ do

    -- Property 1:
    -- Moi hoan vi cua preset 8 hoac 9 nguoi deu hop le.
    -- Chay toi thieu 100 mau QuickCheck.
    it "P01 - Hoan vi Role Preset luon hop le" $
      withNumTests 100 $
        forAll (elements [8, 9]) $ \n ->
          forAll
            (shuffle (maybe [] id (expectedRoles n)))
            $ \roles ->
              validateRolePreset n roles == Right ()

    -- Property 2:
    -- Smart Constructor phai giu nguyen PlayerId,
    -- chuan hoa PlayerName va gan trang thai mac dinh.
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

                  Left _ -> False

    -- Property 3:
    -- Neu hai Player co cung ID, validation phai tu choi.
    it "P03 - PlayerId trung luon bi tu choi" $
      withNumTests 100 $
        forAll
          (listOf1 (elements ['a'..'z']))
          $ \pid ->
            let p =
                  Player pid "Alice" Nothing False Alive

            in validateUniquePlayerIds [p, p]
                 == Left DuplicatePlayerId

    -- Property 4:
    -- Host khong ton tai trong danh sach Player
    -- luon vi pham GameState Invariant.
    it "P04 - Host khong ton tai vi pham Invariant" $
      withNumTests 100 $
        forAll
          (listOf1 (elements ['a'..'z']))
          $ \suffix ->
            let
              invalidHost = "missing-" ++ suffix

              invalidGame =
                lobby8 { gameHost = invalidHost }

            in validateGameInvariant invalidGame
                 == Left InvalidGameState
