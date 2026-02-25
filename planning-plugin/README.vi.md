<!-- Synced with en version: 2026-02-24T12:00:00Z -->

[English version](README.md)

# Planning Plugin

> **Ohmyhotel & Co AI Planning Team** — Plugin Claude Code để tạo đặc tả chức năng thông qua đa tác tử (multi-agent)

## Chức năng chính

Plugin Claude Code này tự động hóa việc tạo đặc tả chức năng thông qua các tác tử AI cộng tác:

- **Analyst** — Thu thập yêu cầu thông qua các câu hỏi có cấu trúc (8 danh mục)
- **Planner** — Đánh giá luồng UX và logic nghiệp vụ
- **Tester** — Đánh giá các trường hợp biên và khả năng kiểm thử
- **Translator** — Tạo bản dịch sang các ngôn ngữ được hỗ trợ
- **DSL Generator** — Chuyển đổi định nghĩa màn hình thành UI DSL JSON có cấu trúc
- **Prototype Generator** — Tạo prototype React độc lập từ UI DSL
- **Figma Designer** — Chuyển đổi prototype React thành các layer Figma qua MCP

Tất cả đặc tả được tạo bằng ngôn ngữ làm việc (Working Language) đã cấu hình làm nguồn chính (Source of Truth), các bản dịch sang ngôn ngữ được hỗ trợ khác được tạo tự động.

## Cài đặt

Plugin này được phân phối qua kho GitHub.

```
# 1. Register the repo as a marketplace source
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. Install the plugin (project scope — saved to .claude/settings.json, shared with the team)
/plugin install planning-plugin@ohmyhotelco --scope project
```

Xác minh cài đặt:
```
/plugin
```

> **Lưu ý**: Đối với môi trường không tương tác (CI, v.v.) cần cập nhật tự động, hãy thiết lập biến môi trường `GITHUB_TOKEN`.

## Cập nhật và Quản lý

**Cập nhật marketplace** để lấy phiên bản plugin mới nhất:
```
/plugin marketplace update ohmyhotelco
```

**Tự động cập nhật**: Chuyển đổi theo từng marketplace qua `/plugin` → tab Marketplaces → chọn `ohmyhotelco` → Bật/Tắt tự động cập nhật. Các marketplace bên thứ ba mặc định tắt tự động cập nhật.

**Vô hiệu hóa / Kích hoạt** plugin mà không cần gỡ cài đặt:
```
/plugin disable planning-plugin@ohmyhotelco
/plugin enable planning-plugin@ohmyhotelco
```

**Gỡ cài đặt**:
```
/plugin uninstall planning-plugin@ohmyhotelco --scope project
```

**Giao diện quản lý plugin**: Chạy `/plugin` để mở giao diện tab (Discover, Installed, Marketplaces, Errors).

## Thiết lập MCP (Figma & Notion)

Plugin này đi kèm hai máy chủ HTTP MCP (được định nghĩa trong `plugin.json`):

| Máy chủ | URL | Sử dụng bởi |
|----------|-----|-------------|
| `figma` | `https://mcp.figma.com/mcp` | Tác tử Figma Designer (Stage 3 của `/planning-plugin:design`) |
| `notion` | `https://mcp.notion.com/mcp` | Tác tử Notion Syncer (`/planning-plugin:sync-notion`) |

Quá trình cài đặt tự động đăng ký các máy chủ này — không cần chạy `claude mcp add` thủ công.

**Xác thực qua OAuth**:
1. Chạy `/mcp` trong Claude Code
2. Chọn máy chủ (`figma` hoặc `notion`)
3. Thực hiện theo luồng đăng nhập OAuth trên trình duyệt

> **Mẹo**:
> - Token xác thực được lưu trữ an toàn và tự động làm mới.
> - Để thu hồi quyền truy cập, sử dụng "Clear authentication" trong menu `/mcp`.
> - Nếu trình duyệt không tự động mở, hãy sao chép URL được cung cấp thủ công.
> - Xác thực Notion là bắt buộc cho `/planning-plugin:sync-notion`. Xác thực Figma chỉ cần cho Stage 3 của `/planning-plugin:design`.

## Bắt đầu nhanh

Tạo đặc tả đầu tiên chỉ trong 6 bước:

### 1. Cài đặt plugin

```
/plugin marketplace add ohmyhotelco/hare-cc-plugins
/plugin install planning-plugin@ohmyhotelco --scope project
```

### 2. Khởi tạo cấu hình dự án

```
/planning-plugin:init
```

Thiết lập `.claude/planning-plugin.json` với ngôn ngữ làm việc, ngôn ngữ được hỗ trợ và URL Notion tùy chọn. Bước này là bắt buộc trước khi chạy `/planning-plugin:spec` — skill spec đọc cấu hình từ tệp này.

### 3. Bắt đầu đặc tả mới

```
/planning-plugin:spec "social login with Google and Apple"
```

### 4. Trả lời câu hỏi của Analyst

Tác tử Analyst trước tiên quét dự án của bạn (package.json, mã nguồn, đặc tả hiện có) để nắm bắt ngữ cảnh, sau đó đặt các câu hỏi có mục tiêu theo 8 danh mục:

