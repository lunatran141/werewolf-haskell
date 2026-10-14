# T05 — Night Actions, Night UI & Server Integration

> **Ghi chú tích hợp T06 (14/10/2026):** Bản ghép giữ StartGame/Night UI và điều phối T05, đã nối `HunterAction` tới Engine T06 thay cho `HUNTER_ENGINE_NOT_READY`. Hunter UI dùng chung ở Night/Voting; kết quả có `hunterId` như contract T05. Test 8 kết nối thật xác nhận Start → Night → Hunter → Day → điểm nối Voting. Các mô tả scaffold/kết quả bên dưới là lịch sử của bản T05 ngày 13/10; trạng thái và giới hạn sau ghép xem [T06-vote.md](T06-vote.md).

**Dự án:** Werewolf Haskell
**Nhánh làm việc:** `feature/T05-night-actions`
**Cập nhật:** 13/10/2026
**Trạng thái:** Các vai Werewolf, Seer, Guard, Witch đã triển khai và kiểm thử; Hunter UI là phần chuẩn bị tích hợp T06, **chưa hoàn thiện end-to-end**.

## 1. Mục tiêu và phạm vi

T05 thực hiện các hành động ban đêm, kiểm tra luật trong Pure Domain/Engine, kết nối Command/Event qua WebSocket và giao diện riêng theo vai. Server là nguồn xác thực danh tính, vai và trạng thái trò chơi. Client không được tự gọi các lệnh nội bộ `ResolveNight`, `ResolveHunter` hoặc `AdvancePhase`.

| Vai | Hành động | Trạng thái |
| --- | --- | --- |
| Werewolf | `WolfTarget targetId` | Đã triển khai và kiểm thử |
| Seer | `SeerTarget targetId` | Đã triển khai và kiểm thử, kết quả riêng tư |
| Guard | `GuardTarget targetId` | Đã triển khai và kiểm thử |
| Witch | `WitchHeal`, `WitchPoison targetId`, `WitchPass` | Đã triển khai và kiểm thử |
| Hunter | `HunterShot targetId`, `HunterPass` | Có UI/Protocol/Broadcast; **chờ Engine T06** |

**Ngoài phạm vi bàn giao UI T05:** màn hình Day, Voting UI và phần Pure Engine xử lý phát bắn Hunter thuộc T06.

## 2. Luật và các điều kiện chính

### 2.1 Werewolf

- Chỉ Sói còn sống được chọn mục tiêu hợp lệ; không được cắn đồng đội Sói.
- Mỗi Sói chỉ được gửi một phiếu trong đêm. Khi mọi Sói còn sống đã bỏ phiếu, Server gọi `closeWolfVoting state False`.
- Mục tiêu có số phiếu cao nhất duy nhất sẽ bị tấn công; hòa phiếu không có nạn nhân theo `NoElimination`.
- Sau khóa phiếu, Witch còn sống nhận `WitchVictimNotice` riêng tư.
- API thuần hỗ trợ khóa phiếu khi timeout, nhưng cơ chế timeout thực tế chưa được nối với Server.

### 2.2 Seer

- Chọn một người chơi hợp lệ khác chính mình.
- `SeerResult` trả về phe `Wolves` hoặc `Village` và chỉ gửi tới Seer đã thực hiện.

### 2.3 Guard

- Được tự bảo vệ.
- Không được bảo vệ cùng một mục tiêu trong hai đêm liên tiếp.
- Bảo vệ có thể ngăn đòn Sói, nhưng không ngăn thuốc độc của Witch.

### 2.4 Witch

- Mỗi đêm Witch gửi đúng một trong ba lựa chọn: Heal, Poison hoặc Pass.
- Heal cần nạn nhân Sói hợp lệ và thuốc cứu còn sẵn; thông báo nạn nhân được gửi sau khi khóa phiếu Sói.
- Poison yêu cầu mục tiêu hợp lệ, không được tự đầu độc, và có thuốc độc còn sẵn.
- Pass không tiêu hao thuốc.
- UI khóa lựa chọn khi nhận `NightActionAccepted`; các hành động và thông báo riêng tư không bị broadcast sang vai khác.

### 2.5 Hunter — hợp đồng tích hợp T06

- Khi Hunter bị loại trong Night, `resolveNightTurn` có thể tạo `gamePendingHunter` và `HunterShotPending` (private).
- UI Hunter khi còn sống chỉ hiển thị trạng thái chờ; nút Bắn/Bỏ lượt luôn bị khóa.
- Khi nhận `HunterShotPending`, UI có thể chọn mục tiêu hoặc Pass, gửi `HunterAction`.
- `Server.WebSocket` hiện trả `HUNTER_ENGINE_NOT_READY` đối với yêu cầu Hunter trong đúng phòng; **chưa cập nhật GameState hay xác nhận bắn thành công**.
- Chỉ sau khi T06 bổ sung `ResolveHunter` và GameLoop kết nối thành công, hệ thống mới có thể phát `HunterShotResolved` thực tế và hoàn tất Night khi Hunter pending.

