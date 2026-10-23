# X02 — Analytics Worker

Game Server va Analytics Worker la hai process doc lap. Server khong ghi truc
tiep file analytics va Worker khong truy cap `GameState` trong RAM.

```text
GameFinished
  -> MatchSummary
  -> TBQueue khong chan GameLoop
  -> TCP / JSON Lines
  -> analytics-worker
  -> analytics/matches.jsonl
```

## Bien moi truong

- Game Server: `ANALYTICS_HOST` (mac dinh `127.0.0.1`) va
  `ANALYTICS_PORT` (mac dinh `9090`).
- Worker: `ANALYTICS_PORT` va `ANALYTICS_OUTPUT`
  (mac dinh `analytics/matches.jsonl`).

## Chay local bang hai terminal

Terminal 1:

```powershell
$env:ANALYTICS_PORT="9090"
$env:ANALYTICS_OUTPUT="analytics/matches.jsonl"
cabal run analytics-worker
```

Terminal 2:

```powershell
$env:APP_PORT="8080"
$env:ANALYTICS_HOST="127.0.0.1"
$env:ANALYTICS_PORT="9090"
cabal run werewolf-server
```

Hoac chay ca hai process bang `docker compose up --build`.

## Dam bao

- Worker vang mat hoac restart khong lam Game Server dung.
- Server thu gui lai summary dang cho khi Worker ket noi lai.
- Worker nap lai cac `matchId` tu file khi khoi dong.
- Cung mot `matchId` chi duoc ghi mot lan.
- Payload khong chua ten, vai tro, muc tieu hanh dong hay noi dung chat.
