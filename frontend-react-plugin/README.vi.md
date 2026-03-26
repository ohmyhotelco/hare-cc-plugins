<!-- Synced with en version: 2026-03-19T00:00:00Z -->

[English version](README.md)

# Frontend React Plugin

> **Ohmyhotel & Co** — Plugin Claude Code để phát triển frontend React với TDD

## Chức năng chính

Plugin Claude Code này tạo mã React sẵn sàng cho production từ đặc tả chức năng sử dụng phương pháp Test-Driven Development nghiêm ngặt. Plugin cung cấp một pipeline hoàn chỉnh từ lập kế hoạch triển khai đến sinh mã, xác minh, đánh giá và sửa lỗi — tất cả đều tuân thủ kỷ luật TDD.

Các khả năng chính:
- **Sinh mã TDD** — Pipeline 6 giai đoạn (foundation → API → store → component → page → integration) với chu trình Red-Green-Refactor nghiêm ngặt cho mỗi giai đoạn
- **Lập kế hoạch dựa trên đặc tả** — Phân tích đặc tả chức năng (từ planning-plugin) và tạo kế hoạch triển khai có cấu trúc
- **Chế độ độc lập** — Tạo kế hoạch mà không cần planning-plugin bằng cách thu thập yêu cầu tương tác
- **Đánh giá tự động** — Đánh giá mã 2 giai đoạn (tuân thủ đặc tả + chất lượng) với 12 chiều chấm điểm
- **Sửa lỗi TDD** — Sửa các vấn đề đánh giá với kỷ luật test-first cho các thay đổi hành vi
- **Tính nhất quán trạng thái** — Cơ chế khóa, timestamp theo giai đoạn và phát hiện lỗi thời xuyên suốt pipeline

## Tổng quan kiến trúc

```
/frontend-react-plugin:fe-init → .claude/frontend-react-plugin.json
        │
        ▼
/frontend-react-plugin:fe-plan "feature" [--standalone]
        │
        ├── spec mode: reads planning-plugin output
        │   └── implementation-planner agent → plan.json
        │
        ├── standalone mode: interactive requirements gathering
        │   └── generates minimal spec stub → implementation-planner agent → plan.json
        │
        ├── incremental mode: detects spec changes after implementation
        │   └── implementation-planner agent → delta-plan.json (affected files only)
        │
        ▼
/frontend-react-plugin:fe-gen "feature"
        │
        ├── Phase 1: Foundation     — types + mocks (foundation-generator)
        ├── Phase 2: API TDD        — RED: tests → GREEN: services (tdd-cycle-runner)
        ├── Phase 3: Store TDD      — RED: tests → GREEN: stores (tdd-cycle-runner)
        ├── Phase 4: Component TDD  — RED: tests → GREEN: components (tdd-cycle-runner)
        ├── Phase 5: Page TDD       — RED: tests → GREEN: pages (tdd-cycle-runner)
        └── Phase 6: Integration    — routes + i18n + MSW setup (integration-generator)
        │
        ▼
/frontend-react-plugin:fe-verify "feature" (optional)
        │
        ▼
Loop 1 — Code Quality:
/frontend-react-plugin:fe-review "feature"
        │
        ├── Stage 1: spec-reviewer → spec compliance
        └── Stage 2: quality-reviewer → code quality
        │
        ▼ (if issues found)
/frontend-react-plugin:fe-fix "feature"
        │
        └── review-fixer agent → TDD fixes + direct fixes
        │
        ▼
/frontend-react-plugin:fe-review "feature" (re-review until pass)
        │
        ▼ (quality pass)
Loop 2 — E2E:
/frontend-react-plugin:fe-e2e "feature"
        │
        └── e2e-test-runner agent → agent-browser drives browser scenarios
        │
        ▼ (if failures)
/frontend-react-plugin:fe-fix "feature" (auto-detects E2E mode)
        │
        ▼
/frontend-react-plugin:fe-e2e "feature" (re-run until pass)
```

## Công nghệ sử dụng

| Category | Technology |
|----------|-----------|
| Runtime | Node.js 22.x LTS (>= 22.12) |
| Package Manager | pnpm |
| Framework | React 19 + TypeScript (strict) |
| Build | Vite |
| Routing | React Router v7 (declarative or data mode) |
| UI | Tailwind CSS + shadcn/ui + Lucide |
| State | Zustand |
| HTTP | Axios (JWT, 401/403 interceptors) |
| Mock | MSW v2 (dev & test — network-level intercept) |
| i18n | i18next + react-i18next (ko/en/ja/vi) |
| Testing | Vitest + @testing-library/react + agent-browser (E2E) |

## Cài đặt

Plugin này được phân phối qua kho GitHub.

```
# 1. Register the repo as a marketplace source
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. Install the plugin (project scope — saved to .claude/settings.json, shared with the team)
/plugin install frontend-react-plugin@ohmyhotelco --scope project
```

Xác minh cài đặt:
```
/plugin
```