| Danh mục | Nội dung câu hỏi |
|----------|-------------------|
| Mục đích (Purpose) | Vấn đề cốt lõi cần giải quyết, tại sao cần ngay bây giờ |
| Đối tượng người dùng (Target Users) | Vai trò người dùng, mức độ quyền hạn |
| Luồng người dùng (User Flow) | Kịch bản sử dụng chính theo từng bước |
| Quy tắc nghiệp vụ (Business Rules) | Ràng buộc, logic xác thực |
| Chuyển đổi trạng thái (State Transitions) | Các chuyển đổi trạng thái chính |
| Tích hợp hệ thống (System Integration) | Cách kết nối với các module hiện có |
| Yêu cầu phi chức năng (Non-Functional) | Hiệu suất, bảo mật, khả năng tiếp cận |
| Phạm vi và ưu tiên (Scope & Priority) | Phạm vi MVP, những gì hoãn lại |

Sau mỗi vòng, Analyst chấm điểm mức độ hoàn thiện theo từng danh mục. Khi điểm trung bình đạt >= 7/10, bạn chuyển sang bước tạo bản nháp. Bạn cũng có thể nói "proceed" bất cứ lúc nào để bỏ qua các câu hỏi còn lại — các mục chưa trả lời sẽ được đánh dấu TBD trong đặc tả.

### 5. Đánh giá đặc tả đã tạo

Sau khi bản nháp được tạo bằng ngôn ngữ làm việc và dịch sang các ngôn ngữ được hỗ trợ khác, hai người đánh giá sẽ kiểm tra tuần tự:

- **Planner** — Chấm điểm hành trình người dùng, logic nghiệp vụ, UX lỗi, tích hợp và phạm vi (5 chiều)
- **Tester** — Chấm điểm khả năng kiểm thử, trường hợp biên, chuyển đổi trạng thái, xử lý lỗi và tiêu chí chấp nhận (Acceptance Criteria) (5 chiều)

Bạn sẽ thấy bản tóm tắt tổng hợp bao gồm điểm số, các vấn đề critical/major và các test case đề xuất.

### 6. Xử lý phản hồi và hoàn thiện

Với mỗi vấn đề, chọn: **Accept** / **Reject** / **Modify** / **Defer**. Bản dịch được đồng bộ tự động sau các thay đổi. Khi cả hai người đánh giá đều cho điểm >= 8/10, plugin đề xuất hoàn thiện.

```
/planning-plugin:progress social-login
```

Sử dụng lệnh này bất cứ lúc nào để kiểm tra tiến độ.

## Tham chiếu Skill

### `/planning-plugin:init`

**Cú pháp**: `/planning-plugin:init`

**Khi nào sử dụng**: Trước khi tạo đặc tả đầu tiên trong dự án, để thiết lập cấu hình plugin.

**Quy trình thực hiện**:
1. Tạo `.claude/planning-plugin.json` trong thư mục dự án của bạn
2. Hướng dẫn bạn chọn ngôn ngữ làm việc (`en`, `ko`, hoặc `vi`)
3. Hướng dẫn bạn cấu hình các ngôn ngữ được hỗ trợ cho bản dịch
4. Tùy chọn thiết lập URL trang cha Notion để đồng bộ tự động

**Ví dụ**:
```
/planning-plugin:init
```

---

### `/planning-plugin:spec`

**Cú pháp**: `/planning-plugin:spec "feature description"`

**Khi nào sử dụng**: Khi bắt đầu tạo đặc tả chức năng mới từ đầu.

**Quy trình thực hiện**:
1. Tạo cấu trúc thư mục dưới `docs/specs/{feature}/`
2. Tác tử Analyst quét dự án và đặt các câu hỏi có cấu trúc
3. Đặc tả được tạo thành 3 tệp bằng ngôn ngữ làm việc từ các template
4. Bản dịch sang các ngôn ngữ được hỗ trợ khác được tạo song song
5. Planner và Tester thực hiện đánh giá tuần tự với chấm điểm
6. Bạn xử lý phản hồi, bản dịch được đồng bộ, lặp lại hoặc hoàn thiện

**Ví dụ**:
```
/planning-plugin:spec "reservation cancellation policy with partial refunds"
```

Nếu thư mục đặc tả cho tính năng đó đã tồn tại, plugin sẽ hỏi bạn muốn tiếp tục hay bắt đầu mới.

---

### `/planning-plugin:review`

**Cú pháp**: `/planning-plugin:review feature-name`

**Khi nào sử dụng**: Sau khi chỉnh sửa thủ công đặc tả, để kiểm tra lại chất lượng với đánh giá mới từ Planner và Tester.

**Quy trình thực hiện**:
1. Tìm thư mục đặc tả tại `docs/specs/{feature}/{workingLanguage}/`
2. Nếu đặc tả đã được hoàn thiện, cảnh báo bạn (đánh giá lại sẽ đổi trạng thái về `reviewing`)
3. Chạy đánh giá Planner, sau đó đánh giá Tester (Tester tham khảo phản hồi của Planner)
4. Trình bày phản hồi tổng hợp với xu hướng điểm số so với các vòng trước
5. Bạn xử lý vấn đề, bản dịch được đồng bộ tự động

**Ví dụ**:
```
/planning-plugin:review social-login
```

---

### `/planning-plugin:translate`

**Cú pháp**: `/planning-plugin:translate feature-name [--file=<name>]`