## 3. Luồng Night ở Server

```text
Host StartGame (Server tự xáo vai)
  -> PhaseChanged Night + YourRole riêng từng người
  -> Các vai gửi NightAction hợp lệ
  -> Khi mọi Sói bỏ phiếu: closeWolfVoting
  -> WitchVictimNotice (chỉ Witch)
  -> Khi các vai hành động còn sống đã hoàn thành:
       resolveNightTurn
       -> Hunter pending? Có: chờ T06, không công bố kết quả sớm
       -> Không: completeNightTurn
           -> PlayerRoleRevealed
           -> PhaseChanged Day / GameFinished
```

`Server.GameLoop` hiện chỉ tự resolve khi các vai Werewolf, Seer, Guard, Witch còn sống đã gửi hành động, và `gameWolfVotingClosed=True`. Nếu còn người chưa hành động, mất kết nối hoặc không có timeout, đêm có thể chưa kết thúc. Không có Hunter pending thì `completeNightTurn` được gọi ngay trong cùng lần xử lý command thành công.

**Bảo vệ thông tin:** `Server.WebSocket.safeNightEvent` không phát trực tiếp `NightResolved deaths` nhằm tránh lộ danh sách chết trước khi hiệu ứng Hunter hoàn tất. Sau đó các sự kiện reveal/đổi phase được gửi theo hợp đồng của Domain.

## 4. JSON WebSocket

Các command gửi từ Browser sử dụng `requestId`, `roomId` và `choice`, **không truyền PlayerId hay Role**; Server gắn actor dựa trên phiên WebSocket.

**Werewolf**

```json
{"type":"NightAction","requestId":"r01","roomId":"ROOM-01","choice":{"action":"WolfTarget","targetId":"p3"}}
```

**Seer**

```json
{"type":"NightAction","requestId":"r02","roomId":"ROOM-01","choice":{"action":"SeerTarget","targetId":"p2"}}
```

**Guard**

```json
{"type":"NightAction","requestId":"r03","roomId":"ROOM-01","choice":{"action":"GuardTarget","targetId":"p4"}}
```

**Witch — Heal / Poison / Pass**

```json
{"type":"NightAction","requestId":"r04","roomId":"ROOM-01","choice":{"action":"WitchHeal"}}
```

```json
{"type":"NightAction","requestId":"r05","roomId":"ROOM-01","choice":{"action":"WitchPoison","targetId":"p5"}}
```

```json
{"type":"NightAction","requestId":"r06","roomId":"ROOM-01","choice":{"action":"WitchPass"}}
```

**Hunter — đang chờ Engine T06**

```json
{"type":"HunterAction","requestId":"r07","roomId":"ROOM-01","choice":{"action":"HunterShot","targetId":"p5"}}
```

```json
{"type":"HunterAction","requestId":"r08","roomId":"ROOM-01","choice":{"action":"HunterPass"}}
```

### 4.1 Các sự kiện Server

| Sự kiện | Phạm vi | Ý nghĩa |
| --- | --- | --- |
| `YourRole` | Private | Vai do Server phân cho từng người |
| `NightActionAccepted` | Private | Xác nhận hành động hợp lệ |
| `SeerResult` | Private | Trả kết quả soi |
| `WitchVictimNotice` | Private | Thông báo nạn nhân Sói cho Witch |
| `HunterShotPending` | Private | Mở quyền bắn cho Hunter đang pending |
| `HunterShotResolved` | Public theo Domain contract | Chỉ có khi Engine xử lý thực tế |
| `NightResolved` | Public theo Domain contract; hiện được WebSocket chặn | Tránh reveal chết sớm |
| `PlayerRoleRevealed` | Public | Công bố vai sau khi hiệu ứng chết được xử lý |
| `PhaseChanged` | Public | Chuyển phase |
| `GameFinished` | Public | Công bố người thắng/hòa |
| `CommandRejected` | Trả riêng cho kết nối gửi lệnh | Lỗi command, kèm `requestId` khi xác định được |

## 5. Seeded RNG và StartGame

Module `src/Domain/RoleShuffle.hs` cung cấp:

```haskell
shuffleRoles :: RandomGen g => g -> [Role] -> ([Role], g)
shuffleRolesWithSeed :: Int -> [Role] -> [Role]
```

