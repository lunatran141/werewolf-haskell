# X02 — Analytics Worker (Tiến trình Phân tích Độc lập & Truyền Thông điệp Đa Tiến trình)

Game Server và Analytics Worker là hai tiến trình (process) độc lập hoàn toàn. Game Server không ghi trực tiếp file thống kê và Analytics Worker tuyệt đối không truy cập trực tiếp vào `GameState` trong bộ nhớ RAM của Server.

```text
GameFinished
  -> MatchSummary
  -> TBQueue (không chặn GameLoop)
  -> TCP / JSON Lines
  -> analytics-worker
  -> analytics/matches.jsonl
```

---

## 1. Kiến trúc & Cơ chế Truyền thông điệp (Message Passing)

1. **Tách biệt tiến trình (Process Isolation)**:
   - Khi một ván chơi kết thúc (`GameFinished`), subscriber đăng ký trên kênh `roomUpdates` (`TChan`) của `RoomRuntime` trích xuất một bản ghi tóm tắt `MatchSummary` (`matchId`, `roomId`, `result`, `dayCount`, `playerCount`).
   - `MatchSummary` được đẩy vào `TBQueue` giới hạn sức chứa (256 phần tử) của `Server.AnalyticsClient`. Nếu hàng đợi đầy do Worker tắt lâu ngày, thao tác trả về `False` ngay lập tức (non-blocking) để không bao giờ làm dừng hoặc chậm `GameLoop`.
2. **Giao thức TCP / JSON Lines (`Protocol.Analytics`)**:
   - Mỗi `MatchSummary` được mã hóa trên đúng một dòng JSON kết thúc bằng ký tự xuống dòng `\n`.
   - Payload chỉ chứa dữ liệu tổng hợp công khai, tuyệt đối không chứa tên người chơi, vai trò bí mật, mục tiêu ban đêm hay nội dung chat.
3. **Khử trùng Idempotent bằng `matchId` (`Analytics.Store`)**:
   - Khi khởi động hoặc khởi động lại sau sự cố, Worker đọc lại các dòng hợp lệ trong file `matches.jsonl` để khôi phục tập `matchId` đã lưu (bỏ qua an toàn nếu có dòng hỏng do crash trước đó).
   - Cùng một `matchId` gửi lại nhiều lần chỉ được ghi đúng một lần duy nhất (`SummaryDuplicate`).

---

## 2. Biến môi trường

- **Game Server**:
  - `ANALYTICS_HOST` (mặc định `127.0.0.1`)
  - `ANALYTICS_PORT` (mặc định `9090`)
- **Analytics Worker**:
  - `ANALYTICS_PORT` (mặc định `9090`)
  - `ANALYTICS_OUTPUT` (mặc định `analytics/matches.jsonl`)

---

## 3. Chạy local bằng hai terminal

Terminal 1 (Analytics Worker):

```powershell
$env:ANALYTICS_PORT="9090"
$env:ANALYTICS_OUTPUT="analytics/matches.jsonl"
cabal run analytics-worker
```

Terminal 2 (Game Server):

```powershell
$env:APP_PORT="8080"
$env:ANALYTICS_HOST="127.0.0.1"
$env:ANALYTICS_PORT="9090"
cabal run werewolf-server
```

Hoặc chạy cả hai tiến trình qua Docker Compose: `docker compose up --build`.

---

## 4. Kiểm thử tự động (Kịch bản E20)

```powershell
cabal test x02-analytics-protocol-test x02-analytics-worker-test x02-analytics-client-test --enable-tests --test-show-details=direct
```

Các đảm bảo đã được kiểm chứng tự động:
- Worker vắng mặt hoặc khởi động lại không làm Game Server dừng hoạt động.
- Khi hàng đợi `publisherQueue` đầy do Worker tắt lâu, Game Server từ chối bản ghi mới ngay lập tức mà không treo `GameLoop`.
- Khi file JSONL có dòng hỏng sau sự cố, Worker khởi động lại vẫn phục hồi đúng các `matchId` đã ghi và tiếp tục ghi nhận ván mới.
- Cùng một `matchId` chỉ được ghi một lần duy nhất.
- Payload không chứa tên, vai trò, mục tiêu hành động hay nội dung chat.