**Khi nào sử dụng**: Sau khi chỉnh sửa trực tiếp đặc tả ngôn ngữ làm việc để đồng bộ bản dịch sang các ngôn ngữ được hỗ trợ khác.

**Quy trình thực hiện**:
1. Đọc thư mục đặc tả nguồn bằng ngôn ngữ làm việc
2. Khởi chạy tác tử Translator song song cho mỗi ngôn ngữ đích
3. Nếu `--file=<name>` được chỉ định, chỉ dịch lại tệp đó (ví dụ: `--file=screens` cho `screens.md`)
4. Cập nhật timestamp đồng bộ trong tệp tiến độ
5. Báo cáo các đánh dấu `<!-- NEEDS_REVIEW -->` mà Translator để lại cho nội dung không rõ ràng

**Ví dụ**:
```
/planning-plugin:translate social-login                    # đồng bộ toàn bộ (tất cả tệp)
/planning-plugin:translate social-login --file=screens       # chỉ đồng bộ screens.md
```

---

### `/planning-plugin:progress`

**Cú pháp**: `/planning-plugin:progress [feature-name]`

**Khi nào sử dụng**: Để kiểm tra tiến độ của một hoặc tất cả đặc tả.

**Quy trình thực hiện**:

Khi chỉ định tên tính năng — hiển thị trạng thái chi tiết:
```
Feature: social-login
Status: reviewing
Current Round: 2

Review History:
┌───────┬─────────────────┬──────────────────┬──────────────────┐
│ Round │ Planner Score   │ Tester Score     │ Key Decisions    │
├───────┼─────────────────┼──────────────────┼──────────────────┤
│   1   │ 6/10            │ 5/10             │ Added error UX   │
│   2   │ 7/10            │ 6/10             │ Expanded tests   │
└───────┴─────────────────┴──────────────────┴──────────────────┘

Translation Status:
  Korean (ko):      Synced — Last synced: 2025-01-15T10:30:00Z
  Vietnamese (vi):  Synced — Last synced: 2025-01-15T10:30:00Z

Open Questions: 2
```

Khi không chỉ định tên tính năng — hiển thị bảng tóm tắt tất cả đặc tả:
```
Specifications Overview:
┌──────────────────┬────────────┬───────┬─────────┬─────────┬────────────┐
│ Feature          │ Status     │ Round │ Planner │ Tester  │ Translated │
├──────────────────┼────────────┼───────┼─────────┼─────────┼────────────┤
│ social-login     │ reviewing  │   2   │  7/10   │  6/10   │ ko✓ vi✓    │
│ user-profile     │ finalized  │   3   │  9/10   │  8/10   │ ko✓ vi✓    │
│ notifications    │ drafting   │   0   │   —     │   —     │ ko✗ vi✗    │
└──────────────────┴────────────┴───────┴─────────┴─────────┴────────────┘
```

---

### `/planning-plugin:migrate-language`

**Cú pháp**: `/planning-plugin:migrate-language feature-name --to=vi`

**Khi nào sử dụng**: Khi chuyển giao dự án cho thành viên nhóm làm việc bằng ngôn ngữ khác, hoặc khi thay đổi ngôn ngữ làm việc của đặc tả hiện có.

**Quy trình thực hiện**:
1. Xác minh rằng bản dịch bằng ngôn ngữ đích đã tồn tại
2. Cập nhật tệp tiến độ để thiết lập ngôn ngữ làm việc mới
3. Xóa header đồng bộ khỏi tệp nguồn mới
4. Đánh dấu tất cả bản dịch ở trạng thái cần đồng bộ (out of sync)
5. Hướng dẫn các bước tiếp theo (chỉnh sửa nguồn mới, dịch lại khi sẵn sàng)

**Ví dụ**:
```
/planning-plugin:migrate-language social-login --to=vi
```

---

### `/planning-plugin:sync-notion`

**Cú pháp**: `/planning-plugin:sync-notion feature-name [--lang=xx]`

**Khi nào sử dụng**: Để đồng bộ thủ công đặc tả đã hoàn thiện lên Notion, hoặc đồng bộ lại sau khi chỉnh sửa. Đồng bộ tự động chạy sau khi hoàn thiện và dịch, nhưng bạn có thể kích hoạt thủ công bất cứ lúc nào.

**Quy trình thực hiện**:
1. Đọc trực tiếp 3 tệp đặc tả cho tính năng và ngôn ngữ được chỉ định (mặc định: ngôn ngữ làm việc)
2. Tạo trang cha + 3 trang con (Overview, Screens, Test Scenarios) dưới `notionParentPageUrl` đã cấu hình
3. Định dạng tiêu đề trang cha: `[{feature}] {lang_name}` (ví dụ: `[social-login] English`)
4. Lưu URL `parentPageUrl` + `childPages` vào trường `notion` của tệp tiến độ
5. Khi chạy lại, cập nhật các trang hiện có thay vì tạo trùng lặp
6. Tự động chuyển đổi định dạng trang đơn cũ sang cấu trúc cha+con mới

**Ví dụ**:
```
/planning-plugin:sync-notion social-login
/planning-plugin:sync-notion social-login --lang=ko
```

> **Lưu ý**: Yêu cầu `notionParentPageUrl` phải được thiết lập trong `.claude/planning-plugin.json`.

---

### `/planning-plugin:design`

