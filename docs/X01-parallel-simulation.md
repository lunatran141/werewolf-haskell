# X01 — Mô phỏng song song và Thống kê cân bằng ván chơi (`parMap` / `rdeepseq`)

## 1. Mục tiêu

Task X01 là một phần mở rộng ứng dụng kiến thức môn học (**Chương 4: Parallel Algorithms & Evaluation Strategies**) vào dự án Ma Sói Haskell, thực hiện các mục tiêu:

1. **Mô phỏng quy mô lớn**: Xây dựng bộ mô phỏng thuần (*Pure Simulator*) có khả năng chạy độc lập từ **1.000 đến 10.000 ván chơi** để khảo sát định lượng mức độ cân bằng game giữa cấu hình **8 người (2 Sói)** và **9 người (3 Sói)**.
2. **Thuật toán song song với Evaluation Strategies**: Áp dụng thư viện `parallel` (`Control.Parallel.Strategies.parMap`, `Control.DeepSeq.rdeepseq`) để phân phối các ván mô phỏng độc lập trên toàn bộ các nhân CPU khả dụng (`-threaded -rtsopts -with-rtsopts=-N`).
3. **Chứng minh tính xác định (Deterministic Parallelism - Kịch bản E19)**: Với cùng một seed ban đầu, kết quả của bản chạy **tuần tự (`map`)** và bản chạy **song song (`parMap rdeepseq`)** luôn **giống nhau tuyệt đối** (từng ván đấu và bảng tổng hợp thống kê).
4. **Báo cáo thực nghiệm**: Tự động đo thời gian thực thi (monotonic clock), tính hệ số tăng tốc (*Speedup*), tỷ lệ thắng của từng phe và xuất dữ liệu ra file [report/balance.csv](file:///d:/HK5/LTH/LTH_project/werewolf-haskell/report/balance.csv).

---

## 2. Ranh giới kiến trúc: Parallelism vs Concurrency (TV2 Gate)

Một nguyên tắc kiến trúc cốt lõi của dự án là **phân biệt rạch ròi giữa Parallelism và Concurrency**:

| Tiêu chí | Concurrency (Game Server) | Parallelism (Simulator X01) |
| :--- | :--- | :--- |
| **Bản chất bài toán** | I/O-bound, tương tác đa người dùng realtime | CPU-bound, tính toán mô phỏng hàng nghìn ván độc lập |
| **Công cụ kỹ thuật** | STM (`TVar`, `TBQueue`, `atomically`) | Strategies (`parMap`, `rdeepseq`, `NFData`) |
| **Trạng thái chia sẻ** | Có trạng thái chia sẻ (`RoomRuntime`) | **Không có trạng thái chia sẻ** (phi trạng thái, pure functions) |
| **Vị trí trong mã nguồn** | `src/Server/GameLoop.hs`, `Room.hs` | `app/Simulate.hs`, `src/Domain/Simulation.hs` |
| **Mục đích** | Đảm bảo tính nhất quán, không lost update khi nhiều người gửi lệnh | Tối ưu thời gian chạy batch mô phỏng trên CPU đa nhân |

> [!IMPORTANT]
> **TV2 Gate Verification**: Simulator X01 được đóng gói thành executable riêng biệt (`werewolf-simulate`) và module thuần `Domain.Simulation`. Thuật toán song song `parMap rdeepseq` tuyệt đối **không nằm trong `Server.GameLoop`**, không làm phức tạp hóa hay ảnh hưởng đến luồng xử lý WebSocket realtime của máy chủ.

---

## 3. Thiết kế kỹ thuật & Cơ sở lý thuyết FP

### 3.1. NFData và Đánh giá triệt để (`rdeepseq`)
Trong Haskell (ngôn ngữ lười - *lazy evaluation*), nếu chỉ dùng `parMap rwhnf` thông thường, runtime chỉ đánh giá cấu trúc đến *Weak Head Normal Form* (dừng lại ở constructor đầu tiên của danh sách), khiến các phép tính mô phỏng thực sự vẫn bị trì hoãn dưới dạng thunk trên Heap, dẫn đến việc không tận dụng được đa nhân và gây tràn bộ nhớ (*thunk leak*).

Để giải quyết, X01 áp dụng `Control.DeepSeq`:
- Các kiểu dữ liệu cốt lõi (`Role`, `Team`, `Phase`, `LifeStatus`, `GameResult`, `MatchOutcome`, `BalanceStats`) đều cài đặt `NFData` và `Generic`.
- Chiến lược đánh giá `rdeepseq` buộc từng spark song song phải ép tính toán toàn bộ ván chơi đến dạng *Normal Form* trước khi trả về:
  ```haskell
  runParallel :: SimConfig -> ([MatchOutcome], BalanceStats)
  runParallel cfg =
    let seeds = [simBaseSeed cfg .. simBaseSeed cfg + simGameCount cfg - 1]
        outcomes = parMap rdeepseq (simulateOneGame (simPresetRoles cfg)) seeds
        stats = aggregateStats outcomes
    in (outcomes, stats)
  ```

### 3.2. Tổng hợp nghiêm ngặt với `foldl'`
Hàm `aggregateStats` áp dụng `Data.List.foldl'` nghiêm ngặt trên `BalanceStats` (với các trường strict `!Int`, `!Bool`):
```haskell
aggregateStats :: [MatchOutcome] -> BalanceStats
aggregateStats = foldl' add (BalanceStats 0 0 0 0 0 True)
```
Điều này đảm bảo việc thu thập thống kê từ 10.000 ván diễn ra trong $O(1)$ không gian bộ nhớ phụ, không tích tụ chuỗi phép cộng lười trên heap.

### 3.3. Mô phỏng ván chơi thuần (`simulateOneGame`)
Mỗi ván chơi được mô phỏng hoàn toàn trên tầng Functional Core (`Domain.Engine`):
1. **Lobby & Phân vai**: Tạo lobby 8 hoặc 9 người, dùng `shuffleRolesWithSeed seed` gán vai xác định, vào `Night 1`.
2. **Vòng lặp các pha**:
   - **Night**: Sói còn sống chọn mục tiêu hợp lệ; Tiên Tri soi người khác; Bảo Vệ chọn mục tiêu khác đêm trước; Phù Thủy quyết định cứu/độc; kết thúc đêm bằng `resolveNightTurn` và `completeNightTurn`.
   - **Hunter**: Nếu Thợ Săn chết và đang chờ bắn (`gamePendingHunter`), tự động bắn mục tiêu còn sống hợp lệ.
   - **Day**: Chuyển tiếp sang `Voting` bằng `AdvancePhase`.
   - **Voting**: Từng người chơi còn sống bỏ phiếu; chốt phiếu bằng `resolveVoting`.
3. **Kết thúc**: Khi `gamePhase == GameOver`, trích xuất kết quả `GameResult`, kiểm tra bất biến `validateGameInvariant` và trả về `MatchOutcome`.

### 3.4. Phân tích cú pháp tham số CLI an toàn (`ReadP`)
Hàm `parseSimulateArgs` trong `Domain.Simulation` sử dụng thư viện parser combinator chuẩn `Text.ParserCombinators.ReadP` (`sepBy1`, `munch1`, `char`, `option`, `eof`) để đọc tham số dòng lệnh:
- Hỗ trợ nhiều dạng nhập: `--games 1000,5000,10000`, `--games=1k,5k,10k`, `--games 1.000,5.000`, `--seed 2026`, `--output report/balance.csv`, `--help`.
- Kiểm tra miền giá trị hợp lệ và từ chối tường minh mọi cờ lạ hoặc số sai định dạng bằng kiểu `Either SimCliError SimCliCommand`, không dùng hàm partial `read` gây dừng chương trình đột ngột.

---

## 4. Kết quả thực nghiệm & Phân tích cân bằng Game

Số liệu thực tế được đo đạc từ lệnh chạy `werewolf-simulate --games 1000,5000,10000 --seed 2026 --output report/balance.csv` trên máy **16 CPU Cores** (ghi nhận tại [report/balance.csv](file:///d:/HK5/LTH/LTH_project/werewolf-haskell/report/balance.csv)):

| Cấu hình | Số ván | Seed | Thắng Dân | Thắng Sói | Hòa | Tỷ lệ Dân | Tỷ lệ Sói | Tỷ lệ Hòa | Vòng tb | Tuần tự (ms) | Song song (ms) | Speedup | E19 (Seq == Par) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **8 người (2 Sói)** | 1.000 | 2026 | 267 | 733 | 0 | **26.70%** | **73.30%** | 0.00% | 3.52 | 1.079.43 ms | 263.91 ms | **4.09x** | **PASS (100%)** |
| **9 người (3 Sói)** | 1.000 | 2026 | 96 | 904 | 0 | **9.60%** | **90.40%** | 0.00% | 3.42 | 1.465.60 ms | 337.44 ms | **4.34x** | **PASS (100%)** |
| **8 người (2 Sói)** | 5.000 | 2026 | 1.307 | 3.685 | 8 | **26.14%** | **73.70%** | 0.16% | 3.52 | 6.747.63 ms | 1.478.94 ms | **4.56x** | **PASS (100%)** |
| **9 người (3 Sói)** | 5.000 | 2026 | 480 | 4.518 | 2 | **9.60%** | **90.36%** | 0.04% | 3.41 | 8.138.88 ms | 1.745.31 ms | **4.66x** | **PASS (100%)** |
| **8 người (2 Sói)** | 10.000 | 2026 | 2.627 | 7.364 | 9 | **26.27%** | **73.64%** | 0.09% | 3.53 | 14.106.15 ms | 5.119.73 ms | **2.76x** | **PASS (100%)** |
| **9 người (3 Sói)** | 10.000 | 2026 | 1.017 | 8.979 | 4 | **10.17%** | **89.79%** | 0.04% | 3.42 | 15.519.37 ms | 5.557.56 ms | **2.79x** | **PASS (100%)** |

### Nhận xét & Đánh giá:

1. **Về kết quả thống kê mô phỏng (Simulation Balance dưới chiến lược Bot ngẫu nhiên)**:
   - **Ván 8 người (2 Sói / 6 Dân = 25% Sói)**: Phe Dân đạt tỷ lệ thắng **26.14% – 26.70%**, phe Sói đạt **73.30% – 73.70%**.
   - **Ván 9 người (3 Sói / 6 Dân = 33.3% Sói)**: Phe Dân đạt **9.60% – 10.17%**, phe Sói đạt **89.79% – 90.40%**.
   - **Lưu ý quan trọng khi diễn giải**: Trong `Domain.Simulation`, các tác nhân (bot) chọn mục tiêu và bỏ phiếu ban ngày theo xác suất ngẫu nhiên hợp lệ (`pickRandom`) mà không sử dụng thông tin suy luận từ kết quả Tiên Tri hay thảo luận nhóm như người thật. Do Sói luôn thống nhất mục tiêu ban đêm trong khi Dân bỏ phiếu ngẫu nhiên ban ngày, tỷ lệ Sói thắng cao (~90% ở cấu hình 3 Sói) phản ánh đúng đặc trưng của **chiến lược bot ngẫu nhiên**, không phải kết luận rằng cấu hình 9 người mất cân bằng khi người thật chơi.
   - Cả hai cấu hình đều ghi nhận một tỷ lệ nhỏ kết quả **Hòa (`Draw`: 0.04% – 0.16%)** khi Thợ Săn bị loại và bắn hạ con Sói cuối cùng, khiến cả hai phe cùng hết người sống.

2. **Về hiệu năng song song (Parallel Speedup)**:
   - Ở mốc **1.000 ván** và **5.000 ván**, `parMap rdeepseq` giúp giảm thời gian thực thi từ **6.75s – 8.14s xuống còn 1.48s – 1.75s**, đạt hệ số tăng tốc **4.09x – 4.66x**.
   - Ở mốc **10.000 ván**, thời gian giảm từ **14.11s – 15.52s xuống còn 5.12s – 5.56s**, hệ số tăng tốc đạt **2.76x – 2.79x**. Hệ số tăng tốc ở 10.000 ván thấp hơn mốc 5.000 ván do benchmark giữ đồng thời cả hai danh sách `seqOutcomes` và `parOutcomes` (mỗi danh sách 10.000 phần tử đã `deepseq`) trong bộ nhớ để đối chiếu trực tiếp `seqOutcomes == parOutcomes`, làm tăng áp lực cấp phát Heap và chi phí đồng bộ Garbage Collection (stop-the-world GC) giữa 16 capabilities của GHC RTS.

3. **Về tính tất định (E19)**:
   - Trên toàn bộ các mốc **1.000, 5.000 và 10.000 ván** (cả cấu hình 8 người và 9 người), phép kiểm chứng `seqOutcomes == parOutcomes` và `seqStats == parStats` đều đạt `TRUE` (100%). Thuật toán song song bảo toàn tuyệt đối tính tất định và mọi bất biến `validateGameInvariant`.

---

## 5. Hướng dẫn chạy và Kiểm thử

### 5.1. Chạy Executable mô phỏng & Xuất file CSV
```powershell
# Chạy mặc định 1.000 và 5.000 ván cho cả 2 cấu hình, ghi file report/balance.csv
cabal run werewolf-simulate

# Tùy chỉnh số ván (hỗ trợ cả dạng số thường, dấu chấm phân nhóm hoặc hậu tố k):
cabal run werewolf-simulate -- --games 1000,5000,10000 --seed 2026 --output report/balance.csv
cabal run werewolf-simulate -- --games=1k,5k,10k --seed=2026

# Xem hướng dẫn sử dụng:
cabal run werewolf-simulate -- --help
```

### 5.2. Chạy Bộ kiểm thử tự động (E19 & CLI Parser)
```powershell
# Chạy test suite riêng cho X01
cabal test x01-simulate-test --enable-tests --test-show-details=direct

# Chạy toàn bộ test suites dự án để kiểm chứng không ảnh hưởng GameLoop
cabal test all --enable-tests --test-show-details=direct -j1
```
