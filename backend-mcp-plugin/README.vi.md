# Backend MCP Plugin

> **Ohmyhotel & Co** — Plugin Claude Code để xây dựng MCP server (Model Context Protocol) trên Spring AI với TDD nghiêm ngặt

[English](./README.md) | [Tiếng Việt](./README.vi.md) | [한국어](./README.ko.md)

## Plugin này làm gì

Pipeline phát triển cho các service Spring Boot mà "sản phẩm" là tập **MCP tool** được LLM client gọi:

- **Description của tool chính là contract** — được gửi cho client ở mọi lần tools/list, nên viết
  theo template gọn, được khoá bằng contract snapshot, và chỉ thay đổi có chủ đích kèm changelog
- **Bên gọi là một model** — text từ upstream là input không tin cậy (sanitize, mask PII), kết quả
  bị giới hạn số dòng kèm cảnh báo máy đọc được, lỗi có mã rõ ràng
- **Server là bên được uỷ quyền** — OAuth2 inbound + RBAC theo từng tool, credential riêng khi gọi
  upstream (không token passthrough), read-only được ArchUnit enforce, mọi lần gọi đều được audit
- **Upstream là hệ thống của người khác** — timeout, retry chỉ cho lỗi transport, rate limit,
  circuit breaker, cache có áp lại RBAC theo từng caller

## Cài đặt

```
/plugin marketplace add ohmyhotelco/hare-cc-plugins
/plugin install backend-mcp-plugin@ohmyhotelco --scope project
```

Không có bước khởi tạo. Mỗi skill chạy `scripts/detect-project.sh` khi bắt đầu để tự nhận diện build
(chỉ Gradle), phiên bản Java/Boot/Spring AI, transport MCP (webmvc/webflux/stdio), package, cách
đăng ký tool, security, contract snapshot/changelog, checkstyle/JaCoCo — đọc lại mỗi lần, không
cache, nên không bao giờ lệch với code. Dừng lại với thông báo rõ ràng nếu project không có Spring AI
MCP server starter.

File chính sách tuỳ chọn `.claude/backend-mcp-plugin.json`, chỉ cần khi muốn đổi mặc định
(`readOnly`, `workDocDir`, `workingLanguage`) hoặc ghi đè một giá trị nhận diện sai (vd. `toolsPackage`).

## Pipeline

```
mcp-plan → mcp-code → mcp-verify → mcp-review ↔ mcp-fix → mcp-commit
```

| Skill | Mục đích |
|-------|----------|
| `mcp-plan` | Jira task / mô tả task / tài liệu API upstream / spec → `plan.json` cho các tool |
| `mcp-code` | Đặc tả tool + triển khai TDD, kết thúc bằng cập nhật contract snapshot có kiểm soát |
| `mcp-verify` | Gate: compile, test, contract (snapshot + changelog), build, checkstyle/coverage tuỳ chọn; `--fix` chạy vòng auto-fix build trước |
| `mcp-review` | Review 7 chiều (tool contract, upstream, security, clean code, logging & audit, test, kiến trúc) + spec; `--dimension <key>` để audit riêng một chiều |
| `mcp-fix` | Sửa theo report review — TDD cho hành vi, sửa trực tiếp cho lỗi cơ học, snapshot + changelog cho thay đổi contract |
| `mcp-commit` | Commit từ thay đổi đã stage: kiểm tra tree, quét secret, kiểm tra cặp snapshot/changelog |
| `mcp-debug` | Debug 4 pha, gồm cả lỗi transport và upstream |
| `mcp-progress` | Dashboard trạng thái pipeline |
| `mcp-recall` | Tra cứu quy tắc + quét vi phạm |

Chi tiết đầy đủ (agent, cấu hình, state machine): xem `README.md` và `CLAUDE.md`.
