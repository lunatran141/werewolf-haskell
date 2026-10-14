# T06 — Vote Rules + Protocol + Handler + UI

## Phạm vi và điểm nối với nhóm

T06 xử lý từ lúc phòng vào Voting đến khi chốt phiếu, xử lý Hunter, reveal người chết và chuyển Night/GameOver. Hunter chết ở Night cũng được xử lý trước khi T05 hoàn tất sang Day. Không thay đổi preset 8/9 người, luật Night hay cách tăng vòng của T04.

Repo hiện chưa có luồng StartGame/điều phối toàn ván trên UI. Bộ điều phối T04/T05 cần gọi `atomically (applyInternalCommand room AdvancePhase)` khi hết Day; phòng phải đang có trạng thái Day hợp lệ. Đây là hàm Haskell nội bộ, không phải thông điệp được Browser quyền gửi. Không ghi thẳng TVar khi tích hợp vì sẽ bỏ qua event/version.

Worker hiện có `runLobbyLoop` dùng chung queue và tự mở timer khi nhận thấy Voting. Mặc định Voting 60 giây, Hunter 30 giây; test truyền thời hạn ngắn qua `runGameLoopWithTimeouts`. Gửi phiếu không kéo dài timer. Hết hạn thì chốt dù chưa đủ phiếu; người chưa chọn được tính là bỏ qua, không tạo phiếu giả. Không thêm timer Day/Night hoặc nút Start thuộc phần khác.

## Luồng thống nhất

`UI → Vote JSON → xác thực session/phòng → queue STM → Domain validation → commit state/version/event → lọc public/private → UI`

`Hết hạn Voting → tally → hòa/không phiếu: không loại; cao nhất duy nhất: lynch → chờ Hunter nếu có → reveal → checkWin → Night hoặc GameOver`

Luật: không tự vote, người chết không vote, mục tiêu phải tồn tại và còn sống, mỗi người chỉ một phiếu/vòng. Phiếu sai không commit, không tăng version, không phát event. Request đã được chấp nhận bị gửi lại trả `DuplicateRequest`; request khác nhưng đã vote trong vòng trả `AlreadyVoted`. Cache request nằm trong bộ nhớ phòng, không phải cơ chế persistence/reconnect sau restart.

Chỉ Hunter đang pending được chọn bắn/bỏ qua dù đã chết. Hết giờ tự bỏ qua. Không chốt thắng hoặc reveal vai trước khi giải quyết xong Hunter. Ưu tiên Draw → Village → Wolves theo luật chung.

## File và kiến thức áp dụng

| File | Vai trò / kiến thức |
|---|---|
| `src/Domain/Types.hs` | ADT cho lỗi duplicate và event kết quả kiểm phiếu |
| `src/Domain/Rules.hs` | Hàm thuần, list/fold đếm phiếu, tìm cao nhất duy nhất, kiểm thắng |
| `src/Domain/Validation.hs` | `Either` và invariant: phiếu/state hợp lệ trước commit |
| `src/Domain/Engine.hs` | Pattern matching, `Maybe`, chuỗi xử lý `Either`; Vote/ResolveVoting/Hunter và tái sử dụng transition T04 |
| `src/Protocol/Types.hs` | ADT + Aeson để đọc/ghi JSON có kiểu |
| `src/Server/Room.hs` | TVar lưu request đã nhận theo actor, tách khỏi luật thuần |
| `src/Server/GameLoop.hs` | STM/TBQueue/TChan, commit nguyên tử, timer và chống replay |
| `src/Server/Broadcast.hs` | Lọc event theo người nhận, snapshot không chứa vai người sống |
| `src/Server/WebSocket.hs` | Lấy actor từ session, kiểm phòng, đưa intent vào queue, phản hồi đúng request |
| `web/index.html`, `web/style.css`, `web/app.js` | Form bỏ phiếu/Hunter, cập nhật từ snapshot, khóa thao tác khi không được phép |
| `werewolf-server.cabal` | Khai báo bộ test; `-threaded` cho test dùng timer STM |
| `test/DomainT06Spec.hs`, `test/T06Main.hs` | Kiểm thử luật, invariant, Hunter Night/Voting, ván 8/9 |
| `test/T06ProtocolSpec.hs`, `test/T06GameLoopSpec.hs` | JSON, quyền nhận event, session, commit và duplicate |
| `test/T06WebSocketSpec.hs` | Hai kết nối thật, timer thật, invalid/duplicate/tie/lynch/Hunter |
| `test/T06UiSpec.cjs` | Chạy app.js thật với DOM giả tối thiểu, không cần thư viện Node ngoài |

