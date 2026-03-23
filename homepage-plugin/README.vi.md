# Homepage Plugin

> **Ohmyhotel & Co** — Plugin Claude Code để phát triển trang chủ marketing với Astro

## Tính năng chính

Plugin Claude Code này tạo ra các trang web marketing homepage sẵn sàng cho production từ các định nghĩa trang/section tương tác. Nó cung cấp một pipeline hoàn chỉnh từ lập kế hoạch trang đến sinh mã, kiểm tra SEO, đánh giá và sửa lỗi — được tối ưu hóa cho các trang nội dung tĩnh.

Khả năng chính:
- **Lập kế hoạch trang tương tác** — Định nghĩa trang và section thông qua hội thoại ngôn ngữ tự nhiên, với tùy chọn phân tích tham chiếu Figma
- **Sinh mã theo section** — 15 section marketing chuẩn (.astro tĩnh + React islands cho tương tác)
- **Kiến trúc ưu tiên SEO** — Đầu ra HTML tĩnh, dữ liệu có cấu trúc JSON-LD, sitemap, meta tags, kiểm tra Lighthouse CI
- **Astro islands** — Mặc định không có JS; chỉ hydrate các component tương tác (form, carousel, accordion)
- **Đánh giá mã 2 giai đoạn** — Tuân thủ SEO (6 chiều) + chất lượng mã/khả năng truy cập (6 chiều)
- **Content Collections** — Bài viết MDX an toàn kiểu với Zod schemas, tích hợp headless CMS tùy chọn

## Tổng quan kiến trúc

```
/homepage-plugin:hp-init → .claude/homepage-plugin.json
        │
        ▼
/homepage-plugin:hp-plan [page-name]
        │
        ├── Interactive: describe site purpose, pages, and per-page content
        │   └── page-planner agent → page-plan.json (per page)
        │
        ├── Optional: provide Figma screenshot for design reference
        │   └── AI vision analyzes design → refines section props
        │
        ▼
/homepage-plugin:hp-gen [page-name]
        │
        ├── Phase 1: Infrastructure   — layout, header/footer, SEO utils, i18n, styles
        ├── Phase 2: Sections & Pages — section-generator + page-assembler (per page)
        └── Phase 3: Verification     — tsc + ESLint + astro build
        │
        ▼
/homepage-plugin:hp-verify [page-name] (optional)
        │
        ▼
/homepage-plugin:hp-review [page-name]
        │
        ├── Stage 1: seo-reviewer → SEO compliance (6 dimensions)
        └── Stage 2: quality-reviewer → code quality + accessibility (6 dimensions)
        │
        ▼ (if issues found)
/homepage-plugin:hp-fix <page-name>
        │
        └── review-fixer agent → direct fixes
        │
        ▼
/homepage-plugin:hp-review [page-name] (re-review)
```

## Tech Stack

| Danh mục | Công nghệ |
|----------|-----------|
| Runtime | Node.js 22.x LTS (>= 22.12) |
| Package Manager | pnpm |
| Framework | Astro 5.x (SSG + islands architecture) |
| Ngôn ngữ | TypeScript (strict) |
| Tích hợp UI | @astrojs/react (React 19 cho interactive islands) |
| Styling | Tailwind CSS (@astrojs/tailwind) |
| Components | shadcn/ui + Lucide icons (có thể thay thế bằng design system nội bộ) |
| Nội dung | Astro Content Collections + @astrojs/mdx, headless CMS tùy chọn |
| i18n | Astro built-in i18n routing |
| SEO | Static HTML + @astrojs/sitemap + JSON-LD structured data |
| Hình ảnh | astro:assets `<Image />` với tối ưu hóa Sharp |
| Testing | Vitest + Playwright + Lighthouse CI + axe-core |
| Linting | ESLint v9 flat config (eslint-plugin-astro) |
| Triển khai | Vercel / Netlify / CloudFlare Pages (static adapter) |

## Cài đặt

Plugin này được phân phối qua GitHub repository.

```
# 1. Đăng ký repo làm nguồn marketplace
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. Cài đặt plugin (phạm vi dự án — lưu vào .claude/settings.json, chia sẻ với team)
/plugin install homepage-plugin@ohmyhotelco --scope project
```

