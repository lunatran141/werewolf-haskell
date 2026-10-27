# X03 — NFS Replay Store (Lưu trữ Replay Dùng chung & Ranh giới Trạng thái)

X03 thiết lập một ranh giới lưu trữ (storage boundary) riêng biệt cho dữ liệu replay công khai trên thư mục chia sẻ / Networked File System (NFS). `GameState` thời gian thực vẫn chỉ nằm trong bộ nhớ STM (`TVar`) của Game Server; NFS hoàn toàn không tham gia vào luồng xử lý `Command`, `Night`, `Vote` hoặc chuyển `Phase`.

---

## 1. Dữ liệu được lưu & Bảo mật Quyền riêng tư

Mỗi ván kết thúc tạo một file `shared/replays/<matchId>.json` theo đúng schema `MatchSummary` đã làm sạch của X02:

- `matchId`: Mã định danh duy nhất của ván đấu (`<roomId>-<roomInstanceId>`).
- `roomId`: Mã phòng chơi.
- `result`: Kết quả trận đấu (`Village`, `Wolves`, hoặc `Draw`).
- `dayCount`: Số ngày diễn ra ván đấu.
- `playerCount`: Tổng số người chơi trong ván.

**Đảm bảo an toàn và quyền riêng tư:**
- File replay tuyệt đối không chứa tên người chơi, vai trò (`Role`), nội dung chat, mục tiêu hành động ban đêm, sự kiện riêng tư (`PrivateEvent`) hay `GameState`.
- Hàm `replayFilePath` chỉ chấp nhận ký tự chữ, số, dấu gạch ngang (`-`) và gạch dưới (`_`), chặn hoàn toàn tấn công leo thang thư mục (*path traversal* như `../secret`).

---

## 2. Ranh giới Chịu lỗi (Fault Boundary)

`Server.ReplayStore` chuyển mọi ngoại lệ I/O của hệ thống tệp (mất kết nối mount, lỗi phân quyền, file hỏng hoặc vượt quá 64 KiB) thành kiểu dữ liệu tường minh `StorageError`:
- `StorageUnavailable FilePath String`
- `StoragePermissionDenied FilePath`
- `StorageCorrupt FilePath String`
- `StorageConflict FilePath`
- `StorageInvalidMatchId String`

Subscriber ghi replay (`subscribeRoomAnalyticsWithReplay`) chạy bên ngoài `GameLoop`, nên mọi lỗi NFS chỉ được ghi log an toàn qua `Server.SafeLog` (không đính kèm payload nhạy cảm) và ván đấu vẫn tiếp tục bình thường. File được ghi nguyên tử (atomic write) qua file tạm rồi đổi tên (`renameFile`) để tránh để lại file JSON dở dang khi mất kết nối giữa chừng.

Nếu biến môi trường `REPLAY_DIR` không được đặt, `ReplayStore` tự động tắt. Cấu hình mặc định và triển khai trên Render không bắt buộc phải có NFS.

---

## 3. Chạy kiểm thử local (Kịch bản E21)

```powershell
cabal test x03-replay-store-test --enable-tests --test-show-details=direct
```

Bộ kiểm thử xác minh đầy đủ:
- Game Server và Analytics Worker đọc cùng một replay từ thư mục chia sẻ.
- Ghi lại cùng `matchId` và cùng nội dung là idempotent (`ReplayAlreadyPresent`); cùng `matchId` nhưng khác nội dung bị từ chối (`StorageConflict`).
- Chặn `matchId` chứa đường dẫn thoát khỏi `shared/replays`.
- Chuyển đổi file hỏng thành `StorageCorrupt`, lỗi mount thành `StorageUnavailable`, lỗi quyền thành `StoragePermissionDenied` mà không ném exception làm sập tiến trình.
- Khi mount NFS bị lỗi ngay lúc ván kết thúc trong `RoomRuntime`, luồng phòng chơi không bị dừng và `MatchSummary` vẫn được đẩy sang hàng đợi Analytics.
- Quét cả nội dung file replay lẫn chuỗi log lỗi xác nhận không rò rỉ vai trò bí mật hay thông tin nhạy cảm.

---

## 4. Chạy NFS Demo qua Docker Profile

NFS demo sử dụng container NFSv4 và Docker local-volume driver với profile riêng `nfs-demo` (nên chạy trên Docker Engine Linux hoặc WSL2):

Khởi động NFS Server trước:

```powershell
docker compose -f compose.yaml -f docker-compose.nfs.yml --profile nfs-demo up -d nfs-server
```

Sau khi NFS Server đã sẵn sàng, khởi động hai tiến trình dùng chung mount:

```powershell
docker compose -f compose.yaml -f docker-compose.nfs.yml --profile nfs-demo up --build server analytics-worker
```

Nếu Docker daemon không truy cập NFS qua `127.0.0.1`, đặt biến `NFS_HOST` thành địa chỉ IP của host/WSL trước khi chạy lệnh thứ hai:

```powershell
$env:NFS_HOST="<dia-chi-host>"
```

Dừng demo:

```powershell
docker compose -f compose.yaml -f docker-compose.nfs.yml --profile nfs-demo down
```
