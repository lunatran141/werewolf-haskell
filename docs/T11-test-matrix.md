# T11 — Kiểm thử chéo, State-Machine Property, Deterministic Replay & Ma trận kiểm thử tổng hợp

## Mục tiêu

Task T11 đóng vai trò là "Quality Gate" toàn diện cho toàn bộ hệ thống Ma Sói Haskell, kết nối và xác minh chéo công việc của tất cả các thành viên (TV1 đến TV5).

Mục tiêu chính bao gồm:
1. **State-Machine Property Testing**: Sử dụng QuickCheck để chứng minh bất biến toàn vẹn (`validateGameInvariant`) luôn được bảo toàn sau mọi chuỗi lệnh `Command` hợp lệ trên cả ván 8 người và 9 người; đồng thời chứng minh các lệnh bị từ chối không làm biến dạng trạng thái (`GameState`).
2. **Cơ sở lý luận Functional Programming (Sheet 04 - Dòng 24 & 25)**: Chứng minh tính chất của `foldl'` và đệ quy cấu trúc (structural recursion / composition) trong hàm `replayCommands`:
   - Base case: `replayCommands s [] == s`
   - Composition step: `replayCommands s (cmds1 ++ cmds2) == replayCommands (replayCommands s cmds1) cmds2`
3. **Deterministic Replay (E16)**: Chứng minh tính tái lập tất định: cùng trạng thái ban đầu và chuỗi `Command` luôn sinh ra cùng kết quả `GameState` và chuỗi `DomainEvent`; bổ sung `replayWithSeed` để replay từ giai đoạn Lobby với Seeded RNG gán vai.
4. **Bảo mật và Quyền riêng tư Broadcast (E15)**: Đảm bảo snapshot công khai (`LobbySnapshot`, `VotingSnapshot`) không chứa vai trò hoặc phe; Dân làng và Sói đã chết không bao giờ nhận thông điệp kênh Sói (`WolvesNight`) hay sự kiện của Tiên Tri/Phù Thủy; vai trò người chơi tuyệt đối không bị lộ trước khi ván kết thúc (`GameOver`).
5. **Quy tắc kiểm phiếu Sói (Sheet 02)**: Xác minh thuật toán kiểm phiếu Sói (Wolf Victim Tally) trong cả tầng pure domain và STM GameLoop:
   - 3 Sói: A-A-B $\to$ chọn A; A-B-C $\to$ hòa $\to$ không có nạn nhân (`Nothing`).
   - 2 Sói: A-B $\to$ hòa $\to$ không có nạn nhân (`Nothing`); A-A $\to$ chọn A.
6. **Kiểm thử tích hợp STM GameLoop đa ngày (TV2)**: Kịch bản tích hợp xuyên suốt `Day 1 -> Night 2 -> Day 2` kiểm tra việc bảo toàn lịch sử chat (`Day 2 còn Day 1`), phân quyền xem chat theo vai/trạng thái sống, tin nhắn hệ thống ghi nhận kết quả bỏ phiếu và cơ chế tự động khóa phiếu Sói (`closeCompletedWolfVote`).
7. **Kiểm thử chéo Giao thức (TV2 Cross-Review TV1)**: Kiểm tra mã hóa/giải mã JSON round-trip cho các thông điệp đồng bộ: `MsgRoomVersion`, `MsgDiscussionSkipState`, `MsgValidTargetsSnapshot`, `MsgPrivateActionState`, và `ClientSkipDiscussion`.

---

## Ma trận phân công trách nhiệm & Kiểm thử chéo (Cross-Review Matrix)

| Thành viên | Trách nhiệm chính (Own Components) | Test Suite sở hữu | Kiểm thử chéo (Cross-Review) |
| :--- | :--- | :--- | :--- |
| **TV1** | Domain Types, ADT, Lobby State | `DomainT02Spec.hs`, `T03LobbySpec.hs` | Review WebSocket/Connection của TV3 |
| **TV2** *(Hiện tại)* | Phase Engine, STM Concurrency, GameLoop | `ServerGameLoopSpec.hs`, `T04PhaseSpec.hs` | **Review Protocol JSON & Sync Messages** (`ProtocolLobbySpec.hs`)<br>**Lead T11 Property & Replay** (`T11PropertyReplaySpec.hs`) |
| **TV3** | Night Action Rules, Role Validation, Seeded RNG | `T05NightSpec.hs`, `T05RngSpec.hs`, `T05WebSocketSpec.hs` | Review Lobby State của TV1 |
| **TV4** | Day Voting, Hunter Pending Chain, UI Core | `DomainT06Spec.hs`, `T06GameLoopSpec.hs`, `T06ProtocolSpec.hs`, `T06WebSocketSpec.hs`, `T06UiSpec.cjs` | Review Night Actions của TV3 |
| **TV5** | Chat Routing, Win Conditions, Reconnect, UI Polish | `T07WinSpec.hs`, `T07UiSpec.cjs` | Review Day Voting của TV4 |