Xác nhận cài đặt:
```
/plugin
```

## Cập nhật & Quản lý

**Cập nhật marketplace** để lấy phiên bản plugin mới nhất:
```
/plugin marketplace update ohmyhotelco
```

**Tắt / Bật** plugin mà không cần gỡ cài đặt:
```
/plugin disable homepage-plugin@ohmyhotelco
/plugin enable homepage-plugin@ohmyhotelco
```

**Gỡ cài đặt**:
```
/plugin uninstall homepage-plugin@ohmyhotelco --scope project
```

**Giao diện quản lý plugin**: Chạy `/plugin` để mở giao diện tab (Discover, Installed, Marketplaces, Errors).

## Bắt đầu nhanh

```
1. /homepage-plugin:hp-init                           # cấu hình plugin
2. /homepage-plugin:hp-plan                           # định nghĩa trang và section tương tác
3. /homepage-plugin:hp-gen                            # sinh mã trang và component Astro
4. /homepage-plugin:hp-verify                         # kiểm tra chất lượng build (tùy chọn)
5. /homepage-plugin:hp-review                         # đánh giá mã SEO + chất lượng
6. /homepage-plugin:hp-fix {page}                     # sửa lỗi đánh giá (nếu có)
```

## Tham chiếu Skills

### `/homepage-plugin:hp-init`

**Cú pháp**: `/homepage-plugin:hp-init`

**Khi nào sử dụng**: Thiết lập lần đầu trong dự án, hoặc cấu hình lại cài đặt.

**Quy trình**:
1. Hỏi về chiến lược nội dung (MDX, headless CMS, hoặc cả hai)
2. Hỏi về locale i18n và locale mặc định
3. Hỏi về mục tiêu triển khai (Vercel, Netlify, CloudFlare, static)
4. Hỏi về tùy chọn template ESLint
5. Ghi `.claude/homepage-plugin.json`
6. Cài đặt 2 skill bên ngoài (Web Design Guidelines, Composition Patterns)
7. Hiển thị hướng dẫn bước tiếp theo

---

### `/homepage-plugin:hp-plan`

**Cú pháp**: `/homepage-plugin:hp-plan [page-name]`

**Khi nào sử dụng**: Để định nghĩa trang và section cho homepage. Chạy trước khi sinh mã.

**Quy trình**:
1. Hỏi về mục đích trang web (trang chủ công ty, landing page sản phẩm, portfolio, v.v.)
2. Hỏi về các trang cần thiết — đề xuất mặc định dựa trên loại trang
3. Với mỗi trang, hỏi nội dung cần hiển thị — người dùng mô tả bằng ngôn ngữ tự nhiên
4. Khớp mô tả với 15 loại section chuẩn từ danh mục section
5. Đề xuất bố cục section cho mỗi trang, người dùng xác nhận/chỉnh sửa
6. Hỏi về layout chung (cấu trúc header/footer)
7. Chấp nhận tham chiếu Figma tùy chọn (ảnh chụp màn hình hoặc URL) để phân tích thiết kế
8. Khởi chạy agent page-planner để tạo `page-plan.json` cho mỗi trang
9. Hiển thị tóm tắt với các trang, section, component chung và bước tiếp theo

**Hỗ trợ chạy lại**: Có thể thêm trang mới, thay thế tất cả, hoặc chỉnh sửa trang cụ thể. Với tham số `[page-name]`, chỉ lập kế hoạch cho trang đó.

---

### `/homepage-plugin:hp-gen`

**Cú pháp**: `/homepage-plugin:hp-gen [page-name]`

**Khi nào sử dụng**: Sau khi `hp-plan` tạo ra kế hoạch trang.

**Quy trình**:
1. Xác thực kế hoạch trang và kiểm tra trạng thái sinh mã hiện có (hỗ trợ tiếp tục)
2. Lấy khóa để ngăn chặn thao tác đồng thời
3. Thực hiện 3 phase tuần tự, mỗi phase trong một phiên agent riêng:

