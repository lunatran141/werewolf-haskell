# S03 Docker và CI

S03 chuẩn hóa một cách build và chạy dự án cho mọi thành viên. Docker dùng GHC 9.6.6 để build library, executable và test suite; runtime image chỉ chứa executable cùng công cụ healthcheck và chạy bằng user không có quyền root.

## Kiểm tra từ clone sạch

Trên Windows, nên clone vào đường dẫn chỉ có ký tự ASCII:

```powershell
cd C:\dev
git clone https://github.com/lunatran141/werewolf-haskell.git
cd werewolf-haskell
git switch develop
docker compose up --build --detach
```

Kiểm tra container:

```powershell
docker compose ps
Invoke-RestMethod http://127.0.0.1:8080/health
```

Kết quả hợp lệ là service `server` có trạng thái `healthy` và endpoint trả về:

```json
{"status":"ok"}
```

Dừng và dọn tài nguyên:

```powershell
docker compose down --volumes --remove-orphans
```

## CI kiểm tra gì

Pull Request vào `develop` hoặc `main` kích hoạt hai job độc lập:

1. `build`: cài GHC/Cabal đã chốt, build mọi component và chạy toàn bộ test.
2. `docker`: kiểm tra Compose, build image, khởi động container, chờ healthcheck, gọi `/health`, in log khi lỗi và luôn dọn tài nguyên.

Quy tắc merge: cả hai job phải xanh và có review của thành viên khác. Job đỏ phải được sửa trên chính feature branch; push commit mới sẽ tự chạy lại CI.

## Điều kiện hoàn thành S03

- [x] Dockerfile multi-stage.
- [x] Runtime chạy bằng non-root user.
- [x] Compose có biến môi trường, port và healthcheck.
- [x] CI build và test Haskell.
- [x] CI build, chạy container và kiểm tra endpoint thật.
- [ ] Một thành viên khác xác minh từ clone sạch.
- [ ] PR S03 được review và merge vào `develop` khi CI xanh.
