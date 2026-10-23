# T11 — Báo cáo kiểm thử TV1 (T02 & T05)

## 1. Phạm vi kiểm thử

TV1 thực hiện kiểm thử các chức năng thuộc T02 (Domain Types, Validation, Role Privacy) và T05 (Night Action, Wolf Voting), đồng thời bổ sung các trường hợp kiểm thử State-Machine Property và Deterministic Replay trong T11.

Nhánh thực hiện: `feature/T11-tv1-tests`.

## 2. Các trường hợp kiểm thử bổ sung

| Mã | Trường hợp kiểm thử | Kết quả |
|---|---|---|
| T11-TV1-01 | Invariant được bảo toàn sau chuỗi Command trong ván 9 người | PASS |
| T11-TV1-01b | Command bị từ chối không làm thay đổi GameState trong ván 9 người | PASS |
| T11-TV1-02 | Replay chuỗi Night Action ván 9 người cho cùng GameState và DomainEvent | PASS |
| T11-TV1-03 | Sói chọn đồng đội, Tiên Tri tự soi, mục tiêu không tồn tại và actor không tồn tại đều bị từ chối; GameState giữ nguyên | PASS |
| T11-TV1-04 | Xác nhận quyền riêng tư của WolfVoteUpdated, SeerResult và NightActionAccepted | PASS |

## 3. Kết quả thực nghiệm

Lệnh thực hiện:

```powershell
cabal test t11-property-replay-test --enable-tests --test-show-details=direct
```

Kết quả:

- Tổng số bài kiểm thử: **12**
- Thành công: **12**
- Thất bại: **0**
- Bộ kiểm thử: `t11-property-replay-test`
- Công cụ: Hspec, QuickCheck, GHC 9.6.6

Bộ kiểm thử bổ sung 5 trường hợp mới so với 7 trường hợp T11 ban đầu.

## 4. Đánh giá

Các kết quả xác nhận:

- Bất biến GameState được bảo toàn đối với các chuỗi Command đã kiểm thử ở ván 8 và 9 người.
- Cùng trạng thái ban đầu và chuỗi Night Action sinh ra cùng trạng thái cuối và sự kiện.
- Các Night Action không hợp lệ trong kịch bản kiểm thử đều bị từ chối và không thay đổi GameState.
- Các sự kiện riêng tư được phân loại đúng bằng EventVisibility.

Các bài kiểm thử mới tập trung ở tầng Domain. Kiểm thử truyền nhận WebSocket thực tế được thực hiện bởi các bộ kiểm thử tích hợp T05/T07/T08 hiện có.

## 5. Kết luận

TV1 đã hoàn thành việc bổ sung và chạy thành công các bài kiểm thử T11 cho phạm vi T02/T05.

**Trạng thái: PASS — sẵn sàng tích hợp sau khi kiểm tra toàn bộ test và review PR.**