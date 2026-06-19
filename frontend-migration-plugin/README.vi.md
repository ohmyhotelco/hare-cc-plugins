# Frontend Migration Plugin (Tiếng Việt)

Plugin Claude Code điều phối việc di trú các ứng dụng OhMyHotel Angular 15 (PC, Mobile, Hana)
sang **React Router v7**, theo bản kế hoạch di trú v2 đã chỉnh sửa. Plugin **độc lập hoàn toàn**
(agent và pipeline riêng) nhưng dùng chung quy ước stack với `frontend-react-plugin` để mã React
sinh ra nhất quán.

> Trạng thái: tooling đã hoàn chỉnh (v0.5.0). Plugin **không** chứa các app sản phẩm — nó vận hành
> trên một monorepo v2 (`apps/` + `packages/`) do dự án di trú dựng lên.

## Plugin làm gì

Bao quanh việc sinh mã bốn việc mà một cuộc di trú cần:
1. **Phân tích mã nguồn Angular** — đọc page/service/store cũ và tạo kế hoạch có cấu trúc.
2. **Trích xuất shared package** — đưa logic thuần vào `packages/shared-*` độc lập framework.
3. **Cổng parity với bản cũ** — chứng minh trang mới khớp trang cũ trước khi chuyển lưu lượng.
4. **Điều phối Strangler Fig** — chuyển route theo từng trang + theo dõi tiến độ.

## Khái niệm (đọc trước)

Nếu mới làm quen, các thuật ngữ sau lặp lại xuyên suốt:

- **Strangler Fig** — di trú theo từng trang. nginx định tuyến mỗi path tới app Angular cũ hoặc
  app React mới; bạn "bóp nghẹt" app cũ từng route một, không viết lại kiểu big-bang.
- **Vòng lặp theo trang** — mỗi trang đi qua cùng một chuỗi: `analyze → plan → gen → verify →
  e2e → parity → route`. Mỗi lần một trang.
- **Ba cổng parity** — sau khi sinh, trang phải vượt qua theo thứ tự: `fm-verify` (kỹ thuật:
  build/types/unit test + ESLint; Prettier là advisory), `fm-e2e` (có hành xử như bản cũ?), `fm-parity` (có giống về giao
  diện/contract/tracking?). Route chỉ được chuyển khi cả ba đạt.
- **Dual-run với bản cũ** — `fm-e2e` chạy cùng kịch bản trên cả app cũ và app mới rồi so sánh.
  Hành vi của bản cũ là chuẩn.
- **Shared packages** — logic thuần (validators, date, DTO, i18n) được trích xuất một lần vào
  `packages/shared-*` và dùng chung cho cả ba app; không phụ thuộc React khi có thể.
- **Feature flag 2-PR** — mỗi trang lên bằng hai PR: PR mã với flag **OFF** (người dùng vẫn dùng
  bản cũ), rồi PR một dòng bật flag **ON** sau khi qua cổng. Rollback = tắt flag.
- **Máy trạng thái + tracker** — trạng thái mỗi trang nằm trong `docs/migration/tracker.json`
  (`analyzed → planned → generated → verified → e2e-passed → parity-passed → flipped → done`).
- **Kiểm toán độc lập bằng Codex** — khi bật (mặc định), mỗi giai đoạn nhận thêm một đánh giá độc
  lập từ **Codex** (advisory), ghi vào `codex-audit.json`. Không đổi trạng thái trang; soft gate duy
  nhất là `fm-route --flag-on` yêu cầu xác nhận (ack) các phát hiện high-severity chưa xử lý. Cần
  Codex CLI; tự bỏ qua nếu không có.

## Điều kiện tiên quyết

Plugin này là **tooling**; giả định dự án di trú đã chuẩn bị workspace:

- Một **monorepo v2** gồm: `apps/legacy-*` (các app Angular đang di trú), `apps/web-*` (các app
  React Router v7 mới), và `packages/` (shared packages).
- **Node + pnpm** (pnpm workspaces), và **trình duyệt Playwright** đã cài (`npx playwright
  install`) cho cổng E2E và visual.
