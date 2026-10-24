# T06 — Vote Rules + Protocol + Handler + UI

**Dự án:** Werewolf Haskell
**Task:** T06 – Vote Rules
**Owner:** TV5

## Phạm vi và điểm nối với nhóm

T06 xử lý từ lúc phòng vào Voting đến khi chốt phiếu, xử lý Hunter, công bố ID người chết và chuyển Night/GameOver. Theo hợp đồng T01/T02 mới, vai thật của mọi người chỉ được công khai tại GameOver. Hunter chết ở Night cũng được xử lý trước khi T05 hoàn tất sang Day. Không thay đổi preset 8/9 người, luật Night hay cách tăng vòng của T04.

Bản ghép đã giữ StartGame, phân vai riêng tư và điều phối Night của T05 trên `develop` tại commit `73513ba`. Bộ điều phối chung gọi `atomically (applyInternalCommand room AdvancePhase)` khi hết Day; phòng phải đang có trạng thái Day hợp lệ. Đây là hàm Haskell nội bộ, không phải thông điệp được Browser quyền gửi. Không ghi thẳng TVar vì sẽ bỏ qua event/version. Chưa thêm timer Night.

Worker `runLobbyLoop` dùng chung queue và tự mở timer khi nhận thấy Day hoặc Voting. Mặc định Day 180 giây, Voting 60 giây, Hunter 30 giây; test truyền thời hạn ngắn qua `runGameLoopWithPhaseTimeouts`. Chat và phiếu không kéo dài timer. Hết Day, server chuyển sang Voting; hết Voting, server chốt dù chưa đủ phiếu. Người chưa chọn được tính là bỏ qua, không tạo phiếu giả. Chưa thêm timer Night hoặc nút Start.

## Luồng thống nhất

`UI → Vote JSON → xác thực session/phòng → queue STM → Domain validation → commit state/version/event → lọc public/private → UI`

`Hết hạn Voting → tally → hòa/không phiếu: không loại; cao nhất duy nhất: lynch → chờ Hunter nếu có → công bố ID người chết → checkWin → Night hoặc GameOver`

Luật: không tự vote, người chết không vote, mục tiêu phải tồn tại và còn sống, mỗi người chỉ một phiếu/vòng. Phiếu sai không commit, không tăng version, không phát event. Request đã được chấp nhận bị gửi lại trả `DuplicateRequest`; request khác nhưng đã vote trong vòng trả `AlreadyVoted`. Cache request nằm trong bộ nhớ phòng, không phải cơ chế persistence/reconnect sau restart.

Chỉ Hunter đang pending được chọn bắn/bỏ qua dù đã chết. Hết giờ tự bỏ qua. Không chốt thắng hoặc công bố người chết trước khi giải quyết xong Hunter; vai thật chỉ công khai khi GameOver. Ưu tiên Draw → Village → Wolves theo luật chung.

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
| `test/T06WebSocketSpec.hs` | Kết nối thật, timer, invalid/duplicate/tie/lynch/Hunter; thêm kịch bản 8 client Start → Night → Hunter → Day → Voting |
| `test/T06UiSpec.cjs` | Chạy app.js thật với DOM giả tối thiểu, không cần thư viện Node ngoài |

Các khối xử lý mới có comment tiếng Việt. Không diễn giải thành đã đối chiếu đầy đủ 5 sheet online: bản triển khai dựa trên đầu ra T06 đã xác nhận và contract/luật có trong repo.

## Hợp đồng JSON bổ sung (giữ tên roomId của nhóm)

```json
{"type":"Vote","requestId":"v1","roomId":"R","targetId":"p2"}
{"type":"HunterAction","requestId":"h1","roomId":"R","choice":{"action":"HunterShot","targetId":"p2"}}
{"type":"HunterAction","requestId":"h2","roomId":"R","choice":{"action":"HunterPass"}}
```

