# X03 — NFS Replay Store

X03 tao mot ranh gioi storage rieng cho replay cong khai. GameState realtime
van chi nam trong `TVar` cua Game Server; NFS khong tham gia vao xu ly Command,
Night, Vote hoac chuyen Phase.

## Du lieu duoc luu

Moi van ket thuc tao mot file `shared/replays/<matchId>.json` theo schema
`MatchSummary` cua X02:

- `matchId`
- `roomId`
- `result`
- `dayCount`
- `playerCount`

Replay khong co ten nguoi choi, role, chat, target, private event hay GameState.
Ten file chi chap nhan chu, so, dau gach ngang va gach duoi de chan path
traversal.

## Fault boundary

`Server.ReplayStore` chuyen loi mount, permission va file hong thanh
`StorageError`. Subscriber ghi replay chay ben ngoai GameLoop, nen loi NFS chi
duoc log va van dau van tiep tuc. File duoc ghi qua file tam roi rename de tranh
de lai JSON dang do.

Neu `REPLAY_DIR` khong duoc dat, ReplayStore bi tat. Cau hinh mac dinh va Render
khong can NFS.

## Chay test local

```powershell
cabal test x03-replay-store-test --enable-tests --test-show-details=direct
```

Test khong can NFS that; no kiem tra hai store doc cung file, idempotency,
mount hong, permission mapping, corrupt JSON va privacy scan.

## Chay NFS demo

NFS demo dung NFSv4 container va Docker local-volume driver. Nen chay bang
Docker Engine Linux hoac WSL2. Render khong dung file compose nay.

Khoi dong NFS server truoc:

```powershell
docker compose -f compose.yaml -f docker-compose.nfs.yml --profile nfs-demo up -d nfs-server
```

Sau khi NFS server da san sang, khoi dong hai process dung chung mount:

```powershell
docker compose -f compose.yaml -f docker-compose.nfs.yml --profile nfs-demo up --build server analytics-worker
```

Neu Docker daemon khong truy cap NFS qua `127.0.0.1`, dat `NFS_HOST` thanh dia
chi cua host/WSL truoc khi chay lenh thu hai.

```powershell
$env:NFS_HOST="<dia-chi-host>"
```

Dung demo:

```powershell
docker compose -f compose.yaml -f docker-compose.nfs.yml --profile nfs-demo down
```
