# T07 — Chat theo ngày, Dashboard và Kết quả ván chơi

## Mục tiêu

T07 hoàn thiện giao diện chơi sau khi người dùng tạo hoặc tham gia phòng. Phạm vi gồm dashboard 9 người, chat công khai ban ngày, chat riêng cho Sói ban đêm, lịch sử chat theo ngày/kênh, hướng dẫn vai trò, trạng thái người chết và màn hình kết quả cuối ván.

T07 không cho trình duyệt tự quyết định vai trò, mục tiêu hợp lệ, thời gian giai đoạn hoặc kết quả thắng/thua. Các dữ liệu này phải đến từ trạng thái và sự kiện của Server.

## Chức năng đã hoàn thành

### Dashboard và ngoại hình

- Sau CreateRoom/JoinGame, giao diện chuyển từ form vào dashboard cố định tối đa 9 ô.
- Mỗi ô hiển thị tên, Host, trạng thái Ready, sống/chết và ngoại hình do Server gửi.
- Ngoại hình gồm kiểu tóc, màu tóc, màu da, trang phục và phụ kiện; ảnh nhân vật được dựng từ các lớp SVG.
- Có thể chọn mục tiêu trực tiếp bằng ô người chơi; ô đang chọn dùng viền tím, không dùng dấu tick che nhân vật.
- Người chết được đánh dấu trên ô nhưng vai thật không bị công khai trước khi ván kết thúc.
- Khi nhận `GameRolesRevealed` ở GameOver, dashboard mới hiển thị toàn bộ vai trò.

### Vai trò và khả năng riêng

- `YourRole` chỉ được gửi cho đúng người sở hữu vai.
- Nút **Khả năng của tôi** ưu tiên nội dung `ability` riêng do Server gửi, thay vì phụ thuộc vào mô tả viết cứng trong JavaScript.
- Sói nhận danh sách đồng đội riêng từ `WolfTeam`; người không phải Sói không nhận dữ liệu này.
- Danh sách mục tiêu ban đêm lọc theo người còn sống và luật của từng vai.
- Bảo vệ không thể bảo vệ lại mục tiêu của đêm trước.
- Phù thủy chỉ được cứu sau khi Sói khóa nạn nhân, có thể dùng thuốc cứu, thuốc độc hoặc bỏ lượt; trạng thái thuốc được khôi phục khi reconnect.
- Thợ săn chỉ thấy bộ chọn bắn khi Server phát `HunterShotPending`; khi còn sống bình thường không có hành động ban đêm.

### Chat và lịch sử

- `PublicDay`: người còn sống được chat chung trong Day.
- `WolvesNight`: chỉ Sói còn sống được gửi và nhận chat riêng trong Night.
- Tin nhắn rỗng hoặc dài hơn 300 ký tự bị từ chối.
- Mỗi tin có `roomId`, `day`, `channel`, `messageId`, `sequence`, `senderId` và `text`.
- Server lưu lịch sử theo phòng; UI nhóm lịch sử theo Ngày 1, Ngày 2... và theo kênh.
- Khi Voting được chốt, Server lưu một tin hệ thống chứa số vòng, bảng phiếu và
  người bị loại; lượt bắn Thợ săn và danh sách người chết cũng được lưu. Vì vậy
  đổi sang đêm/vòng mới hoặc reconnect vẫn xem lại được trong chat ngày cũ.
- UI dùng `messageId`/`sequence` để giữ đúng thứ tự và không hiển thị trùng tin.
- Tin mới hiện thành bong bóng trên ô người gửi rồi tự ẩn; snapshot lịch sử cũ không tạo bong bóng mới.
- Snapshot chat Sói chỉ được lọc và gửi cho Sói còn sống.

### Phối hợp Sói

- Mỗi Sói chọn một mục tiêu hợp lệ; Sói không thể chọn bản thân hoặc đồng đội.
- UI hiển thị số Sói đã gửi lựa chọn trên tổng số Sói còn sống.
- Khi lựa chọn đã được khóa, Server gửi mục tiêu cuối qua `WolfTargetLocked`.
- Trường hợp nhiều Sói chọn khác nhau được giải quyết theo luật phía Server; trình duyệt chỉ hiển thị kết quả đã khóa.