---

## Báo cáo Kiểm thử T11

### 1. State-Machine Property Testing (`test/T11PropertyReplaySpec.hs`)

- **Bảo toàn Invariant trên ván 8 người (100 runs)**:
  Với cấu hình chuẩn 8 người (`[Werewolf, Werewolf, Seer, Guard, Witch, Hunter, Villager, Villager]`), sinh ngẫu nhiên chuỗi `Command` (Join, StartGame, NightAction, Vote, SkipDiscussion, ChatInChannel, ResolveNight, ResolveVoting, ResolveHunter, AdvancePhase...). Sau mỗi bước áp dụng thành công, `validateGameInvariant` đều trả về `Right ()`.
- **Bảo toàn Invariant trên ván 9 người (100 runs)**:
  Tương tự với cấu hình chuẩn 9 người (3 Sói, 4 Dân có chức năng, 2 Dân thường). Toàn bộ 100 chuỗi ngẫu nhiên đều duy trì bất biến hợp lệ.
- **Bảo toàn trạng thái khi lệnh bị từ chối (Rejection State Preservation)**:
  Khi một lệnh không hợp lệ bị từ chối (`Left err`), `GameState` được chứng minh giữ nguyên vẹn 100% không bị thay đổi (áp dụng cho cả ván 8 và 9 người qua 100 runs mỗi loại).

### 2. Chứng minh Lý thuyết FP: `foldl'` và Đệ quy cấu trúc (Sheet 04 Row 24 & 25)

Trong module `Domain.Replay`:
```haskell
replayCommands :: GameState -> [Command] -> ReplayResult
replayCommands initial = foldl' step (ReplayResult initial [])
  where
    step acc cmd = ...
```
- **Base Case**:
  $$\text{replayCommands}(s, []) \equiv \text{ReplayResult}(s, [])$$
  Replay với chuỗi rỗng trả về đúng trạng thái ban đầu và danh sách sự kiện rỗng.
