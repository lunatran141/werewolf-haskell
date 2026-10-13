
# T05 - Night Actions, Rules, Commands/Events and Seeded RNG

## 1. Overview

T05 đã triển khai logic xử lý giai đoạn Night trong trò chơi Ma Sói bằng Haskell.

Phạm vi bao gồm:

- Night Rules cho Werewolf, Seer, Guard và Witch.
- Validation cho các hành động ban đêm.
- Xử lý kết quả Night và điều kiện thắng.
- NightAction Command và Server Events.
- Định tuyến sự kiện Private/Public qua WebSocket.
- RNG hỗ trợ seed và generator injection.
- Unit tests, property-based tests và WebSocket tests.

Nguyên tắc thiết kế:

- Pure Engine không trực tiếp thực hiện IO hoặc gửi WebSocket.
- GameState được cập nhật thông qua Command Processing.
- PlayerId được xác định từ phiên kết nối Server.
- Thông tin riêng tư chỉ được gửi đến người chơi có quyền nhận.
- Logic ngẫu nhiên được tách khỏi Pure Engine để dễ kiểm thử và tái lập kết quả.

## 2. Night Rules

### 2.1. Werewolf

Werewolf sử dụng hành động `WolfTarget targetId` để chọn mục tiêu.

Quy tắc:

- Chỉ Werewolf còn sống được bỏ phiếu.
- Mục tiêu phải là người chơi còn sống thuộc phe Village.
- Không được chọn đồng đội Werewolf.
- Một Werewolf không được gửi hai hành động trong cùng đêm.
- Sau khi khóa phiếu, Werewolf không được tiếp tục bỏ phiếu.
- Kết quả được xác định từ các phiếu của Werewolf và chính sách xử lý hòa phiếu.

### 2.2. Seer

Seer sử dụng hành động `SeerTarget targetId`.

Quy tắc:

- Chỉ Seer còn sống được thực hiện.
- Mục tiêu phải hợp lệ.
- Seer không được soi chính mình.
- Kết quả trả về phe `Wolves` hoặc `Village`.
- `SeerResult` là sự kiện Private, chỉ Seer thực hiện hành động được nhận.

### 2.3. Guard

Guard sử dụng hành động `GuardTarget targetId`.

Quy tắc:

- Chỉ Guard còn sống được thực hiện.
- Guard có thể tự bảo vệ.
- Không được bảo vệ cùng một mục tiêu trong hai đêm liên tiếp.
- Bảo vệ thành công có thể ngăn tác động tấn công từ Werewolf.
- Bảo vệ không ngăn được Witch Poison.

### 2.4. Witch

Witch hỗ trợ các hành động:

| Action | Ý nghĩa |
|---|---|
| `WitchHeal` | Cứu nạn nhân bị Werewolf tấn công |
| `WitchPoison targetId` | Dùng thuốc độc lên mục tiêu |
| `WitchPass` | Bỏ lượt |

Quy tắc:

- Chỉ Witch còn sống được thực hiện.
- Heal và Poison phụ thuộc vào tài nguyên thuốc còn lại.
- Heal chỉ hợp lệ sau khi phiếu Werewolf đã được khóa và xác định được nạn nhân.
- Witch không được Poison chính mình.
- WitchPass không tiêu hao thuốc.
- `WitchVictimNotice` được gửi riêng cho Witch.

## 3. Night Processing Flow

Luồng xử lý được thiết kế như sau:

```text
Night Phase
    |
    v
Players submit NightAction
    |
    v
Validate NightAction
    |
    v
Store valid actions in GameState
    |
    v
Close Wolf Voting
    |
    v
Send private WitchVictimNotice
    |
    v
Resolve Night Effects
    |
    v
Update player status and resources
    |
    v
Check Pending Hunter
    |
    +---- Hunter pending ---> Wait for T06 handling
    |
    v
Complete Night
    |
    v
Reveal dead player roles
    |
    v
Check Win Conditions
    |
    +---- Winner/Draw ---> GameOver
    |
    v
Day Phase
```

