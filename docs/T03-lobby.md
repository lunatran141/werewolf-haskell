# T03 – Hoàn thành chức năng Lobby

**Dự án:** Werewolf Haskell
**Task:** T03 – Lobby end-to-end
**Thành viên phụ trách:** TV3

## 1. Mục tiêu

Cho phép người chơi tham gia phòng, rời phòng và đổi trạng thái sẵn sàng. Lệnh đi từ Browser qua WebSocket đến Server và Domain; kết quả được gửi lại để giao diện của những người trong phòng cập nhật.

## 2. Chức năng đã hoàn thành

- Join: thêm người chơi hợp lệ vào Lobby. Người đầu tiên trở thành Host.
- Leave: xóa người chơi khỏi Lobby. Nếu Host rời, người vào sớm nhất còn lại trở thành Host.
- Ready: đổi trạng thái sẵn sàng của người chơi.
- Từ chối các trường hợp không hợp lệ như tên hoặc PlayerId trùng, phòng đầy, người chơi không tồn tại và lệnh ở sai phase.
- Mã hóa và giải mã thông điệp JSON cho các lệnh, snapshot, sự kiện và lỗi Lobby.
- Server xử lý lệnh và gửi trạng thái mới đến Browser.
- Giao diện hiển thị danh sách người chơi, Host và trạng thái Ready theo dữ liệu từ Server.

## 3. File liên quan

- `src/Domain/Engine.hs`
- `src/Domain/Validation.hs`
- `src/Protocol/Types.hs`
- `src/Protocol/Json.hs`
- `src/Server/GameLoop.hs`
- `src/Server/Broadcast.hs`
- `src/Server/WebSocket.hs`
- `web/app.js`
- `web/index.html`

## 4. Kiểm thử

- `test/T03LobbySpec.hs`: 17 bài kiểm tra luật Join, Leave và Ready.
- `test/ProtocolLobbySpec.hs`: 11 bài kiểm tra JSON, bao gồm mã hóa rồi giải mã lại thông điệp.
- `test/ServerGameLoopSpec.hs`: kiểm tra cập nhật state, event, snapshot và phản hồi lỗi.
- Các log test đã lưu trên máy báo PASS cho `t03-lobby-test`, `protocol-lobby-test` và `server-gameloop-test`.
- Đã kiểm tra thủ công với từ hai tab Browser: người chơi cùng vào phòng và trạng thái Lobby được đồng bộ.

## 5. Kết luận
Phần code T03 trên máy đã hoàn thành theo phạm vi Lobby Join/Leave/Ready. Trạng thái commit, push và merge vào nhánh `develop` cần được kiểm tra riêng trên GitHub.