### Thời gian và chuyển giai đoạn

- Day có 180 giây thảo luận, sau đó Server tự chuyển sang Voting.
- Mỗi người còn sống có thể bấm **Đồng ý chuyển sang bỏ phiếu** một lần. Chỉ
  khi 100% người còn sống đồng ý, Server mới bỏ qua thời gian còn lại và chuyển
  ngay sang Voting; nếu chưa đủ người, đồng hồ 180 giây tiếp tục chạy.
- Voting có 60 giây; hết giờ Server tự chốt kể cả khi chưa đủ phiếu.
- Đồng hồ dùng thời hạn từ Server và không tự reset khi nhận snapshot mới hoặc reconnect.
- UI chỉ mở nút chat, chọn mục tiêu và gửi hành động ở đúng phase.
- Bảng Voting mở ngay từ Voting vòng 1; số vòng lấy trực tiếp từ snapshot Server.

### Rời phòng sau khi kết thúc

- Khi ván kết thúc, mọi người chơi đều có nút **Rời phòng và quay lại**.
- Mỗi người tự rời phòng; thao tác này không reset hoặc bắt những người còn lại chơi tiếp.
- Nếu Host rời, Server chuyển Host cho người còn lại; nếu người cuối cùng rời,
  RoomRuntime được dọn khỏi registry.
- Trình duyệt xóa session phòng cũ và trở về form ban đầu để người chơi tự tạo
  phòng mới hoặc tham gia một phòng khác.

### Kết quả ván chơi

- Dân thắng khi không còn Sói.
- Sói thắng khi số Sói còn sống lớn hơn hoặc bằng số người phe Dân còn sống.
- Không còn ai sống thì hòa.
- Không kết thúc ván khi Thợ săn vẫn còn quyền bắn đang chờ xử lý.
- Màn hình GameOver hiển thị kết quả và vai thật của tất cả người chơi sau `GameRolesRevealed`.

### Reconnect

- Trình duyệt lưu reconnect token và dùng lại để vào đúng phòng/người chơi.
- Server khôi phục snapshot phòng, vai riêng, đồng đội Sói, lịch sử chat và trạng thái hành động riêng.
- Trạng thái riêng gồm hành động đêm đã gửi, thuốc của Phù thủy và mục tiêu Bảo vệ đêm trước.
- Dữ liệu hiện nằm trong bộ nhớ tiến trình Server; tắt hẳn Server sẽ không khôi phục được ván. Persistence bằng database nằm ngoài phạm vi T07.

## Luồng dữ liệu chính

`Browser intent → WebSocket → xác thực session/phòng → queue STM → Domain validation → commit state/event → lọc Public/Private/TeamOnly → Browser render`

Browser không được gửi `actorId`, tự gán role hoặc tự công bố người chết. Server lấy danh tính từ session, kiểm tra phase/quyền và chỉ chuyển sự kiện tới đúng nhóm người nhận.

## Contract và sự kiện T07

Các loại dữ liệu chính được sử dụng:

- `ChannelChat` / `ChatMessage`: gửi và nhận tin theo `PublicDay` hoặc `WolvesNight`.
- `ChatHistorySnapshot`: lịch sử đã lọc theo người nhận.
- `WolfTeam`: danh sách ID Sói, chỉ gửi riêng cho Sói.
- `WolfVoteUpdated`: tiến độ lựa chọn mục tiêu của Sói.
- `WolfTargetLocked`: mục tiêu cuối đã được Server khóa.
- `PrivateActionState`: trạng thái hành động/thuốc/Bảo vệ riêng của người nhận.
- `SkipDiscussion` / `DiscussionSkipState`: xác nhận bỏ qua thảo luận và tiến
  độ đồng thuận do Server quản lý.
- `PlayerDied`: chỉ công khai ID người chết, không kèm vai.
- `GameFinished`: kết quả thắng/thua/hòa.
- `GameRolesRevealed`: công khai vai trò toàn bộ người chơi tại GameOver.

Quyền hiển thị:

