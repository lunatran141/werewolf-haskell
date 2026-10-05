# Quy trình làm việc

`main` luôn phải build được. Không commit trực tiếp vào `main`.

1. Tạo Issue theo mã ở Sheet 02, ví dụ `S01` hoặc `T07`.
2. Tạo branch từ `main`: `task/S01-github-workflow`, `feature/T07-chat-win`, hoặc `fix/<issue>-mo-ta`.
3. Commit ngắn gọn, có mã task: `S01: add pull request template`.
4. Push branch và mở Pull Request; điền đủ template và gắn Issue.
5. Ít nhất một thành viên khác review; CI phải xanh trước khi merge.
6. Merge bằng Squash and merge, sau đó xóa branch.

Không commit `.env`, token, mật khẩu, khóa riêng hoặc vai bí mật trong log.

