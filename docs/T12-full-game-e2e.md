# T12 - Full game E2E và bằng chứng demo

## Phạm vi tự động

Test `T12FullGameE2ESpec.hs` kiểm tra:

- 9 WebSocket client Create/Join cùng một phòng với ngoại hình đã chọn.
- Cả 9 người Ready, Host Start và mỗi kết nối nhận đúng một vai riêng.
- Lệnh Vote trong Night bị từ chối.
- Chat Sói được Server chấp nhận và lưu đúng kênh riêng.
- Night 1 được thực hiện bằng hành động thật của Sói, Tiên Tri, Bảo Vệ và Phù Thủy.
- Day 1 lưu chat và cùng `requestId` không tạo tin thứ hai.
- Toàn bộ người sống bỏ qua thảo luận; khi người sống cuối cùng bỏ phiếu,
  Server chốt ngay và chuyển thật sang Night 2 mà không chờ hết 60 giây.
- Reconnect bằng token giữ PlayerId, Night 2 và lịch sử Day 1.
- Night 2 được thực hiện bằng WebSocket và tự kết thúc tại GameOver.
- Một client không đọc tiếp dữ liệu không chặn các client còn lại.
- GameOver công khai đủ 9 vai.
- Pure replay cùng input tạo cùng final state và event transcript.

## Lệnh chạy

```powershell
cabal test --enable-tests t12-full-game-e2e-test
```

## Checklist 2-3 trình duyệt thật

- [ ] Mở 2-3 cửa sổ/trình duyệt khác nhau và cùng vào một mã phòng.
- [ ] Mỗi người thấy cùng 9 ô, tên, ngoại hình và trạng thái sống/chết.
- [ ] Chỉ ô của chính mình hiển thị vai và khả năng riêng.
- [ ] Dân không thấy chat Sói, danh sách Sói hoặc kết quả riêng của Tiên Tri.
- [ ] Chat Day hiện trong lịch sử và bong bóng đúng người gửi.
- [ ] Refresh một trình duyệt: không mất người, phase, ngày hoặc lịch sử.
- [ ] Gửi lại request không tạo hai tin, hai phiếu hoặc hai action.
- [ ] Người chết có dấu X nhưng chưa lộ vai.
- [ ] FAQ và mô tả khả năng mở/đóng được.
- [ ] GameOver hiển thị kết quả và toàn bộ vai.

## Bằng chứng cần lưu

| Bằng chứng | Trạng thái | Đường dẫn/link |
| --- | --- | --- |
| Log test 9 client | Chưa ghi | |
| Ảnh Lobby đủ 9 người | Chưa ghi | |
| Ảnh Night từ góc nhìn Sói và Dân | Chưa ghi | |
| Ảnh Day/chat/bubble | Chưa ghi | |
| Ảnh reconnect giữ Day 2 và lịch sử | Chưa ghi | |
| Ảnh Voting/người chết | Chưa ghi | |
| Ảnh GameOver/reveal | Chưa ghi | |
| Video cùng một ván trên 2-3 browser | Chưa ghi | |

Phần code T12 đạt gate khi test T12 và toàn bộ test Haskell đều PASS. Checklist
trình duyệt là phần demo/minh chứng thực tế, không phải review chéo.
