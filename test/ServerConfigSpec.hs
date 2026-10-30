module Main (main) where

import Server.Config
  ( ConfigError(..)
  , parseNonEmpty
  , parsePort
  , renderConfigError
  )
import System.IO (hSetEncoding, stderr, stdout, utf8)
import Test.Hspec

main :: IO ()
main = do
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  hspec $ do
    describe "Server.Config - Cau hinh cong mang va bien moi truong" $ do
      it "parsePort chap nhan cac cong hop le trong dai 1..65535" $ do
        parsePort "APP_PORT" "80" `shouldBe` Right 80
        parsePort "APP_PORT" "8080" `shouldBe` Right 8080
        parsePort "ANALYTICS_PORT" "9090" `shouldBe` Right 9090
        parsePort "APP_PORT" "1" `shouldBe` Right 1
        parsePort "APP_PORT" "65535" `shouldBe` Right 65535

      it "parsePort tu choi cac gia tri sai: chu, so 0, so am hoac vuot qua 65535" $ do
        parsePort "APP_PORT" "abc" `shouldBe` Left (InvalidPort "APP_PORT" "abc")
        parsePort "APP_PORT" "0" `shouldBe` Left (InvalidPort "APP_PORT" "0")
        parsePort "APP_PORT" "-80" `shouldBe` Left (InvalidPort "APP_PORT" "-80")
        parsePort "APP_PORT" "65536" `shouldBe` Left (InvalidPort "APP_PORT" "65536")
        parsePort "APP_PORT" "99999" `shouldBe` Left (InvalidPort "APP_PORT" "99999")
        parsePort "APP_PORT" "" `shouldBe` Left (InvalidPort "APP_PORT" "")

      it "parseNonEmpty tu choi chuoi rong hoac chi chua khoang trang" $ do
        parseNonEmpty "ANALYTICS_HOST" "127.0.0.1" `shouldBe` Right "127.0.0.1"
        parseNonEmpty "ANALYTICS_HOST" "" `shouldBe` Left (EmptyConfig "ANALYTICS_HOST")
        parseNonEmpty "ANALYTICS_HOST" "   " `shouldBe` Left (EmptyConfig "ANALYTICS_HOST")

      it "renderConfigError in thong bao loi ro rang co ten bien va huong dan sua" $ do
        let msg = renderConfigError (InvalidPort "APP_PORT" "invalid")
        msg `shouldContain` "APP_PORT"
        msg `shouldContain` "invalid"
        msg `shouldContain` "1..65535"
