# T09 — Server Runtime, STM và Reconnect

## 1. Mục tiêu và phạm vi

T09 hoàn thiện đường đi của lệnh và trạng thái giữa Browser, WebSocket và Room Worker: lệnh có giới hạn chờ, request có khóa chống áp dụng lặp, reconnect lấy lại snapshot có version, và kết nối hụt cập nhật tự đồng bộ lại.

Phạm vi tài liệu dựa trên phân công T09 của TV5 và phần triển khai hiện có trong nhánh `feature/T09-sever-runtime-connect`. T09 nối tiếp Room Runtime, STM, bounded queue và chat sequence đã có; không thay đổi luật Domain, phân quyền vai, hoặc hành vi Hunter.

Các yêu cầu chính:

- Lệnh có `requestId` ổn định; gửi lặp không áp dụng hiệu ứng lần hai.
- Hàng đợi lệnh đầy hoặc worker không phản hồi phải trả lỗi có giới hạn thời gian, không giữ WebSocket chờ vô hạn.
- Mỗi cập nhật phòng có `roomVersion`; reconnect luôn khôi phục snapshot hiện tại và trạng thái riêng mà người chơi được quyền xem. Server không nhận `lastVersion` vì chưa có delta replay.
- Client phát hiện hụt version thì reconnect để nhận snapshot đầy đủ. Queue gửi tràn cũng đóng kết nối để kích hoạt cùng cơ chế phục hồi; tin chat dùng `messageId`/`sequence` để loại tin trùng.
- Join và Leave chỉ giữ khóa registry khi tra cứu hoặc cập nhật registry, không giữ khóa trong lúc đợi Room Worker.
- Nếu timeout hoặc mất kết nối, client giữ lại command cùng `requestId` và gửi lại chính command đó sau reconnect; server từ chối duplicate đã commit mà không áp dụng hiệu ứng lần hai.

---

## 2. Chức năng đã hoàn thành

### 2.1 Queue, timeout và idempotency

- `Server.WebSocket.submitCommand` dùng `tryEnqueueRoomCommand`; nếu hàng đợi `roomCommands` đầy, trả `ServerBusy` ngay.
- Sau khi enqueue, WebSocket đợi tối đa 5 giây. Quá hạn trả `ServerTimeout` thay vì chặn vô thời hạn.
- `Server.GameLoop.processPlayerCommand` ghi nhận `(actorId, requestId)` của mọi lệnh client thành công. Gửi lại cùng cặp khóa trả `DuplicateRequest` và không đổi state/version hay phát update lần hai.
- Lệnh thất bại không được ghi vào danh sách đã chấp nhận; client có thể gửi lại sau khi sửa lỗi bằng request mới.

### 2.2 Version và phục hồi kết nối

- Server phát `RoomVersion` sau snapshot khi thiết lập phiên và sau các cập nhật phòng. Version lấy từ `roomVersion` đã commit trong STM.
- Server luôn gửi snapshot đầy đủ theo quyền của actor khi reconnect; `lastVersion` không nằm trong request contract vì server không phát lại delta.
- Browser dùng version nhận được để phát hiện khoảng trống khi đang kết nối. Queue tràn được phát hiện trực tiếp ở server, socket đóng và Browser reconnect để lấy snapshot, kể cả khi một version liên tiếp không đủ thể hiện sự kiện đã mất.
- Sau timeout hoặc mất kết nối, Browser giữ command chưa xác nhận. Khi reconnect snapshot hoàn tất, Browser gửi lại cùng command và `requestId`; duplicate đã commit được coi là hoàn tất, nên chat/vote/night action không bị áp dụng lần hai.
- Chat đã có `messageId` và `sequence`; snapshot lịch sử cùng UI khử tin trùng theo sequence.
- `beginSession` khôi phục Lobby/Voting snapshot, vai riêng, danh sách đồng đội Sói, trạng thái hành động riêng, kết quả Seer trong đêm và nạn nhân Witch được phép biết sau khi khóa phiếu Sói.

### 2.3 Chờ worker và registry

- `leaveAndPrune` gửi lệnh Leave trước khi khóa `registryRooms`; một worker chậm không giữ khóa registry trong thời gian chờ.
- Chỉ xóa phòng nếu registry vẫn trỏ tới cùng runtime, state vẫn rỗng và queue lệnh đã rỗng.

---

## 3. Luồng dữ liệu và phân quyền