- **Composition Step (Tính kết hợp của foldl')**:
  $$\text{replayCommands}(s, c_1 \mathbin{++} c_2) \equiv \text{replayCommands}(\text{replayCommands}(s, c_1)\text{.state}, c_2)$$
  Kiểm thử QuickCheck (100 runs) chứng minh việc thực thi chuỗi gộp tương đương hoàn toàn với việc thực thi tuần tự từng chuỗi con.

### 3. Deterministic Replay (E16)

- **Chuỗi cố định Day 1 $\to$ Voting $\to$ Night 2**:
  Cùng trạng thái ban đầu và cùng chuỗi `Command` xác định sinh ra kết quả `GameState` và danh sách sự kiện giống nhau từng byte.
- **Replay từ Lobby với Seeded RNG (`replayWithSeed`)**:
  Hàm `replayWithSeed :: Int -> GameState -> [Role] -> [Command] -> ReplayResult` sử dụng `shuffleRolesWithSeed` để phân vai xác định từ seed. Chạy lặp lại nhiều lần với cùng seed luôn cho phân vai và kết quả diễn biến trùng khớp tuyệt đối.
- **Độc lập Seed**:
  Hai seed khác nhau tạo ra hai bảng phân vai khác nhau, dẫn đến kết quả diễn biến khác nhau, nhưng cả hai đều đảm bảo tuyệt đối `validateGameInvariant`.
- **Chu trình xuyên suốt 3 pha**:
  Chuỗi `Night 1 -> Day 1 -> Voting 1` được replay xác định và chuyển pha mượt mà.

### 4. Bảng quy tắc phiếu Sói (Sheet 02)

Được kiểm tra độc lập ở cả tầng pure `Domain.Night` và tầng STM `Server.GameLoop`:
- **3 Sói A-A-B**: Hai Sói chọn `p8`, một Sói chọn `p9` $\to$ Nạn nhân được chọn là `Just "p8"`.
- **3 Sói A-B-C**: Ba Sói chọn 3 mục tiêu khác nhau $\to$ Hòa phiếu $\to$ `Nothing`.
- **2 Sói A-B** (khi 1 Sói đã chết): Hai Sói chọn 2 mục tiêu khác nhau $\to$ Hòa phiếu $\to$ `Nothing`.
- **2 Sói A-A** (khi 1 Sói đã chết): Cả hai Sói đồng thuận chọn `p8` $\to$ Nạn nhân được chọn là `Just "p8"`.

### 5. Bảo mật & Chống rò rỉ thông tin bí mật qua Broadcast (E15)

- Dân làng không bao giờ nhận thông điệp kênh Sói (`WolvesNight`) hay sự kiện nội bộ của Sói (`WolfVoteUpdated`, `WolfTargetLocked`).
- Dân làng không nhận thông báo soi của Tiên Tri (`SeerResult`) hay thông báo cứu của Phù Thủy (`WitchVictimNotice`).
- Snapshot công khai (`LobbySnapshot`, `VotingSnapshot`) chỉ chứa thông tin hiển thị (`displayName`, `alive`, `ready`, `appearance`), tuyệt đối không có trường `role` hay `team`.
- Khi người chơi chết trước khi ván kết thúc, chỉ phát sự kiện `MsgPlayerDied` (không kèm vai trò).
- Toàn bộ danh sách vai trò người chơi chỉ được công bố duy nhất qua sự kiện `MsgGameRolesRevealed` khi ván chuyển sang trạng thái `GameOver`.

### 6. Kịch bản tích hợp STM GameLoop đa ngày (`test/ServerGameLoopSpec.hs`)

- **Bảo toàn lịch sử qua nhiều ngày ("Day 2 còn Day 1")**:
  - Ban ngày 1: Dân làng chat `PublicDay`.
  - Hết thảo luận Day 1 $\to$ chuyển Voting 1 $\to$ chốt Voting 1 (Server tự động chèn tin nhắn hệ thống ghi nhận kết quả bỏ phiếu vào lịch sử chat).
  - Sang Đêm 2: Sói sống chat qua kênh `WolvesNight`.
  - Sang Ban ngày 2: Dân làng tiếp tục chat `PublicDay`.
  - Tổng lịch sử trong STM gồm 4 tin nhắn (Day 1 chat, Day 1 voting system summary, Night 2 wolf chat, Day 2 chat).
- **Phân quyền snapshot lịch sử chat theo vai và trạng thái sống**:
  - Sói sống ở Day 2 xem được toàn bộ 4 tin nhắn (bao gồm cả tin nhắn mật đêm 2 của Sói và tin nhắn ban ngày 1).
  - Dân làng ở Day 2 nhận được 3 tin nhắn công khai (Day 1 chat, Day 1 voting summary, Day 2 chat), tuyệt đối không nhận được tin nhắn `WolvesNight` của Night 2.
  - Sói đã chết trước Night 2 cũng bị thu hồi quyền xem kênh `WolvesNight` của Night 2, chỉ nhận được các tin nhắn công khai.
- **Tally phiếu Sói trực tiếp qua STM GameLoop**:
  Sử dụng hàng đợi lệnh `submit room actor (NightAction actor (WolfTarget target))`. Khi đủ phiếu từ các Sói còn sống, GameLoop tự động kích hoạt `closeCompletedWolfVote`, khóa phiếu và phát sự kiện `WolfTargetLocked`.

### 7. Cross-Review Protocol JSON & Sync Messages (`test/ProtocolLobbySpec.hs`)

Kiểm tra round-trip JSON và đối chiếu schema frontend cho các thông điệp đồng bộ:
- `MsgRoomVersion`: Thông điệp đồng bộ phiên bản phòng (`{"type":"RoomVersion","roomId":"...","version":42}`).
- `MsgDiscussionSkipState`: Tiến độ bỏ qua thảo luận ban ngày (`{"type":"DiscussionSkipState","roomId":"...","submitted":5,"total":8,"hasSkipped":true}`).
- `MsgValidTargetsSnapshot`: Danh sách mục tiêu hợp lệ theo từng hành động của người chơi trong đêm/ngày.
- `MsgPrivateActionState`: Khôi phục trạng thái riêng tư của người chơi (trạng thái bình thuốc Phù Thủy, mục tiêu Bảo Vệ đêm trước, trạng thái đã gửi hành động đêm).
- `ClientSkipDiscussion`: Lệnh đồng ý bỏ qua thảo luận từ client (`{"type":"SkipDiscussion","requestId":"...","roomId":"..."}`).

---

## Kết quả kiểm thử phần TV3 phụ trách

| Phần | Kịch bản | File test | Kết quả | Review chéo |
| :--- | :--- | :--- | :--- | :--- |
| **T03** | Join/Leave/Ready; chuỗi lệnh giữ Lobby hợp lệ, tối đa 9 người và Host đúng | `test/T03LobbySpec.hs` | **PASS: 18/18**; QuickCheck 100 lần | Đã tích hợp |
| **T04** | StartGame 8/9 người; invariant sau Join/Ready và khi chuyển pha | `test/T04PhaseSpec.hs` | **PASS: 24/24**; mỗi property 100 lần | Đã tích hợp |
| **T10** | Chat, quyền vai, reconnect, bong bóng chat tự ẩn và giữ lịch sử | `test/T07UiSpec.cjs` | **PASS: 29/29** | Đã tích hợp |

---

## Ma trận kiểm thử tổng hợp (Full Traceability Matrix)

| STT | Test Suite | File Test | Số lượng Test | Trạng thái |
| :---: | :--- | :--- | :---: | :---: |
| 1 | `t11-property-replay-test` | `test/T11PropertyReplaySpec.hs` | 17 (gồm 700 QuickCheck runs) | **PASS** |
| 2 | `server-gameloop-test` | `test/ServerGameLoopSpec.hs` | 27 | **PASS** |
| 3 | `protocol-lobby-test` | `test/ProtocolLobbySpec.hs` | 53 | **PASS** |
| 4 | `skeleton-test` | `test/Spec.hs` | 1 | **PASS** |
| 5 | `t02-domain-test` | `test/DomainT02Spec.hs` | 23 | **PASS** |
| 6 | `t03-lobby-test` | `test/T03LobbySpec.hs` | 18 | **PASS** |
| 7 | `t04-phase-test` | `test/T04PhaseSpec.hs` | 24 (gồm QuickCheck) | **PASS** |
| 8 | `t05-night-test` | `test/T05NightSpec.hs` | 27 | **PASS** |
| 9 | `t05-rng-test` | `test/T05RngSpec.hs` | 8 (gồm QuickCheck) | **PASS** |
| 10 | `t05-websocket-test` | `test/T05WebSocketSpec.hs` | 13 | **PASS** |
| 11 | `t06-domain-test` | `test/DomainT06Spec.hs` | 24 | **PASS** |
| 12 | `t06-gameloop-test` | `test/T06GameLoopSpec.hs` | 5 | **PASS** |
| 13 | `t06-protocol-test` | `test/T06ProtocolSpec.hs` | 13 | **PASS** |
| 14 | `t06-websocket-test` | `test/T06WebSocketSpec.hs` | 7 | **PASS** |
| 15 | `t07-win-test` | `test/T07WinSpec.hs` | 44 | **PASS** |
| 16 | Node.js UI Test (T06) | `test/T06UiSpec.cjs` | 18 | **PASS** |
| 17 | Node.js UI Test (T07 & T10) | `test/T07UiSpec.cjs` | 29 | **PASS** |
| **Tổng cộng** | **15 Haskell Suites + 2 UI Suites** | | **323+ Tests & Properties** | **100% PASS** |

---

## Hướng dẫn chạy Gate kiểm thử

Chạy toàn bộ cổng kiểm thử tự động trước khi commit hoặc tạo PR:

```powershell
# 1. Chạy toàn bộ 15 test suite Haskell (bao gồm cả QuickCheck và WebSocket tích hợp)
cabal test all --enable-tests --test-show-details=direct -j1

# 2. Chạy toàn bộ 47 kiểm thử giao diện người dùng Node.js
node --test test/T06UiSpec.cjs test/T07UiSpec.cjs

# 3. Kiểm tra định dạng code và ký tự khoảng trắng
git diff --check
```
