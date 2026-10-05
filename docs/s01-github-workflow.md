# S01 GitHub workflow cho cả nhóm

Tài liệu này là quy trình bắt buộc để năm thành viên cùng làm việc mà không ghi đè code của nhau. Nguồn trạng thái chính vẫn là Sheet 02; GitHub lưu Issue, code, review và lịch sử merge.

## Quy trình cho mỗi task

1. Chọn task trong Sheet 02 và đọc dependency, đầu ra cùng điều kiện hoàn thành.
2. Tạo GitHub Issue với đúng mã task, owner, test và Definition of Done.
3. Đồng bộ `main` trước khi bắt đầu:

   ```bash
   git switch main
   git pull origin main
   ```

4. Tạo branch theo mẫu `feature/<Task-ID>-<ten-ngan>`:

   ```bash
   git switch -c feature/T07-chat-win-result
   ```

5. Commit nhỏ, ghi rõ mã task:

   ```bash
   git add <file>
   git commit -m "T07: add chat permission rule"
   ```

6. Push branch, không push trực tiếp vào `main`:

   ```bash
   git push -u origin feature/T07-chat-win-result
   ```

7. Mở Pull Request vào `main`, điền đủ template và dùng `Closes #<issue>`.
8. Một thành viên khác review code và test. Tác giả không tự approve PR của mình.
9. Chỉ merge khi CI xanh và đã có approval; ưu tiên **Squash and merge**.
10. Sau khi merge, cập nhật trạng thái, phần trăm hoàn thành, Issue, PR, reviewer và blocker trong Sheet 02.

## Quy ước branch

- `feature/S01-github-workflow`: task hoặc tính năng mới.
- `fix/T09-reconnect-duplicate`: sửa lỗi.
- `docs/T14-report`: tài liệu và báo cáo.

Không dùng mã task trong các tab `LEGACY`.

## Quy ước commit

Commit viết ở dạng mệnh lệnh, ngắn gọn và bắt đầu bằng mã task:

```text
S01: document team GitHub workflow
T07: add win condition tests
T09: reject duplicate request id
```

Không commit `.env`, token, mật khẩu, khóa riêng, file build hoặc log làm lộ vai bí mật.

## Checklist Pull Request

- [ ] Branch được tạo từ `main` mới nhất.
- [ ] PR liên kết Issue bằng `Closes #...`.
- [ ] Scope chỉ thuộc một task hoặc một mục đích rõ ràng.
- [ ] Build và test local đã chạy.
- [ ] `docker compose config` hợp lệ khi có thay đổi Docker.
- [ ] CI xanh.
- [ ] Có ít nhất một reviewer khác tác giả.
- [ ] Sau merge đã cập nhật Sheet 02.

## Gate hoàn thành S01

- [x] Repository chung đã được tạo.
- [x] Có `CONTRIBUTING.md`, Issue template và Pull Request template.
- [x] Có workflow CI ban đầu.
- [ ] Bật branch protection hoặc ruleset cho `main`.
- [ ] Cả năm thành viên clone repository thành công.
- [ ] Cả năm thành viên tạo branch, commit, push và mở PR thử.
- [ ] Mỗi PR thử có ít nhất một thành viên khác review.