**Cú pháp**: `/planning-plugin:design feature-name [--stage=dsl|prototype|figma]`

**Khi nào sử dụng**: Sau khi hoàn thiện đặc tả, để tạo UI DSL, prototype React và tùy chọn thiết kế Figma.

**Quy trình thực hiện** (toàn bộ pipeline):
1. **Stage 1 — Tạo DSL**: Tác tử DSL Generator đọc `screens.md` và `{feature}-spec.md`, sau đó tạo các tệp UI DSL JSON có cấu trúc trong `docs/specs/{feature}/ui-dsl/` (một `manifest.json` với chỉ mục màn hình + bản đồ điều hướng, và một `screen-{id}.json` cho mỗi màn hình)
2. **Stage 2 — Tạo Prototype**: Tác tử Prototype Generator đọc UI DSL và tạo dự án Vite + React + TypeScript + TailwindCSS + shadcn/ui độc lập trong `src/prototypes/{feature}/`
3. **Stage 3 — Tạo Figma** (tùy chọn): Tác tử Figma Designer đọc mã prototype React và chuyển đổi thành các layer Figma qua công cụ MCP `generate_figma_design`

Các stage chạy tuần tự (1→2→3). Sử dụng `--stage` để chạy từng stage độc lập.

**Ví dụ**:
```
/planning-plugin:design social-login                    # toàn bộ pipeline (stage 1→2→3)
/planning-plugin:design social-login --stage=dsl        # chỉ tạo DSL
/planning-plugin:design social-login --stage=prototype  # chỉ tạo prototype
/planning-plugin:design social-login --stage=figma      # chỉ tạo Figma
```

> **Lưu ý**: Stage 3 (Figma) là tùy chọn và yêu cầu cấu hình Figma MCP.

---

### `/planning-plugin:design-system`

**Cú pháp**: `/planning-plugin:design-system [--domain=b2b-admin|hotel-travel] [--query="context"]`

**Khi nào sử dụng**: Trước khi chạy design pipeline, để xây dựng hệ thống thiết kế theo domain với màu sắc, typography, component và UX pattern.

**Quy trình thực hiện**:
1. Đọc 7 cơ sở dữ liệu CSV đã được tuyển chọn từ thư mục `data/design-system/` của plugin
2. Lọc dữ liệu theo domain đã chọn (các hàng khớp với domain + các hàng `general`)
3. Áp dụng quy tắc suy luận ngành từ `industry-rules.csv` (critical/recommended/optional)
4. Tạo `design-system/MASTER.md` + 6 tệp trang trong `design-system/pages/`

**Domain**:
- `b2b-admin` — Bảng quản trị, dashboard, quản lý dữ liệu, công cụ nội bộ
- `hotel-travel` — Đặt phòng khách sạn, nền tảng du lịch, quản lý khách sạn

**Tệp đầu ra**:
- `design-system/MASTER.md` — Tổng quan, nguyên tắc thiết kế, chỉ mục trang, hướng dẫn tích hợp
- `design-system/pages/colors.md` — Bảng màu, CSS custom properties, Tailwind mapping
- `design-system/pages/typography.md` — Thang kiểu chữ, font family, CSS properties
- `design-system/pages/spacing-layout.md` — Thang khoảng cách, pattern bố cục
- `design-system/pages/components.md` — Danh mục component với props và variants
- `design-system/pages/patterns.md` — UX pattern, template trang, luồng người dùng
- `design-system/pages/icons.md` — Ánh xạ icon Lucide, hướng dẫn sử dụng

**Ví dụ**:
```
/planning-plugin:design-system --domain=b2b-admin
/planning-plugin:design-system --domain=hotel-travel --query="booking CRM"
```

## Hướng dẫn quy trình đầy đủ

### Bước 1: Thu thập yêu cầu

Khi bạn chạy `/planning-plugin:spec`, **tác tử Analyst** bắt đầu bằng cách tự động quét dự án của bạn:

- Đọc `package.json`, `README.md`, `CLAUDE.md` và các metadata tương tự
- Lập bản đồ cấu trúc thư mục và tổ chức mã nguồn
- Nhận diện các API, mô hình dữ liệu và tính năng liên quan hiện có
- Kiểm tra `docs/specs/` để tìm các đặc tả đã viết trước đó

Sau đó tạo bản tóm tắt ngữ cảnh và đặt câu hỏi theo 8 danh mục, mỗi danh mục 2-3 câu hỏi. Các câu hỏi tham chiếu đến phát hiện cụ thể từ codebase của bạn (ví dụ: "Tôi tìm thấy `UserService` hiện có — tính năng mới có nên tích hợp với nó không?").

**Chấm điểm hoàn thiện** — sau mỗi vòng trả lời:

| Điểm | Ý nghĩa |
|------|---------|
| 0-3 | Thiếu hụt nghiêm trọng — không thể viết đặc tả nếu thiếu thông tin này |
| 4-6 | Một phần — có thể viết đặc tả nhưng cần nhiều giả định |
| 7-8 | Tốt — đủ để viết đặc tả chắc chắn |
| 9-10 | Xuất sắc — toàn diện, không có thiếu sót |

**Ngưỡng**: Trung bình trên toàn bộ 8 danh mục >= 7 để tiến hành. Dưới mức đó, Analyst đặt câu hỏi bổ sung nhắm vào các danh mục yếu nhất.