## Cập nhật và Quản lý

**Cập nhật marketplace** để lấy phiên bản plugin mới nhất:
```
/plugin marketplace update ohmyhotelco
```

**Vô hiệu hóa / Kích hoạt** plugin mà không cần gỡ cài đặt:
```
/plugin disable frontend-react-plugin@ohmyhotelco
/plugin enable frontend-react-plugin@ohmyhotelco
```

**Gỡ cài đặt**:
```
/plugin uninstall frontend-react-plugin@ohmyhotelco --scope project
```

**Giao diện quản lý plugin**: Chạy `/plugin` để mở giao diện tab (Discover, Installed, Marketplaces, Errors).

## Bắt đầu nhanh

### Phương án A — Với planning-plugin (khuyến nghị)

Từ số không đến mã nguồn được sinh chỉ trong 5 bước:

```
1. /frontend-react-plugin:fe-init                     # configure plugin
2. /planning-plugin:init                               # configure planning
3. /planning-plugin:spec "feature description"         # generate spec
4. /frontend-react-plugin:fe-plan {feature}            # create implementation plan
5. /frontend-react-plugin:fe-gen {feature}             # generate code (TDD)
```

### Phương án B — Độc lập (không có planning-plugin)

Sinh mã mà không cần đặc tả chức năng:

```
1. /frontend-react-plugin:fe-init                      # configure plugin
2. /frontend-react-plugin:fe-plan {feature} --standalone   # interactive requirements → plan
3. /frontend-react-plugin:fe-gen {feature}             # generate code (TDD)
```

Chế độ độc lập thu thập yêu cầu tương tác (mô tả, thực thể, màn hình) và tạo spec stub tối thiểu + plan.json. Hạn chế: không có mã lỗi, quy tắc xác thực, tham chiếu kịch bản kiểm thử (TS-nnn), hoặc UI DSL.

## Tham chiếu Skill

### `/frontend-react-plugin:fe-init`

**Cú pháp**: `/frontend-react-plugin:fe-init`

**Khi nào sử dụng**: Thiết lập lần đầu trong dự án, hoặc cấu hình lại cài đặt.

**Quy trình thực hiện**:
1. Hỏi chế độ React Router (declarative hoặc data)
2. Hỏi về phát triển mock-first (MSW v2, mặc định: bật)
3. Hỏi thư mục nguồn cơ sở (mặc định: `app/src`)
4. Hỏi về sử dụng template ESLint (tự động tạo `eslint.config.js` nếu chưa có, mặc định: bật)
5. Ghi `.claude/frontend-react-plugin.json`
6. Cài đặt 6 skill bên ngoài (React Router, Vitest, React Best Practices, Composition Patterns, Web Design Guidelines, Agent Browser)
7. Hiển thị các tùy chọn bước tiếp theo (có hoặc không có planning-plugin)

---

### `/frontend-react-plugin:fe-plan`

**Cú pháp**: `/frontend-react-plugin:fe-plan <feature-name> [--standalone]`

**Khi nào sử dụng**: Sau khi tạo đặc tả chức năng, hoặc chế độ độc lập khi chưa có đặc tả.

**Quy trình thực hiện**:
1. **Chế độ đặc tả** (mặc định): đọc đặc tả planning-plugin và UI DSL, phát hiện layout chia sẻ, phân tích các pattern dự án hiện có
2. **Chế độ độc lập** (`--standalone`): thu thập yêu cầu tương tác (mô tả, thực thể, màn hình, ngôn ngữ), tạo spec stub tối thiểu
3. **Chế độ gia tăng** (tự động phát hiện): khi plan.json và mã đã sinh tồn tại, phát hiện thay đổi đặc tả và tạo delta plan thay vì sinh lại toàn bộ
4. **Tự động phát hiện**: nếu không tìm thấy đặc tả và không chỉ định `--standalone`, đưa ra lựa chọn giữa chế độ độc lập và tạo đặc tả trước
5. Khởi chạy tác tử Implementation Planner để tạo `plan.json` (hoặc `delta-plan.json` trong chế độ gia tăng)
6. Hiển thị tóm tắt kế hoạch (tệp, giai đoạn TDD, phụ thuộc shadcn/ui)
7. Cập nhật tệp tiến độ với trạng thái `planned` (hoặc giữ trạng thái hiện có trong chế độ gia tăng)

Tác tử planner phân tích:
- Các pattern dự án hiện có (cấu trúc thư mục, path alias, tệp route, cấu hình i18n, store, dịch vụ API, thiết lập MSW, hạ tầng kiểm thử)
- Thực thể đặc tả → types, dịch vụ API, store
- Màn hình đặc tả → component, page, route, khóa i18n
- Kịch bản kiểm thử đặc tả → kế hoạch tệp kiểm thử với truy vết TS-nnn
- Thiếu hụt shadcn/ui → lệnh cài đặt

---

### `/frontend-react-plugin:fe-gen`