| Dữ liệu | Người nhận |
|---|---|
| Dashboard/Lobby snapshot, phase, người chết, kết quả | Public |
| Vai của chính mình, trạng thái thuốc/hành động | PrivatePlayerId |
| Chat Sói, đồng đội Sói, tiến độ/mục tiêu Sói | TeamOnly Wolves |
| Tất cả vai trò | Public nhưng chỉ tại GameOver |

## File liên quan

| File | Trách nhiệm |
|---|---|
| `src/Domain/Types.hs` | Trạng thái người chơi, chat, phase, winner và dữ liệu hành động riêng |
| `src/Domain/Engine.hs` | Luật chat, kết quả ván và phát event |
| `src/Domain/Validation.hs` | Kiểm quyền chat, phase, người sống và mục tiêu hợp lệ |
| `src/Protocol/Types.hs` | Kiểu Client/Server message và JSON contract |
| `src/Server/Room.hs` | Bộ nhớ lịch sử chat, sequence và reconnect trong tiến trình |
| `src/Server/GameLoop.hs` | Commit trạng thái, timer Day/Voting và điều phối phase |
| `src/Server/Broadcast.hs` | Lọc Public/PrivatePlayerId/TeamOnly |
| `src/Server/WebSocket.hs` | Session, reconnect và gửi snapshot riêng đúng người |
| `web/index.html` | Cấu trúc dashboard, chat, FAQ, hành động và kết quả |
| `web/style.css` | Giao diện 9 ô, trạng thái mục tiêu, người chết và nền sao |
| `web/app.js` | Render snapshot/event, lịch sử chat, timer và thao tác người dùng |
| `web/avatar.js` | Ghép các lớp SVG thành ngoại hình nhân vật |
| `test/T07WinSpec.hs` | Luật thắng, chat, protocol và mô tả vai |
| `test/T07UiSpec.cjs` | Hành vi dashboard/chat/timer/reconnect trên UI |
| `test/T05WebSocketSpec.hs` | Kịch bản WebSocket thật liên quan reconnect và dữ liệu riêng |

## Cách kiểm tra

Đóng tiến trình Server cũ trước khi build để tránh Windows khóa file `.exe`.

```powershell
cd C:\Users\Ngan\Documents\LTH\werewolf-haskell
cabal test t07-win-test protocol-lobby-test t05-websocket-test --offline --test-show-details=direct
```

Nếu `node` chưa có trong PATH, dùng runtime hiện có của Codex:

```powershell
$nodeExe = "C:\Users\Ngan\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
& $nodeExe --check .\web\app.js
& $nodeExe --check .\web\avatar.js
& $nodeExe --test .\test\T07UiSpec.cjs
```

Kiểm tra toàn dự án trước khi cập nhật PR:

```powershell
cabal build all --offline
cabal test all --offline --test-show-details=direct
git diff --check
git status --short
```

Chạy thử giao diện cần hai tiến trình riêng:

```powershell
# Terminal 1: WebSocket Server
cabal run werewolf-server

# Terminal 2: HTTP tĩnh cho giao diện
python -m http.server 5500 --directory web
```

Mở `http://localhost:5500`. Server game lắng nghe WebSocket ở cổng 8080; HTTP server cổng 5500 chỉ phục vụ các file giao diện cho trình duyệt.

## Trạng thái xác nhận gần nhất

- `test/T07UiSpec.cjs`: 24/24 trường hợp PASS.
- `t07-win-test`: bao gồm test thành viên/Host tự rời phòng tại GameOver.
- `protocol-lobby-test`: kiểm tra JSON Lobby và `LeaveGame`.
- `cabal test all --enable-tests --test-show-details=direct`: toàn bộ 14 test suite PASS.
- `git diff --check`: không có lỗi whitespace; Windows có thể cảnh báo chuyển LF thành CRLF.

## Phối hợp và giới hạn

- T07 dùng timer và Voting từ T06, hành động Night từ T05 và routing/snapshot từ phần Server/T08.
- Không đổi luật hoặc JSON contract một phía khi chưa đồng bộ với các thành viên phụ trách những phần trên.
- Không commit `dist-newstyle`, file log, token hoặc build artifact.
- Chỉ commit/push sau khi review danh sách file thay đổi và chạy lại test toàn dự án.
