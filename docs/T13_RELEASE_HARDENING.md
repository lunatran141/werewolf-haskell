# T13 - Release hardening

T13 does not add gameplay. It turns the integrated T12 + X01-X03 build into a
repeatable release candidate with explicit safety gates.

## Gates covered

- **Input/resource limits:** room command and outbound queues remain bounded;
  chat is limited to 300 characters on both browser and server; player names are
  limited to 30 characters on the server; WebSocket JSON frames over 4096 bytes
  are rejected before parsing.
- **Privacy:** the full test suite retains the role/chat filtering tests from
  T07/T08, analytics payload tests from X02 and sanitized replay tests from X03.
- **Safe logs:** server, analytics publisher, replay store and analytics worker
  emit JSON lines. Fields whose names may carry roles, chat, targets, tokens,
  secrets or raw payloads are redacted automatically.
- **Browser safety:** user chat is inserted with `textContent`/`createTextNode`,
  not HTML sinks. FAQ and ability dialogs use native modal `<dialog>` semantics,
  labelled headings, visible close buttons and autofocus targets; native Escape
  handling closes the modal and restores focus.
- **CI/Docker:** CI treats compiler warnings as failures, runs the complete
  Haskell suite twice (one coverage pass), runs every browser test including the
  T13 security contract, validates both Compose files and performs a clean
  Docker build/health smoke test.

## Local release check

```powershell
cabal build all --enable-tests --ghc-options=-Werror
cabal test all --enable-tests --test-show-details=direct
cabal test all --enable-tests --test-show-details=direct
node --check web/app.js
node --test test/T06UiSpec.cjs test/T07UiSpec.cjs test/T13UiSecuritySpec.cjs
docker compose config
docker compose -f compose.yaml -f docker-compose.nfs.yml --profile nfs-demo config
docker compose up --build --detach
docker compose ps
curl.exe --fail http://127.0.0.1:8080/health
docker compose down --volumes --remove-orphans
```

For the NFS integration evidence, use the separate X03 procedure in
`docs/X03_NFS_REPLAY.md`; GitHub-hosted runners validate that profile but do not
start a privileged NFS server.