**Mẹo cho bước này**:
- Đưa ra câu trả lời chi tiết, cụ thể — câu trả lời mơ hồ tạo ra đặc tả mơ hồ
- Bạn có thể nói "tôi không biết" hoặc "quyết định sau" — mục đó sẽ được đánh dấu TBD
- Bạn có thể nói "proceed" bất cứ lúc nào để bỏ qua câu hỏi còn lại và chuyển sang tạo bản nháp
- Analyst sẽ không gây áp lực — nó hỏi từng danh mục một hoặc nhóm các danh mục liên quan lại

### Bước 2: Tạo bản nháp đặc tả

Plugin điền vào 3 tệp template bằng câu trả lời của bạn (tách ra để đọc chọn lọc):

1. **Tổng quan (Overview)** — Mục đích, đối tượng người dùng, chỉ số thành công (KPI)
2. **Câu chuyện người dùng (User Stories)** — ID, vai trò, mục tiêu, ưu tiên (P0/P1/P2)
3. **Yêu cầu chức năng (Functional Requirements)** — Mỗi mục có quy tắc nghiệp vụ (BR-xxx) và tiêu chí chấp nhận (AC-xxx)
4. **Định nghĩa màn hình (Screen Definitions)** — Bố cục, thành phần, hành động người dùng theo màn hình
5. **Xử lý lỗi (Error Handling)** — Mã lỗi, điều kiện, thông báo người dùng, cách giải quyết
6. **Yêu cầu phi chức năng (Non-Functional Requirements)** — Hiệu suất, bảo mật, khả năng tiếp cận, quốc tế hóa (i18n)
7. **Kịch bản kiểm thử (Test Scenarios)** — Định dạng Given/When/Then
8. **Câu hỏi mở (Open Questions)** — Các mục chưa giải quyết với ngữ cảnh và trạng thái
9. **Lịch sử đánh giá (Review History)** — Điểm số và quyết định theo từng vòng

Các phần thiếu thông tin sẽ được đánh dấu TBD. Bản nháp được lưu thành 3 tệp trong `docs/specs/{feature}/{workingLanguage}/` với trạng thái `DRAFT`:
- `{feature}-spec.md` — Tổng quan, Câu chuyện người dùng, Yêu cầu chức năng, Chỉ mục tệp đặc tả, Câu hỏi mở, Lịch sử đánh giá
- `screens.md` — Định nghĩa màn hình, Xử lý lỗi
- `test-scenarios.md` — Yêu cầu phi chức năng, Kịch bản kiểm thử

### Bước 3: Dịch thuật

Các tác tử Translator chạy song song, tạo ra các phiên bản bằng các ngôn ngữ được hỗ trợ khác. Quy tắc dịch:

- **Được dịch**: Tiêu đề phần, mô tả, câu chuyện người dùng, quy tắc nghiệp vụ, thông báo lỗi
- **Giữ nguyên tiếng Anh**: Thuật ngữ kỹ thuật (API, endpoint, schema, CRUD, JWT, OAuth, REST, GraphQL, v.v.), khối mã, tên trường, ID (US-001, FR-001, v.v.), giá trị trạng thái (DRAFT, FINALIZED, TBD)
- **Văn phong**: Tiếng Hàn sử dụng văn phong trang trọng (합쇼체/하십시오체); tiếng Việt sử dụng văn phong kỹ thuật trang trọng
- **Sự mơ hồ**: Khi thuật ngữ dịch không rõ ràng, thuật ngữ tiếng Anh được thêm trong ngoặc đơn

Mỗi tệp dịch có chú thích timestamp đồng bộ ở đầu tệp.

### Bước 4: Chu trình đánh giá

Đánh giá được thực hiện tuần tự — Planner đánh giá trước, Tester xem phản hồi của Planner để tránh phát hiện trùng lặp.

**Planner** đánh giá 5 chiều:
1. Hoàn thiện hành trình người dùng (User Journey Completeness) — tất cả các đường dẫn được lập tài liệu, điểm vào được xác định
2. Rõ ràng logic nghiệp vụ (Business Logic Clarity) — quy tắc rõ ràng, trường hợp biên được xử lý
3. UX lỗi và trường hợp biên (Error & Edge Case UX) — thông báo người dùng, trạng thái tải/trống, hộp thoại xác nhận
4. Tính nhất quán tích hợp (Integration Consistency) — phù hợp với các mẫu hệ thống hiện có
5. Phạm vi và tính khả thi (Scope & Feasibility) — MVP được phân tách rõ ràng, phụ thuộc được xác định

**Tester** đánh giá 5 chiều:
1. Khả năng kiểm thử yêu cầu (Testability of Requirements) — tiêu chí chấp nhận đo lường được, kiểm thử xác minh được
2. Trường hợp biên và điều kiện ranh giới (Edge Cases & Boundary Conditions) — giới hạn đầu vào, giá trị null, truy cập đồng thời
3. Chuyển đổi trạng thái (State Transitions) — tất cả chuyển đổi được lập tài liệu, các chuyển đổi không hợp lệ được xử lý
4. Hoàn thiện xử lý lỗi (Error Handling Completeness) — mã lỗi được ánh xạ, chiến lược thử lại được định nghĩa
5. Tiêu chí chấp nhận và kịch bản kiểm thử (Acceptance Criteria & Test Scenarios) — phạm vi bao phủ Given/When/Then, trường hợp phủ định