**Cú pháp**: `/frontend-react-plugin:fe-gen <feature-name>`

**Khi nào sử dụng**: Sau khi `fe-plan` tạo plan.json.

**Quy trình thực hiện**:
1. Xác thực kế hoạch và kiểm tra trạng thái sinh mã hiện có (hỗ trợ tiếp tục)
2. Lấy khóa để ngăn các thao tác đồng thời trên cùng tính năng
3. Thực thi 6 giai đoạn TDD tuần tự, mỗi giai đoạn trong một phiên tác tử riêng:

| Phase | Agent | Nội dung thực hiện |
|-------|-------|-------------|
| Foundation | foundation-generator | Types, mock factories/fixtures/handlers, shared layouts |
| API TDD | tdd-cycle-runner | RED: API tests → GREEN: API services |
| Store TDD | tdd-cycle-runner | RED: store tests → GREEN: Zustand stores |
| Component TDD | tdd-cycle-runner | RED: component tests → GREEN: components |
| Page TDD | tdd-cycle-runner | RED: page tests → GREEN: pages (4-state) |
| Integration | integration-generator | Routes, i18n, MSW global setup, barrel exports |

4. Mỗi giai đoạn TDD ghi lại timestamp `completedAt` để hỗ trợ tiếp tục chính xác
5. Hiển thị kết quả toàn diện với tỷ lệ kiểm thử đạt và danh sách tệp
6. Giải phóng khóa và cập nhật tiến độ

**Chế độ delta**: Khi `delta-plan.json` tồn tại (được tạo bởi `fe-plan` trong chế độ gia tăng), `fe-gen` chỉ thực thi các giai đoạn và tệp bị ảnh hưởng. Các giai đoạn không thay đổi được bỏ qua hoàn toàn. Các thay đổi sử dụng tác tử delta-modifier; tệp mới sử dụng tdd-cycle-runner với phạm vi giới hạn.

**Hỗ trợ tiếp tục**: Nếu quá trình sinh mã bị gián đoạn, chạy lại `fe-gen` sẽ phát hiện trạng thái hiện có và đề xuất tiếp tục từ giai đoạn chưa hoàn thành cuối cùng. Độ mới của kế hoạch được kiểm tra ở cấp giai đoạn — nếu `plan.json` được sửa đổi sau khi một giai đoạn cụ thể hoàn thành, bạn có thể chọn chạy lại từ giai đoạn đó trở đi.

**Khi thất bại**: Mỗi giai đoạn cung cấp tùy chọn thử lại, bỏ qua hoặc dừng. Các giai đoạn bị bỏ qua hoặc thất bại dẫn đến trạng thái `gen-failed` (ngăn mã không hoàn chỉnh đi vào pipeline đánh giá).

---

### `/frontend-react-plugin:fe-verify`

**Cú pháp**: `/frontend-react-plugin:fe-verify <feature-name>`

**Khi nào sử dụng**: Sau khi sinh mã để xác minh tính đúng đắn. Tùy chọn — bạn có thể chuyển thẳng đến `fe-review`.

**Quy trình thực hiện**:
1. Chạy trình biên dịch TypeScript (`tsc`)
2. Chạy ESLint (nếu đã cấu hình)
3. Chạy Vite build
4. Chạy Vitest
5. Báo cáo đạt/không đạt cho mỗi cổng kiểm tra

---

### `/frontend-react-plugin:fe-review`

**Cú pháp**: `/frontend-react-plugin:fe-review <feature-name>`

**Khi nào sử dụng**: Sau khi sinh mã (hoặc sau khi sửa lỗi) để đánh giá chất lượng mã.

**Quy trình thực hiện**:
1. Lấy khóa để ngăn các thao tác đồng thời
2. Kiểm tra độ lỗi thời của đặc tả (cảnh báo nếu đặc tả được sửa đổi sau khi sinh mã)
3. **Giai đoạn 1 — Đánh giá đặc tả**: tác tử Spec Reviewer kiểm tra mức độ bao phủ yêu cầu, độ trung thực UI, hoàn thiện i18n, khả năng tiếp cận, bao phủ route (5 chiều, chấm điểm 1-10)
4. **Giai đoạn 2 — Đánh giá chất lượng** (chỉ khi đánh giá đặc tả đạt): tác tử Quality Reviewer kiểm tra nguyên tắc trách nhiệm đơn lẻ, pattern nhất quán, không chuỗi hardcode, xử lý lỗi, TypeScript strict, tuân thủ quy ước, kiến trúc (7 chiều, chấm điểm 1-10)
5. Lưu báo cáo đánh giá với chi tiết vấn đề đầy đủ (được bổ sung refs, fixHints, missingArtifact)
6. Giải phóng khóa và cập nhật tiến độ

**Kết quả trạng thái**:
- Cả hai đều đạt sạch → `done`
- Đạt có cảnh báo → `reviewed`
- Một trong hai thất bại → `review-failed`

---

### `/frontend-react-plugin:fe-fix`

