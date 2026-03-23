# Homepage Plugin

A Claude Code plugin for building company marketing and homepage websites with Astro 5, Tailwind CSS, shadcn/ui, and SEO optimization.

## Quick Start

```bash
# 1. Initialize plugin configuration
/homepage-plugin:hp-init

# 2. Define pages and sections interactively
/homepage-plugin:hp-plan

# 3. Generate Astro pages and components
/homepage-plugin:hp-gen

# 4. Verify build quality
/homepage-plugin:hp-verify

# 5. Run SEO + quality code review
/homepage-plugin:hp-review

# 6. Fix review issues (if any)
/homepage-plugin:hp-fix
```

## Architecture

### Pipeline

```
hp-init → hp-plan → hp-gen → hp-verify → hp-review → hp-fix
                                                       ↓
                                                  hp-review (re-review)
```

### Skills

| Skill | Command | Purpose |
|---|---|---|
| hp-init | `/homepage-plugin:hp-init` | Project setup (content strategy, i18n, deploy target) |
| hp-plan | `/homepage-plugin:hp-plan [page]` | Interactive page/section definition |
| hp-gen | `/homepage-plugin:hp-gen [page]` | Generate Astro pages and sections (3-phase) |
| hp-verify | `/homepage-plugin:hp-verify [page]` | Build + Lighthouse + accessibility audit |
| hp-review | `/homepage-plugin:hp-review [page]` | 2-stage code review (SEO + quality) |
| hp-fix | `/homepage-plugin:hp-fix <page>` | Fix review issues |

### Agents

| Agent | Model | Role |
|---|---|---|
| page-planner | Opus | Analyze descriptions/Figma → page-plan.json |
| section-generator | Opus | Generate .astro sections + React islands |
| page-assembler | Opus | Assemble sections → pages + SEO + i18n |
| seo-reviewer | Sonnet | 6-dimension SEO audit |
| quality-reviewer | Sonnet | 6-dimension quality + accessibility audit |
| review-fixer | Opus | Direct fixes for review issues |

## Tech Stack

| Area | Technology |
|---|---|
| Framework | Astro 5.x (SSG + islands architecture) |
| Language | TypeScript (strict) |
| Styling | Tailwind CSS |
| Components | shadcn/ui + Lucide icons (replaceable with in-house design system) |
| Content | Astro Content Collections + MDX, optional headless CMS |
| i18n | Astro built-in i18n routing |
| SEO | Static HTML + @astrojs/sitemap + JSON-LD |
| Testing | Vitest + Playwright + Lighthouse CI + axe-core |
| Linting | ESLint v9 flat config |

## Configuration

`.claude/homepage-plugin.json` (created by hp-init):

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

| Field | Options | Default |
|---|---|---|
| `contentStrategy` | `"mdx"` \| `"headless-cms"` \| `"both"` | `"mdx"` |
| `i18nLocales` | Array of locale codes | `["ko", "en"]` |
| `defaultLocale` | Locale code | `"ko"` |
| `deployTarget` | `"vercel"` \| `"netlify"` \| `"cloudflare"` \| `"static"` | `"vercel"` |
| `eslintTemplate` | `true` \| `false` | `true` |

## Generated Project Structure

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
│   ├── islands/                    ← React interactive components
│   ├── ui/                         ← shadcn/ui components
│   └── layout/                     ← Header, Footer, Navigation
├── content/
│   ├── config.ts                   ← Content Collection schemas
│   └── blog/                       ← MDX blog posts
├── i18n/                           ← Translation JSON files
├── lib/
│   ├── structured-data.ts          ← JSON-LD generators
│   └── cms.ts                      ← Headless CMS client (optional)
└── styles/
    └── globals.css
```

## Section Catalog

15 canonical marketing sections available:

| Section | Type | Interactive |
|---|---|---|
| HeroSection | Static | — |
| FeaturesSection | Static | — |
| TestimonialsSection | Island (optional) | Carousel |
| CTASection | Static | — |
| PricingSection | Island (optional) | Toggle |
| FAQSection | Island | Accordion |
| StatsSection | Static | — |
| LogoCloudSection | Static | — |
| NewsletterSection | Island | Form |
| ContactSection | Island | Form |
| TeamSection | Static | — |
| TimelineSection | Static | — |
| GallerySection | Island (optional) | Lightbox |
| FooterSection | Static | — |
| HeaderSection | Island | Mobile nav |

Custom sections are also supported via `hp-plan`.

## State Files

```
docs/pages/{page-name}/
├── page-plan.json
├── .progress/{page-name}.json
└── .implementation/homepage/
    ├── generation-state.json
    ├── review-report.json
    ├── fix-report.json
    └── .lock
```

### Progress State Machine

```
planned → generated → verified → reviewed → done
             ↓            ↓         ↓
        gen-failed   verify-failed  review-failed
                                    ↓
                               fixing → (re-review)
                               escalated
```

## Hooks

| Hook | Trigger | Purpose |
|---|---|---|
| SessionStart | Claude Code startup | Check config, report page pipeline status |
| PostToolUse | Write/Edit | Detect page plan edits, warn about staleness |

## Communication Language

Skills read `defaultLocale` from configuration:
- `ko` → Korean
- `en` → English
- `vi` → Vietnamese
