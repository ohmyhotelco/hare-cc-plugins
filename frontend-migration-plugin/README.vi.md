# Frontend Migration Plugin (Tiếng Việt)

Plugin Claude Code điều phối việc di trú các ứng dụng OhMyHotel Angular 15 (PC, Mobile, Hana)
sang **React Router v7**, theo bản kế hoạch di trú v2 đã chỉnh sửa. Plugin **độc lập hoàn toàn**
(có agent và pipeline riêng) nhưng dùng chung quy ước stack với `frontend-react-plugin` để mã
React sinh ra nhất quán.

> Trạng thái build: tooling đã hoàn chỉnh (skills/agents/templates). Việc chạy thực tế nhắm tới
> monorepo v2 (`apps/` + `packages/`) do chính dự án di trú dựng lên.

## Plugin làm gì

Bao quanh việc sinh mã bốn việc mà một cuộc di trú cần:
1. **Phân tích mã nguồn Angular** — đọc page/service/store cũ và tạo kế hoạch có cấu trúc.
2. **Trích xuất shared package** — đưa logic thuần vào `packages/shared-*` độc lập framework.
3. **Cổng kiểm tra tương đương (parity)** — chứng minh trang mới khớp trang cũ trước khi chuyển lưu lượng.
4. **Điều phối Strangler Fig** — chuyển route theo từng trang + theo dõi tiến độ.

## Stack mục tiêu

React Router v7 (framework mode) · TypeScript (strict) · Tailwind · shadcn/ui · TanStack Query ·
Zustand · axios · react-hook-form + zod · i18next · dayjs · Vitest + MSW · **Playwright** (E2E +
visual regression — khác biệt có chủ đích so với agent-browser của frontend-react-plugin).

## Bắt đầu

```
/frontend-migration-plugin:fm-init
```
Phát hiện các app Angular cũ + bố cục monorepo và ghi `.claude/frontend-migration-plugin.json`
(theo từng app: `legacyDir`/`targetDir`/`appDir`/`domain`/`port`/`ssr`/`webview`/`sso`), rồi khởi
tạo `docs/migration/tracker.json`. Ưu tiên PC; Mobile/Hana được dựng khung và kiểm chứng sau.

## Luồng làm việc

```
/fm-init                       cấu hình + tracker (một lần)

[Phase 0]
/fm-secret-audit               kiểm kê secret cũ (client vs server) — OMH-477
/fm-analyze <target>           Angular → analysis.json
/fm-extract <candidate>        logic thuần → packages/shared-*

[vòng lặp theo trang]
/fm-analyze <page> → /fm-plan → /fm-gen → /fm-verify
                                             │ fail → /fm-fix
                                   /fm-e2e   (cổng Playwright)
                                   /fm-parity (visual/contract/webview/telemetry)
                                   /fm-route --flag-off (PR1) → --flag-on (PR2, có cổng kiểm)

/fm-delta <page>               chỉ di trú lại phần thay đổi khi nguồn cũ thay đổi
/fm-progress                   trạng thái theo app/trang (chỉ đọc)
```

Sau khi sinh mã có hai cổng cứng nối tiếp — `fm-verify` (build/tsc/vitest) rồi `fm-parity` (tương
đương cũ), với `fm-e2e` (Playwright) là cổng chức năng ở giữa. Chỉ chuyển route khi verify + e2e
+ parity đều đạt.

## Skills

`fm-init` · `fm-analyze` · `fm-extract` · `fm-plan` · `fm-gen` · `fm-verify` · `fm-fix` ·
`fm-e2e` · `fm-parity` · `fm-route` · `fm-progress` · `fm-delta` · `fm-clean-code` ·
`fm-test-review` · `fm-secret-audit` (chi tiết: `docs/skill-reference.md`)

## Tài liệu

- `docs/workflow.md` — máy trạng thái theo trang, chuỗi cổng, topology
- `docs/skill-reference.md` — tham chiếu mọi skill/agent
- `CLAUDE.md` — quy ước, quy tắc state-file & lock, nguyên tắc thiết kế, chỉ mục mapping/gate
- `templates/` — catalog ánh xạ, spec/quy ước shared package, WebView bridge, Hana SSO,
  Strangler Fig, quy tắc TDD, schema migration-plan

English: `README.md` · 한국어: `README.ko.md`
