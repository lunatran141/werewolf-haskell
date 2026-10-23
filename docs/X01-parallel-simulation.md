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

---

## 4. Kết quả thực nghiệm & Phân tích cân bằng Game

Số liệu thực tế được đo đạc từ lệnh chạy `werewolf-simulate` trên máy **16 CPU Cores** với Seed gốc `2026` (ghi nhận tại `report/balance.csv`):

| Cấu hình | Số ván | Seed | Thắng Dân | Thắng Sói | Hòa | Tỷ lệ Dân | Tỷ lệ Sói | Tỷ lệ Hòa | Vòng tb | Tuần tự (ms) | Song song (ms) | Speedup | E19 (Seq == Par) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **8 người (2 Sói)** | 1.000 | 2026 | 267 | 733 | 0 | **26.70%** | **73.30%** | 0.00% | 3.52 | 801.3 ms | 163.9 ms | **4.89x** | **PASS (100%)** |
| **9 người (3 Sói)** | 1.000 | 2026 | 96 | 904 | 0 | **9.60%** | **90.40%** | 0.00% | 3.42 | 957.9 ms | 183.0 ms | **5.23x** | **PASS (100%)** |
| **8 người (2 Sói)** | 5.000 | 2026 | 1.307 | 3.685 | 8 | **26.14%** | **73.70%** | 0.16% | 3.52 | 3.923.0 ms | 782.5 ms | **5.01x** | **PASS (100%)** |
| **9 người (3 Sói)** | 5.000 | 2026 | 480 | 4.518 | 2 | **9.60%** | **90.36%** | 0.04% | 3.41 | 5.208.4 ms | 917.5 ms | **5.68x** | **PASS (100%)** |

### Nhận xét & Đánh giá:

1. **Về mức độ cân bằng (Game Balance)**:
   - **Ván 8 người (2 Sói / 6 Dân = 25% Sói)**: Phe Dân đạt tỷ lệ thắng **~26.1%**. Với sự hỗ trợ của 4 vai chức năng (Tiên Tri, Bảo Vệ, Phù Thủy, Thợ Săn), phe Dân có cơ hội lật ngược tình thế tốt hơn đáng kể.
   - **Ván 9 người (3 Sói / 6 Dân = 33.3% Sói)**: Phe Sói chiếm ưu thế áp đảo với tỷ lệ thắng **~90.4%**. Nguyên nhân là số lượng Sói ban đầu chiếm 1/3 phòng, chỉ cần Sói cắn thành công 2 đêm và phe Dân vote nhầm 1 lần là số lượng Sói bằng số Dân, kích hoạt điều kiện thắng tức thì của Sói (`so Soi >= so Dan`).
   - Cả hai cấu hình đều xuất hiện một tỷ lệ rất nhỏ kết quả **Hòa (`Draw`)** (khi Thợ Săn bị cắn/treo và bắn chết con Sói cuối cùng, khiến cả 2 phe cùng hết người sống).

2. **Về hiệu năng song song (Parallel Speedup)**:
   - Nhờ chiến lược `parMap rdeepseq` chia nhỏ việc mô phỏng trên các spark độc lập không chia sẻ tài nguyên, thời gian chạy giảm từ **5.2 giây xuống dưới 0.92 giây** cho 5.000 ván.
   - Hệ số tăng tốc đạt **5.01x – 5.68x** trên CPU đa nhân, chứng minh rõ ràng lợi ích thực tế của Parallelism trong Haskell.

3. **Về tính tất định (E19)**:
   - Ở toàn bộ 1.000 và 5.000 ván, so sánh mảng kết quả `outcomesSeq == outcomesPar` đều trả về `True` tuyệt đối. Bản song song không làm sai lệch bất kỳ kết quả hay trạng thái nào so với bản tuần tự.

---

## 5. Hướng dẫn chạy và Kiểm thử

### 5.1. Chạy Executable mô phỏng & Xuất file CSV
```powershell
# Chạy mặc định 1.000 và 5.000 ván cho cả 2 cấu hình, ghi file report/balance.csv
cabal run werewolf-simulate

# Tùy chỉnh số ván, seed và file xuất kết quả:
cabal run werewolf-simulate -- --games 1000,5000,10000 --seed 2026 --output report/balance.csv
```

### 5.2. Chạy Bộ kiểm thử tự động (E19)
```powershell
# Chạy test suite riêng cho X01
cabal test x01-simulate-test --enable-tests --test-show-details=direct

# Chạy toàn bộ test suites dự án để kiểm chứng không ảnh hưởng GameLoop
cabal test all --enable-tests --test-show-details=direct -j1
```