- Cùng danh sách vai và cùng seed cho cùng kết quả, thuận tiện kiểm thử tái lập.
- StartGame thực tế do Server sinh RNG (`newStdGen`) và dùng preset từ `expectedRoles` (8 hoặc 9 người).
- Client không tự chọn vai hay gửi seed để thao túng phân vai.

## 6. File liên quan

| File | Nội dung |
| --- | --- |
| `src/Domain/Types.hs` | Role, Phase, Command, NightChoice, DomainEvent, GameState |
| `src/Domain/Validation.hs` | Điều kiện hợp lệ/invariant của state và hành động |
| `src/Domain/Night.hs` | Tổng hợp phiếu Sói và hiệu ứng Night |
| `src/Domain/Engine.hs` | Xử lý NightAction, resolve, complete, win conditions |
| `src/Domain/RoleShuffle.hs` | Seeded RNG và xáo vai |
| `src/Protocol/Types.hs` | JSON ClientMessage/ServerMessage |
| `src/Server/Broadcast.hs` | Ánh xạ và lọc sự kiện private/public |
| `src/Server/GameLoop.hs` | Dispatch, khóa phiếu, điều phối resolve/complete |
| `src/Server/WebSocket.hs` | Session, phân vai, nhận/gửi thông điệp |
| `web/index.html` | Lobby, Night panels và Hunter UI |
| `web/app.js` | Hiển thị, gửi action, nhận events, trạng thái pending |
| `web/style.css` | CSS Night panels, bảo đảm `[hidden]` được tôn trọng |
| `test/T05NightSpec.hs` | Night logic, validation, win conditions |
| `test/T05RngSpec.hs` | Kiểm thử RNG |
| `test/T05WebSocketSpec.hs` | Kiểm thử WebSocket T05 |
| `test/ProtocolLobbySpec.hs` | JSON round-trip và phân quyền sự kiện |

## 7. Kết quả kiểm thử được báo cáo

Kiểm thử gần nhất trên Windows, GHC 9.6.6:

```powershell
git diff --check
cabal build all
cabal test all --test-show-details=direct
```

| Test suite | Examples | Kết quả |
| --- | ---: | --- |
| `skeleton-test` | 1 | PASS |
| `t02-domain-test` | 38 | PASS |
| `t03-lobby-test` | 17 | PASS |
| `t04-phase-test` | 23 | PASS |
| `t05-night-test` | 84 | PASS |
| `t05-rng-test` | 8 | PASS |
| `protocol-lobby-test` | 36 | PASS |
| `server-gameloop-test` | 13 | PASS |
| `t05-websocket-test` | 4 | PASS |
| **Tổng** | **224** | **9/9 suite PASS** |

**Thử thủ công đã xác nhận:** Lobby/Ready/StartGame, riêng tư của YourRole, Sói/Seer/Guard/Witch, WitchHeal/Poison/Pass, tab Hunter còn sống hiển thị và khóa nút. Trang tải trên Microsoft Edge và đã kết nối WebSocket. Log WebSocket test có dòng `ConnectionClosed`, nhưng suite báo PASS.

**Không nên suy diễn:** Các suite Haskell không kiểm thử cú pháp frontend JavaScript; máy thử nghiệm không nhận lệnh `node`, và chưa có kiểm thử tự động Hunter end-to-end.

## 8. Hạn chế, phụ thuộc và bàn giao

- **Hunter (T06):** cần hàm Engine thực thi HunterShot/Pass, tích hợp GameLoop, kiểm thử authorization, pending, target và hoàn tất Night. Các nút Hunter đã có giao diện nhưng chưa bắn thành công.
- **End-to-end ResolveNight → Day:** logic/server đã có, unit test PASS, nhưng chưa xác nhận đầy đủ bằng 8 tab Edge. Day UI nằm ngoài phạm vi UI T05.
- **Timeout/mất kết nối:** chưa có cơ chế đóng đêm nếu vai bắt buộc không hành động.
- **Thông tin sống/chết trên client:** `PlayerView` không có `lifeStatus`. Danh sách Hunter có thể chứa người đã chết nhưng chưa công bố; Server phải tiếp tục kiểm tra target.
- **Test mới nên thêm khi tích hợp:** JSON HunterAction, `HunterShotPending` chỉ đúng client nhận, HunterShotResolved, và case Hunter pending không kết thúc Night sớm.
- **Mã nguồn:** không commit file thử nghiệm `web/test-*.html`, `t05-review.diff`, `t05-ui-review.diff`.

### Kết luận

T05 Night UI cho **Werewolf, Seer, Guard và Witch** đã sẵn sàng đưa lên nhánh để nhóm review. Phần Hunter UI/Protocol/Broadcast là **integration scaffold**, đang chờ Engine T06. Các phần chưa kiểm thử hoặc thuộc phạm vi thành viên khác không được ghi là đã hoàn thành.
