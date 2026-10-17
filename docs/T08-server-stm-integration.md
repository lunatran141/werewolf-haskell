# T08 — Ghép Server, STM, Broadcast, Supervisor và Backpressure
## 1. Mục tiêu và phạm vi

T08 hoàn thiện tầng thực thi đồng thời và biên I/O của máy chủ (`Server.*` và `app/Main.hs`), kết nối liền mạch luồng lệnh từ WebSocket vào bộ máy luật thuần (`Domain.*`) thông qua giao dịch bộ nhớ phần mềm (`STM`), đồng thời phân phối sự kiện và trạng thái về đúng từng người chơi.

Phạm vi của T08 tập trung vào 4 trụ cột kỹ thuật:

- **Giám sát vòng đời luồng (`Server.Supervisor`, `Server.Connection`, `app/Main.hs`):** Quản lý các luồng `reader`, `writer`, `broadcast` và `game-loop`; cô lập lỗi theo từng phòng/kết nối để không làm sập toàn bộ máy chủ và không để lại luồng mồ côi.
- **Backpressure và hàng đợi giới hạn (`Server.Room`, `Server.Connection`, `Server.GameLoop`, `Server.WebSocket`):** Giới hạn sức chứa cho cả hàng đợi lệnh vào phòng (`roomCommands`) lẫn hàng đợi gửi tin ra từng kết nối (`OutboundQueue`), ngăn rò rỉ bộ nhớ hoặc treo phòng khi có client gửi dồn dập hoặc đọc chậm.
- **Giao dịch STM nguyên tử, chống trùng lệnh và chống đua với bộ đếm giờ (`Server.GameLoop`):** Đảm bảo mọi cập nhật `roomState`, `roomVersion`, `roomChatHistory` và phát `RoomUpdate` diễn ra trong một khối `atomically` duy nhất; xử lý an toàn trường hợp bộ đếm giờ hết hạn đúng lúc người chơi vừa chuyển giai đoạn.
- **Định tuyến sự kiện theo quyền riêng tư (`Server.Broadcast`):** Lọc sự kiện `Public`, `Private` và `TeamOnly` dựa trên `GameState` thực tế tại máy chủ; đảm bảo Sói đã chết hoặc Dân làng không nhận được dữ liệu mật của phe Sói ban đêm và không lộ vai trò của người chết trước `GameOver`.

T08 giữ nguyên 100% lớp `src/Domain/*` thuần khiết (không thêm `IO`, `STM`, `WebSocket` hay sinh số ngẫu nhiên vào Domain) và tương thích ngược hoàn toàn với các chức năng của T01–T07.

---

## 2. Chức năng đã hoàn thành

### 2.1 Giám sát luồng (Supervisor) và cô lập lỗi

- Module `src/Server/Supervisor.hs` cung cấp bộ giám sát nhẹ dựa trên `STM`:
  - `newSupervisor`, `forkSupervised`, `shutdownSupervisor` và `withSupervisedGroup`.
  - Mỗi worker con chỉ bắt đầu thực thi thân hàm sau khi `ThreadId` của nó đã được đăng ký vào `supervisorThreads` thông qua chốt đồng bộ `TVar Bool`.
  - Khi một worker kết thúc bình thường hoặc do lỗi đóng socket lành tính (`ConnectionClosed`, `CloseRequest`, `Invalid argument`, `broken pipe`), worker tự gỡ `ThreadId` khỏi danh sách và ghi nhận `WorkerStopped`.
  - Khi một worker ném ngoại lệ bất thường, Supervisor ghi nhận `WorkerFailed` và chủ động hủy toàn bộ các luồng anh em trong cùng nhóm giám sát, đảm bảo `activeWorkerCount` về `0` (không còn luồng mồ côi).
- Trong `app/Main.hs`, `startRoomWorker` sử dụng `Supervisor` riêng cho từng phòng thay vì gọi `throwTo mainThread err`. Sự cố ở một phòng chỉ dừng worker của phòng đó mà không làm sập tiến trình máy chủ hay ảnh hưởng tới các phòng đang chơi khác.
- Trong `src/Server/WebSocket.hs`, các luồng `writerThread`, `broadcastThread` và `receiveLoop` được bọc bởi `runIgnoringBenignSocketException` để đóng kết nối êm ái khi trình duyệt tắt tab đột ngột mà không in lỗi giả ra `stderr`.

### 2.2 Backpressure và hàng đợi giới hạn (Bounded Queues)

