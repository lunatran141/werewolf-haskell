# Toolchain S02

Nhóm thống nhất dùng GHC 9.6.6 và Cabal 3.10 cho local, Docker và GitHub Actions. Khi thay đổi phiên bản, phải cập nhật đồng thời README, Dockerfile và workflow CI trong cùng một Pull Request.

Trên Windows, dùng đường dẫn chỉ có ký tự ASCII như `C:\dev\werewolf-haskell`. Tránh thư mục có dấu tiếng Việt vì GHC/Cabal có thể mã hóa sai đường dẫn package database.

## Gate kiểm tra

```bash
cabal update
cabal build all
cabal test all
```

S02 hoàn thành khi năm thành viên chạy được các lệnh trên từ clone sạch. Module trong `src` mới là skeleton; T01 và T02 mới được phép chốt luật, ADT, validation và contract gameplay.
