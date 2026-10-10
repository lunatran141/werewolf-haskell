
-- Điểm khởi chạy bộ kiểm thử T02.
-- Sử dụng Hspec để thực thi Unit Test và Property Test.

module Main where

import Test.Hspec (hspec)
import qualified DomainT02Spec

main :: IO ()
main = hspec DomainT02Spec.spec
