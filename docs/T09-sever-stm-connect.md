# T09 — Server Runtime, STM và Reconnect

## 1. Mục tiêu và phạm vi

T09 hoàn thiện đường đi của lệnh và trạng thái giữa Browser, WebSocket và Room Worker: lệnh có giới hạn chờ, request có khóa chống áp dụng lặp, reconnect lấy lại snapshot có version, và kết nối hụt cập nhật tự đồng bộ lại.

Phạm vi tài liệu dựa trên phân công T09 của TV5 và phần triển khai hiện có trong nhánh `feature/T09-sever-runtime-connect`. T09 nối tiếp Room Runtime, STM, bounded queue và chat sequence đã có; không thay đổi luật Domain, phân quyền vai, hoặc hành vi Hunter.

Các yêu cầu chính:

- Lệnh có `requestId` ổn định; gửi lặp không áp dụng hiệu ứng lần hai.
- Hàng đợi lệnh đầy hoặc worker không phản hồi phải trả lỗi có giới hạn thời gian, không giữ WebSocket chờ vô hạn.
- Mỗi cập nhật phòng có `roomVersion`; reconnect khôi phục snapshot hiện tại và trạng thái riêng mà người chơi được quyền xem.
- Client phát hiện hụt version thì reconnect để nhận snapshot đầy đủ. Tin chat dùng `messageId`/`sequence` để loại tin trùng.
- Rời phòng không giữ khóa registry chung trong lúc đợi Room Worker.

---

## 2. Chức năng đã hoàn thành

### 2.1 Queue, timeout và idempotency

- `Server.WebSocket.submitCommand` dùng `tryEnqueueRoomCommand`; nếu hàng đợi `roomCommands` đầy, trả `ServerBusy` ngay.
- Sau khi enqueue, WebSocket đợi tối đa 5 giây. Quá hạn trả `ServerTimeout` thay vì chặn vô thời hạn.
- `Server.GameLoop.processPlayerCommand` ghi nhận `(actorId, requestId)` của mọi lệnh client thành công. Gửi lại cùng cặp khóa trả `DuplicateRequest` và không đổi state/version hay phát update lần hai.
- Lệnh thất bại không được ghi vào danh sách đã chấp nhận; client có thể gửi lại sau khi sửa lỗi bằng request mới.

### 2.2 Version và phục hồi kết nối

- Server phát `RoomVersion` sau snapshot khi thiết lập phiên và sau các cập nhật phòng. Version lấy từ `roomVersion` đã commit trong STM.
- Browser lưu `lastVersion` cùng reconnect token và gửi cursor khi reconnect. Server hiện luôn gửi snapshot đầy đủ theo quyền của actor; cursor chưa được dùng để phát lại delta.
- Nếu Browser đang kết nối nhận một version nhảy cóc, client đóng kết nối và dùng reconnect token để lấy snapshot đầy đủ. Lần reconnect đầu tiên coi version trong snapshot là mốc mới.
- Chat đã có `messageId` và `sequence`; snapshot lịch sử cùng UI khử tin trùng theo sequence.
- `beginSession` khôi phục Lobby/Voting snapshot, vai riêng, danh sách đồng đội Sói, trạng thái hành động riêng, kết quả Seer trong đêm và nạn nhân Witch được phép biết sau khi khóa phiếu Sói.

### 2.3 Chờ worker và registry

- `leaveAndPrune` gửi lệnh Leave trước khi khóa `registryRooms`; một worker chậm không giữ khóa registry trong thời gian chờ.
- Chỉ xóa phòng nếu registry vẫn trỏ tới cùng runtime, state vẫn rỗng và queue lệnh đã rỗng.

---

## 3. Luồng dữ liệu và phân quyền

```text
Browser command (requestId, roomId, lastVersion)
  -> Server.WebSocket: xác thực session và actor
  -> tryEnqueueRoomCommand: TBQueue giới hạn
  -> Room Worker: xử lý trong STM, kiểm tra DuplicateRequest
  -> commit roomState + roomVersion + RoomUpdate
  -> Server.Broadcast: lọc Public / Private / TeamOnly
  -> OutboundQueue: snapshot/event rồi RoomVersion
  -> Browser: lưu cursor; nếu hụt version thì reconnect
  -> Server: xác thực token và gửi snapshot hiện tại theo quyền
```

| Dữ liệu | Quyền nhận |
|---|---|
| Lobby/Voting snapshot và RoomVersion | Người chơi trong room; snapshot không chứa vai ẩn |
| YourRole, trạng thái hành động, SeerResult | Đúng người chơi sở hữu thông tin |
| WolfTeam, tiến độ/đích Sói, chat WolvesNight | Người thuộc phe Sói còn sống theo bộ lọc hiện có |
| WitchVictimNotice | Witch trong room, sau khi phiếu Sói đã khóa |
| Lịch sử chat | Theo room, ngày và channel; lọc quyền WolvesNight trước khi gửi |