Cả hai tác tử đều chấm điểm từng chiều từ 1-10 và phân loại vấn đề theo mức độ nghiêm trọng:

| Mức độ | Ý nghĩa |
|--------|---------|
| **Critical** | Đặc tả không thể triển khai hoặc kiểm thử ở trạng thái hiện tại. Chặn phát triển. |
| **Major** | Thiếu sót quan trọng có thể dẫn đến làm lại hoặc lỗi nếu không được giải quyết. |
| **Minor** | Cải tiến nhỏ, không chặn phát triển. |
| **Suggestion** | Cải tiến tùy chọn, có thể hoãn lại. |

Tester cũng đề xuất các test case cụ thể (Given/When/Then) cho các thiếu sót được phát hiện.

### Bước 5: Xử lý phản hồi

Với mỗi vấn đề do người đánh giá nêu ra, bạn chọn một trong bốn hành động:

| Hành động | Kết quả |
|-----------|---------|
| **Accept** | Đề xuất được áp dụng vào đặc tả ngôn ngữ làm việc nguyên trạng |
| **Reject** | Vấn đề bị từ chối với ghi chú giải thích lý do |
| **Modify** | Phiên bản đã chỉnh sửa của đề xuất được áp dụng |
| **Defer** | Vấn đề được chuyển đến phần Câu hỏi mở (Open Questions) |

Sau khi áp dụng thay đổi, các tác tử Translator tự động đồng bộ các phiên bản ngôn ngữ khác (dịch một phần — chỉ dịch lại các phần đã thay đổi).

### Bước 6: Hội tụ và hoàn thiện

Plugin áp dụng các quy tắc hội tụ sau mỗi vòng đánh giá:

- **Cả hai điểm >= 8/10**: "Cả hai người đánh giá đều hài lòng. Sẵn sàng hoàn thiện?"
- **Điểm cải thiện qua từng vòng**: "Điểm đang cải thiện. Bạn muốn thực hiện thêm một vòng?"
- **3 vòng không cải thiện**: "Sau 3 vòng, đây là các câu hỏi mở còn lại. Sẵn sàng hoàn thiện ở trạng thái hiện tại?"

Quyết định cuối cùng luôn thuộc về bạn. Khi hoàn thiện:

1. Trạng thái đặc tả đổi thành `FINALIZED` trên tất cả phiên bản ngôn ngữ
2. Trạng thái tệp tiến độ cập nhật thành `finalized`
3. Bạn nhận được bản tóm tắt: tổng số vòng, điểm cuối cùng, quyết định quan trọng, câu hỏi mở còn lại
4. Các bước tiếp theo được đề xuất:
   - `/planning-plugin:design-system --domain=...` — Xây dựng hệ thống thiết kế theo domain (khuyến nghị trước khi chạy design pipeline)
   - `/planning-plugin:design {feature}` — Tạo UI DSL, prototype React và thiết kế Figma
   - `/planning-plugin:review {feature}` — Đánh giá lại bất cứ lúc nào
   - Chỉnh sửa trực tiếp đặc tả ngôn ngữ làm việc và chạy `/planning-plugin:translate {feature}` để đồng bộ

## Tác tử

### Analyst

**Vai trò**: Thu thập yêu cầu thông qua đối thoại có cấu trúc

Hoạt động theo hai giai đoạn: (A) phân tích ngữ cảnh dự án tự động (quét codebase để tìm tech stack, API, model, đặc tả hiện có), sau đó (B) đặt câu hỏi có cấu trúc theo 8 danh mục với chấm điểm hoàn thiện. Sử dụng mô hình Opus để phân tích chuyên sâu. Chấm điểm mỗi danh mục 0-10; trung bình tổng thể phải đạt >= 7 để chuyển sang bước tạo bản nháp.

### Planner

**Vai trò**: Đánh giá sản phẩm và UX của đặc tả

Đánh giá 5 chiều: hoàn thiện hành trình người dùng, rõ ràng logic nghiệp vụ, UX lỗi/trường hợp biên, tính nhất quán tích hợp, và tính khả thi phạm vi. Sử dụng mô hình Opus. Vấn đề được phân loại theo critical/major/minor/suggestion, và mỗi vấn đề đều có đề xuất cụ thể. Ghi nhận các phần viết tốt trong `approved_sections`.

### Tester

**Vai trò**: Đánh giá khả năng kiểm thử và trường hợp biên

Đánh giá 5 chiều: khả năng kiểm thử yêu cầu, trường hợp biên và điều kiện ranh giới, chuyển đổi trạng thái, hoàn thiện xử lý lỗi, và tiêu chí chấp nhận (Acceptance Criteria). Sử dụng mô hình Sonnet. Luôn tham chiếu phản hồi của Planner để tránh trùng lặp. Đề xuất test case cụ thể (Given/When/Then) cho mọi vấn đề Critical và Major.

### Translator

**Vai trò**: Dịch giữa các ngôn ngữ được hỗ trợ (en/ko/vi)