- **Mã nguồn Angular cũ** có thể truy cập để phân tích.
- Plugin đã **cấu hình** — chạy `fm-init` một lần (ghi `.claude/frontend-migration-plugin.json` +
  `docs/migration/tracker.json`).

> Nếu monorepo v2 chưa tồn tại, việc dựng nó là công việc hạ tầng Phase 0 của dự án di trú
> (OMH-455 / OMH-502), không phải do plugin này tạo.

## Stack mục tiêu

React Router v7 (framework mode) · TypeScript (strict) · Tailwind · shadcn/ui · TanStack Query ·
Zustand · axios · react-hook-form + zod · i18next · dayjs · Vitest + MSW · **Playwright** (E2E +
visual regression — khác biệt có chủ đích so với agent-browser của frontend-react-plugin).

## Skill bên ngoài (dùng chung với frontend-react-plugin)

Kiến thức React/kiểm thử tổng quát không được viết lại ở đây — `fm-init` cài đặt cùng bộ skill
upstream mà `frontend-react-plugin` dùng, qua `npx skills add … --copy` (vendor vào
`.claude/skills/`), để mã React sinh ra nhất quán trên toàn tổ chức. Kiến thức riêng của di trú
(ánh xạ Angular→React, Strangler Fig, WebView/SSO) nằm trong `templates/`.

| Skill | Nguồn | Mục đích |
| --- | --- | --- |
| `react-router-framework-mode` | `remix-run/agent-skills` | Định tuyến RR v7 **framework mode** (loader/action, SSR/SSG/SPA theo route) |
| `vitest` | `antfu/skills` | Pattern kiểm thử unit/component |
| `vercel-react-best-practices` | `vercel-labs/agent-skills` | Hiệu năng React — áp dụng **SSR-aware** (framework mode, không phải Vite SPA) |
| `vercel-composition-patterns` | `vercel-labs/agent-skills` | Pattern composition component |

Các agent nạp từng skill theo từng pha, có kiểm tra tồn tại — nếu cài đặt bị từ chối/vắng mặt
(hoặc `externalSkills: false`) thì bỏ qua, không gây lỗi. `web-design-guidelines` và `agent-browser`
(mà frontend-react-plugin dùng) cố ý không được áp dụng: độ trung thực UI do `fm-parity` đánh giá so
với bản cũ, và E2E chạy trên Playwright.

## Bắt đầu nhanh — di trú trang đầu tiên

Sau khi đã đủ điều kiện tiên quyết:

```
# 0. thiết lập một lần
/frontend-migration-plugin:fm-init
#    phát hiện bố cục legacy/monorepo, ghi config + tracker. Ưu tiên PC.

# 1. (Phase 0) chuẩn bị bảo mật + trích xuất logic dùng chung cho trang
/frontend-migration-plugin:fm-secret-audit                 # kiểm kê secret cũ (posture; OMH-477)
/frontend-migration-plugin:fm-analyze hotel-booking-info   # → analysis.json (phụ thuộc, cổng, ứng viên shared)
/frontend-migration-plugin:fm-extract --from hotel-booking-info   # logic thuần → packages/shared-*

# 2. vòng lặp theo trang
/frontend-migration-plugin:fm-plan hotel-booking-info      # → migration-plan.json (cây, rendering, cổng, kịch bản e2e)
/frontend-migration-plugin:fm-gen hotel-booking-info       # trang RR v7 qua TDD → trạng thái: generated
/frontend-migration-plugin:fm-verify hotel-booking-info    # build/tsc/vitest → verified   (cổng 1)
/frontend-migration-plugin:fm-e2e hotel-booking-info       # Playwright + dual-run → e2e-passed   (cổng 2)
/frontend-migration-plugin:fm-parity hotel-booking-info    # visual/contract/webview/telemetry → parity-passed   (cổng 3)

# 3. chuyển route (hai PR)
/frontend-migration-plugin:fm-route hotel-booking-info --flag-off   # PR mã (flag OFF)
/frontend-migration-plugin:fm-route hotel-booking-info --flag-on    # PR một dòng bật flag (chỉ khi mọi cổng đạt)

# bất cứ lúc nào: trạng thái mọi trang
/frontend-migration-plugin:fm-progress
```

