# SEO Checklist

Complete SEO requirements reference for the `seo-reviewer` agent. Each item is evaluated during `hp-review`.

## 1. Per-Page Metadata

Every page must include:

| Tag | Required | Example |
|---|---|---|
| `<title>` | Yes | `Company Name — Tagline` |
| `<meta name="description">` | Yes | 150-160 characters, includes primary keyword |
| `<meta property="og:title">` | Yes | Match or customize from `<title>` |
| `<meta property="og:description">` | Yes | Match or customize from description |
| `<meta property="og:image">` | Yes | Absolute URL, 1200x630px recommended |
| `<meta property="og:type">` | Yes | `website` for pages, `article` for blog posts |
| `<meta property="og:url">` | Yes | Canonical URL |
| `<meta name="twitter:card">` | Yes | `summary_large_image` |
| `<meta name="twitter:title">` | Recommended | Match og:title |
| `<meta name="twitter:description">` | Recommended | Match og:description |
| `<link rel="canonical">` | Yes | Absolute URL, self-referencing |

### Title Format
- Home: `{Company Name} — {Tagline}`
- Subpages: `{Page Title} | {Company Name}`
- Blog posts: `{Post Title} | {Company Name} Blog`
- Max 60 characters to avoid truncation in search results

### Description Guidelines
- 150-160 characters
- Include primary keyword naturally
- Actionable language (learn, discover, get started)
- Unique per page — never duplicate

## 2. Structured Data (JSON-LD)

Each page type requires specific JSON-LD schemas:

| Page Type | Required Schemas |
|---|---|
| Home | `Organization`, `WebSite` |
| About | `Organization`, `BreadcrumbList` |
| Services | `Service`, `BreadcrumbList` |
| Pricing | `Product` or `Offer`, `BreadcrumbList` |
| Contact | `Organization` (with `contactPoint`), `BreadcrumbList` |
| Blog list | `Blog`, `BreadcrumbList` |
| Blog post | `Article` (or `BlogPosting`), `BreadcrumbList` |
| FAQ | `FAQPage`, `BreadcrumbList` |

### Validation Rules
- Valid JSON-LD syntax (parseable by `JSON.parse`)
- `@context` must be `"https://schema.org"`
- `@type` must match the declared schema type
- Required fields per schema type must be present
- URLs must be absolute
- Dates must be in ISO 8601 format

## 3. Heading Hierarchy

| Rule | Severity |
|---|---|
| Single `<h1>` per page | Critical |
| Logical nesting: `h1` → `h2` → `h3` (no skipping levels) | Warning |
| `<h1>` reflects page topic and includes primary keyword | Warning |
| No empty headings | Critical |
| Headings not used solely for visual styling | Warning |

## 4. Image Optimization

| Rule | Severity |
|---|---|
| All images use `<Image />` from `astro:assets` | Critical |
| Every image has `alt` attribute (non-empty for content images) | Critical |
| Decorative images use `alt=""` and `aria-hidden="true"` | Warning |
| `width` and `height` explicitly set (prevent CLS) | Critical |
| Hero/above-fold images have `loading="eager"` or `priority` | Warning |
| Below-fold images have `loading="lazy"` (default) | Warning |
| Images served in modern formats (WebP/AVIF via Sharp) | Info |
| No images wider than 2x display size | Warning |

## 5. Sitemap & Robots

### Sitemap (`@astrojs/sitemap`)
- All public pages included in sitemap
- Blog posts included with `lastmod` dates
- `changefreq` and `priority` set appropriately
- Sitemap URL referenced in `robots.txt`

### robots.txt
```
User-agent: *
Allow: /
Sitemap: https://example.com/sitemap-index.xml
```

- No public pages blocked by `Disallow`
- Draft/preview pages blocked if applicable
- `sitemap-index.xml` URL is absolute and correct

## 6. Performance Indicators

| Rule | Severity |
|---|---|
| No unnecessary `client:load` on static content sections | Critical |
| Use `client:visible` or `client:idle` instead of `client:load` when possible | Warning |
| No render-blocking scripts in `<head>` (except critical inline styles) | Warning |
| Font loading uses `font-display: swap` or `font-display: optional` | Warning |
| Below-fold sections do not block initial render | Warning |
| Total page JS bundle < 50KB (excluding third-party) | Warning |
| No unused CSS shipped to production | Info |
| Preload critical assets (fonts, hero image) | Info |

## Scoring

Each dimension is scored 0-10:
- **10**: All rules pass, no issues
- **7-9**: Minor issues only (Info/Warning)
- **4-6**: Some Critical issues present
- **0-3**: Multiple Critical issues, fundamental problems

**Pass**: overall weighted average >= 7, zero critical issues
**Fail**: overall average < 7 OR any critical issue count >= 1
**Pass with warnings**: average >= 7, no critical, but warning count > 3
