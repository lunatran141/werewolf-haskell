# T13 — Hoàn thiện Phát hành, Bảo mật Log & Cổng Kiểm thử CI (Release Hardening)

Task T13 không thêm tính năng gameplay mới mà đóng vai trò khóa chặt các cổng an toàn (Safety & Quality Gates), biến bản tích hợp T12 và các phần mở rộng X01–X03 thành một Release Candidate ổn định, tái lập được.

---

## 1. Các Cổng An toàn (Release Gates)

- **Giới hạn đầu vào và tài nguyên (Input & Resource Limits — E14)**:
  - Hàng đợi lệnh của phòng (`roomCommands` `TBQueue`) và hàng đợi gửi ra của từng kết nối (`OutboundQueue`) đều có giới hạn sức chứa cố định. Khi client spam lệnh hoặc đọc quá chậm (slow consumer), hệ thống từ chối hoặc đánh dấu overflow ngay lập tức trong bộ nhớ giới hạn mà không treo luồng xử lý.
  - Nội dung chat được giới hạn tối đa **300 ký tự** đồng bộ trên cả trình duyệt và Server.
  - Tên người chơi được chuẩn hóa và giới hạn tối đa **30 ký tự** trên Server.
  - Các frame WebSocket vượt quá **4096 bytes** bị từ chối ngay trước bước giải mã JSON (`clientMessageWithinLimit`).
- **Bảo vệ quyền riêng tư xuyên suốt (Privacy Boundary — E15)**:
  - Giữ vững toàn bộ các kiểm thử lọc sự kiện riêng tư theo vai trò và kênh chat từ T07/T08, kiểm thử payload tổng hợp của X02 và kiểm thử replay đã làm sạch của X03.
- **Ghi log có cấu trúc kèm Correlation ID & Che dữ liệu nhạy cảm (`Server.SafeLog`)**:
  - Game Server, Analytics Publisher, Replay Store và Analytics Worker xuất log trên từng dòng JSON (JSON Lines).
  - Hỗ trợ bộ 5 trường correlation ID thống nhất gồm `requestId`, `gameId`, `playerId`, `eventType`, `errorCode` (`CorrelationLog` / `encodeCorrelationLogLine`) theo đặc tả Sheet 03 Dòng 70 & Sheet 04 Dòng 35.
  - Mọi trường có khóa nhạy cảm (`role`, `chat`, `message`, `target`, `token`, `secret`, `password`, `payload`, `private`, `seer`, `witch`, `wolf`) hoặc giá trị chứa tên vai trò bí mật đều tự động bị thay thế bằng `"[REDACTED]"`.
- **An toàn giao diện trình duyệt & Khả năng truy cập (Browser Safety & Accessibility)**:
  - Nội dung chat của người chơi chỉ được gắn qua `textContent` / `createTextNode`, tuyệt đối không chèn qua `innerHTML`, `insertAdjacentHTML` hay `document.write` (chống XSS).
  - Hộp thoại hướng dẫn chung (`#game-help-dialog`) và hộp thoại khả năng vai trò (`#role-help-dialog`) sử dụng phần tử `<dialog>` chuẩn với `aria-labelledby`, nút đóng có `autofocus` và hỗ trợ phím `ESC`.
- **CI & Clean-Clone Docker**:
  - GitHub Actions biên dịch toàn bộ thành phần với cờ `--ghc-options=-Werror` (mọi cảnh báo đều được xem là lỗi), chạy toàn bộ bộ test Haskell hai lần (gồm một lượt đo coverage), chạy toàn bộ 4 bộ test trình duyệt (`T06UiSpec.cjs`, `T07UiSpec.cjs`, `AtmosphereAudioSpec.cjs`, `T13UiSecuritySpec.cjs`), kiểm tra cấu hình Compose (`compose.yaml` và `docker-compose.nfs.yml`) và chạy smoke test `/health` trên container Docker.

---

## 2. Lệnh Kiểm tra Phát hành Local

```powershell
# 1. Biên dịch nghiêm ngặt không cảnh báo
cabal build all --enable-tests --ghc-options=-Werror

# 2. Chạy toàn bộ test Haskell (kèm coverage và chạy lặp kiểm tra tính ổn định)
cabal --project-file=cabal.project.coverage test all --enable-tests --test-show-details=direct
cabal test all --enable-tests --test-show-details=direct

# 3. Kiểm tra cú pháp JS và chạy toàn bộ 4 bộ test UI / Audio / Security
node --check web/app.js
node --test test/T06UiSpec.cjs test/T07UiSpec.cjs test/AtmosphereAudioSpec.cjs test/T13UiSecuritySpec.cjs

# 4. Kiểm tra cấu hình Docker Compose và chạy smoke test container
docker compose config
docker compose -f compose.yaml -f docker-compose.nfs.yml --profile nfs-demo config
docker compose up --build --detach
docker compose ps
curl.exe --fail http://127.0.0.1:8080/health
docker compose down --volumes --remove-orphans
```

Đối với quy trình chạy thử nghiệm tích hợp NFSv4 bằng Docker profile `nfs-demo`, xem hướng dẫn chi tiết tại [docs/X03_NFS_REPLAY.md](X03_NFS_REPLAY.md).