Mỗi bước ghi sản phẩm vào `docs/migration/{app}/{page}/` và đẩy trạng thái trong tracker. Nếu một
cổng fail, chạy `fm-fix <page>` (tự nhận diện cổng) rồi chạy lại cổng đó.

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

## Các cổng

Chuyển route (`fm-route --flag-on`) bị từ chối trừ khi cả ba cổng đạt.

| Cổng | Skill | Kiểm tra | Khi fail |
| --- | --- | --- | --- |
| 1 · kỹ thuật | `fm-verify` | build, `tsc` (composite-aware), Vitest, ESLint (hard); Prettier `--check` (advisory) | `fm-fix` (verify-fix) |
| 2 · chức năng | `fm-e2e` | luồng người dùng Playwright; dual-run với bản cũ; cổng thanh toán staging | `fm-fix` (e2e-fix) |
| 3 · parity | `fm-parity` | visual regression so bản cũ, đóng băng API contract, round-trip WebView bridge, telemetry dual-fire | `fm-fix` (parity-fix) |

## Skills

`fm-init` · `fm-analyze` · `fm-extract` · `fm-plan` · `fm-gen` · `fm-verify` · `fm-fix` ·
`fm-e2e` · `fm-parity` · `fm-route` · `fm-progress` · `fm-delta` · `fm-clean-code` ·
`fm-test-review` · `fm-secret-audit` · `fm-audit-codex`

Đầu vào/đầu ra, agent tương ứng và trạng thái tracker của từng skill: xem `docs/skill-reference.md`.

## Xử lý sự cố / FAQ

- **Một cổng fail.** Chạy `/frontend-migration-plugin:fm-fix <page>` — tự nhận diện mode
  (verify/e2e/parity) từ report fail mới nhất, sửa tối thiểu rồi chạy lại cổng. Sau đó chạy lại cổng để xác nhận.
- **Trang cũ thay đổi sau khi đã di trú.** Chạy `/frontend-migration-plugin:fm-delta <page>` —
  chỉ di trú lại phần thay đổi và giữ các sửa đổi đã tích lũy (delta lớn sẽ fallback `fm-gen`).
  Hook PostToolUse sẽ cảnh báo.
- **`fm-gen` bị gián đoạn.** Chạy lại — nó resume từ phase dở dang qua `generation-state.json`.
- **"Another operation is in progress."** `.lock` của trang đang giữ; quá 30 phút thì tự xóa.
- **`fm-gen` báo thiếu shared package.** Kế hoạch đã đánh dấu phụ thuộc chưa trích xuất — chạy
  `/frontend-migration-plugin:fm-extract` trước.
- **Mọi thứ đang ở đâu?** `/frontend-migration-plugin:fm-progress` (chỉ đọc) hiển thị trạng thái
  theo app/trang, kết quả cổng, và lệnh kế tiếp gợi ý.
- **Secret / thanh toán.** Việc đọc `merchantKey` (PG) và `client_secret` (OAuth) bị chặn trong
  `shared-domain` và chuyển sang server (theo dõi ở OMH-477); `fm-secret-audit` kiểm kê chúng.

## Tài liệu

- `docs/workflow.md` — máy trạng thái theo trang, chuỗi cổng, topology
- `docs/skill-reference.md` — mọi skill/agent với đầu vào/đầu ra và hiệu ứng trạng thái
- `docs/build-context.md` — quá trình build, quyết định thiết kế, ngữ cảnh giữa các phiên
- `CLAUDE.md` — quy ước, quy tắc state-file & lock, nguyên tắc thiết kế, chỉ mục mapping/gate
- `templates/` — catalog ánh xạ, spec/quy ước shared package, WebView bridge, Hana SSO,
  Strangler Fig, quy tắc TDD, schema migration-plan, cấu hình cổng lint & format ESLint/Prettier (`eslint-config.md`, `prettier-config.md`)

English: `README.md` · 한국어: `README.ko.md`