```text
Browser command (requestId, roomId)
  -> Server.WebSocket: xác thực session và actor
  -> tryEnqueueRoomCommand: TBQueue giới hạn
  -> Room Worker: xử lý trong STM, kiểm tra DuplicateRequest
  -> commit roomState + roomVersion + RoomUpdate
  -> Server.Broadcast: lọc Public / Private / TeamOnly
  -> OutboundQueue: snapshot/event rồi RoomVersion; overflow đánh dấu cần reconnect
  -> Browser: dò khoảng trống version; reconnect khi hụt dữ liệu hoặc timeout
  -> Server: xác thực token và gửi snapshot đầy đủ theo quyền
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
| Reconnect snapshot | Kết nối lại bằng token | Nhận snapshot hiện tại và RoomVersion mới; không gửi `lastVersion` |
| Queue gửi đầy | Hàng đợi outbound tràn | Đánh dấu overflow, đóng socket và reconnect để nhận snapshot |
| Retry sau timeout/mất kết nối | Gửi lại cùng command sau reconnect | Giữ nguyên requestId; command đã commit không phát sinh hiệu ứng thứ hai |
| Worker phòng chậm | Join vào phòng chậm trong khi thao tác phòng khác | Phòng khác vẫn xử lý do khóa registry đã được nhả trước khi chờ worker |
| Hụt version | Client nhận version không liên tục | Đóng socket và tự reconnect để nhận snapshot |
| Private-state reconnect | Reconnect khi đang Night sau hành động Seer/Witch hoặc sau khi khóa phiếu Sói | Chỉ actor được quyền nhận kết quả tương ứng; trạng thái hành động được phục hồi |
| Rời phòng | Worker xử lý Leave trong lúc các phòng khác đang hoạt động | Không giữ khóa registry chung trong lúc chờ worker |
| Chat replay | Nhận trực tiếp và từ snapshot lịch sử | UI không hiển thị trùng message theo sequence |

---

## 5. File liên quan

| File | Trách nhiệm |
|---|---|
| `src/Server/WebSocket.hs`, `src/Server/Broadcast.hs` | Join không giữ registry khi chờ worker; timeout có mã rõ ràng; reconnect, phục hồi private state và RoomVersion |
| `src/Server/Connection.hs` | OutboundQueue, phát hiện overflow và `tryEnqueueRoomCommand` |
| `src/Server/GameLoop.hs` | Commit STM, roomVersion và kiểm tra requestId lặp |
| `src/Server/Room.hs` | Room state, command queue, version, reconnect token và chat sequence |
| `src/Protocol/Types.hs` | JSON message `RoomVersion` |
| `web/app.js` | Lưu cursor cục bộ để dò khoảng trống; retry command giữ nguyên requestId sau timeout/reconnect |
| `test/ServerGameLoopSpec.hs` | Idempotency Join, queue đầy và phát hiện outbound overflow |
| `test/T05WebSocketSpec.hs` | Join vào worker treo không chặn phòng khác; reconnect qua socket thật và phục hồi dữ liệu riêng |
| `test/T06UiSpec.cjs`, `test/T07UiSpec.cjs` | Hành vi UI, reconnect token, giữ nguyên requestId khi gửi lại và dò khoảng trống version |
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
| T05 WebSocket/reconnect | PASS, 13 examples |
| Server GameLoop | PASS, 25 examples |
| Browser UI | PASS, 37 tests |
| `node --check web/app.js` | PASS |
| `git diff --check` | PASS |

---

## 8. Phối hợp và giới hạn

- Server luôn trả snapshot đầy đủ khi reconnect; `lastVersion` không được gửi vì chưa có delta replay. Đây là cơ chế phục hồi state đã chốt cho T09, nhưng có thể gửi nhiều dữ liệu hơn khi room lớn.
- Timeout sau khi command đã enqueue chỉ giới hạn thời gian chờ của kết nối. Command có thể vẫn được Room Worker xử lý; client giữ nguyên requestId khi retry để chống áp dụng lặp.
- `roomAcceptedRequests`, reconnect token và room state nằm trong bộ nhớ tiến trình. Khởi động lại server không giữ phiên hoặc cache idempotency.
- Supervisor đã có module và test cô lập worker, nhưng việc đưa toàn bộ reader/writer/broadcast/game-loop vào lifecycle supervision đồng nhất vẫn thuộc phần connection hardening tiếp theo; không ghi nhận T09 đã hoàn tất hạng mục đó.
- Không thay đổi hành vi Hunter đã được nhóm chấp thuận. Không commit hoặc push trong lần cập nhật tài liệu này.