| Phase | Agent | Chức năng |
|-------|-------|-----------|
| Infrastructure | page-assembler | Layout, header/footer, SEO utils, i18n, styles, Content Collections |
| Sections & Pages | section-generator + page-assembler | .astro sections, React islands, lắp ráp trang (mỗi trang) |
| Verification | (trực tiếp) | TypeScript, ESLint, Astro build |

4. Theo dõi tiến trình phase trong `generation-state.json` để hỗ trợ tiếp tục
5. Giải phóng khóa và cập nhật tiến trình

**Hỗ trợ tiếp tục**: Nếu quá trình sinh mã bị gián đoạn, chạy lại `hp-gen` sẽ phát hiện các phase đã hoàn thành và đề xuất tiếp tục từ phase/trang chưa hoàn thành cuối cùng.

---

### `/homepage-plugin:hp-verify`

**Cú pháp**: `/homepage-plugin:hp-verify [page-name]`

**Khi nào sử dụng**: Sau khi sinh mã để xác minh tính đúng đắn. Tùy chọn — bạn có thể chuyển thẳng đến `hp-review`.

**Quy trình**:
1. Chạy TypeScript compiler (`tsc`)
2. Chạy ESLint (tự động sinh config từ template nếu cần)
3. Chạy Astro build (`astro build`)
4. Chạy Lighthouse CI (mục tiêu performance/accessibility/SEO >= 90)
5. Chạy component tests cho interactive islands (nếu có)
6. Báo cáo đạt/không đạt cho mỗi cổng kiểm tra

---

### `/homepage-plugin:hp-review`

**Cú pháp**: `/homepage-plugin:hp-review [page-name]`

**Khi nào sử dụng**: Sau khi sinh mã (hoặc sau khi sửa lỗi) để đánh giá chất lượng mã.

**Quy trình**:
1. Lấy khóa để ngăn chặn thao tác đồng thời
2. **Giai đoạn 1 — Đánh giá SEO**: agent seo-reviewer kiểm tra tính đầy đủ metadata, dữ liệu có cấu trúc, hệ thống phân cấp heading, tối ưu hình ảnh, sitemap/robots, chỉ số hiệu suất (6 chiều, chấm điểm 0-10)
3. **Giai đoạn 2 — Đánh giá chất lượng** (chỉ khi SEO đạt): agent quality-reviewer kiểm tra khả năng truy cập WCAG AA, thiết kế responsive, bố cục component, TypeScript strictness, tính đầy đủ i18n, quy ước Astro (6 chiều, chấm điểm 0-10)
4. Lưu báo cáo đánh giá hợp nhất với chi tiết vấn đề (severity, file, line, fixHint)
5. Giải phóng khóa và cập nhật tiến trình

**Kết quả trạng thái**:
- Cả hai đạt sạch → `done`
- Đạt với cảnh báo → `reviewed`
- Một trong hai không đạt → `review-failed`

---

### `/homepage-plugin:hp-fix`

**Cú pháp**: `/homepage-plugin:hp-fix <page-name>`

**Khi nào sử dụng**: Sau khi `hp-review` phát hiện vấn đề.

**Quy trình**:
1. Xác thực điều kiện tiên quyết (kế hoạch trang, báo cáo đánh giá, tiến trình)
2. Lấy khóa để ngăn chặn thao tác đồng thời
3. Khởi chạy agent review-fixer — áp dụng sửa lỗi trực tiếp cho tất cả vấn đề (không phân loại TDD vì section là trình bày)
4. Chạy xác minh sau khi sửa (tsc + ESLint + astro build)
5. Hiển thị báo cáo sửa lỗi và hướng dẫn đánh giá lại
6. Giải phóng khóa và cập nhật tiến trình

**Vòng sửa lỗi**: Cảnh báo sau 3 vòng nếu vấn đề vẫn tồn tại. Đề xuất sửa đổi kế hoạch hoặc can thiệp thủ công.

## Quy trình Pipeline đầy đủ

### Bước 1: Khởi tạo

```
/homepage-plugin:hp-init
```

Thiết lập chiến lược nội dung (MDX/headless CMS), locale i18n, mục tiêu triển khai và tùy chọn ESLint. Cài đặt skill bên ngoài cho khả năng truy cập và mẫu bố cục component.

### Bước 2: Định nghĩa trang & section

```
/homepage-plugin:hp-plan
```