- **Hàng đợi lệnh của phòng (`roomCommands :: TBQueue QueuedCommand`):**
  - Mặc định giới hạn 128 lệnh (`defaultCommandQueueCapacity`), có thể cấu hình qua `newRoomRuntimeWithCapacity`.
  - Cung cấp `tryEnqueueRoomCommand` (trong `Server.Connection`) và `trySubmitCommand` (trong `Server.GameLoop`): khi hàng đợi đầy, trả về `False` / `Nothing` ngay lập tức thay vì treo luồng đọc của kết nối.
- **Hàng đợi gửi ra mỗi client (`OutboundQueue` trong `Server.Connection`):**
  - Thay thế `TQueue ServerMessage` không giới hạn bằng `OutboundQueue` bọc `TBQueue ServerMessage` (mặc định `defaultOutboundCapacity = 256`).
  - Cung cấp `sendBounded` (trả `False` nếu đầy) và `writeBoundedDropOldest` (nếu đầy thì bỏ thông điệp cũ nhất để nhường chỗ cho thông điệp trạng thái mới nhất), bảo đảm một kết nối mạng chậm không làm nghẽn luồng broadcast của cả phòng.

### 2.3 Điều phối STM GameLoop, Idempotency và Phase Timer

- **Giao dịch STM nguyên tử:**
  - Mọi lệnh người chơi đi qua `processPlayerCommand` đều kiểm tra danh tính phiên (`actorMatches`), kiểm tra trùng lặp `(actorId, requestId)` trong `roomAcceptedRequests`, gọi hàm thuần `dispatchPlayerCommand`, lưu lịch sử chat (`appendAcceptedChat`), tăng `roomVersion` và phát `RoomUpdate` vào `roomUpdates` trong cùng một khối `atomically`.
  - Nếu lệnh bị từ chối (`Left GameError`), trạng thái phòng, `roomVersion`, `roomChatHistory` và kênh broadcast hoàn toàn không thay đổi.
- **Chống xử lý trùng lệnh (Idempotency):**
  - Danh sách lệnh theo dõi `(actorId, requestId)` trong `processPlayerCommand` bao gồm `NightAction`, `Vote`, `ResolveHunter`, `Chat`, `ChatInChannel` và `SkipDiscussion`.
  - Khi client gửi lại cùng `requestId` đã thành công trước đó, Server trả `Left DuplicateRequest` mà không áp dụng hiệu ứng lần hai.
- **Đua giữa Timer và hành động người chơi:**
  - Trong `runGameLoopWithPhaseTimeouts`, bộ đếm giờ (`registerDelay`) và hàng đợi lệnh người chơi tranh chấp trên cùng các `TVar` của `RoomRuntime`.
  - Khi timer hết hạn đúng lúc người chơi vừa làm đổi phase, lệnh nội bộ (`AdvancePhase`, `ResolveVoting`, `ResolveHunter`) trả về `Left _` được xử lý an toàn bằng cách khởi động lại cửa sổ timer cho phase mới, tuyệt đối không gọi `error` gây sập luồng phòng.

### 2.4 Định tuyến sự kiện theo quyền riêng tư và đồng bộ Dashboard

- `Server.Broadcast` xuất đầy đủ các hàm dựng thông điệp trạng thái riêng và công khai:
  - `wolfTeamMessage`: chỉ trả `Just (MsgWolfTeam roomId wolfIds)` khi người nhận có vai `Werewolf`, trả `Nothing` cho mọi vai khác.
  - `privateActionStateMessage`: trả `MsgPrivateActionState` chứa trạng thái đã hành động trong đêm, trạng thái bình thuốc cứu/độc (chỉ dành cho `Witch`) và mục tiêu bảo vệ đêm trước (chỉ dành cho `Guard`).
  - `discussionSkipStateMessage`: trả `MsgDiscussionSkipState` với số người đã đồng ý bỏ qua thảo luận trên tổng số người còn sống.
- Bộ lọc `nightMessagesForState`, `chatMessageForState` và `chatHistorySnapshot`:
  - Kiểm tra cả vai trò (`playerRole == Just Werewolf`) lẫn trạng thái sống (`playerLifeStatus == Alive`) trước khi chuyển giao các sự kiện `TeamOnly Wolves` (`WolfVoteUpdated`, `WolfTargetLocked`, `ChatMessageInChannel WolvesNight`) và lịch sử chat Sói.
  - Sói đã chết (`Dead`) hoặc người chơi thuộc phe Dân không nhận được tin nhắn hay tiến độ bỏ phiếu của Sói trong đêm.
  - Trước `GameOver`, khi có người chết chỉ phát `MsgPlayerDied` (chặn `PlayerRoleRevealed`); toàn bộ vai trò chỉ được công bố qua `MsgGameRolesRevealed` khi ván đấu kết thúc (`GameOver`).

---

## 3. Luồng dữ liệu và phân quyền hiển thị

