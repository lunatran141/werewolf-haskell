# Werewolf Haskell

Đồ án Ma Sói online của môn Lập trình hàm. Haskell Server giữ luật và `GameState`; browser chỉ gửi `Command` và hiển thị `Event` do server trả về.

## Chạy bằng Docker

```bash
cp .env.example .env
docker compose up --build
```

Kiểm tra health tại <http://localhost:8080/health>. Dừng bằng `docker compose down`.

Hướng dẫn clean-clone, healthcheck và CI smoke test nằm trong [tài liệu S03](docs/s03-docker-ci.md).

Kiến trúc phân lớp và luồng `JoinGame` từ Browser đến UI nằm trong [tài liệu S04](docs/architecture.md).

## Toolchain đã chốt cho S02

- GHC 9.6.6
- Cabal 3.10

Local, Docker và GitHub Actions phải dùng cùng phiên bản chính này để tránh tình trạng một máy build được nhưng máy khác không build được.

Trên Windows, nên clone repository vào đường dẫn chỉ có ký tự ASCII, ví dụ `C:\dev\werewolf-haskell`. Một số phiên bản GHC/Cabal có thể lỗi package database khi đường dẫn chứa dấu tiếng Việt.

## Chạy local

Yêu cầu GHC 9.6.6 và Cabal 3.10:

```bash
cabal update
cabal build all
cabal test all
cabal run werewolf-server
```

## Quy trình Git

Đọc [CONTRIBUTING.md](CONTRIBUTING.md) và [hướng dẫn S01 cho cả nhóm](docs/s01-github-workflow.md). Mỗi thay đổi đi theo Issue → feature branch → PR vào `develop` → review → CI → merge. `main` chỉ nhận PR phát hành cuối từ `develop`. Nguồn trạng thái duy nhất là Sheet 02; không dùng mã task ở các tab LEGACY.

## Cấu trúc ban đầu

```text
app/             executable/health endpoint tạm thời
src/Domain/      pure types, validation, rules
src/Protocol/    command/event JSON contract
src/Server/      WebSocket, room runtime, STM
web/             frontend
test/            Hspec/QuickCheck
docs/            architecture, game rules, evidence
```

S02 chỉ tạo module skeleton có thể build/test. Kiểu dữ liệu, luật và triển khai thật sẽ được bổ sung đúng owner trong T01–T15.