Sau merge, dùng duy nhất `HunterAction` theo contract T05: `HunterPass` là bỏ qua; `HunterShot` bắt buộc có targetId. Giao thức thử nghiệm `HunterChoice` trước đó không còn được sử dụng. Client không quyết định actor, role, kết quả hay phase.

- `ActionAccepted`: `requestId`, `roomId`; chỉ xác nhận request tương ứng.
- `CommandRejected`: giữ contract lỗi hiện có, gồm requestId/code/message.
- `VoteUpdated`: receipt riêng, không lộ mục tiêu của voter cho người khác.
- `VotingResolved`: roomId, tally dạng `[["p2",2]]`, targetId hoặc null. Tally chỉ công khai sau khóa phiếu.
- `VotingSnapshot`: roomId, phase, day, players (playerId/displayName/alive), hasVoted của chính người nhận, canShoot của chính người nhận, resolved, result. Không có vai thật của người sống hoặc người chết, cũng không có danh sách phiếu cá nhân. Trạng thái của người chết đang chờ Hunter được che cho tới khi hoàn tất hiệu ứng liên quan.
- `PlayerDied`: công khai PlayerId của người chết sau khi xử lý xong Hunter, không kèm Role/Team. `GameRolesRevealed` chỉ gửi danh sách vai thật khi GameOver. `PlayerRoleRevealed` còn trong parser cũ nhưng không được phát trong luồng mới sau khi PR T02/T05 được tích hợp.
- `PhaseChanged`, `GameFinished`, `HunterShotPending/Resolved`: giữ contract T05. `HunterShotResolved` có cả `hunterId` và `targetId` (null nếu bỏ qua). Handler không còn nhánh `HUNTER_ENGINE_NOT_READY`.

Phiên bản commit vẫn nằm ở RoomUpdate nội bộ. Chưa bổ sung envelope gameVersion/sequence hay reconnect cùng định danh cho toàn protocol: đây là điểm tích hợp connection hardening chung, không được xem là đã hoàn thành bởi T06.

## Kiểm tra và chạy lại

```powershell
cabal test all --offline --test-show-details=direct
node --check web/app.js
node --test test/T06UiSpec.cjs
```

Các lệnh này chỉ dùng được khi dependency đã có. Không tự cài hay nâng GHC/Cabal. Kiểm thử socket mở localhost; sandbox có thể cần cấp quyền. Test T06 socket dùng cổng 18766. Các case tập trung Voting dùng fixture dựng 8 người; case tích hợp sau merge dùng 8 kết nối Join/Ready/StartGame thật, nhận vai và gửi NightAction thật. Chỉ bước Day → Voting được gọi bằng điểm nối nội bộ vì chưa có Day timer. Không có endpoint sửa state trong production.

Ở lần triển khai ban đầu, các bộ Haskell được biên dịch trực tiếp bằng GHC. Kết quả đó được ghi lịch sử bên dưới; kết quả Cabal sau merge được ghi riêng. UI test là kiểm thử hành vi với DOM giả, chưa phải kiểm tra trực quan bằng trình duyệt thật. Khi review UI trong ván thật, cần có bộ điều phối của nhóm đưa phòng vào Voting như mô tả trên.

Kết quả trước khi ghép T05, ngày 14/10/2026 (không dùng thay kết quả sau merge):

- T06: 24 Domain + 11 Protocol + 3 GameLoop + 6 WebSocket thật + 5 UI = 49 kiểm thử, không thất bại.
- Hồi quy nhóm: 223 kiểm thử T02/T03/T04/T05/Protocol/GameLoop, không thất bại; skeleton smoke test cũng qua. Các property test hiện có chạy 100 mẫu/property.
- `app/Main.hs` qua kiểm tra kiểu; `node --check web/app.js` và `git diff --check` qua.
- Package database local có hai bản build của Warp cùng version. Khi kiểm tra app trực tiếp bằng GHC đã chỉ định một package-id, không xóa/cài lại package hay đổi cấu hình máy.
- Các test socket kết thúc với exit code 0. Khi client test đóng nhanh vẫn có log ngoại lệ ở thread gửi (`ConnectionClosed`/`Network.Socket.sendBuf ... Invalid argument`) từ cơ chế cleanup kết nối hiện có. Chưa khẳng định connection hardening toàn server đã hoàn tất; cần xử lý riêng vòng đời writer/cleanup trong phần đó.