**Cú pháp**: `/frontend-react-plugin:fe-fix <feature-name>`

**Khi nào sử dụng**: Sau khi `fe-review` tìm thấy vấn đề.

**Quy trình thực hiện**:
1. Xác thực điều kiện tiên quyết (kế hoạch, báo cáo đánh giá, trạng thái)
2. Phát hiện thay đổi mã nguồn kể từ lần đánh giá cuối (cảnh báo về các vấn đề có thể đã được giải quyết)
3. Lấy khóa để ngăn các thao tác đồng thời
4. Phân loại vấn đề theo chiến lược sửa:
   - **TDD-required**: Thay đổi hành vi — viết test trước, sau đó sửa
   - **Direct-fix**: Thay đổi cơ học (lỗi chính tả, thiếu import) — sửa trực tiếp
   - **Regen-required**: Toàn bộ tệp bị thiếu — đánh dấu giai đoạn cần chạy lại `fe-gen`
5. Khởi chạy tác tử Review Fixer
6. Hiển thị báo cáo sửa lỗi với số lượng test và thay đổi tệp
7. Hướng dẫn đánh giá lại và giải phóng khóa

**Vòng sửa lỗi**: Cảnh báo sau 3 vòng nếu vấn đề vẫn tồn tại. Đề xuất sửa đổi kế hoạch hoặc gỡ lỗi.

---

### `/frontend-react-plugin:fe-e2e`

**Cú pháp**: `/frontend-react-plugin:fe-e2e <feature-name>`

**Khi nào sử dụng**: Sau khi `fe-review` đạt (điểm vào Loop 2). Chạy kiểm thử end-to-end trên trình duyệt.

**Quy trình thực hiện**:
1. Xác thực điều kiện tiên quyết (kế hoạch, mã đã sinh, kịch bản E2E trong plan.json, CLI agent-browser)
2. Xác thực URL kịch bản E2E với các route đã định nghĩa
3. Khởi động Vite dev server với `VITE_ENABLE_MOCKS=true`
4. Chạy kiểm tra sức khỏe runtime (xác minh ứng dụng tải không có lỗi)
5. Khởi chạy tác tử e2e-test-runner để điều khiển kịch bản trình duyệt
6. Dừng dev server và hiển thị kết quả E2E
7. Cập nhật tệp tiến độ với trạng thái E2E

**Vòng sửa E2E**: Nếu kịch bản thất bại, chạy `fe-fix` (tự động phát hiện chế độ E2E) rồi chạy lại `fe-e2e`. Lặp lại cho đến khi tất cả kịch bản đạt.

---

### `/frontend-react-plugin:fe-debug`

**Cú pháp**: `/frontend-react-plugin:fe-debug <feature-name>`

**Khi nào sử dụng**: Cho lỗi runtime hoặc vấn đề phức tạp tại bất kỳ điểm nào trong pipeline.

**Quy trình thực hiện**:
1. Khởi chạy tác tử Debugger với phương pháp 4 giai đoạn:
   - **Observe**: Thu thập bằng chứng (thông báo lỗi, nhật ký, bước tái tạo)
   - **Hypothesize**: Hình thành giả thuyết xếp hạng với điểm tin cậy
   - **Test**: Xác minh từng giả thuyết một cách có hệ thống
   - **Fix**: Áp dụng sửa lỗi TDD với xác minh
2. Nếu không giải quyết được, leo thang với chẩn đoán chi tiết

---

### `/frontend-react-plugin:fe-progress`

**Cú pháp**: `/frontend-react-plugin:fe-progress [feature-name]`

**Khi nào sử dụng**: Bất cứ lúc nào muốn kiểm tra trạng thái pipeline hiện tại.

**Quy trình thực hiện**:
- **Có tên tính năng**: Hiển thị trạng thái chi tiết — trạng thái triển khai, tiến độ giai đoạn TDD, kết quả xác minh, điểm đánh giá, vòng sửa lỗi, kết quả E2E, lịch sử delta, kiểm tra tính mới của đặc tả, và hướng dẫn bước tiếp theo.
- **Không có tên tính năng**: Hiển thị bảng tóm tắt tất cả tính năng — trạng thái, tiến độ sinh mã, điểm đánh giá, vòng sửa lỗi, kết quả E2E, trạng thái delta.

## Hướng dẫn quy trình đầy đủ

### Bước 1: Khởi tạo

```
/frontend-react-plugin:fe-init
```

Thiết lập chế độ router (declarative/data), bật/tắt mock-first và thư mục cơ sở. Cài đặt skill bên ngoài cho routing, testing, hiệu suất, composition và accessibility.

### Bước 2: Tạo kế hoạch triển khai

```
/frontend-react-plugin:fe-plan {feature}
```

Tác tử Implementation Planner đọc đặc tả chức năng (hoặc thu thập yêu cầu trong chế độ độc lập) và phân tích dự án hiện có để tạo `plan.json`. Kế hoạch ánh xạ mọi phần tử đặc tả sang các tệp cụ thể:

