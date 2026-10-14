-- Điểm chạy riêng cho bộ kiểm thử T06.
module Main (main) where

import DomainT06Spec (t06Spec)
import Test.Hspec (hspec)

main :: IO ()
main = hspec t06Spec
