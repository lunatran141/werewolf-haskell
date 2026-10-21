# T10 — Hoàn thiện giao diện theo Event từ Server

## 1. Mục tiêu

T10 hoàn thiện giao diện Lobby, Game và Result dựa trên dữ liệu Server gửi qua WebSocket. Browser hiển thị hành động phù hợp với trạng thái được nhận; Server vẫn là nơi kiểm tra quyền, mục tiêu và luật chơi trước khi chấp nhận lệnh.

## 2. Chức năng đã hoàn thành

- Dashboard luôn có 9 ô người chơi trong Lobby, Đêm, Ngày, Bỏ phiếu và Kết thúc. Ô trống hiển thị trạng thái chờ; ô có người hiển thị tên, ngoại hình và trạng thái.
- Chỉ ô của chính người chơi hiển thị vai và nút **Khả năng của tôi**. Nút mở hướng dẫn về vai, không gửi hành động.
- Người bị loại có dấu ✕ và ô bị làm tối. Vai của người khác chỉ được hiển thị khi Server gửi `GameRolesRevealed` ở GameOver.
- Khi hành động ban đêm, bỏ phiếu hoặc bắn của Thợ săn, giao diện dùng `ValidTargetsSnapshot` riêng do Server gửi để mở các mục tiêu hợp lệ. Mục tiêu cũ bị khóa khi nhận trạng thái mới hoặc mất kết nối. Server kiểm tra lại lệnh được gửi.
- Chat chung và chat Sói hiển thị riêng theo ngày/đêm. Lịch sử được khôi phục khi reconnect theo quyền của người xem. Tin mới hiện bong bóng trên ô người gửi khoảng 5 giây; nội dung dài được rút gọn trong bong bóng.
- Nút `?` mở hướng dẫn chung về cách vào phòng, thứ tự các giai đoạn, vai trò, bỏ phiếu và điều kiện thắng. Nội dung không tiết lộ người đang giữ vai.
- Giao diện dùng bố cục đáp ứng theo kích thước màn hình. Nhóm đã chấp nhận cách sắp xếp các ô hiện tại trên điện thoại.

## 3. Luồng dữ liệu và quyền riêng tư

1. Browser gửi command kèm `requestId` tới Server.
2. Server xác thực phiên, vai, giai đoạn và mục tiêu.
3. Server phát Event/Snapshot tới những người được quyền nhận.
4. `state.js` cập nhật trạng thái; `ui.js` render lại giao diện.
5. Dữ liệu chat được đưa vào DOM bằng `textContent` hoặc `createTextNode`, không chèn HTML từ nội dung người chơi gửi.

`YourRole`, trạng thái hành động riêng và `ValidTargetsSnapshot` chỉ gửi cho đúng người chơi. Chat Sói và thông tin phối hợp của Sói chỉ gửi tới người có quyền xem. Dấu ✕ là thông tin công khai; danh sách vai đầy đủ chỉ công khai ở GameOver.

## 4. Các file liên quan

- `web/protocol.js`: kết nối WebSocket, gửi command, xử lý lỗi và reconnect.
- `web/state.js`: lưu trạng thái giao diện từ Event/Snapshot.
- `web/ui.js`: render dashboard, chọn mục tiêu, chat, bong bóng, hướng dẫn và kết quả.
- `web/app.js`: gắn sự kiện cho nút, form và hành động người chơi.
- `web/index.html`, `web/style.css`: cấu trúc và giao diện đáp ứng.
- `src/Protocol/Types.hs`: JSON contract của `ValidTargetsSnapshot`.
- `src/Server/Broadcast.hs`, `src/Server/WebSocket.hs`: tính và gửi danh sách mục tiêu riêng theo trạng thái Server.

## 5. Kiểm thử

Đã chạy:

```powershell
node --test test/T06UiSpec.cjs test/T07UiSpec.cjs
```

Kết quả: **40 test đạt, 0 lỗi**.

Đã chạy:

```powershell
cabal test t06-protocol-test --enable-tests --test-show-details=direct --builddir "C:\Users\khanh\werewolf-build-966"
```

Kết quả: **13 trường hợp đạt, 0 lỗi**, gồm kiểm tra Sói không được chọn đồng đội vào ban đêm nhưng vẫn có thể bỏ phiếu cho đồng đội trong pha Voting theo luật hiện tại.

Nhóm cũng đã chơi thử bằng nhiều trình duyệt và trên điện thoại để kiểm tra chat Sói, reconnect, hướng dẫn bằng bàn phím và bố cục.
