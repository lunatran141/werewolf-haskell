# Werewolf Haskell

Đồ án Ma Sói online của môn Lập trình hàm. Haskell Server giữ luật và `GameState`; browser chỉ gửi `Command` và hiển thị `Event` do server trả về.

## Chạy bằng Docker

```bash
cp .env.example .env
docker compose up --build
```

Kiểm tra health tại <http://localhost:8080/health>. Dừng bằng `docker compose down`.

## Chạy local

Yêu cầu GHC 9.6.6 và Cabal 3.10:

```bash
cabal update
cabal run werewolf-server
```

## Quy trình Git

Đọc [CONTRIBUTING.md](CONTRIBUTING.md) và [hướng dẫn S01 cho cả nhóm](docs/s01-github-workflow.md). Mỗi thay đổi phải đi theo Issue → branch → PR → review → CI → merge. Nguồn trạng thái duy nhất là Sheet 02; không dùng mã task ở các tab LEGACY.

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

Các thư mục chức năng sẽ được bổ sung trong S02 và các task T01–T15.