- Thực thể → TypeScript interfaces + DTOs
- Thao tác CRUD → module dịch vụ Axios
- Màn hình → Zustand stores + components + pages
- Điều hướng → cấu hình route
- Văn bản hiển thị cho người dùng → namespace + khóa i18n
- Kịch bản kiểm thử → tệp kiểm thử với truy vết nguồn

### Bước 3: Sinh mã (TDD)

```
/frontend-react-plugin:fe-gen {feature}
```

Thực thi 6 giai đoạn TDD nghiêm ngặt. Mỗi giai đoạn TDD (2-5):
1. **RED** — Viết test trước, chạy vitest, xác minh chúng thất bại
2. **GREEN** — Viết triển khai tối thiểu để test đạt
3. **REFACTOR** — Dọn dẹp trong khi giữ test xanh

Các skill bên ngoài được tải theo giai đoạn: Vitest cho các giai đoạn TDD, Composition Patterns cho component, React Best Practices cho page, React Router cho integration.

### Bước 4: Xác minh (tùy chọn)

```
/frontend-react-plugin:fe-verify {feature}
```

### Bước 5: Đánh giá

```
/frontend-react-plugin:fe-review {feature}
```

Đánh giá hai giai đoạn với báo cáo vấn đề được bổ sung (refs, gợi ý sửa, phân loại artifact thiếu).

### Bước 6: Sửa lỗi và đánh giá lại

```
/frontend-react-plugin:fe-fix {feature}
/frontend-react-plugin:fe-review {feature}
```

Lặp lại cho đến khi đánh giá đạt. Skill sửa lỗi áp dụng kỷ luật TDD cho các thay đổi hành vi và sửa trực tiếp cho các thay đổi cơ học.

### Bước 7: Kiểm thử E2E

```
/frontend-react-plugin:fe-e2e {feature}
```

Sau khi đánh giá đạt, chạy kiểm thử end-to-end trên trình duyệt. Tác tử e2e-test-runner điều khiển agent-browser qua các luồng người dùng đa trang được định nghĩa trong plan.json, xác minh với dữ liệu mock MSW.

### Bước 8: Sửa E2E và kiểm thử lại

```
/frontend-react-plugin:fe-fix {feature}
/frontend-react-plugin:fe-e2e {feature}
```

Nếu kịch bản E2E thất bại, `fe-fix` tự động phát hiện chế độ E2E (bằng cách so sánh timestamp báo cáo) và sửa nguyên nhân gốc. Lặp lại cho đến khi tất cả kịch bản E2E đạt.

## Tác tử

### Implementation Planner

**Vai trò**: Phân tích đặc tả → kế hoạch triển khai (plan.json).

Tác tử chỉ phân tích — không sinh bất kỳ mã nguồn nào. Đọc đặc tả chức năng, UI DSL (nếu có) và các pattern dự án hiện có. Tạo kế hoạch có cấu trúc bao gồm types, dịch vụ API, store, component, page, route, i18n, mock, test và thứ tự build TDD. Trong chế độ độc lập, suy luận types và tạo thao tác CRUD mặc định từ spec stub tối thiểu. Sử dụng mô hình Opus.

### Foundation Generator

**Vai trò**: Sinh types + hạ tầng mock.

Sinh TypeScript interfaces, DTOs, enums, mock factories, fixtures và MSW handlers. Xác minh với `tsc`. Không có TDD (chỉ hạ tầng).

### TDD Cycle Runner

**Vai trò**: Chu trình TDD Red-Green nghiêm ngặt cho mỗi giai đoạn.

Thực thi một giai đoạn TDD (api, store, component hoặc page). Viết test trước (RED — phải xác minh thất bại), sau đó viết triển khai tối thiểu (GREEN — phải xác minh đạt). Mỗi test tham chiếu kịch bản kiểm thử đặc tả qua chú thích `// TS-nnn`.

### Integration Generator

**Vai trò**: Routes + i18n + thiết lập MSW toàn cục + xác minh đầy đủ.

Sinh định nghĩa route của tính năng, đăng ký namespace i18n, barrel exports và tổng hợp MSW toàn cục. Tự động tích hợp vào tệp route trung tâm và cấu hình i18n hiện có. Chạy xác minh đầy đủ (tsc, vitest, build).

### Spec Reviewer

**Vai trò**: Đánh giá tuân thủ đặc tả (5 chiều).

So sánh mã sinh ra với đặc tả chức năng. Đánh giá mức độ bao phủ yêu cầu, độ trung thực UI, hoàn thiện i18n, khả năng tiếp cận và bao phủ route. Bổ sung vấn đề với refs (FR-nnn), gợi ý sửa và phân loại artifact thiếu.

### Quality Reviewer

**Vai trò**: Đánh giá chất lượng mã (7 chiều).

Đánh giá nguyên tắc trách nhiệm đơn lẻ, pattern nhất quán, không chuỗi hardcode, xử lý lỗi, TypeScript strict, tuân thủ quy ước và kiến trúc. Chỉ chạy khi đánh giá đặc tả đạt.