Agent page-planner tổng hợp mô tả ngôn ngữ tự nhiên của bạn và tham chiếu Figma tùy chọn thành kế hoạch trang có cấu trúc. Mỗi kế hoạch trang ánh xạ:

- Mục đích trang → metadata SEO (title, description, OG tags, kiểu JSON-LD)
- Mô tả nội dung → loại section chuẩn (15 loại tích hợp + tùy chỉnh)
- Nhu cầu tương tác → phân loại React island (client:load vs client:visible)
- Phần tử chung → cấu trúc layout (header, footer, navigation)
- Bản dịch → namespace i18n và nhóm key

### Bước 3: Sinh mã

```
/homepage-plugin:hp-gen
```

Thực hiện 3 phase sinh mã:
1. **Infrastructure** — layout chung, header/footer, tiện ích SEO, thiết lập i18n, cấu hình Content Collection
2. **Sections & Pages** — mỗi trang: sinh section (.astro + React islands), lắp ráp trang với metadata SEO
3. **Verification** — TypeScript, ESLint, Astro build

### Bước 4: Xác minh (tùy chọn)

```
/homepage-plugin:hp-verify
```

Xác minh đầy đủ bao gồm ngân sách hiệu suất Lighthouse CI (mục tiêu: 90+ trên tất cả danh mục).

### Bước 5: Đánh giá

```
/homepage-plugin:hp-review
```

Đánh giá hai giai đoạn: tuân thủ SEO trước (metadata, dữ liệu có cấu trúc, hình ảnh, hiệu suất), sau đó chất lượng mã (khả năng truy cập, responsive, TypeScript, i18n, quy ước Astro).

### Bước 6: Sửa lỗi & Đánh giá lại

```
/homepage-plugin:hp-fix {page}
/homepage-plugin:hp-review {page}
```

Lặp lại cho đến khi đánh giá đạt. Skill sửa lỗi áp dụng sửa trực tiếp và xác minh sau mỗi đợt.

## Agents

### Page Planner

**Vai trò**: Phân tích đầu vào người dùng → kế hoạch trang (`page-plan.json`).

Agent chỉ phân tích — không sinh bất kỳ mã nguồn nào. Tổng hợp mô tả trang, lựa chọn section và tham chiếu Figma tùy chọn của người dùng thành kế hoạch có cấu trúc. Đối chiếu với danh mục section để tìm các mẫu chuẩn và phát hiện section chung giữa các trang. Sử dụng model Opus.

### Section Generator

**Vai trò**: Sinh section `.astro` + React island.

Sinh các component section riêng lẻ từ kế hoạch trang. Tạo file `.astro` tĩnh theo mặc định; chỉ thêm React `.tsx` island cho các phần tử tương tác (form, carousel, accordion). Cài đặt component shadcn/ui cần thiết và sinh key dịch i18n.

### Page Assembler

**Vai trò**: Lắp ráp section → trang hoàn chỉnh + infrastructure.

Lắp ráp các section đã sinh thành trang Astro hoàn chỉnh với tích hợp layout, metadata SEO (tương đương `generateMetadata`), dữ liệu có cấu trúc JSON-LD và kết nối i18n. Khi sinh trang đầu tiên, tạo infrastructure chung (layout, header/footer, tiện ích SEO, thiết lập i18n, cấu hình Content Collections).

### SEO Reviewer

**Vai trò**: Đánh giá tuân thủ SEO (6 chiều).

Agent chỉ đọc, đánh giá tính đầy đủ metadata, tính hợp lệ dữ liệu có cấu trúc, hệ thống phân cấp heading, tối ưu hình ảnh, phạm vi sitemap/robots và chỉ số hiệu suất. Chấm điểm mỗi chiều 0-10 với vấn đề chi tiết (severity, file, line, fixHint).

### Quality Reviewer

**Vai trò**: Đánh giá chất lượng mã + khả năng truy cập (6 chiều).

Agent chỉ đọc, đánh giá khả năng truy cập (WCAG 2.1 AA), thiết kế responsive, bố cục component, TypeScript strictness, tính đầy đủ i18n và tuân thủ quy ước Astro. Chỉ chạy khi đánh giá SEO đạt.

### Review Fixer