`RoomVersion` chỉ là cursor đồng bộ; nó không chứa vai trò, phiếu cá nhân hoặc nội dung private.

---

## 4. Các kịch bản kiểm thử trọng tâm của T09

| Kịch bản | Kiểm tra | Kết quả mong đợi |
|---|---|---|
| Duplicate request | Gửi lại Join với cùng `(actorId, requestId)` | Lần sau trả `DuplicateRequest`, không thêm Player hoặc tăng version |
| Queue đầy | Enqueue khi `roomCommands` đã đầy | Trả `ServerBusy` mà không đợi queue |
| Worker timeout | Worker không trả lời trong giới hạn | WebSocket trả `ServerTimeout` sau tối đa 5 giây |
| Reconnect cursor | Kết nối lại bằng token và cursor đã lưu | Nhận snapshot hiện tại và RoomVersion mới |
| Hụt version | Client nhận version không liên tục | Đóng socket và tự reconnect để nhận snapshot |
| Private-state reconnect | Reconnect khi đang Night sau hành động Seer/Witch hoặc sau khi khóa phiếu Sói | Chỉ actor được quyền nhận kết quả tương ứng; trạng thái hành động được phục hồi |
| Rời phòng | Worker xử lý Leave trong lúc các phòng khác đang hoạt động | Không giữ khóa registry chung trong lúc chờ worker |
| Chat replay | Nhận trực tiếp và từ snapshot lịch sử | UI không hiển thị trùng message theo sequence |

---

## 5. File liên quan

| File | Trách nhiệm |
|---|---|
| `src/Server/WebSocket.hs` | Bounded enqueue, timeout lệnh, reconnect, phục hồi private state, RoomVersion và Leave/prune |
| `src/Server/Connection.hs` | OutboundQueue và `tryEnqueueRoomCommand` |
| `src/Server/GameLoop.hs` | Commit STM, roomVersion và kiểm tra requestId lặp |
| `src/Server/Room.hs` | Room state, command queue, version, reconnect token và chat sequence |
| `src/Protocol/Types.hs` | JSON message `RoomVersion` |
| `web/app.js` | Lưu cursor, gửi cursor khi reconnect, tự reconnect khi version bị hụt |
| `test/ServerGameLoopSpec.hs` | Idempotency Join, bounded queue, timer race và các kiểm thử tích hợp T08 |
| `test/T05WebSocketSpec.hs` | Reconnect qua socket thật, version snapshot và phục hồi thông tin Witch |
| `test/T06UiSpec.cjs`, `test/T07UiSpec.cjs` | Hành vi UI, reconnect token/cursor và phát hiện hụt version |
| `.github/workflows/ci.yml` | Chạy kiểm tra cú pháp và UI test bằng Node.js trong CI |

---

## 6. Cách kiểm tra và chạy lại

```powershell
cabal build all --enable-tests -j1
cabal test all --enable-tests --test-show-details=direct -j1
node --check web/app.js
node --test test/T06UiSpec.cjs test/T07UiSpec.cjs
git diff --check
```

Các test WebSocket mở cổng localhost. `-j1` dùng để tránh lỗi linker hệ thống GHC khi nhiều test executable được link đồng thời trên Windows.

---

## 7. Trạng thái xác nhận kiểm thử

Kết quả trên Windows với GHC 9.6.6 và Cabal 3.16.1.0:

| Kiểm tra | Kết quả |
|---|---|
| `cabal build all --enable-tests -j1` | PASS |
| `cabal test all --enable-tests --test-show-details=direct -j1` | PASS, toàn bộ 14 test suite |
| T05 WebSocket/reconnect | PASS, 11 examples |
| Server GameLoop | PASS, 24 examples |
| Browser UI | PASS, 36 tests |
| `node --check web/app.js` | PASS |
| `git diff --check` | PASS |

---

## 8. Phối hợp và giới hạn

- Server hiện luôn trả snapshot đầy đủ khi reconnect; chưa triển khai delta replay dựa trên `lastVersion`. Đây là cơ chế an toàn để phục hồi state, nhưng có thể gửi nhiều dữ liệu hơn khi room lớn.
- Timeout sau khi command đã enqueue chỉ giới hạn thời gian chờ của kết nối. Command có thể vẫn được Room Worker xử lý; requestId chống áp dụng lặp khi client gửi lại.
- `roomAcceptedRequests`, reconnect token và room state nằm trong bộ nhớ tiến trình. Khởi động lại server không giữ phiên hoặc cache idempotency.
- Supervisor đã có module và test cô lập worker, nhưng việc đưa toàn bộ reader/writer/broadcast/game-loop vào lifecycle supervision đồng nhất vẫn thuộc phần connection hardening tiếp theo; không ghi nhận T09 đã hoàn tất hạng mục đó.
- Không thay đổi hành vi Hunter đã được nhóm chấp thuận. Không commit hoặc push trong lần cập nhật tài liệu này.
