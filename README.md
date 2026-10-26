# Werewolf Haskell — game Ma Sói nhiều người chơi

Game Ma Sói chạy trên trình duyệt, với Haskell Server quản lý luật chơi và trạng thái phòng. Trình duyệt gửi `Command` qua WebSocket; Server kiểm tra lệnh, cập nhật `GameState` và trả về `Event`. Client chỉ hiển thị thông tin mà Server cho phép người chơi đó xem.

Dự án hỗ trợ ván **8 hoặc 9 người**; cấu hình 9 người là kịch bản demo chính. Game có Lobby, Ready, phân vai, hành động ban đêm, thảo luận và chat ban ngày, bỏ phiếu, kỹ năng Thợ Săn, điều kiện thắng và công khai vai khi kết thúc. Người chơi có thể kết nối lại để tiếp tục ván đang chạy. Luật chi tiết nằm trong [đặc tả T01](docs/T01-game-rules.md).

## Chơi trực tuyến

**Mở game tại [werewolf-haskell.onrender.com](https://werewolf-haskell.onrender.com/).** Người chơi chỉ cần trình duyệt; không cần cài Haskell hay Docker để tham gia bản web.

1. Một người tạo phòng và chia sẻ mã phòng cho những người còn lại.
2. Mỗi người nhập tên, tham gia phòng và chọn **Sẵn sàng**.
3. Khi phòng đủ 8 hoặc 9 người và tất cả đã sẵn sàng, Host bắt đầu ván.

Nếu trang chưa tải ngay, hãy chờ dịch vụ khởi động rồi tải lại. Trạng thái ván đang chơi được giữ trong bộ nhớ Server, nên ván sẽ không được khôi phục nếu dịch vụ khởi động lại.

## Chạy game bằng Docker

Cần Docker Desktop đang hoạt động. Từ thư mục gốc của repository:

```powershell
docker compose up --build --detach
docker compose ps
curl.exe --fail http://127.0.0.1:8080/health
```

Mở <http://127.0.0.1:8080> để chơi. Endpoint `/health` trả về `{"status":"ok"}` khi Server sẵn sàng. Docker Compose chạy cả Game Server và Analytics Worker; Worker chỉ nhận bản tóm tắt trận đấu sau khi ván kết thúc. Xem log bằng `docker compose logs --tail=100 server analytics-worker`.

```powershell
docker compose down
```

Compose và giao diện local đang dùng cổng `8080`. Không commit `.env` hoặc thông tin bí mật. Hướng dẫn kiểm tra từ bản clone sạch nằm trong [tài liệu Docker và CI](docs/s03-docker-ci.md).

## Chạy bằng GHC/Cabal

Toolchain của dự án là **GHC 9.6.6** và **Cabal 3.10**. Trên Windows, nên đặt repository ở đường dẫn chỉ gồm ký tự ASCII, ví dụ `C:\dev\werewolf-haskell`, để tránh lỗi package database của một số bản GHC/Cabal.

```powershell
cabal update
cabal build all --enable-tests
cabal test all --enable-tests
```

Để chạy cả hai tiến trình ở local, mở hai terminal trong thư mục repository:

```powershell
# Terminal 1: Analytics Worker
cabal run analytics-worker
```

```powershell
# Terminal 2: Game Server và giao diện web
cabal run werewolf-server
```

Sau đó mở <http://127.0.0.1:8080>. Mặc định Worker nghe TCP cổng `9090`; Server kết nối đến `127.0.0.1:9090`. Các biến `ANALYTICS_HOST`, `ANALYTICS_PORT`, `ANALYTICS_OUTPUT` và `APP_PORT` được mô tả trong [tài liệu X02](docs/X02_ANALYTICS.md). Nếu chỉ chạy Server, game vẫn hoạt động khi Worker không có mặt; dữ liệu analytics sẽ chưa được ghi cho đến khi Worker kết nối lại.

## Các phần mở rộng

| Phần | Vai trò trong đồ án | Chạy/đọc thêm |
| --- | --- | --- |
| **X01 — Mô phỏng song song** | Chạy nhiều ván độc lập bằng `parMap rdeepseq`, so sánh kết quả tuần tự và song song, thống kê tỷ lệ thắng. Không thay đổi GameLoop thời gian thực. | `cabal run werewolf-simulate`; [phương pháp và số liệu](docs/X01-parallel-simulation.md), [CSV kết quả](report/balance.csv) |
| **X02 — Analytics Worker** | Tiến trình riêng nhận `MatchSummary` qua TCP/JSON Lines; Game Server tiếp tục chạy khi Worker lỗi hoặc khởi động lại. | [Cấu hình và kiểm thử X02](docs/X02_ANALYTICS.md) |
| **X03 — NFS Replay Store** | Lưu bản tóm tắt replay đã loại thông tin riêng tư trên thư mục chia sẻ. Lỗi mount hoặc quyền truy cập không làm dừng ván. | [Quy trình NFS demo](docs/X03_NFS_REPLAY.md) |

NFS là **profile demo tùy chọn**. Cấu hình Docker và bản triển khai thông thường không cần NFS. Replay X03 là `MatchSummary`, không phải toàn bộ `GameState` hay lịch sử chat; NFS không lưu và không đồng bộ trạng thái game đang diễn ra.

Để thử NFS bằng Docker trên máy hỗ trợ NFSv4, khởi động NFS Server trước, sau đó chạy Game Server và Worker với profile demo:

```powershell
docker compose -f compose.yaml -f docker-compose.nfs.yml --profile nfs-demo up -d nfs-server
docker compose -f compose.yaml -f docker-compose.nfs.yml --profile nfs-demo up --build server analytics-worker
```

Nhấn `Ctrl+C` để dừng lệnh thứ hai, rồi chạy `docker compose -f compose.yaml -f docker-compose.nfs.yml --profile nfs-demo down`. Nếu Docker daemon không kết nối được NFS qua `127.0.0.1`, xem cách đặt `NFS_HOST` và kiểm tra dữ liệu trong [hướng dẫn X03](docs/X03_NFS_REPLAY.md).

## Triển khai trên Render

Tạo **Web Service** từ repository với Docker runtime và `Dockerfile` ở thư mục gốc. Cấu hình `PORT=8080` và `APP_PORT=8080` để cổng Render mong đợi khớp với cổng Haskell Server đang nghe; đặt HTTP health check path là `/health`. Server phục vụ cả trang web và WebSocket `/ws` trên cùng một cổng. Khi mở trang bằng HTTPS, client dùng `wss://` cùng hostname.

Dockerfile mặc định chỉ khởi động Game Server. Muốn lưu analytics trên Render thì cần một dịch vụ Worker riêng có kết nối nội bộ và nơi lưu dữ liệu phù hợp; còn bản demo NFS là cấu hình Docker local, không dùng trong Web Service này. Xem [hướng dẫn Docker của Render](https://render.com/docs/docker), [cấu hình cổng](https://render.com/docs/web-services#port-binding) và [WebSocket](https://render.com/docs/websocket). Sau khi deploy, kiểm tra `https://<ten-dich-vu>.onrender.com/health` và chơi thử trên 2–3 trình duyệt; lưu kết quả vào [checklist T12](docs/T12-full-game-e2e.md).

## Kiểm thử và CI

```powershell
cabal build all --enable-tests --ghc-options=-Werror
cabal test all --enable-tests --test-show-details=direct
node --check web/app.js
node --test test/T06UiSpec.cjs test/T07UiSpec.cjs test/T13UiSecuritySpec.cjs
docker compose config
```

GitHub Actions chạy các bài test Haskell với coverage, lặp lại toàn bộ suite, chạy test giao diện, kiểm tra cấu hình Compose và khởi động Docker để gọi `/health`. [T12](docs/T12-full-game-e2e.md) có bài test tự động 9 WebSocket client đi qua một ván hoàn chỉnh; [T13](docs/T13_RELEASE_HARDENING.md) mô tả các giới hạn đầu vào, log an toàn và bước kiểm tra trước phát hành.

## Cấu trúc repository

```text
app/                  Game Server, Analytics Worker, simulator
src/Domain/           Kiểu dữ liệu, luật thuần, replay và mô phỏng
src/Protocol/         Command/Event JSON và MatchSummary
src/Server/           WebSocket, phòng, STM, broadcast, replay storage
src/Analytics/        Lưu kết quả analytics
web/                  Giao diện trình duyệt
test/                 Unit, property, integration, E2E và UI tests
docs/                 Luật, kiến trúc, hướng dẫn từng task và minh chứng
report/               Số liệu mô phỏng X01
```

Xem [kiến trúc và luồng `JoinGame`](docs/s04-architecture.md), [protocol T02](docs/T02-contract.md) và [ma trận test T11](docs/T11-test-matrix.md) để truy vết từ chức năng đến code và bài kiểm tra.

## Giới hạn và trạng thái hoàn thiện

- `GameState` của phòng đang nằm trong bộ nhớ Server. Kết nối lại được hỗ trợ khi Server còn chạy; khởi động lại Server không khôi phục ván đang diễn ra.
- X02 và X03 chỉ lưu dữ liệu tổng hợp đã lọc. Chúng không thay thế database lưu ván hoặc trạng thái phòng.
- Bài test T12 đã tự động hóa ván 9 người. [Checklist T12](docs/T12-full-game-e2e.md) vẫn cần ảnh/video 2–3 trình duyệt thật và kết quả kiểm tra môi trường triển khai.
- Liên kết báo cáo, slide, video demo và release cuối (T14–T15) cần được bổ sung vào README khi các tài liệu đó được công bố. Tài liệu có thể được lưu ngoài repository.

## Đóng góp

Đọc [CONTRIBUTING.md](CONTRIBUTING.md) và [quy trình Git S01](docs/s01-github-workflow.md). Thay đổi đi qua Issue → nhánh riêng → Pull Request vào `develop` → review và CI → merge. `main` dành cho bản phát hành cuối từ `develop`.