### Review Fixer

**Vai trò**: Sửa vấn đề đánh giá với kỷ luật TDD.

Phân loại mỗi vấn đề là TDD-required (thay đổi hành vi — test trước), direct-fix (thay đổi cơ học) hoặc regen-required (tệp bị thiếu). Áp dụng sửa lỗi với kỷ luật phù hợp.

### Delta Modifier

**Vai trò**: Áp dụng thay đổi đặc tả gia tăng.

Sửa đổi các tệp triển khai hiện có dựa trên `delta-plan.json`. Tuân theo pattern review-fixer: TDD cho thay đổi hành vi (hành vi UI mới, trường form mới), chỉnh sửa trực tiếp cho thay đổi cấu trúc (thêm type, cập nhật factory, kết nối route). Xử lý tạo foundation, xóa mã và sửa đổi cascade phụ thuộc. Bảo toàn tất cả công việc review/fix đã tích lũy.

### E2E Test Runner

**Vai trò**: Thực thi kiểm thử E2E qua agent-browser.

Điều khiển Chromium headless qua các luồng người dùng đa trang được định nghĩa trong plan.json. Sử dụng chu trình snapshot → interact → re-snapshot → assert → screenshot. Giải quyết tham số route động từ dữ liệu fixture. Phân loại thất bại thành assertion, agent-error hoặc timeout. Sử dụng mô hình Opus.

### Debugger

**Vai trò**: Gỡ lỗi có hệ thống với phương pháp 4 giai đoạn.

Observe → Hypothesize → Test → Fix. Duy trì danh sách giả thuyết xếp hạng với điểm tin cậy. Leo thang nếu không giải quyết được.

## Skill

| Skill | Command | Mô tả |
|-------|---------|-------------|
| Init | `/frontend-react-plugin:fe-init` | Thiết lập plugin và cài đặt hàng loạt skill bên ngoài |
| Plan | `/frontend-react-plugin:fe-plan` | Phân tích đặc tả chức năng (hoặc thu thập yêu cầu) và tạo kế hoạch triển khai |
| Gen | `/frontend-react-plugin:fe-gen` | Sinh mã production dựa trên kế hoạch triển khai (TDD) |
| Verify | `/frontend-react-plugin:fe-verify` | Chạy xác minh TypeScript, build và test trên mã đã sinh |
| Review | `/frontend-react-plugin:fe-review` | Đánh giá mã 2 giai đoạn (tuân thủ đặc tả + chất lượng) |
| Fix | `/frontend-react-plugin:fe-fix` | Sửa vấn đề đánh giá với kỷ luật TDD |
| E2E | `/frontend-react-plugin:fe-e2e` | Chạy kiểm thử E2E trên trình duyệt qua agent-browser |
| Debug | `/frontend-react-plugin:fe-debug` | Gỡ lỗi có hệ thống với kiểm thử giả thuyết và leo thang |
| Progress | `/frontend-react-plugin:fe-progress` | Hiển thị trạng thái pipeline triển khai cho tất cả hoặc một tính năng cụ thể |

### Skill bên ngoài (được cài đặt bởi init)

| Skill | Source | Mô tả |
|-------|--------|-------------|
| React Router v7 | `remix-run/agent-skills` | Pattern routing (theo chế độ đã cấu hình) |
| Vitest | `antfu/skills` | Pattern kiểm thử |
| React Best Practices | `vercel-labs/agent-skills` | Tối ưu hóa hiệu suất React (57 quy tắc) |
| Composition Patterns | `vercel-labs/agent-skills` | Pattern composition component (10 quy tắc) |
| Web Design Guidelines | `vercel-labs/agent-skills` | Kiểm tra accessibility/thiết kế (100+ quy tắc) |
| Agent Browser | `vercel-labs/agent-browser` | CLI cho tự động hóa trình duyệt E2E |

## Cấu hình

Plugin sử dụng `.claude/frontend-react-plugin.json` trong thư mục dự án (được tạo bởi `/frontend-react-plugin:fe-init`):

```json
{
  "routerMode": "declarative",
  "mockFirst": true,
  "baseDir": "app/src",
  "appDir": "app",
  "eslintTemplate": true
}
```

| Field | Mô tả | Mặc định |
|-------|-------------|---------|
| `routerMode` | Chế độ React Router v7 (`"declarative"` hoặc `"data"`) | `"declarative"` |
| `mockFirst` | Bật phát triển mock-first MSW v2 | `true` |
| `baseDir` | Thư mục cơ sở cho mã nguồn được sinh | `"app/src"` |
| `appDir` | Thư mục chứa `vite.config.*` và `package.json` — tất cả lệnh build/test chạy ở đây | Tự động từ `baseDir` |
| `eslintTemplate` | Tự động tạo `eslint.config.js` từ template đi kèm khi chưa có cấu hình ESLint | `true` |