**Vai trò**: Sửa lỗi trực tiếp cho vấn đề đánh giá.

Sửa các vấn đề SEO và chất lượng được xác định bởi reviewer. Tất cả sửa lỗi đều trực tiếp (không phân loại TDD) vì section homepage chủ yếu là trình bày. Tối đa 3 vòng thử lại mỗi vấn đề. Chuyển tiếp vấn đề không thể giải quyết.

## Skills

| Skill | Lệnh | Mô tả |
|-------|-------|-------|
| Init | `/homepage-plugin:hp-init` | Thiết lập plugin và cài đặt skill bên ngoài |
| Plan | `/homepage-plugin:hp-plan` | Định nghĩa và lập kế hoạch trang/section tương tác |
| Gen | `/homepage-plugin:hp-gen` | Sinh trang và section Astro (pipeline 3 phase) |
| Verify | `/homepage-plugin:hp-verify` | Xác minh TypeScript, ESLint, Astro build, Lighthouse CI |
| Review | `/homepage-plugin:hp-review` | Đánh giá mã 2 giai đoạn (SEO + chất lượng/khả năng truy cập) |
| Fix | `/homepage-plugin:hp-fix` | Sửa vấn đề đánh giá bằng sửa lỗi trực tiếp |

### Skill bên ngoài (cài đặt bởi init)

| Skill | Nguồn | Mô tả |
|-------|--------|-------|
| Web Design Guidelines | `vercel-labs/agent-skills` | Kiểm tra khả năng truy cập/thiết kế (100+ quy tắc) |
| Composition Patterns | `vercel-labs/agent-skills` | Mẫu bố cục component (10 quy tắc) |

## Cấu hình

Plugin sử dụng `.claude/homepage-plugin.json` trong thư mục dự án (được tạo bởi `/homepage-plugin:hp-init`):

```json
{
  "framework": "astro",
  "contentStrategy": "mdx",
  "i18nLocales": ["ko", "en"],
  "defaultLocale": "ko",
  "deployTarget": "vercel",
  "eslintTemplate": true
}
```

| Trường | Mô tả | Mặc định |
|--------|--------|----------|
| `framework` | Framework (dành cho mở rộng tương lai) | `"astro"` |
| `contentStrategy` | Phương pháp quản lý nội dung (`"mdx"` \| `"headless-cms"` \| `"both"`) | `"mdx"` |
| `i18nLocales` | Mã locale được hỗ trợ | `["ko", "en"]` |
| `defaultLocale` | Locale mặc định cho trang web và ngôn ngữ đầu ra skill | `"ko"` |
| `deployTarget` | Mục tiêu triển khai (`"vercel"` \| `"netlify"` \| `"cloudflare"` \| `"static"`) | `"vercel"` |
| `eslintTemplate` | Tự động sinh cấu hình ESLint khi chưa có | `true` |

## Cấu trúc dự án được tạo

```
src/
├── pages/                          ← Astro file-based routing
│   ├── index.astro
│   ├── about.astro
│   └── blog/
│       ├── index.astro
│       └── [slug].astro
├── layouts/
│   └── MarketingLayout.astro       ← Header + Footer + <slot />
├── components/
│   ├── sections/                   ← .astro static sections
│   ├── islands/                    ← React interactive components (client: directives)
│   ├── ui/                         ← shadcn/ui components
│   └── layout/                     ← Header, Footer, Navigation
├── content/
│   ├── config.ts                   ← Content Collection schemas (Zod)
│   └── blog/                       ← MDX blog posts
├── i18n/                           ← Translation JSON files
├── lib/
│   ├── structured-data.ts          ← JSON-LD generators
│   └── cms.ts                      ← Headless CMS client (optional)
└── styles/
    └── globals.css
```

## Danh mục Section

15 section marketing chuẩn có sẵn. Section tùy chỉnh cũng được hỗ trợ qua `hp-plan`.

