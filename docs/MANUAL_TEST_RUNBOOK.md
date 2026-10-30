# Hướng dẫn Kiểm thử Thực tế Trọn vẹn Ván chơi Web (8–9 Người) & Tái sử dụng Phòng

Tài liệu này cung cấp kịch bản kiểm thử từng bước (Runbook) cho nhóm nhằm phục vụ buổi kiểm thử cuối kỳ và buổi trình diễn (demo) trực tiếp trước giảng viên.

---

## 1. Chuẩn bị Môi trường Kiểm thử

### Cách 1: Chạy cục bộ trên máy (Local)
1. Mở Terminal 1 (Game Server):
   ```bash
   cabal run exe:werewolf-server
   ```
   *Server sẽ lắng nghe tại `http://127.0.0.1:8080` (hoặc cổng cấu hình qua `APP_PORT`).*

2. Mở Terminal 2 (Analytics Worker - tùy chọn):
   ```bash
   cabal run exe:analytics-worker
   ```
   *Worker lắng nghe tại `127.0.0.1:9090`, tự động ghi nhận ván đấu và chống trùng `matchId`.*

### Cách 2: Sử dụng bản Deploy trực tuyến
- Truy cập trực tiếp link web game trên dịch vụ đám mây (Render / Docker) đã triển khai của nhóm.

---

## 2. Kịch bản Kiểm thử Từng bước (Step-by-Step Test Script)

### Bước 1: Tạo phòng & Tham gia phòng (Lobby)
1. **Host tạo phòng**:
   - Mở trình duyệt (Tab 1), truy cập `http://127.0.0.1:8080`.
   - Chọn tab **Tạo phòng**: Nhập tên Host (ví dụ: `Host-Minh`), chọn kiểu tóc và phụ kiện avatar.
   - Bấm **Tạo phòng**. Ghi nhận mã phòng (ví dụ: `ROOM-DEMO`).
2. **Các người chơi khác tham gia**:
   - Mở thêm 7 hoặc 8 tab trình duyệt (có thể mở tab ẩn danh Incognito hoặc mở nhiều trình duyệt khác nhau: Chrome, Edge, Firefox).
   - Chọn tab **Vào phòng**: Nhập mã phòng `ROOM-DEMO`, tên người chơi (`Nguoi-2` đến `Nguoi-9`), chọn avatar riêng biệt.
   - Bấm **Vào phòng**.
3. **Trạng thái Sẵn sàng**:
   - Trên mỗi tab, người chơi click nút **Sẵn sàng**.
   - Kiểm tra danh sách người chơi trên màn hình cập nhật đồng bộ tick xanh "Đã sẵn sàng".
   - Khi đủ từ 8 đến 9 người sẵn sàng, nút **Bắt đầu ván** trên màn hình của Host sẽ sáng lên.
   - Host click **Bắt đầu ván**.

---

### Bước 2: Ban đêm (Night 1) & Phân vai bí mật
1. **Kiểm tra vai riêng biệt (Privacy Check)**:
   - Mỗi tab hiển thị thẻ vai trò bí mật của chính mình (ví dụ: Sói, Tiên Tri, Bảo Vệ, Phù Thủy, Thợ Săn, Dân Làng).
   - Tuyệt đối không thấy vai trò của người khác trong bảng người chơi.
2. **Lượt Sói (Wolf Turn - 60 giây)**:
   - Các tab Sói: Hiển thị kênh chat riêng màu đỏ (**Kênh Sói**). Chat thử trong kênh này và kiểm tra các tab Dân Làng không hề thấy nội dung chat.
   - Các con Sói cùng chọn một mục tiêu cắn (ví dụ: cắn người chơi giữ vai `Thợ Săn`).
   - Khi toàn bộ Sói đã chốt phiếu, lượt Sói tự động khóa.
3. **Lượt các vai Dân (Seer, Guard, Witch - 30 giây)**:
   - **Tiên Tri**: Chọn 1 người chơi để soi -> Nhận thông báo kết quả soi chính xác (Phe Sói hoặc Phe Dân).
   - **Bảo Vệ**: Chọn 1 người chơi để bảo vệ ban đêm.
   - **Phù Thủy**: Hiển thị thông báo nạn nhân bị Sói cắn -> Có thể chọn dùng bình cứu, bình độc hoặc bỏ qua (Pass).

