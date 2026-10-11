# T04 – Hoàn thành Phase Engine

**Dự án:** Werewolf Haskell
**Task:** T04 – StartGame và chuyển phase
**Thành viên phụ trách:** TV3

## 1. Mục tiêu

Xây dựng logic thuần để bắt đầu ván chơi và chuyển phase theo thứ tự Lobby → Night → Day → Voting. Cùng một state và cùng một input phải cho cùng kết quả; Domain không thực hiện IO.

## 2. Chức năng đã hoàn thành

- `startGame` kiểm tra Host, số người chơi, trạng thái Ready và bộ vai trước khi bắt đầu.
- Chia vai vào state và tạo các Domain Event khi bắt đầu ván.
- Chuyển phase Night → Day → Voting → Night; xử lý trường hợp kết thúc ván vào GameOver.
- Từ chối lệnh chuyển phase không hợp lệ hoặc bỏ qua bước resolve.
- Dùng `gameNightResolved` và `gameVotingResolved` để ngăn chuyển phase khi Night hoặc Voting chưa được xử lý.
- Logic chuyển state nằm trong các hàm thuần, trả kết quả qua `Either`.

## 3. File liên quan

- `src/Domain/Engine.hs`
- `src/Domain/Types.hs`
- `src/Domain/Validation.hs`
- `test/T04PhaseSpec.hs`
- `werewolf-server.cabal`

## 4. Kiểm thử

Suite `t04-phase-test` đã đạt **23 examples, 0 failures**. Các test bao gồm:

- StartGame hợp lệ và các trường hợp bị từ chối.
- Cùng input cho cùng kết quả.
- Kiểm tra sự kiện chia vai riêng cho từng người.
- Chuyển phase hợp lệ và từ chối chuyển phase quá sớm.
- Hai kiểm thử QuickCheck về tính hợp lệ của Phase Engine.

## 5. Ranh giới tích hợp

Các test đặt dấu `gameNightResolved` hoặc `gameVotingResolved` để mô phỏng kết quả đã resolve. Việc xử lý hành động Night, phiếu Voting và nối toàn bộ luồng chơi qua Server/Browser thuộc các task tích hợp tiếp theo.

## 6. Kết luận

Phần **Phase Engine thuần của T04** trên máy đã hoàn thành và test đạt.