| Section | Loại | Phần tử tương tác |
|---|---|---|
| HeroSection | Static | — |
| FeaturesSection | Static | — |
| TestimonialsSection | Island (tùy chọn) | Carousel |
| CTASection | Static | — |
| PricingSection | Island (tùy chọn) | Monthly/yearly toggle |
| FAQSection | Island | Accordion |
| StatsSection | Static | — |
| LogoCloudSection | Static | — |
| NewsletterSection | Island | Email form |
| ContactSection | Island | Contact form + validation |
| TeamSection | Static | — |
| TimelineSection | Static | — |
| GallerySection | Island (tùy chọn) | Lightbox |
| FooterSection | Static | — |
| HeaderSection | Island | Mobile navigation |

**Static** = component `.astro`, được render thành HTML tĩnh tại thời điểm build (không có JS).
**Island** = wrapper `.astro` + component React `.tsx`, được hydrate qua `client:load` hoặc `client:visible`.

## Tệp trạng thái Pipeline

Tệp trạng thái trong `docs/pages/{page-name}/`:

| Tệp | Mục đích |
|-----|----------|
| `page-plan.json` | Kế hoạch trang với section, metadata SEO, cấu hình i18n (đầu vào cho hp-gen) |
| `.progress/{page-name}.json` | Theo dõi tiến trình pipeline |
| `.implementation/homepage/generation-state.json` | Tiến trình phase với timestamp (cho phép tiếp tục) |
| `.implementation/homepage/review-report.json` | Kết quả đánh giá hợp nhất (SEO + chất lượng) |
| `.implementation/homepage/fix-report.json` | Kết quả sửa lỗi với theo dõi vòng |
| `.implementation/homepage/.lock` | Ngăn chặn thực thi đồng thời (tự động hết hạn sau 30 phút) |

Kế hoạch layout chung: `docs/pages/_shared/layout-plan.json`

### Máy trạng thái tiến trình

```
planned → generated → verified → reviewed → done
             ↓            ↓         ↓
        gen-failed   verify-failed  review-failed
                                    ↓
                               fixing → (re-review)
                               escalated
```

### An toàn tệp trạng thái

- **Cơ chế khóa**: Các skill thay đổi tệp trạng thái lấy `.lock` trước khi bắt đầu. Ngăn chặn thực thi đồng thời hp-gen/hp-fix/hp-review trên cùng một trang. Khóa cũ (>30 phút) được tự động xóa. Định dạng khóa: JSON với `lockedBy`, `lockedAt`, `pageName`.
- **Quy tắc Read-Modify-Write**: Luôn đọc nội dung tệp mới nhất trước khi ghi. Chỉ hợp nhất các trường đã thay đổi — giữ nguyên tất cả trường hiện có.
- **Hỗ trợ tiếp tục**: `generation-state.json` theo dõi phase/trang đã hoàn thành với timestamp để phát hiện chính xác điểm tiếp tục.
- **Phát hiện lỗi thời**: validate-pages.sh cảnh báo khi kế hoạch trang được chỉnh sửa sau khi sinh mã.

## Hooks

Plugin đăng ký hai hook vòng đời chạy tự động:

### SessionStart — `session-init.sh`

Chạy khi phiên Claude Code bắt đầu. Kiểm tra:
- **Cấu hình**: Tải `.claude/homepage-plugin.json` và báo cáo cài đặt hiện tại
- **Skill thiếu**: Cảnh báo nếu bất kỳ skill bên ngoài nào chưa được cài đặt
- **Trạng thái pipeline**: Quét tất cả trang và báo cáo trạng thái hiện tại với hướng dẫn bước tiếp theo:
  - `planned` → đề xuất `hp-gen`
  - `generated` → đề xuất `hp-verify` hoặc `hp-review`
  - `gen-failed` → đề xuất thử lại `hp-gen`
  - `verify-failed` → đề xuất xem lại lỗi
  - `review-failed` → đề xuất `hp-fix` rồi `hp-review`
  - `fixing` → đề xuất `hp-review` (đánh giá lại)
  - `escalated` → cảnh báo cần can thiệp thủ công
  - `done` → báo cáo hoàn thành

### PostToolUse — `validate-pages.sh`

Chạy sau mỗi lần gọi công cụ `Write` hoặc `Edit`. Chỉ kích hoạt trên file trong `docs/pages/`:
- **Phát hiện lỗi thời**: Nếu kế hoạch trang hoặc tệp trạng thái được chỉnh sửa khi trạng thái triển khai đã vượt qua giai đoạn lập kế hoạch, cảnh báo rằng mã đã sinh có thể không đồng bộ

