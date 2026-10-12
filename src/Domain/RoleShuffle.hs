
-- | Tron danh sach Role bang RNG co seed.
-- Pure Engine khong tu sinh random.

module Domain.RoleShuffle
  ( shuffleRoles
  , shuffleRolesWithSeed
  ) where

import Domain.Types (Role)

import System.Random
  ( RandomGen
  , mkStdGen
  , randomR
  )

-- Tron danh sach Role bang generator duoc truyen vao.
-- Tra ve danh sach da tron va generator tiep theo.
shuffleRoles :: RandomGen g => g -> [Role] -> ([Role], g)
shuffleRoles gen [] = ([], gen)
shuffleRoles gen roles =
  let (index, nextGen) = randomR (0, length roles - 1) gen
  in case splitAt index roles of
       (before, selected : after) ->
         let remaining = before ++ after
             (shuffled, finalGen) = shuffleRoles nextGen remaining
         in (selected : shuffled, finalGen)

       -- Nhanh phong ve, khong xay ra khi index hop le.
       _ -> (roles, nextGen)

-- Cung seed va cung input cho cung output.
shuffleRolesWithSeed :: Int -> [Role] -> [Role]
shuffleRolesWithSeed seed roles =
  fst (shuffleRoles (mkStdGen seed) roles)