```text
Browser JSON
  -> Server.WebSocket (xác thực session, gắn actorId, lọc lỗi đóng socket lành tính)
  -> Server.Connection.tryEnqueueRoomCommand (TBQueue có giới hạn)
  -> Server.GameLoop.processPlayerCommand (1 khối STM atomically):
       1. Kiểm tra DuplicateRequest qua roomAcceptedRequests
       2. Kiểm tra actorMatches
       3. Gọi Domain.Engine thuần (applyLobbyCommand / applyPhaseCommand / applyNightCommand / applyCommand)
       4. Ghi TVar: roomState, roomVersion (+1), roomChatHistory, roomNextChatSequence
       5. Phát RoomUpdate vào TChan roomUpdates
  -> Server.Broadcast (lọc Public / Private / TeamOnly theo GameState)
  -> Server.Connection.writeBoundedDropOldest (OutboundQueue giới hạn 256 tin/client)
  -> writerThread gửi JSON frame về Browser
```

Bảng phân quyền thông điệp tại `Server.Broadcast`:

| Thông điệp / Sự kiện | Phạm vi | Điều kiện nhận tại Server |
|---|---|---|
| `MsgLobbySnapshot`, `MsgVotingSnapshot`, `MsgPhaseChanged` | Public | Mọi kết nối trong phòng (không chứa vai trò ẩn) |
| `MsgPlayerDied`, `MsgPlayerEliminated`, `MsgVotingResolved` | Public | Mọi kết nối trong phòng sau khi hoàn tất batch/Hunter |
| `MsgYourRole`, `MsgPrivateActionState` | Private | Chỉ đúng `playerId` sở hữu vai |
| `MsgSeerResult`, `MsgWitchVictimNotice`, `MsgHunterShotPending` | Private | Chỉ đúng `playerId` của Tiên tri / Phù thủy / Thợ săn |
| `MsgWolfTeam` | Role-private | Chỉ người chơi có `playerRole == Just Werewolf` |
| `MsgWolfVoteUpdated`, `MsgWolfTargetLocked`, chat `WolvesNight` | TeamOnly Wolves | Chỉ Sói đang còn sống (`Alive` và `Just Werewolf`) |
| `MsgGameRolesRevealed`, `MsgGameFinished` | Public (cuối ván) | Mọi kết nối trong phòng khi `gamePhase == GameOver` |

---

## 4. Các kịch bản kiểm thử trọng tâm của T08

Bộ kiểm thử `test/ServerGameLoopSpec.hs` bảo vệ 13 kịch bản Lobby ban đầu cùng 7 nhóm kịch bản bắt buộc của T08:

| Mã kịch bản | Nội dung kiểm tra | Kết quả kỳ vọng |
|---|---|---|
| **E02** | Bảo mật vai trò và đồng bộ trạng thái Dashboard khi `StartGame` | `MsgYourRole` chỉ tới đúng chủ nhân; `MsgWolfTeam` chỉ tới Sói; snapshot công khai không lộ role |
| **E07** | 9 client đồng thời gửi `Join`, `SetReady` và `ChatInChannel` qua STM | Không mất cập nhật, `roomVersion` tăng tuần tự đúng +9, `chatSequence` liên tục `1..9`, giữ nguyên invariant |
| **E11** | Gửi trùng `(actorId, requestId)` cho `NightAction`, `ChatInChannel`, `Vote` | Lần 1 thành công và tăng version; lần 2 trả `Left DuplicateRequest`, không đổi state/version hay phát event |
| **E13** | Đua giữa Phase Timer hết hạn và lệnh `SkipDiscussion` của người chơi | Chuyển phase đúng một lần, giữ vững `validateGameInvariant`, không bao giờ crash khi lệnh nội bộ gặp `Left` |
| **E14** | Hàng đợi `roomCommands` và `OutboundQueue` đầy (Backpressure) | `tryEnqueueRoomCommand`/`trySubmitCommand` từ chối ngay khi đầy mà không treo; `writeBoundedDropOldest` giữ các tin mới nhất |
| **E17** | Một worker trong nhóm `Supervisor` ném ngoại lệ bất thường | Supervisor bắt lỗi, ghi nhận `WorkerFailed`, hủy toàn bộ luồng anh em (`activeWorkerCount == 0`), phòng khác không bị ảnh hưởng |
| **Privacy Filter** | Lọc chat `WolvesNight` với Sói đã chết và ẩn vai người chết trước `GameOver` | Dân làng và Sói `Dead` không nhận được chat/phiếu Sói; người chết trước `GameOver` chỉ phát `MsgPlayerDied` |

---

## 5. File liên quan