**Lưu ý:** Đây là luồng xử lý dự kiến khi tích hợp hoàn chỉnh. Hiện tại Pure Engine đã có các hàm nghiệp vụ tương ứng, nhưng Server chưa tự động điều phối toàn bộ các bước.

### 3.1. Submit NightAction

Hàm:

```haskell
submitNightAction
  :: GameState
  -> PlayerId
  -> NightChoice
  -> Either GameError (GameState, [DomainEvent])
```

Nhiệm vụ:

1. Kiểm tra tính hợp lệ của hành động.
2. Tạo các sự kiện riêng tư tương ứng.
3. Lưu hành động hợp lệ vào `gameNightActions`.
4. Trả về GameState mới cùng danh sách DomainEvents.

Khi validation thất bại, hàm trả về `Left GameError`.

### 3.2. Close Wolf Voting

Hàm:

```haskell
closeWolfVoting
  :: GameState
  -> Bool
  -> Either GameError (GameState, [DomainEvent])
```

Tham số `Bool` biểu diễn trạng thái hết thời gian do Server cung cấp.

Hàm thực hiện:

- Kiểm tra Phase Night.
- Ngăn khóa phiếu nhiều lần.
- Chỉ cho phép khóa khi đủ phiếu hoặc khi hết thời gian.
- Đặt `gameWolfVotingClosed = True`.
- Tạo `WitchVictimNotice` cho Witch còn sống.

Client không được tự quyết định giá trị timeout.

### 3.3. Resolve Night

Hàm:

```haskell
resolveNightTurn
  :: GameState
  -> Either GameError (GameState, [DomainEvent])
```

Nhiệm vụ:

- Kiểm tra điều kiện resolve.
- Tổng hợp tác động các hành động Night.
- Xác định người chết.
- Cập nhật trạng thái người chơi.
- Cập nhật tài nguyên Role.
- Xóa các NightAction đã xử lý.
- Đánh dấu `gameNightResolved = True`.
- Tạo `NightResolved` và các sự kiện Hunter pending nếu có.

Hàm không trực tiếp chuyển sang Day.

### 3.4. Complete Night

Hàm:

```haskell
completeNightTurn
  :: GameState
  -> Either GameError (GameState, [DomainEvent])
```

Nhiệm vụ:

- Chỉ cho phép hoàn tất sau khi Night đã resolve.
- Không cho chuyển pha khi Hunter còn pending.
- Phát `PlayerRoleRevealed` cho các trường hợp hợp lệ.
- Kiểm tra điều kiện thắng.
- Chuyển sang Day hoặc GameOver.

### 3.5. Win Conditions

Hàm:

```haskell
nightGameResult :: GameState -> Maybe GameResult
```

Các trường hợp:

| Điều kiện | Kết quả |
|---|---|
| Không còn người sống ở cả hai phe | `Draw` |
| Không còn Werewolf sống | `Winner Village` |
| Số Werewolf sống lớn hơn hoặc bằng số người Village sống | `Winner Wolves` |
| Chưa thỏa điều kiện thắng | `Nothing` |

## 4. Protocol - Client NightAction

Client gửi NightAction qua WebSocket dưới dạng JSON.

### 4.1. WolfTarget

```json
{
  "type": "NightAction",
  "requestId": "r01",
  "roomId": "ROOM-01",
  "choice": {
    "action": "WolfTarget",
    "targetId": "7"
  }
}
```

### 4.2. SeerTarget

```json
{
  "type": "NightAction",
  "requestId": "r02",
  "roomId": "ROOM-01",
  "choice": {
    "action": "SeerTarget",
    "targetId": "1"
  }
}
```

### 4.3. GuardTarget

```json
{
  "type": "NightAction",
  "requestId": "r03",
  "roomId": "ROOM-01",
  "choice": {
    "action": "GuardTarget",
    "targetId": "4"
  }
}
```

