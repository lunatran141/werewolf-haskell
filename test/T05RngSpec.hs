
module Main (main) where

import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck (Positive(..))

import Domain.RoleShuffle
  ( shuffleRoles
  , shuffleRolesWithSeed
  )

import Domain.Types (Role)
import Domain.Validation (expectedRoles)

import Data.List (sort)
import System.Random (mkStdGen)

-- Lay danh sach Role dung preset 8/9 nguoi.
rolesFor :: Int -> [Role]
rolesFor count =
  case expectedRoles count of
    Just roles -> roles
    Nothing -> error "Preset khong hop le"

roles8 :: [Role]
roles8 = rolesFor 8

roles9 :: [Role]
roles9 = rolesFor 9

main :: IO ()
main = hspec $ do

  describe "T05 - RNG Seed va Injection" $ do

    it "R01 - Cung seed cho cung ket qua van 8 nguoi" $ do
      shuffleRolesWithSeed 123 roles8
        `shouldBe` shuffleRolesWithSeed 123 roles8

    it "R02 - Cung seed cho cung ket qua van 9 nguoi" $ do
      shuffleRolesWithSeed 456 roles9
        `shouldBe` shuffleRolesWithSeed 456 roles9

    it "R03 - Tron vai khong lam mat Role van 8 nguoi" $ do
      sort (shuffleRolesWithSeed 123 roles8)
        `shouldBe` sort roles8

    it "R04 - Tron vai khong lam mat Role van 9 nguoi" $ do
      sort (shuffleRolesWithSeed 456 roles9)
        `shouldBe` sort roles9

    it "R05 - Generator injection cho ket qua lap lai" $ do
      let result1 = shuffleRoles (mkStdGen 789) roles8
          result2 = shuffleRoles (mkStdGen 789) roles8
      result1 `shouldBe` result2

    it "R06 - Generator duoc tra ve de tiep tuc su dung" $ do
      let (first, nextGen) = shuffleRoles (mkStdGen 321) roles8
          (second, _) = shuffleRoles nextGen roles9

      length first `shouldBe` 8
      length second `shouldBe` 9
      sort first `shouldBe` sort roles8
      sort second `shouldBe` sort roles9

    prop "R07 - Moi seed deu giu dung preset 8 nguoi" $
      \(Positive seed) ->
        sort (shuffleRolesWithSeed seed roles8) == sort roles8

    prop "R08 - Moi seed deu cho ket qua lap lai o van 9 nguoi" $
      \(Positive seed) ->
        shuffleRolesWithSeed seed roles9
          == shuffleRolesWithSeed seed roles9