## Cấu trúc dự án được sinh

```
{baseDir}/
├── layouts/                        ← Shared layouts (cross-feature, uses <Outlet />)
├── features/{feature}/
│   ├── types/                      ← TypeScript interfaces, DTOs, enums
│   ├── api/                        ← Axios service modules
│   ├── stores/                     ← Zustand stores
│   ├── components/                 ← Shared components (forms, tables)
│   ├── pages/                      ← Page components (4-state: loading/empty/error/success)
│   ├── mocks/                      ← MSW factories, fixtures, handlers
│   ├── __tests__/                  ← Test files (api, store, component, page)
│   ├── routes.tsx                  ← Feature route definitions (auto-integrated)
│   └── i18n.ts                     ← Feature i18n registration (auto-integrated)
├── components/ui/                  ← shadcn/ui components
├── mocks/                          ← Global MSW setup (server.ts, browser.ts, handlers.ts)
├── locales/                        ← i18n JSON files
└── ...
```

## Tệp trạng thái pipeline

Tệp trạng thái trong `docs/specs/{feature}/.implementation/frontend/`:

| File | Mục đích |
|------|---------|
| `plan.json` | Kế hoạch triển khai (đầu vào cho fe-gen) |
| `generation-state.json` | Theo dõi tiến độ giai đoạn với timestamp (hỗ trợ tiếp tục) |
| `review-report.json` | Kết quả đánh giá đầy đủ với chi tiết vấn đề được bổ sung (đầu vào cho fe-fix) |
| `fix-report.json` | Kết quả sửa lỗi với phân tích chiến lược |
| `e2e-report.json` | Kết quả kiểm thử E2E với chi tiết kịch bản (đầu vào cho chế độ E2E của fe-fix) |
| `debug-report.json` | Kết quả phiên gỡ lỗi với nhật ký giả thuyết |
| `delta-plan.json` | Kế hoạch thay đổi đặc tả gia tăng (đầu vào cho delta fe-gen, lưu trữ sau thực thi) |
| `.lock` | Ngăn thực thi đồng thời (tự động hết hạn sau 30 phút) |

### Máy trạng thái tiến độ

```
planned → generated → verified → reviewed → done
             ↓    ↘       ↓         ↓    ↓
         gen-failed  ↘ verify-failed ↓  review-failed
                      ↘     ↓        ↓      ↓
                       → resolved  fixing → (re-review → reviewed/review-failed)
                         escalated    ↓  ↘ generated (regen-required → fe-gen)
                            ↓    escalated
                      (manual intervention)
```

### An toàn tệp trạng thái

- **Cơ chế khóa**: Các skill sửa đổi tệp trạng thái sẽ lấy `.lock` trước khi bắt đầu. Ngăn thực thi đồng thời của fe-gen/fe-fix/fe-review trên cùng tính năng. Khóa cũ (>30 phút) được tự động xóa.
- **Quy tắc Read-Modify-Write**: Luôn đọc nội dung tệp mới nhất trước khi ghi. Chỉ hợp nhất các trường đã thay đổi — bảo toàn tất cả trường hiện có.
- **Timestamp giai đoạn**: Mỗi giai đoạn TDD ghi lại `completedAt` để hỗ trợ tiếp tục chính xác và phát hiện độ mới của kế hoạch.
- **Phát hiện lỗi thời**: fe-fix cảnh báo khi tệp nguồn thay đổi kể từ lần đánh giá cuối. fe-review cảnh báo khi đặc tả thay đổi kể từ lần sinh mã.

## Hook

Plugin đăng ký hai hook vòng đời chạy tự động:

### SessionStart — `session-init.sh`

Chạy khi phiên Claude Code bắt đầu. Kiểm tra:
- **Cấu hình**: Tải `.claude/frontend-react-plugin.json` và báo cáo cài đặt hiện tại
- **Thiếu skill**: Cảnh báo nếu skill bên ngoài nào chưa được cài đặt
- **Trạng thái pipeline**: Quét tất cả tính năng và báo cáo trạng thái hiện tại với hướng dẫn bước tiếp theo:
  - `planned` → đề xuất `fe-gen`
  - `generated` → đề xuất `fe-verify` hoặc `fe-review`
  - `gen-failed` → đề xuất thử lại `fe-gen`
  - `verify-failed` → đề xuất `fe-debug`
  - `review-failed` → đề xuất `fe-fix` rồi `fe-review`
  - `fixing` → đề xuất `fe-review` hoặc `fe-e2e` (tự động phát hiện chế độ sửa E2E, hoặc `fe-gen` nếu cần sinh lại)
  - `escalated` → cảnh báo cần can thiệp thủ công
  - `done` → đề xuất `fe-e2e` nếu chưa chạy E2E, nếu không thì báo cáo hoàn thành

### PostToolUse — `validate-implementation.sh`