### 4.4. WitchHeal

```json
{
  "type": "NightAction",
  "requestId": "r04",
  "roomId": "ROOM-01",
  "choice": {
    "action": "WitchHeal"
  }
}
```

### 4.5. WitchPoison

```json
{
  "type": "NightAction",
  "requestId": "r05",
  "roomId": "ROOM-01",
  "choice": {
    "action": "WitchPoison",
    "targetId": "8"
  }
}
```

### 4.6. WitchPass

```json
{
  "type": "NightAction",
  "requestId": "r06",
  "roomId": "ROOM-01",
  "choice": {
    "action": "WitchPass"
  }
}
```

**Security:** Client không gửi PlayerId hoặc Role trong NightAction. Server lấy PlayerId từ phiên WebSocket và xác định quyền hành động bằng GameState.

## 5. Server Events

| Event | Phạm vi | Ý nghĩa |
|---|---|---|
| `NightActionAccepted` | Private | Xác nhận hành động Night hợp lệ |
| `SeerResult` | Private | Kết quả soi của Seer |
| `WitchVictimNotice` | Private | Thông báo nạn nhân cho Witch |
| `NightResolved` | Public theo Domain contract | Kết quả xử lý Night |
| `PlayerRoleRevealed` | Public | Công khai vai người chết |
| `PhaseChanged` | Public | Thông báo chuyển Phase |
| `GameFinished` | Public | Thông báo kết quả ván chơi |

### 5.1. Event Routing

Hàm:

```haskell
nightMessagesFor
  :: RoomId
  -> PlayerId
  -> [DomainEvent]
  -> [ServerMessage]
```

Nguyên tắc:

- `Public`: Được chuyển thành thông điệp cho từng client trong phòng.
- `Private pid`: Chỉ chuyển thành thông điệp khi PlayerId người nhận khớp `pid`.
- Event chưa có JSON contract trong router T05 sẽ bị bỏ qua.

Hàm `eventVisibility` trong `Domain.Types` xác định quyền nhận sự kiện.

**Lưu ý về NightResolved:** Mặc dù `NightResolved` có JSON contract, lớp WebSocket hiện đang lọc bỏ sự kiện này để tránh tiết lộ danh sách người chết trước khi Hunter và các death effects được xử lý hoàn tất.

### 5.2. NightAction Errors

Server từ chối NightAction trong các trường hợp như:

- Client chưa Join phòng.
- RoomId không khớp với phòng của phiên kết nối.
- GameState không ở Phase Night.
- Người chơi không có Role phù hợp.
- Người chơi đã chết.
- Mục tiêu không hợp lệ.
- Hành động trùng hoặc không thỏa điều kiện sử dụng.

Các lỗi được gửi về thông qua `CommandRejected` và không cập nhật GameState khi Command bị từ chối.

## 6. Seeded RNG and Generator Injection

Module:

```text
src/Domain/RoleShuffle.hs
```

Các hàm chính:

```haskell
shuffleRoles
  :: RandomGen g
  => g
  -> [Role]
  -> ([Role], g)

shuffleRolesWithSeed
  :: Int
  -> [Role]
  -> [Role]
```

### 6.1. Seeded RNG

Sử dụng `shuffleRolesWithSeed` khi cần kết quả tái lập từ một seed xác định.

Ví dụ:

```haskell
roles1 = shuffleRolesWithSeed 42 roles
roles2 = shuffleRolesWithSeed 42 roles
```

Với cùng danh sách đầu vào và cùng seed:

```haskell
roles1 == roles2
```

### 6.2. Generator Injection

`shuffleRoles` nhận bộ sinh số ngẫu nhiên từ bên ngoài và trả về generator tiếp theo.

Lợi ích:

- Dễ kiểm thử.
- Không phụ thuộc nguồn random toàn cục.
- Bảo đảm tính tái lập.
- Tách RNG khỏi Pure Engine.