## Trước khi tự push

Review riêng các thay đổi T06 và kết quả đồng bộ với `develop`; không dùng add-all nếu còn file ngoài phạm vi. Không commit build artifact. Tác giả tự commit/push sau khi kiểm tra lại các phần phụ thuộc của nhóm.

Ba đổi tên tài liệu đã nằm trong commit T06 trước khi sửa conflict được giữ nguyên; các liên kết README/T02 tới tên cũ được cập nhật. Không phải file của nhóm bị bỏ sót. `develop` local đã được pull fast-forward và kiểm tra khớp origin trước khi ghép. Giữ `docs/T05-night-actions.md` và thay đổi test quyền nhận YourRole từ develop.

## Kết quả sau khi ghép develop — 14/10/2026

- `cabal build all --offline`: PASS với GHC 9.6.6/Cabal 3.16.1.0 đang có trên máy; không cài hoặc đổi toolchain. CI của nhóm dùng Cabal 3.10, cần đợi kết quả riêng trên GitHub.
- `cabal test all --offline --test-show-details=direct`: 13/13 test suites PASS.
- T06: 24 Domain + 12 Protocol + 3 GameLoop + 7 WebSocket + 7 UI = 53 kiểm thử PASS.
- Kịch bản tích hợp 8 client đi qua StartGame/Night tự điều phối của T05, HunterAction T06, Day, điểm nối Voting, tally/lynch và Night tiếp theo.
- `node --check web/app.js`, `node --test test/T06UiSpec.cjs`: PASS. Test UI kiểm tra ID HTML duy nhất và giữ Start/Night sau khi ghép.
- Docker không khả dụng trong PATH local nên chưa chạy `docker compose config` hoặc build container; không đánh dấu Docker PASS.
- Còn log ngoại lệ khi client test đóng socket nhanh; test vẫn exit 0. Chưa mở rộng sửa connection hardening ngoài phạm vi merge này.

## Đồng bộ T06 với PR T02/T05 — 15/10/2026

T01 yêu cầu trước GameOver chỉ công khai PlayerId của người chết; vai thật của toàn bộ người chơi chỉ công khai tại GameOver. PR T02/T05 thêm `Appearance` vào `Player`, đổi sự kiện chết sang `PlayerDied` và phát `GameRolesRevealed` tại GameOver. Bốn bộ test T06 trong thư mục chính đã được cập nhật fixture và kỳ vọng sự kiện tương ứng; logic Vote/Tally/Tie/Lynch và Hunter không thay đổi.

- Trên bản review dựa vào commit `5637142` của PR T02/T05, bốn bộ test T06 chạy qua: 4/4 bộ, 46/46 trường hợp. Thay đổi đã được chép vào thư mục chính nhưng nhánh hiện tại chưa chứa PR T02/T05; không được tính là kết quả test PASS trên nhánh này.
- Để chạy bốn test T06 đã cập nhật, cần tích hợp PR T02/T05 vào cùng nhánh. Không tự nhập 11 file của bạn cùng nhóm khi PR chưa được merge; sau khi PR được merge vào `develop`, đồng bộ nhánh T06 với `develop` rồi chạy lại test.
- Toàn bộ `cabal test all` trên bản review PR T02/T05 còn lỗi ở test T04 (thiếu kỳ vọng `GameRolesRevealed`) và test `server-gameloop-test` (constructor `PlayerView` thêm `alive`/`appearance`). Đây là test của phần nhóm khác, chưa được T06 sửa.