Dịch đặc tả trong khi bảo toàn cấu trúc markdown, thuật ngữ kỹ thuật, khối mã và ID. Sử dụng mô hình Sonnet. Hỗ trợ dịch toàn bộ (đặc tả mới) và dịch một phần (cập nhật cấp tệp sau khi đánh giá). Thêm chú thích timestamp đồng bộ và đánh dấu các bản dịch không rõ ràng bằng `<!-- NEEDS_REVIEW -->`.

### Notion Sync

**Vai trò**: Đồng bộ đặc tả đã hoàn thiện lên các trang Notion

Skill `sync-notion` đọc trực tiếp các tệp đặc tả và tạo trang cha + 3 trang con (Overview, Screens, Test Scenarios) cho mỗi ngôn ngữ dưới URL trang cha đã cấu hình. Mỗi trang con chứa nội dung của một tệp đặc tả, tránh giới hạn token đầu ra LLM với đặc tả lớn. Lưu URL trang vào tệp tiến độ để cập nhật trong tương lai. Được kích hoạt tự động sau khi hoàn thiện và dịch, hoặc thủ công qua `/planning-plugin:sync-notion`.

### DSL Generator

**Vai trò**: Chuyển đổi định nghĩa màn hình thành UI DSL JSON có cấu trúc

Đọc `screens.md` và `{feature}-spec.md` từ đặc tả đã hoàn thiện, sau đó tạo các tệp JSON có cấu trúc trong `docs/specs/{feature}/ui-dsl/`. Đầu ra bao gồm `manifest.json` (chỉ mục màn hình + bản đồ điều hướng) và một `screen-{id}.json` cho mỗi màn hình. Sử dụng từ vựng thành phần shadcn/ui độc quyền. Sử dụng mô hình Opus.

### Prototype Generator

**Vai trò**: Tạo prototype React độc lập từ UI DSL

Đọc UI DSL JSON và tạo dự án Vite + React + TypeScript + TailwindCSS + shadcn/ui hoàn chỉnh trong `src/prototypes/{feature}/`. Bao gồm dữ liệu mock, routing trang và tất cả thành phần shadcn/ui được tham chiếu. Prototype là độc lập — không phụ thuộc vào dự án chính. Sử dụng mô hình Opus.

### Figma Designer

**Vai trò**: Chuyển đổi prototype React thành các layer Figma qua MCP

Đọc mã prototype React và chuyển đổi các thành phần, bố cục và kiểu dáng thành các layer Figma bằng công cụ MCP `generate_figma_design`. Stage này là tùy chọn và yêu cầu cấu hình Figma MCP. Sử dụng mô hình Sonnet.

## Cấu hình

Plugin sử dụng `.claude/planning-plugin.json` trong thư mục dự án của người dùng (được tạo bởi `/planning-plugin:init`):

```json
{
  "workingLanguage": "en",
  "supportedLanguages": ["en", "ko", "vi"],
  "notionParentPageUrl": ""
}
```

| Trường | Mô tả | Mặc định |
|--------|-------|----------|
| `workingLanguage` | Ngôn ngữ để soạn thảo và đánh giá đặc tả (`en`, `ko`, hoặc `vi`) | `"en"` |
| `supportedLanguages` | Tất cả ngôn ngữ cần duy trì bản dịch | `["en", "ko", "vi"]` |
| `notionParentPageUrl` | URL trang cha Notion để đồng bộ tự động | `""` |

Để thay đổi ngôn ngữ làm việc, chỉnh sửa `.claude/planning-plugin.json` trước khi tạo đặc tả mới. Đặc tả hiện có giữ nguyên ngôn ngữ làm việc gốc (lưu trong tệp tiến độ).

## Cấu trúc đầu ra

```
docs/specs/{feature}/
├── {workingLanguage}/                     ← Source of truth (ngôn ngữ làm việc)
│   ├── {feature}-spec.md                  ← Chỉ mục: Tổng quan, Câu chuyện người dùng, Yêu cầu chức năng, Câu hỏi mở, Lịch sử đánh giá
│   ├── screens.md                         ← Định nghĩa màn hình, Xử lý lỗi
│   └── test-scenarios.md                  ← Yêu cầu phi chức năng, Kịch bản kiểm thử
├── {target_lang_1}/                       ← Bản dịch (cùng cấu trúc tệp)
│   ├── {feature}-spec.md
│   ├── screens.md
│   └── test-scenarios.md
├── {target_lang_2}/                       ← Bản dịch (cùng cấu trúc tệp)
│   └── ...
├── ui-dsl/                                ← UI DSL JSON (từ design pipeline)
│   ├── manifest.json                      ← Chỉ mục màn hình + bản đồ điều hướng
│   └── screen-{id}.json                   ← Định nghĩa thành phần theo màn hình
└── .progress/
    └── {feature}.json                     ← Workflow state

src/prototypes/{feature}/                  ← Prototype React (dự án Vite độc lập)
├── package.json
├── src/
│   ├── App.tsx
│   ├── pages/                             ← Một thành phần trang cho mỗi màn hình
│   └── mocks/                             ← Dữ liệu mock cho prototype
└── ...
```

## Các phần template đặc tả

1. Tổng quan (Overview) — Mục đích, Đối tượng người dùng, Chỉ số thành công
2. Câu chuyện người dùng (User Stories)
3. Yêu cầu chức năng (Functional Requirements)
4. Định nghĩa màn hình (Screen Definitions)
5. Xử lý lỗi (Error Handling)
6. Yêu cầu phi chức năng (Non-Functional Requirements)
7. Kịch bản kiểm thử (Test Scenarios)
8. Câu hỏi mở (Open Questions)
9. Lịch sử đánh giá (Review History)