---

### Bước 3: Thợ Săn bị hạ gục & Kích hoạt Bắn trả (Hunter Shot)
1. Giả định ban đêm Thợ Săn bị Sói cắn chết và Phù Thủy không cứu.
2. Khi trời sáng (chuyển sang pha Day 1):
   - Hệ thống thông báo Thợ Săn đã chết.
   - Tab của Thợ Săn hiển thị bảng chọn mục tiêu **Bắn trả**.
   - Thợ Săn chọn bắn một người chơi khác (ví dụ: bắn một con Sói).
   - Hệ thống công bố nạn nhân thứ hai bị Thợ Săn bắn hạ. Cả hai người đều chuyển sang trạng thái Đã chết (thẻ xám).

---

### Bước 4: Ban ngày & Bỏ phiếu loại trừ (Day & Voting)
1. **Pha Thảo luận (Day)**:
   - Người chơi còn sống chat công khai trong **Kênh Chung**.
   - Người đã chết bị khóa ô chat, không gửi được tin nhắn gây nhiễu ván đấu.
   - Kiểm tra nút **Bỏ qua thảo luận**: Khi tất cả người chơi còn sống cùng bấm bỏ qua, hệ thống lập tức mở pha Bỏ phiếu mà không cần đợi hết đồng hồ thảo luận.
2. **Pha Bỏ phiếu (Voting - 60 giây)**:
   - Bảng bỏ phiếu hiện danh sách người chơi còn sống.
   - Từng người chơi còn sống chọn 1 nghi phạm và bấm **Bỏ phiếu**.
   - Khi hết giờ bỏ phiếu hoặc tất cả đã vote: Hệ thống kiểm phiếu công khai, thông báo số phiếu từng người và loại người bị nhiều phiếu nhất.

---

### Bước 5: Kiểm tra Mất kết nối & Vào lại (Reconnect & Resilience)
1. Tại bất kỳ thời điểm nào trong ván chơi, thử tắt 1 tab trình duyệt hoặc nhấn `F5` tải lại trang.
2. **Xác nhận**:
   - Trình duyệt tự động dùng session token đã lưu trong `localStorage` để kết nối lại phòng.
   - Giao diện khôi phục chính xác: đúng pha hiện tại, đúng vai trò bí mật, đúng trạng thái sống/chết và giữ nguyên toàn bộ lịch sử tin nhắn đã chat trước đó.

---

### Bước 6: Kết thúc ván (GameOver) & Tái sử dụng phòng (Room Reuse)
1. **Điều kiện kết thúc**:
   - Khi một phe chiến thắng (toàn bộ Sói bị loại hoặc số Sói bằng/lớn hơn số Dân còn sống):
   - Màn hình chuyển sang trạng thái **Kết thúc ván (GameOver)**.
   - Nhạc chiến thắng tương ứng được phát.
   - Bảng **Toàn bộ vai trò** được công bố minh bạch cho tất cả người chơi.
2. **Tái sử dụng phòng**:
   - Người chơi bấm nút **Rời phòng** để quay về sảnh chính.
   - Sau khi phòng kết thúc, hệ thống kích hoạt bộ hẹn giờ dọn dẹp phòng tự động.
   - Thử dùng lại đúng mã phòng đó (`ROOM-DEMO`) để tạo phòng mới -> Hệ thống chấp nhận tạo phòng mới thành công, không gặp lỗi phòng bị kẹt hay dữ liệu ván cũ tồn đọng.
3. **Kiểm tra Analytics & Replay**:
   - Dữ liệu kết quả trận đấu được ghi nhận tự động vào `analytics/matches.jsonl` và thư mục `shared/replays`.
   - Cơ chế Spooling đảm bảo không bị thất thoát ván đấu ngay cả khi Worker bị tắt tạm thời trong lúc chơi.

