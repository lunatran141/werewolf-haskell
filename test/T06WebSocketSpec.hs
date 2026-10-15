{-# LANGUAGE OverloadedStrings #-}
-- T06: Dùng kết nối thật để kiểm tra JSON -> session -> STM -> timer -> sự kiện.
module Main (main) where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Concurrent.MVar (newMVar, modifyMVar_, readMVar)
import Control.Concurrent.STM (atomically, readTVar, readTVarIO, writeTVar)
import Control.Exception (bracket)
import Control.Monad (void, forM, forM_)
import Data.Aeson (encode, eitherDecode)
import Data.List (sort)
import qualified Data.ByteString.Lazy as BL
import Domain.Engine (startGame, closeWolfVoting, resolveNightTurn, completeNightTurn)
import Domain.Types
import Protocol.Types
import qualified Network.WebSockets as WS
import Server.GameLoop (runGameLoopWithTimeouts, applyInternalCommand)
import Server.Room
import Server.WebSocket (webSocketApp)
import System.Timeout (timeout)
import System.IO (hSetEncoding, stdout, stderr, utf8)
import Test.Hspec

-- Thời hạn test ngắn hơn production, nhưng vẫn chạy đúng cùng worker.
port :: Int
port = 18766

send :: WS.Connection -> ClientMessage -> IO ()
send connection = WS.sendTextData connection . encode

receiveUntil :: WS.Connection -> (ServerMessage -> Bool) -> IO ServerMessage
receiveUntil connection predicate = do
  found <- timeout 5000000 loop
  maybe (fail "T06: hết thời gian đợi thông điệp") pure found
  where
    loop = do
      bytes <- WS.receiveData connection :: IO BL.ByteString
      message <- either fail pure (eitherDecode bytes)
      if predicate message then pure message else loop

isSnapshot :: ServerMessage -> Bool
isSnapshot (MsgVotingSnapshot _ Voting _ _ _ _ _ _) = True
isSnapshot _ = False

-- Chỉ fixture test dựng đủ 8 người. Đi qua hàm T04/T05 để tới Day hợp lệ,
-- rồi gọi điểm nối nội bộ; production không có endpoint sửa state từ Browser.
enterVoting :: RoomRuntime -> PlayerId -> PlayerId -> IO ()
enterVoting room first second = do
  let ids = [first, second] ++ ["fixture" ++ show n | n <- [3 :: Int .. 8]]
      roles = [Werewolf, Hunter, Werewolf, Seer, Guard, Witch, Villager, Villager]
      lobby = emptyLobby {gamePlayers = [Player pid pid Nothing True Alive defaultAppearance | pid <- ids], gameHost = first}
      prepared = do
        (night, _) <- startGame lobby first roles
        (locked, _) <- closeWolfVoting night True
        (resolved, _) <- resolveNightTurn locked
        completeNightTurn resolved
  (day, _) <- either (fail . show) pure prepared
  result <- atomically $ do
    writeTVar (roomState room) day
    applyInternalCommand room AdvancePhase
  either (fail . show) (const (pure ())) result

withPlayers :: RoomRegistry -> String -> (RoomRuntime -> WS.Connection -> WS.Connection -> PlayerId -> PlayerId -> IO ()) -> IO ()
withPlayers registry rid action = WS.runClient "127.0.0.1" port "/ws" $ \one -> do
  send one (ClientCreateRoom "create" rid "Một")
  firstMessage <- receiveUntil one isLobby
  let first = case firstMessage of MsgLobbySnapshot _ pid _ _ -> pid; _ -> ""
  WS.runClient "127.0.0.1" port "/ws" $ \two -> do
    send two (ClientJoin "join" rid "Hai")
    secondMessage <- receiveUntil two isLobby
    let second = case secondMessage of MsgLobbySnapshot _ pid _ _ -> pid; _ -> ""
    room <- findRoom registry rid >>= maybe (fail "Không tìm thấy phòng") pure
    enterVoting room first second
    void (receiveUntil one isSnapshot)
    void (receiveUntil two isSnapshot)
    action room one two first second
  where
    isLobby (MsgLobbySnapshot _ _ _ _) = True
    isLobby _ = False

expectReject :: WS.Connection -> String -> String -> IO ()
expectReject connection request code = do
  message <- receiveUntil connection $ \m -> case m of
    MsgRejected (Just rid) _ _ -> rid == request
    _ -> False
  case message of
    MsgRejected _ actual _ -> actual `shouldBe` code
    _ -> expectationFailure "Thiếu lỗi"

-- Tích hợp sau merge: 8 client thật Join/Ready, Host Start qua JSON của T05.
-- Không chỉnh state để chia vai hoặc hoàn tất Night trong kịch bản này.
withReadyPlayers :: String -> ([(PlayerId, WS.Connection)] -> IO ()) -> IO ()
withReadyPlayers rid action = joinNext 1 []
  where
    joinNext :: Int -> [(PlayerId, WS.Connection)] -> IO ()
    joinNext n connections
      | n > 8 = action connections
      | otherwise = WS.runClient "127.0.0.1" port "/ws" $ \connection -> do
          let joinMessage = if n == 1 then ClientCreateRoom else ClientJoin
          send connection (joinMessage "join" rid ("Nguoi " ++ show n))
          joined <- receiveUntil connection $ \m -> case m of MsgLobbySnapshot {} -> True; _ -> False
          pid <- case joined of MsgLobbySnapshot _ self _ _ -> pure self; _ -> fail "Thiếu ID"
          send connection (ClientSetReady "ready" rid True)
          void $ receiveUntil connection $ \m -> case m of
            MsgLobbySnapshot _ _ _ ps -> any (\p -> viewPlayerId p == pid && viewReady p) ps
            _ -> False
          joinNext (n + 1) (connections ++ [(pid, connection)])

main :: IO ()
main = do
  -- Console Windows có thể dùng bảng mã cũ; xuất UTF-8 cho tên test tiếng Việt.
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  registry <- newRoomRegistry
  workers <- newMVar []
  let startWorker room = do
        tid <- forkIO (runGameLoopWithTimeouts 1000000 1000000 room)
        modifyMVar_ workers (pure . (tid :))
      startServer = do
        tid <- forkIO (WS.runServer "127.0.0.1" port (webSocketApp registry startWorker))
        threadDelay 200000
        pure tid
      stopServer tid = do
        workerIds <- readMVar workers
        -- Trên Windows, throwTo có thể chờ accept socket kết thúc. Gửi yêu cầu
        -- dừng ở luồng riêng; kết thúc executable sẽ đóng toàn bộ socket test.
        mapM_ (\thread -> void (forkIO (killThread thread))) (tid : workerIds)
  bracket startServer stopServer $ \_ -> hspec $ do
    describe "T06 WebSocket thực và timer" $ do
      it "Ghép T05 Start/Night với T06 Hunter/Vote qua 8 kết nối" $
        withReadyPlayers "MERGED" $ \connections -> do
          let (_, host) = head connections
          send host (ClientStartGame "start" "MERGED")
          assigned <- forM connections $ \(pid, connection) -> do
            message <- receiveUntil connection $ \m -> case m of MsgYourRole {} -> True; _ -> False
            case message of
              MsgYourRole _ role -> pure (pid, connection, role)
              _ -> fail "Thiếu vai riêng tư"
          let (hunterId, hunterSocket, _) = head [p | p@(_, _, Hunter) <- assigned]
              wolves = [(pid, c) | (pid, c, Werewolf) <- assigned]
              wolfId = fst (head wolves)
              act connection choice = do
                send connection (ClientNightAction "night" "MERGED" choice)
                void (receiveUntil connection (== MsgNightActionAccepted "MERGED"))
          forM_ wolves $ \(_, c) -> act c (WolfTarget hunterId)
          forM_ assigned $ \(pid, c, role) -> case role of
            Seer -> act c (SeerTarget wolfId)
            Guard -> act c (GuardTarget pid)
            _ -> pure ()
          forM_ assigned $ \(_, c, role) -> case role of
            Witch -> do
              void (receiveUntil c (== MsgWitchVictimNotice "MERGED" (Just hunterId)))
              act c WitchPass
            _ -> pure ()
          void (receiveUntil hunterSocket (== MsgHunterShotPending "MERGED"))
          send hunterSocket (ClientHunterAction "shot" "MERGED" (HunterShot wolfId))
          void (receiveUntil host (== MsgPhaseChanged "MERGED" Day))
          room <- findRoom registry "MERGED" >>= maybe (fail "Thiếu phòng") pure
          dayState <- readTVarIO (roomState room)
          gamePendingHunter dayState `shouldBe` Nothing
          -- Day timer thuộc bộ điều phối chung: gọi đúng điểm nối nội bộ của T04.
          result <- atomically (applyInternalCommand room AdvancePhase)
          fmap gamePhase result `shouldBe` Right Voting
          let (voter, voteSocket, _) = head [p | p@(_, _, Villager) <- assigned]
              target = head [pid | (pid, _, Villager) <- assigned, pid /= voter]
          void (receiveUntil voteSocket isSnapshot)
          send voteSocket (ClientVote "vote" "MERGED" target)
          void (receiveUntil voteSocket (== MsgActionAccepted "vote" "MERGED"))
          void (receiveUntil host (== MsgVotingResolved "MERGED" [(target, 1)] (Just target)))
          void (receiveUntil host (== MsgPhaseChanged "MERGED" Night))

      it "Từ chối Vote khi chưa vào phòng" $
        WS.runClient "127.0.0.1" port "/ws" $ \connection -> do
          send connection (ClientVote "unjoined" "none" "p2")
          expectReject connection "unjoined" "NOT_JOINED"

      it "Phiếu sai/trùng không commit; hết hạn lynch và gửi kết quả công khai" $
        withPlayers registry "LYNCH" $ \room one two first _ -> do
          versionBefore <- readTVarIO (roomVersion room)
          send one (ClientVote "room" "OTHER" "fixture8")
          expectReject one "room" "WRONG_ROOM"
          send one (ClientVote "self" "LYNCH" first)
          expectReject one "self" "InvalidTarget"
          readTVarIO (roomVersion room) `shouldReturn` versionBefore
          send one (ClientVote "v1" "LYNCH" "fixture8")
          void (receiveUntil one (== MsgActionAccepted "v1" "LYNCH"))
          send one (ClientVote "v2" "LYNCH" "fixture7")
          expectReject one "v2" "AlreadyVoted"
          send one (ClientVote "v1" "LYNCH" "fixture8")
          expectReject one "v1" "DuplicateRequest"
          -- Nếu receipt riêng bị gửi sang two, phép so sánh này sẽ thất bại.
          public <- receiveUntil two $ \m -> case m of
            MsgVoteUpdated _ -> True
            MsgVotingResolved _ _ _ -> True
            _ -> False
          public `shouldBe` MsgVotingResolved "LYNCH" [("fixture8", 1)] (Just "fixture8")
          void (receiveUntil two (== MsgPhaseChanged "LYNCH" Night))
          send one (ClientVote "late" "LYNCH" "fixture7")
          expectReject one "late" "WrongPhase"
          -- Giả lập bộ điều phối bắt đầu vòng sau; request cũ vẫn bị chặn.
          atomically $ do
            current <- readTVar (roomState room)
            writeTVar (roomState room) current {gamePhase = Day}
            void (applyInternalCommand room AdvancePhase)
          send one (ClientVote "v1" "LYNCH" "fixture7")
          expectReject one "v1" "DuplicateRequest"

      it "Hòa phiếu không loại ai và không vote lại" $
        withPlayers registry "TIE" $ \_ one two _ _ -> do
          send one (ClientVote "a" "TIE" "fixture7")
          send two (ClientVote "b" "TIE" "fixture8")
          message <- receiveUntil one $ \m -> case m of MsgVotingResolved _ _ _ -> True; _ -> False
          case message of
            MsgVotingResolved _ tally target -> do
              sort tally `shouldBe` [("fixture7", 1), ("fixture8", 1)]
              target `shouldBe` Nothing
            _ -> expectationFailure "Thiếu tally"
          void (receiveUntil one (== MsgPhaseChanged "TIE" Night))

      it "Không phiếu tự chốt sang Night" $
        withPlayers registry "EMPTY" $ \_ one _ _ _ -> do
          void (receiveUntil one (== MsgVotingResolved "EMPTY" [] Nothing))
          void (receiveUntil one (== MsgPhaseChanged "EMPTY" Night))

      it "Hunter gửi lựa chọn qua socket rồi công khai người chết và đổi phase" $
        withPlayers registry "HUNTER" $ \_ one two _ hunter -> do
          send one (ClientVote "v" "HUNTER" hunter)
          void (receiveUntil two (== MsgHunterShotPending "HUNTER"))
          send one (ClientHunterAction "fake" "HUNTER" (HunterShot "fixture3"))
          expectReject one "fake" "HunterNotPending"
          send two (ClientHunterAction "shot" "HUNTER" (HunterShot "fixture3"))
          void (receiveUntil two (== MsgActionAccepted "shot" "HUNTER"))
          -- Khi chua GameOver, T02 chi cho cong khai PlayerId cua nguoi chet.
          void (receiveUntil one (== MsgPlayerDied "HUNTER" "fixture3"))
          void (receiveUntil one (== MsgPhaseChanged "HUNTER" Night))

      it "Hunter không trả lời thì timeout bỏ qua phát bắn" $
        withPlayers registry "PASS" $ \_ one two _ hunter -> do
          send one (ClientVote "v" "PASS" hunter)
          void (receiveUntil two (== MsgHunterShotPending "PASS"))
          void (receiveUntil one (== MsgHunterShotResolved "PASS" hunter Nothing))
          void (receiveUntil one (== MsgPhaseChanged "PASS" Night))