Chạy sau mỗi lệnh gọi công cụ `Write` hoặc `Edit`. Chỉ kích hoạt trên các tệp trong `docs/specs/`:
- **Phát hiện lỗi thời**: Nếu tệp đặc tả hoặc plan.json được chỉnh sửa trong khi trạng thái triển khai là sau khi lập kế hoạch, cảnh báo rằng mã đã sinh có thể không đồng bộ

## Ngôn ngữ giao tiếp

Các skill cấp tính năng (fe-plan, fe-gen, fe-verify, fe-review, fe-fix, fe-debug) đọc `workingLanguage` từ tệp tiến độ. Tất cả đầu ra cho người dùng (tóm tắt, câu hỏi, phản hồi, hướng dẫn bước tiếp theo) được viết bằng ngôn ngữ làm việc.

Ánh xạ tên ngôn ngữ: `en` = English, `ko` = Korean, `vi` = Vietnamese.

## Mẹo và thực hành tốt nhất

- **Xem lại kế hoạch trước khi sinh mã** — `plan.json` có thể chỉnh sửa được. Điều chỉnh tên tệp, đường dẫn route hoặc test case trước khi chạy `fe-gen`.

- **Sử dụng mock-first để lặp nhanh** — Với `mockFirst: true`, chạy `VITE_ENABLE_MOCKS=true pnpm dev` để phát triển với MSW mocks mà không cần backend. Khi backend sẵn sàng, chỉ cần xóa biến môi trường.

- **Không bỏ qua đánh giá lại sau khi sửa** — Luôn chạy `fe-review` sau `fe-fix`. Chu trình sửa-đánh giá đảm bảo không có hồi quy.

- **Sử dụng fe-debug cho vấn đề runtime** — Nếu test đạt nhưng ứng dụng hoạt động không đúng, `fe-debug` cung cấp kiểm thử giả thuyết có hệ thống thay vì gỡ lỗi tùy ý.

- **Chế độ độc lập là khởi đầu nhanh, không phải đường tắt** — Nó tạo kế hoạch đơn giản hơn mà không có mã lỗi, quy tắc xác thực hoặc tham chiếu kịch bản kiểm thử. Đối với tính năng production, hãy đầu tư vào đặc tả đúng đắn với planning-plugin.

- **Sử dụng chế độ gia tăng khi đặc tả thay đổi** — Sau khi sửa đổi đặc tả trên mã đã sinh, chạy lại `fe-plan`. Nó tự động phát hiện triển khai hiện có và đề xuất chế độ gia tăng, chỉ sinh lại các tệp bị ảnh hưởng trong khi bảo toàn tất cả công việc review/fix. Delta lớn (>60% tệp) sẽ hiển thị cảnh báo đề xuất sinh lại toàn bộ.

- **Tiếp tục là an toàn** — Nếu quá trình sinh mã bị gián đoạn, chỉ cần chạy lại `fe-gen`. Nó phát hiện các giai đoạn đã hoàn thành và tiếp tục. Timestamp cấp giai đoạn đảm bảo kiểm tra độ mới chính xác.

- **Khóa bảo vệ trạng thái của bạn** — Không chạy `fe-gen` và `fe-fix` trên cùng tính năng đồng thời. Cơ chế khóa ngăn hỏng tệp trạng thái.

## Lộ trình

- [x] Đặc tả công nghệ sử dụng
- [x] Skill routing React Router
- [x] Tích hợp skill bên ngoài (vercel-labs/agent-skills)
- [x] Tác tử sinh mã (TDD 6 giai đoạn)
- [x] Skill xác minh
- [x] Skill đánh giá mã (tuân thủ đặc tả + chất lượng)
- [x] Skill sửa lỗi (kỷ luật TDD)
- [x] Skill gỡ lỗi (gỡ lỗi có hệ thống)
- [x] Chế độ độc lập (fe-plan không cần planning-plugin)
- [x] Tính nhất quán trạng thái (khóa, timestamp, phát hiện lỗi thời)
- [x] Bộ xử lý hook (session-init, xác thực triển khai)
- [x] Skill kiểm thử E2E (tích hợp agent-browser)
- [x] Sinh lại delta (xử lý thay đổi đặc tả gia tăng)
- [ ] Thư viện template component
- [ ] Skill thiết lập i18n
- [ ] Template pattern Auth/RBAC

## Cấu trúc thư mục

```
agents/          Agent definitions (planner, foundation-generator, tdd-cycle-runner,
                 integration-generator, spec-reviewer, quality-reviewer, review-fixer,
                 delta-modifier, e2e-test-runner, debugger)
skills/          Skill entry points (fe-init, fe-plan, fe-gen, fe-verify, fe-review, fe-fix,
                 fe-e2e, fe-debug, fe-progress)
hooks/           Lifecycle hook configuration
scripts/         Hook handler scripts (session-init.sh, validate-implementation.sh)
templates/       Template files (feature-module.md, tdd-rules.md, eslint-config.md, e2e-testing.md)
docs/            Documentation
```

## Tác giả

Justin Choi — Ohmyhotel & Co
