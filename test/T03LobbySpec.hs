module Main (main) where

import Domain.Engine (applyLobbyCommand)
import Domain.Types
import GHC.IO.Encoding (utf8)
import System.IO (hSetEncoding, stderr, stdout)
import Test.Hspec (Spec, describe, hspec, it, shouldBe)

-- Tạo state mẫu. Nếu bước chuẩn bị thất bại, test sẽ báo lỗi.
mustRight :: Show e => Either e a -> a
mustRight result =
  case result of
    Right value -> value
    Left err -> error ("Không tạo được state test: " ++ show err)

onePlayer :: GameState
onePlayer =
  fst (mustRight (applyLobbyCommand emptyLobby (Join "p1" "  Van  ")))

twoPlayers :: GameState
twoPlayers =
  fst (mustRight (applyLobbyCommand onePlayer (Join "p2" "Binh")))

ninePlayers :: GameState
ninePlayers =
  foldl addPlayer emptyLobby [1 :: Int .. 9]
  where
    addPlayer state n =
      fst
        (mustRight
          (applyLobbyCommand state
            (Join ("p" ++ show n) ("Name" ++ show n))))

main :: IO ()
main = do
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  hspec lobbyTests

lobbyTests :: Spec
lobbyTests = describe "T03 Lobby" $ do
  it "Join dau tien thanh Host, NotReady va phat PlayerJoined" $ do
    let (state, events) =
          mustRight (applyLobbyCommand emptyLobby (Join "p1" "  Van  "))
    gameHost state `shouldBe` "p1"
    map playerName (gamePlayers state) `shouldBe` ["Van"]
    map playerReady (gamePlayers state) `shouldBe` [False]
    events `shouldBe` [PlayerJoined "p1"]

  it "Nguoi Join thu hai khong doi Host" $
    gameHost twoPlayers `shouldBe` "p1"

  it "Tu choi ten trung sau khi chuan hoa" $
    applyLobbyCommand onePlayer (Join "p2" " van ")
      `shouldBe` Left DuplicatePlayerName

  it "Tu choi PlayerId trung" $
    applyLobbyCommand twoPlayers (Join "p2" "Khac")
      `shouldBe` Left DuplicatePlayerId

  it "Tu choi nguoi thu 10" $
    applyLobbyCommand ninePlayers (Join "p10" "Name10")
      `shouldBe` Left RoomFull

  it "Ready doi False thanh True va phat event" $ do
    let (state, events) =
          mustRight (applyLobbyCommand onePlayer (SetReady "p1" True))
    map playerReady (gamePlayers state) `shouldBe` [True]
    events `shouldBe` [ReadyChanged "p1" True]

  it "Ready cung gia tri khong phat event" $ do
    let (readyState, _) =
          mustRight (applyLobbyCommand onePlayer (SetReady "p1" True))
    let (sameState, events) =
          mustRight (applyLobbyCommand readyState (SetReady "p1" True))
    sameState `shouldBe` readyState
    events `shouldBe` []

  it "Unready doi True thanh False va phat event" $ do
    let (readyState, _) =
          mustRight (applyLobbyCommand onePlayer (SetReady "p1" True))
    let (state, events) =
          mustRight (applyLobbyCommand readyState (SetReady "p1" False))
    map playerReady (gamePlayers state) `shouldBe` [False]
    events `shouldBe` [ReadyChanged "p1" False]

  it "Host roi thi chuyen quyen cho nguoi Join som nhat con lai" $ do
    let (state, events) =
          mustRight (applyLobbyCommand twoPlayers (Leave "p1"))
    gameHost state `shouldBe` "p2"
    events `shouldBe` [PlayerLeft "p1", HostChanged "p2"]

  it "Nguoi cuoi roi thi Host rong" $ do
    let (state, events) =
          mustRight (applyLobbyCommand onePlayer (Leave "p1"))
    gamePlayers state `shouldBe` []
    gameHost state `shouldBe` ""
    events `shouldBe` [PlayerLeft "p1"]

  it "Tu choi Join sai Phase" $
    applyLobbyCommand (emptyLobby {gamePhase = Night}) (Join "p1" "Van")
      `shouldBe` Left WrongPhase

  it "Tu choi ten chi co khoang trang" $
    applyLobbyCommand emptyLobby (Join "p1" "   ")
      `shouldBe` Left InvalidPlayerName

  it "Tu choi Leave khi Player khong ton tai" $
    applyLobbyCommand onePlayer (Leave "p99")
      `shouldBe` Left PlayerNotFound

  it "Tu choi SetReady khi Player khong ton tai" $
    applyLobbyCommand onePlayer (SetReady "p99" True)
      `shouldBe` Left PlayerNotFound

  it "Tu choi Leave sai Phase" $
    applyLobbyCommand (onePlayer {gamePhase = Night}) (Leave "p1")
      `shouldBe` Left WrongPhase

  it "Tu choi SetReady sai Phase" $
    applyLobbyCommand (onePlayer {gamePhase = Night}) (SetReady "p1" True)
      `shouldBe` Left WrongPhase

  it "Nguoi khong phai Host roi thi Host giu nguyen" $ do
    let (state, events) =
          mustRight (applyLobbyCommand twoPlayers (Leave "p2"))
    gameHost state `shouldBe` "p1"
    map playerId (gamePlayers state) `shouldBe` ["p1"]
    events `shouldBe` [PlayerLeft "p2"]