## Ngôn ngữ giao tiếp

Các skill đọc `defaultLocale` từ tệp cấu hình. Tất cả đầu ra hướng tới người dùng (tóm tắt, câu hỏi, phản hồi, hướng dẫn bước tiếp theo) được viết bằng ngôn ngữ của locale đã cấu hình.

Ánh xạ tên ngôn ngữ: `en` = English, `ko` = Korean, `vi` = Vietnamese.

## Mẹo & Thực hành tốt nhất

- **Mô tả nội dung, không phải cấu trúc** — Khi định nghĩa trang trong `hp-plan`, hãy mô tả nội dung bạn muốn hiển thị ("đánh giá của khách hàng", "bảng giá") thay vì cấu trúc HTML. Planner sẽ khớp mô tả của bạn với danh mục section.

- **Cung cấp tham chiếu Figma** — Nếu bạn có thiết kế Figma, hãy truyền ảnh chụp màn hình cho `hp-plan`. Phân tích AI vision trích xuất chi tiết cụ thể (màu sắc, khoảng cách, nội dung) vào props của section.

- **Tĩnh theo mặc định** — Không yêu cầu React islands trừ khi thực sự cần tương tác. Section `.astro` tĩnh không tạo JavaScript và cho điểm Lighthouse tốt nhất.

- **Đánh giá SEO trước khi triển khai** — Luôn chạy `hp-review` trước khi triển khai. Đánh giá SEO phát hiện meta tags thiếu, dữ liệu có cấu trúc lỗi và vấn đề phân cấp heading ảnh hưởng trực tiếp đến thứ hạng tìm kiếm.

- **Không bỏ qua đánh giá lại sau khi sửa** — Luôn chạy `hp-review` sau `hp-fix`. Chu trình sửa-đánh giá đảm bảo không có hồi quy.

- **Tiếp tục an toàn** — Nếu quá trình sinh mã bị gián đoạn, chỉ cần chạy lại `hp-gen`. Nó phát hiện phase và trang đã hoàn thành, sau đó tiếp tục từ điểm chưa hoàn thành cuối cùng.

- **Khóa bảo vệ trạng thái** — Không chạy `hp-gen` và `hp-fix` trên cùng một trang đồng thời. Cơ chế khóa ngăn chặn hỏng tệp trạng thái.

- **Thêm trang dần dần** — Sau khi sinh mã ban đầu, sử dụng `hp-plan {page-name}` để thêm trang mới từng trang một mà không ảnh hưởng đến các trang hiện có.

## Lộ trình

- [x] Đặc tả tech stack (Astro 5 + Tailwind + shadcn/ui)
- [x] Danh mục section (15 section marketing chuẩn)
- [x] Lập kế hoạch trang tương tác (hp-plan)
- [x] Sinh mã (pipeline 3 phase)
- [x] Xác minh SEO (Lighthouse CI)
- [x] Đánh giá mã 2 giai đoạn (SEO + chất lượng/khả năng truy cập)
- [x] Skill sửa lỗi (sửa trực tiếp)
- [x] Nhất quán trạng thái (khóa, timestamp, tiếp tục)
- [x] Xử lý hook (session-init, page validation)
- [ ] Tích hợp Figma MCP (đồng bộ thiết kế tự động)
- [ ] Thư viện template blog (layout MDX có sẵn)
- [ ] Template CMS adapter (Sanity, Contentful)
- [ ] Tích hợp giám sát hiệu suất (Web Analytics, Sentry)

## Cấu trúc thư mục

```
agents/          Agent definitions (page-planner, section-generator, page-assembler,
                 seo-reviewer, quality-reviewer, review-fixer)
skills/          Skill entry points (hp-init, hp-plan, hp-gen, hp-verify, hp-review, hp-fix)
hooks/           Lifecycle hook configuration
scripts/         Hook handler scripts (session-init.sh, validate-pages.sh)
templates/       Template files (section-catalog, page-module, seo-checklist, eslint-config, astro-conventions)
docs/            Documentation
```

## Tác giả

Justin Choi — Ohmyhotel & Co