**Giới hạn:** Cơ chế RNG đã được triển khai và kiểm thử, nhưng chưa được kết nối vào toàn bộ luồng StartGame qua WebSocket.

## 7. Testing

### 7.1. Build

```powershell
cabal build all
```

### 7.2. Test All

```powershell
cabal test all --test-show-details=direct
```

### 7.3. Test từng nhóm T05

```powershell
cabal test t05-night-test --test-show-details=direct
cabal test t05-rng-test --test-show-details=direct
cabal test t05-websocket-test --test-show-details=direct
```

### 7.4. Kết quả kiểm thử

Kết quả tại thời điểm hoàn thành bản triển khai T05:

| Test suite | Examples | Status |
|---|---:|---|
| `skeleton-test` | 1 | PASS |
| `t02-domain-test` | 38 | PASS |
| `t03-lobby-test` | 17 | PASS |
| `t04-phase-test` | 23 | PASS |
| `t05-night-test` | 84 | PASS |
| `t05-rng-test` | 8 | PASS |
| `protocol-lobby-test` | 36 | PASS |
| `server-gameloop-test` | 13 | PASS |
| `t05-websocket-test` | 4 | PASS |
| **Total** | **224** | **PASS** |

Bộ test T05 kiểm tra:

- Luật của Werewolf, Seer, Guard và Witch.
- Ván chơi 8 và 9 người.
- Các trường hợp hợp lệ, lỗi và edge cases.
- Wolf Voting Lock và Witch Victim Notice.
- Night Resolution và Win Conditions.
- Seeded RNG và generator injection.
- JSON serialization/deserialization.
- Phân quyền private/public.
- WebSocket validation và event delivery.

Trong kiểm thử WebSocket, thông báo `ConnectionClosed` có thể xuất hiện khi đóng kết nối, nhưng bộ test đã báo PASS.

## 8. Main Files

### Domain

- `src/Domain/Night.hs`
- `src/Domain/Engine.hs`
- `src/Domain/Types.hs`
- `src/Domain/Validation.hs`
- `src/Domain/RoleShuffle.hs`

### Protocol and Server

- `src/Protocol/Types.hs`
- `src/Server/Broadcast.hs`
- `src/Server/GameLoop.hs`
- `src/Server/WebSocket.hs`

### Tests

- `test/T05NightSpec.hs`
- `test/T05RngSpec.hs`
- `test/T05WebSocketSpec.hs`
- `test/ProtocolLobbySpec.hs`

### Build Configuration

- `werewolf-server.cabal`

## 9. Limitations and Integration Notes

Các giới hạn hiện tại:

1. Pure Engine đã có Night Rules và Night Resolution, nhưng Server chưa tự động gọi toàn bộ các bước trong vòng đời Night.
2. RNG chưa được tích hợp với luồng StartGame WebSocket.
3. UI cho NightAction chưa được xác nhận hoàn thiện.
4. Hunter Shot/Pass thuộc phần việc T06; không được tự ý bỏ qua trạng thái Hunter pending.
5. `NightResolved` chưa được gửi công khai từ WebSocket vì cần bảo vệ thông tin trước khi hoàn tất death effects.
6. Việc đóng WebSocket có thể ghi log `ConnectionClosed`; cần tiếp tục xử lý sạch ngoại lệ này khi tích hợp.

## 10. Conclusion

T05 đã triển khai và kiểm thử các thành phần:

- Night Rules và Validation.
- Night Resolution và Win Conditions.
- NightAction Command/Event.
- Private/Public Event Routing.
- Seeded RNG và Generator Injection.
- GameLoop và WebSocket NightAction Integration.

Kết quả kiểm thử gần nhất: **9/9 test suites PASS, 224 examples, 0 failures**.

Các chức năng thuộc Pure Engine và giao thức đã sẵn sàng để nhóm review, đồng thời cần phối hợp với các phần StartGame, Hunter, Game Orchestration và UI để hoàn thành luồng chơi thực tế.
