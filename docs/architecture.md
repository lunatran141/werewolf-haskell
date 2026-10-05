# Kiến trúc dự kiến

Browser gửi `Command` qua WebSocket. Haskell Server giải mã và chuyển lệnh vào Pure Engine. Engine trả về state mới cùng `DomainEvent`; STM commit state và Broadcast gửi event public/private đúng người nhận. Frontend chỉ render event từ server.

```text
Browser -> Protocol -> WebSocket -> GameLoop/STM -> Pure Engine
   ^                                              |
   +--------------- Broadcast/Event -------------+
```

