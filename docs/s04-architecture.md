# S04 - Kiến trúc và luồng `JoinGame`

Tài liệu này thống nhất cách một lệnh đi từ trình duyệt vào Haskell server và cách kết quả quay lại giao diện. Đây là kiến trúc mục tiêu để các nhiệm vụ sau triển khai đồng nhất; ở thời điểm S04, các module đã có dưới dạng skeleton và HTTP `/health` đã hoạt động, còn WebSocket, STM và luật `JoinGame` chưa được cài đặt đầy đủ.

## Các lớp và trách nhiệm

| Lớp | Module/thành phần | Trách nhiệm |
| --- | --- | --- |
| UI | `web/` | Nhận thao tác người dùng, gửi command và render event; không tự quyết định luật game. |
| Transport | `Server.WebSocket`, `Server.Connection` | Quản lý kết nối, nhận/gửi text frame và gắn kết nối với người chơi. |
| Protocol | `Protocol.Json`, `Protocol.Types` | Giải mã JSON thành kiểu Haskell, mã hóa event và trả lỗi khi dữ liệu sai. |
| Điều phối | `Server.GameLoop`, `Server.Room` | Tìm phòng, đọc state hiện tại và điều phối command vào engine. |
| Luật thuần | `Domain.Validation`, `Domain.Rules`, `Domain.Engine` | Kiểm tra command và tính state/event mới bằng hàm thuần, không làm I/O. |
| Đồng thời | STM trong `Server.Room`/`Server.GameLoop` | Commit state nguyên tử để hai command đồng thời không ghi đè nhau. |
| Phát sự kiện | `Server.Broadcast` | Gửi event public cho cả phòng và event private đúng người nhận. |

Quy tắc phụ thuộc: lớp `Domain` không import `Server`, WebSocket hay STM. Nhờ vậy luật game có thể unit test mà không cần mạng hoặc container.

## Command `JoinGame`

Browser gửi một JSON command qua WebSocket:

```json
{
  "type": "JoinGame",
  "requestId": "req-001",
  "roomId": "ROOM-01",
  "playerName": "Luna"
}
```

Ý nghĩa các trường:

- `type`: loại command để Protocol chọn bộ giải mã.
- `requestId`: mã đối chiếu request với lỗi hoặc kết quả trả về.
- `roomId`: phòng người chơi muốn tham gia.
- `playerName`: tên hiển thị đã được người dùng nhập.

Khi thành công, server có thể phát event công khai:

```json
{
  "type": "PlayerJoined",
  "roomId": "ROOM-01",
  "player": {
    "playerId": "player-04",
    "displayName": "Luna"
  }
}
```

Khi thất bại, chỉ gửi lỗi về kết nối đã tạo command:

```json
{
  "type": "CommandRejected",
  "requestId": "req-001",
  "code": "ROOM_FULL",
  "message": "Phòng đã đủ người chơi"
}
```

## Truy vết Browser đến UI

1. Người dùng nhập tên và nhấn **Tham gia**; UI tạo JSON `JoinGame` và gửi qua WebSocket.
2. `Server.WebSocket` nhận text frame và chuyển bytes sang `Protocol.Json`.
3. `Protocol.Json` giải mã dữ liệu thành `Command`. JSON sai cấu trúc bị từ chối tại đây và không đi vào engine.
4. `Server.GameLoop` lấy `RoomState` của `roomId` trong STM và chuyển command cùng state hiện tại vào `Domain.Engine`.
5. `Domain.Validation` kiểm tra dữ liệu; `Domain.Rules` kiểm tra luật như phòng tồn tại, chưa đầy và tên hợp lệ.
6. `Domain.Engine` trả về `Either DomainError (RoomState, [DomainEvent])`. Engine không tự sửa biến STM và không tự gửi mạng.
7. Nếu thành công, `Server.GameLoop` commit `RoomState` mới trong cùng transaction STM. Nếu transaction xung đột, STM tự chạy lại với state mới nhất.
8. Sau khi commit, `Server.Broadcast` mã hóa `PlayerJoined` và gửi cho các kết nối trong phòng. Lỗi private chỉ gửi cho người tạo command.
9. Browser nhận event và UI render danh sách người chơi từ dữ liệu server; UI không tự thêm người chơi trước khi có event xác nhận.

## Sequence diagram

```mermaid
sequenceDiagram
    actor User as Người dùng
    participant UI as Browser/UI
    participant WS as WebSocket Server
    participant JSON as Protocol.Json
    participant Loop as GameLoop
    participant STM as RoomState (STM)
    participant Engine as Pure Engine
    participant Events as Broadcast/Event

    User->>UI: Nhấn Tham gia
    UI->>WS: JSON JoinGame
    WS->>JSON: decode payload
    alt JSON không hợp lệ
        JSON-->>WS: ProtocolError
        WS-->>UI: CommandRejected
    else JSON hợp lệ
        JSON->>Loop: JoinGame command
        Loop->>STM: atomically đọc RoomState
        STM-->>Loop: state hiện tại
        Loop->>Engine: handle JoinGame state
        alt Vi phạm luật game
            Engine-->>Loop: Left DomainError
            Loop->>Events: private CommandRejected
            Events-->>UI: lỗi theo requestId
        else Hợp lệ
            Engine-->>Loop: Right (newState, PlayerJoined)
            Loop->>STM: atomically commit newState
            Loop->>Events: publish PlayerJoined
            Events-->>UI: JSON PlayerJoined
            UI-->>User: Render danh sách mới
        end
    end
```

Luồng rút gọn:

```text
Browser -> JSON -> Server -> Pure Engine -> STM commit -> Event -> UI
```

## Ranh giới lỗi và tính đúng đắn

- JSON lỗi: Protocol trả `CommandRejected`; state không thay đổi.
- Luật game lỗi: Engine trả `DomainError`; state không thay đổi.
- Hai người tham gia đồng thời: STM bảo đảm mỗi commit dùng state nhất quán.
- Broadcast chỉ chạy sau khi commit thành công, tránh UI hiển thị event chưa tồn tại trong state.
- Event private (ví dụ vai trò hoặc lỗi riêng) không được gửi cho toàn phòng.

## Cách kiểm tra S04

Mỗi thành viên dùng sequence diagram để giải thích lại một lệnh `JoinGame`, sau đó ghi tên/GitHub và đánh dấu xác nhận:

| Thành viên | GitHub | Giải thích được luồng | Ngày xác nhận |
| --- | --- | --- | --- |
| Thành viên 1 | | [ ] | |
| Thành viên 2 | | [ ] | |
| Thành viên 3 | | [ ] | |
| Thành viên 4 | `@lunatran141` | [ ] | |
| Thành viên 5 | | [ ] | |

S04 đạt gate khi 5/5 thành viên giải thích được ba điểm: JSON được đổi thành kiểu Haskell ở đâu, state được commit ở đâu và event được gửi về UI khi nào.