Các khối xử lý mới có comment tiếng Việt. Không diễn giải thành đã đối chiếu đầy đủ 5 sheet online: bản triển khai dựa trên đầu ra T06 đã xác nhận và contract/luật có trong repo.

## Hợp đồng JSON bổ sung (giữ tên roomId của nhóm)

```json
{"type":"Vote","requestId":"v1","roomId":"R","targetId":"p2"}
{"type":"HunterChoice","requestId":"h1","roomId":"R","targetId":"p2"}
{"type":"HunterChoice","requestId":"h2","roomId":"R","targetId":null}
```

`targetId: null` là Hunter bỏ qua; thiếu targetId bị từ chối. Client không quyết định actor, role, kết quả hay phase.

- `ActionAccepted`: `requestId`, `roomId`; chỉ xác nhận request tương ứng.
- `CommandRejected`: giữ contract lỗi hiện có, gồm requestId/code/message.
- `VoteUpdated`: receipt riêng, không lộ mục tiêu của voter cho người khác.
- `VotingResolved`: roomId, tally dạng `[["p2",2]]`, targetId hoặc null. Tally chỉ công khai sau khóa phiếu.
- `VotingSnapshot`: roomId, phase, day, players (playerId/displayName/alive), hasVoted của chính người nhận, canShoot của chính người nhận, resolved, result. Không có role người sống hoặc danh sách phiếu cá nhân. Người chết đang chờ batch reveal vẫn được che trạng thái cho tới khi hoàn tất Hunter.
- `PlayerRoleRevealed`, `PhaseChanged`, `GameFinished`, `HunterShotPending/Resolved`: sử dụng contract sự kiện hiện có.

Phiên bản commit vẫn nằm ở RoomUpdate nội bộ. Chưa bổ sung envelope gameVersion/sequence hay reconnect cùng định danh cho toàn protocol: đây là điểm tích hợp connection hardening chung, không được xem là đã hoàn thành bởi T06.

## Kiểm tra và chạy lại

```powershell
cabal test all --offline --test-show-details=direct
node --check web/app.js
node --test test/T06UiSpec.cjs
```

Các lệnh này chỉ dùng được khi dependency đã có. Không tự cài hay nâng GHC/Cabal. Kiểm thử socket mở localhost; sandbox có thể cần cấp quyền. Test T06 socket dùng cổng 18766, fixture dựng đủ 8 người qua luật T04/T05 rồi bước vào Voting; đó là dữ liệu test, không phải endpoint sửa state trong production.

Trong phiên triển khai, các bộ Haskell được biên dịch trực tiếp bằng GHC với package database đã cài, không coi đây là bằng chứng `cabal test all` đã chạy thành công. UI test là kiểm thử hành vi với DOM giả, chưa phải kiểm tra trực quan bằng trình duyệt thật. Khi review UI trong ván thật, cần có bộ điều phối của nhóm đưa phòng vào Voting như mô tả trên.

Kết quả kiểm tra 14/10/2026:

- T06: 24 Domain + 11 Protocol + 3 GameLoop + 6 WebSocket thật + 5 UI = 49 kiểm thử, không thất bại.
- Hồi quy nhóm: 223 kiểm thử T02/T03/T04/T05/Protocol/GameLoop, không thất bại; skeleton smoke test cũng qua. Các property test hiện có chạy 100 mẫu/property.
- `app/Main.hs` qua kiểm tra kiểu; `node --check web/app.js` và `git diff --check` qua.
- Package database local có hai bản build của Warp cùng version. Khi kiểm tra app trực tiếp bằng GHC đã chỉ định một package-id, không xóa/cài lại package hay đổi cấu hình máy.
- Các test socket kết thúc với exit code 0. Khi client test đóng nhanh vẫn có log ngoại lệ ở thread gửi (`ConnectionClosed`/`Network.Socket.sendBuf ... Invalid argument`) từ cơ chế cleanup kết nối hiện có. Chưa khẳng định connection hardening toàn server đã hoàn tất; cần xử lý riêng vòng đời writer/cleanup trong phần đó.

## Trước khi tự push

Review riêng các thay đổi T06; không dùng add-all nếu còn tài liệu nhóm đang đổi tên. Không commit build artifact. Thống nhất JSON mới và điểm gọi AdvancePhase với người phụ trách T04/Protocol. Các đổi tên/xóa tài liệu có sẵn trong working tree không thuộc thay đổi T06 này.