## Mẹo và thực hành tốt nhất

- **Cung cấp mô tả tính năng chi tiết** — Bạn cung cấp càng nhiều ngữ cảnh trong lệnh `/planning-plugin:spec` ban đầu, câu hỏi của Analyst sẽ càng chính xác. "Social login" thì được; "social login with Google and Apple for both web and mobile apps, replacing the current email-only signup" thì tốt hơn nhiều.

- **Không bỏ qua các mục TBD mãi mãi** — Đánh dấu TBD cho phép bạn tiến lên, nhưng hãy quay lại giải quyết trước khi hoàn thiện. Planner và Tester sẽ chỉ ra các TBD chưa giải quyết như là vấn đề.

- **Chỉnh sửa thủ công được hoan nghênh** — Bạn có thể chỉnh sửa trực tiếp đặc tả ngôn ngữ làm việc bất cứ lúc nào. Sau khi chỉnh sửa, chạy `/planning-plugin:translate feature-name` để đồng bộ bản dịch, và `/planning-plugin:review feature-name` để kiểm tra lại chất lượng.

- **Sử dụng `--file` cho dịch có mục tiêu** — Nếu bạn chỉ thay đổi một tệp, sử dụng `/planning-plugin:translate feature-name --file=screens` thay vì dịch lại toàn bộ đặc tả.

- **Kiểm tra trạng thái thường xuyên** — Sử dụng `/planning-plugin:progress` (không tham số) để xem tổng quan tất cả đặc tả, đặc biệt khi làm việc trên nhiều tính năng cùng lúc.

- **Tiếp tục phiên làm việc** — Nếu bạn đóng Claude Code giữa chừng, plugin sẽ tự động phát hiện các đặc tả đang xử lý khi khởi động lại và thông báo cho bạn. Sử dụng `/planning-plugin:progress` để xem bạn dừng ở đâu, sau đó `/planning-plugin:spec` để tiếp tục.

- **Không nên đuổi theo điểm hoàn hảo** — Nếu điểm bão hòa sau 3 vòng, plugin đề xuất hoàn thiện với các câu hỏi mở. Đây thường là lựa chọn đúng — đặc tả đã hoàn thiện với câu hỏi mở được lập tài liệu hữu ích hơn bản nháp được đánh giá vô tận.

- **Đánh giá lại sau thay đổi lớn** — Ngay cả sau khi hoàn thiện, bạn có thể đánh giá lại bất cứ lúc nào bằng `/planning-plugin:review`. Điều này sẽ đổi trạng thái về `reviewing` để bạn có thể lặp lại thêm.

- **Thay đổi ngôn ngữ làm việc** — Có hai kịch bản:
  - *Đối với đặc tả mới*: Chỉnh sửa `.claude/planning-plugin.json` và đặt `workingLanguage` thành ngôn ngữ mong muốn (ví dụ: `"vi"`). Tất cả đặc tả sau này sẽ được soạn thảo bằng ngôn ngữ đó.
  - *Đối với đặc tả hiện có*: Chạy `/planning-plugin:migrate-language feature-name --to=vi`. Lệnh này chuyển source of truth sang bản dịch ngôn ngữ đích, đánh dấu tất cả bản dịch khác là cần đồng bộ, và giữ nguyên trạng thái đặc tả. Bản dịch ngôn ngữ đích phải tồn tại trước — chạy `/planning-plugin:translate` trước nếu cần.

## Cấu trúc thư mục

```
agents/          Agent definitions (analyst, planner, tester, translator, dsl-generator, prototype-generator, figma-designer)
skills/          Skill entry points (init, spec, review, translate, progress, design, design-system, migrate-language, sync-notion)
hooks/           Lifecycle hook configuration
scripts/         Hook handler scripts
data/            Curated CSV databases (data/design-system/*.csv — styles, colors, typography, components, patterns, industry-rules, icons)
templates/       Spec templates + UI DSL schema (spec-overview.md, screens.md, test-scenarios.md, ui-dsl-schema.json)
docs/specs/      Generated specifications (3 tệp mỗi thư mục ngôn ngữ + ui-dsl/)
src/prototypes/  Generated React prototypes (dự án Vite độc lập theo tính năng)
```

## Quy tắc

- Thuật ngữ kỹ thuật (API, endpoint, schema, CRUD) được giữ nguyên tiếng Anh trong tất cả bản dịch
- Tất cả đánh giá của tác tử chỉ nhắm vào thư mục đặc tả ngôn ngữ làm việc
- Đặc tả được tách thành 3 tệp mỗi ngôn ngữ — `{feature}-spec.md` là tệp chỉ mục; các tệp chi tiết (`screens.md`, `test-scenarios.md`) chứa phần còn lại
- UI DSL và prototype sử dụng từ vựng thành phần shadcn/ui độc quyền (Card, Table, Button, Dialog, Alert, Badge, Form, Input, Select, v.v.)
- Prototype là dự án Vite độc lập, không phụ thuộc vào dự án chính
- Tạo Figma là tùy chọn và yêu cầu cấu hình Figma MCP

## Tác giả

Justin Choi — Ohmyhotel & Co AI Planning Team
