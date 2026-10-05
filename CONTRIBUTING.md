# Quy trình làm việc

`develop` là nhánh tích hợp hằng ngày; `main` chỉ chứa phiên bản ổn định để demo hoặc phát hành. Không commit trực tiếp vào hai nhánh này.

1. Tạo Issue theo mã ở Sheet 02, ví dụ `S01` hoặc `T07`.
2. Đồng bộ `develop`, rồi tạo branch từ `develop`: `feature/S01-github-workflow`, `feature/T07-chat-win`, hoặc `fix/<issue>-mo-ta`.
3. Commit ngắn gọn, có mã task: `S01: add pull request template`.
4. Push branch và mở Pull Request; điền đủ template và gắn Issue.
5. Mở Pull Request vào `develop`. Ít nhất một thành viên khác review; CI phải xanh trước khi merge.
6. Merge bằng Squash and merge, sau đó xóa branch.

Khi hoàn thành toàn bộ đồ án, tạo Pull Request phát hành từ `develop` vào `main`. Không merge từng feature trực tiếp vào `main`.

Không commit `.env`, token, mật khẩu, khóa riêng hoặc vai bí mật trong log.