| File | Trách nhiệm |
|---|---|
| `src/Server/Supervisor.hs` | Quản lý vòng đời nhóm worker bằng STM, tự động hủy luồng anh em khi có lỗi và lọc ngoại lệ socket lành tính |
| `src/Server/Connection.hs` | Hàng đợi gửi có giới hạn (`OutboundQueue`), `sendBounded`, `writeBoundedDropOldest`, `tryEnqueueRoomCommand` và `runSupervisedConnection` |
| `src/Server/Room.hs` | Khởi tạo `RoomRuntime` với `TBQueue` giới hạn (`defaultCommandQueueCapacity`, `newRoomRuntimeWithCapacity`), lưu `roomState`, `roomVersion`, `roomAcceptedRequests` và `roomChatHistory` |
| `src/Server/GameLoop.hs` | Giao dịch STM `processPlayerCommand`, kiểm tra `DuplicateRequest` (gồm cả `NightAction`), `trySubmitCommand` và bộ đếm giờ `runGameLoopWithPhaseTimeouts` an toàn |
| `src/Server/Broadcast.hs` | Định tuyến sự kiện `Public`/`Private`/`TeamOnly`, xuất `wolfTeamMessage`, `privateActionStateMessage`, `discussionSkipStateMessage` và lọc lịch sử chat |
| `src/Server/WebSocket.hs` | Gắn kết nối WebSocket với `OutboundQueue`, xử lý session/reconnect và bọc các luồng đọc/ghi bằng `runIgnoringBenignSocketException` |
| `app/Main.hs` | Điểm vào máy chủ HTTP/WebSocket, khởi chạy worker mỗi phòng qua `Supervisor` để cô lập lỗi |
| `werewolf-server.cabal` | Khai báo module `Server.Supervisor` trong `library` và bật `-threaded` cho `server-gameloop-test` |
| `test/ServerGameLoopSpec.hs` | 23 bài kiểm thử Hspec cho Lobby GameLoop và các kịch bản đồng thời/bảo mật T08 (`E02`, `E07`, `E11`, `E13`, `E14`, `E17`, `Chat & Privacy Filter`) |

---

## 6. Cách kiểm tra và chạy lại

Đóng các tiến trình `werewolf-server` đang chạy trước khi build để tránh khóa file `.exe` trên Windows:

```powershell
cabal build all --enable-tests
cabal test server-gameloop-test --enable-tests --test-show-details=direct
```

Chạy toàn bộ 13 bộ kiểm thử của dự án:

```powershell
cabal test all --enable-tests --test-show-details=direct
git diff --check
git status -s
```

Chạy thử máy chủ và giao diện trên máy local:

```powershell
# Terminal 1: Khởi chạy WebSocket + HTTP health server (cổng 8080)
cabal run werewolf-server

# Terminal 2: Phục vụ giao diện tĩnh (cổng 5500)
python -m http.server 5500 --directory web
```

---

## 7. Trạng thái xác nhận kiểm thử

Kết quả chạy trên Windows với GHC 9.6.6 / Cabal 3.16.1.0:

| Test suite | Số lượng test | Kết quả |
|---|---:|---|
| `skeleton-test` | 1 | PASS |
| `t02-domain-test` | 43 | PASS |
| `t03-lobby-test` | 17 | PASS |
| `t04-phase-test` | 24 | PASS |
| `t05-night-test` | 34 | PASS |
| `t05-rng-test` | 8 | PASS |
| `t05-websocket-test` | 11 | PASS |
| `t06-domain-test` | 24 | PASS |
| `t06-protocol-test` | 12 | PASS |
| `t06-gameloop-test` | 4 | PASS |
| `t06-websocket-test` | 7 | PASS |
| `t07-win-test` | 41 | PASS |
| `protocol-lobby-test` | 46 | PASS |
| `server-gameloop-test` | 23 | PASS |
| **Tổng cộng** | **295** | **PASS toàn bộ** |

- Tất cả các module tạo mới/chỉnh sửa trong phạm vi T08 biên dịch với **0 cảnh báo** dưới cờ `-Wall -Wcompat`.
- Không sử dụng các hàm partial không an toàn (`error`, `undefined`, `head`) trong mã nguồn runtime của T08.

---

## 8. Phối hợp và giới hạn

- T08 giữ nguyên giao thức JSON (`Protocol.Types`, `Protocol.Json`) và toàn bộ chữ ký hàm đã được các bài kiểm thử của T02–T07 sử dụng.
- Trạng thái phòng, lịch sử chat và danh sách `reconnectToken` được quản lý trong bộ nhớ tiến trình bằng `STM` (`TVar`/`TBQueue`/`TChan`); việc lưu trữ bền vững xuống cơ sở dữ liệu ngoài nằm ngoài phạm vi của đồ án.
- Không commit thư mục `dist-newstyle`, file thực thi hoặc log tạm khi tạo Pull Request.

