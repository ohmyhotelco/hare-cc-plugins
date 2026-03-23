# Homepage Plugin

Plugin Claude Code để xây dựng trang web marketing và homepage công ty với Astro 5, Tailwind CSS, shadcn/ui và tối ưu hóa SEO.

## Bắt đầu nhanh

```bash
# 1. Khởi tạo cấu hình plugin
/homepage-plugin:hp-init

# 2. Định nghĩa trang và section tương tác
/homepage-plugin:hp-plan

# 3. Tạo trang và component Astro
/homepage-plugin:hp-gen

# 4. Kiểm tra chất lượng build
/homepage-plugin:hp-verify

# 5. Đánh giá code SEO + chất lượng
/homepage-plugin:hp-review

# 6. Sửa lỗi đánh giá (nếu có)
/homepage-plugin:hp-fix
```

## Kiến trúc

### Pipeline

```
hp-init → hp-plan → hp-gen → hp-verify → hp-review → hp-fix
                                                       ↓
                                                  hp-review (đánh giá lại)
```

### Skills

| Skill | Lệnh | Mục đích |
|---|---|---|
| hp-init | `/homepage-plugin:hp-init` | Thiết lập dự án (chiến lược nội dung, i18n, mục tiêu deploy) |
| hp-plan | `/homepage-plugin:hp-plan [page]` | Định nghĩa trang/section tương tác |
| hp-gen | `/homepage-plugin:hp-gen [page]` | Tạo trang và section Astro (3 giai đoạn) |
| hp-verify | `/homepage-plugin:hp-verify [page]` | Build + Lighthouse + kiểm tra accessibility |
| hp-review | `/homepage-plugin:hp-review [page]` | Đánh giá code 2 giai đoạn (SEO + chất lượng) |
| hp-fix | `/homepage-plugin:hp-fix <page>` | Sửa lỗi đánh giá |

### Agents

| Agent | Model | Vai trò |
|---|---|---|
| page-planner | Opus | Phân tích mô tả/Figma → page-plan.json |
| section-generator | Opus | Tạo section .astro + React islands |
| page-assembler | Opus | Lắp ráp section → trang + SEO + i18n |
| seo-reviewer | Sonnet | Đánh giá SEO 6 chiều |
| quality-reviewer | Sonnet | Đánh giá chất lượng + accessibility 6 chiều |
| review-fixer | Opus | Sửa lỗi đánh giá trực tiếp |

## Tech Stack

| Lĩnh vực | Công nghệ |
|---|---|
| Framework | Astro 5.x (SSG + kiến trúc islands) |
| Ngôn ngữ | TypeScript (strict) |
| Styling | Tailwind CSS |
| Components | shadcn/ui + Lucide icons (có thể thay thế bằng design system nội bộ) |
| Nội dung | Astro Content Collections + MDX, Headless CMS tùy chọn |
| i18n | Astro i18n routing tích hợp |
| SEO | HTML tĩnh + @astrojs/sitemap + JSON-LD |
| Testing | Vitest + Playwright + Lighthouse CI + axe-core |
| Linting | ESLint v9 flat config |

## Cấu hình

`.claude/homepage-plugin.json` (tạo bởi hp-init):

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

## Catalog Section

15 section marketing canonical:

| Section | Loại | Tương tác |
|---|---|---|
| HeroSection | Tĩnh | — |
| FeaturesSection | Tĩnh | — |
| TestimonialsSection | Island (tùy chọn) | Carousel |
| CTASection | Tĩnh | — |
| PricingSection | Island (tùy chọn) | Toggle |
| FAQSection | Island | Accordion |
| StatsSection | Tĩnh | — |
| LogoCloudSection | Tĩnh | — |
| NewsletterSection | Island | Form |
| ContactSection | Island | Form |
| TeamSection | Tĩnh | — |
| TimelineSection | Tĩnh | — |
| GallerySection | Island (tùy chọn) | Lightbox |
| FooterSection | Tĩnh | — |
| HeaderSection | Island | Mobile nav |

Section tùy chỉnh cũng được hỗ trợ qua `hp-plan`.

## Ngôn ngữ giao tiếp

Skills đọc `defaultLocale` từ cấu hình:
- `ko` → Tiếng Hàn
- `en` → Tiếng Anh
- `vi` → Tiếng Việt
