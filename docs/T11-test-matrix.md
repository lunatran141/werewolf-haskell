# T11 - Ma trận kiểm thử tích hợp

Tài liệu này đối chiếu yêu cầu T11 với test tự động hiện có. Mục tiêu của T11
là gom test T03-T10 thành một gate, bổ sung property theo chuỗi `Command` và
chứng minh replay xác định.

## Ma trận yêu cầu

| Yêu cầu | Test chính |
| --- | --- |
| Phòng 8/9 người, role preset và invariant | `DomainT02Spec.hs`, `T04PhaseSpec.hs`, `T05NightSpec.hs` |
| Ngoại hình khi tạo/tham gia phòng | `T05WebSocketSpec.hs`, `T06UiSpec.cjs` |
| Quyền role, Night Action và target hợp lệ | `T05NightSpec.hs`, `T05WebSocketSpec.hs` |
| Phiếu Sói A-A-B, A-B-C và A-B | `T11PropertyReplaySpec.hs` |
| Vote, hòa phiếu, loại người và Hunter chain | `DomainT06Spec.hs`, `T06WebSocketSpec.hs` |
| Chat công khai/riêng, giới hạn 300 ký tự | `T07WinSpec.hs`, `T07UiSpec.cjs` |
| Lịch sử Day, không nhân đôi tin và system message | `T07UiSpec.cjs`, `T05WebSocketSpec.hs` |
| Người chết không chat/hành động, role chỉ reveal ở GameOver | `T07WinSpec.hs`, `T07UiSpec.cjs` |
| Reconnect giữ PlayerId, snapshot, timer và private state | `T05WebSocketSpec.hs` |
| Invariant sau mọi bước trong chuỗi Command | `T11PropertyReplaySpec.hs` |
| Replay cùng input cho cùng state/event output | `T11PropertyReplaySpec.hs` |

## Fixture tích hợp

- Ván 8 người: 2 Sói, Tiên Tri, Bảo Vệ, Phù Thủy, Thợ Săn và 2 Dân.
- Ván 9 người: 3 Sói, Tiên Tri, Bảo Vệ, Phù Thủy, Thợ Săn và 2 Dân.
- Luồng cố định: Day 1 -> Voting -> Night 2.
- Actor gồm người còn sống, người đã chết và ID không tồn tại.
- Command hợp lệ và không hợp lệ cùng được replay; command bị từ chối phải giữ
  nguyên state.

## Gate đề nghị trước khi merge

```powershell
cabal test all
node --test test/T06UiSpec.cjs test/T07UiSpec.cjs
git diff --check
```

Mỗi thành viên cần kiểm tra test phần mình sở hữu và có ít nhất một người khác
review. Người tổng hợp T11 chạy lại toàn bộ gate trên commit cuối cùng.


## Kết quả kiểm thử phần TV3 phụ trách

| Phần | Kịch bản | File test | Kết quả | Review chéo |
| --- | --- | --- | --- | --- |
| T03 | Join/Leave/Ready; chuỗi lệnh giữ Lobby hợp lệ, tối đa 9 người và Host đúng | `test/T03LobbySpec.hs` | PASS: 18/18; QuickCheck 100 lần | Chờ thành viên khác review |
| T04 | StartGame 8/9 người; invariant sau Join/Ready và khi chuyển pha | `test/T04PhaseSpec.hs` | PASS: 24/24; mỗi property 100 lần | Chờ thành viên khác review |
| T10 | Chat, quyền vai, reconnect, bong bóng chat tự ẩn và giữ lịch sử | `test/T07UiSpec.cjs` | PASS: 29/29 | Chờ thành viên khác review |

Đã chạy `t11-property-replay-test`: PASS 7/7. Đây là phần kiểm thử chung của T11, cần TV5 tổng hợp cùng kết quả của các thành viên khác.
