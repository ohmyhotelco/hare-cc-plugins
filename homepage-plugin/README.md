# Homepage Plugin

> **Ohmyhotel & Co** — Claude Code plugin for marketing homepage development with Astro, shadcn/ui (or Figma-derived custom components), and SEO optimization

## What It Does

This Claude Code plugin generates production-ready marketing homepage websites from interactive page/section definitions. It provides a complete pipeline from page planning through code generation, SEO verification, review, and fix — optimized for static-first content sites.

Key capabilities:
- **Interactive page planning** — Define pages and sections through natural language conversation, with optional Figma reference analysis
- **Section-based generation** — 15 canonical marketing sections (.astro static + React islands for interactivity)
- **SEO-first architecture** — Static HTML output, JSON-LD structured data, sitemap, meta tags, Lighthouse CI auditing
- **Astro islands** — Zero JS by default; only hydrate interactive components (forms, carousels, accordions)
- **Figma design system integration** — Optional Figma MCP sync extracts design tokens and auto-generates custom components replacing shadcn/ui
- **2-stage code review** — SEO compliance (6 dimensions) + code quality/accessibility (6 dimensions, +1 Design Token Consistency when design system exists)
- **Content Collections** — Type-safe MDX blog posts with Zod schemas, optional headless CMS integration

## Architecture Overview

```
/homepage-plugin:hp-init → .claude/homepage-plugin.json
        │
        ▼
[/homepage-plugin:hp-design-sync] (optional — requires Figma MCP)
        │
        ├── design-token-extractor agent → design-tokens.json + component-map.json
        └── Enables Figma-derived custom components in hp-gen
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
        └── Stage 2: quality-reviewer → code quality + accessibility (6+1 dimensions)
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

| Category | Technology |
|----------|-----------|
| Runtime | Node.js 22.x LTS (>= 22.12) |
| Package Manager | pnpm |
| Framework | Astro 5.x (SSG + islands architecture) |
| Language | TypeScript (strict) |
| UI Integration | @astrojs/react (React 19 for interactive islands) |
| Styling | Tailwind CSS (@astrojs/tailwind) |
| Components | shadcn/ui + Lucide icons (auto-replaced with Figma-derived custom components when design system exists) |
| Content | Astro Content Collections + @astrojs/mdx, optional headless CMS |
| i18n | Astro built-in i18n routing |
| SEO | Static HTML + @astrojs/sitemap + JSON-LD structured data |
| Images | astro:assets `<Image />` with Sharp optimization |
| Testing | Playwright (E2E + visual) + Lighthouse CI + axe-core |
| Linting | ESLint v9 flat config (eslint-plugin-astro) |
| Deploy | Vercel / Netlify / CloudFlare Pages (static adapter) |

## Installation

This plugin is distributed via a GitHub repository.

```
# 1. Register the repo as a marketplace source
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. Install the plugin (project scope — saved to .claude/settings.json, shared with the team)
/plugin install homepage-plugin@ohmyhotelco --scope project
```

Verify the installation:
```
/plugin
```

## Update & Management

**Update marketplace** to pull the latest plugin versions:
```
/plugin marketplace update ohmyhotelco
```

**Disable / Enable** a plugin without uninstalling:
```
/plugin disable homepage-plugin@ohmyhotelco
/plugin enable homepage-plugin@ohmyhotelco
```

**Uninstall**:
```
/plugin uninstall homepage-plugin@ohmyhotelco --scope project
```

**Plugin manager UI**: Run `/plugin` to open the tabbed interface (Discover, Installed, Marketplaces, Errors).

## Quick Start

```
1. /homepage-plugin:hp-init                           # configure plugin
2. /homepage-plugin:hp-design-sync                    # sync Figma design tokens (optional)
3. /homepage-plugin:hp-plan                           # define pages and sections interactively
4. /homepage-plugin:hp-gen                            # generate Astro pages and components
5. /homepage-plugin:hp-verify                         # verify build quality (optional)
6. /homepage-plugin:hp-review                         # SEO + quality code review
7. /homepage-plugin:hp-fix {page}                     # fix review issues (if any)
```

## Skills Reference

### `/homepage-plugin:hp-init`

**Syntax**: `/homepage-plugin:hp-init`

**When to use**: First-time setup in a project, or reconfiguring settings.

**What happens**:
1. Prompts for content strategy (MDX, headless CMS, or both)
2. Prompts for i18n locales and default locale
3. Prompts for deploy target (AWS, Vercel, Netlify, CloudFlare, static)
4. Prompts for ESLint template preference
5. Writes `.claude/homepage-plugin.json`
6. Installs 2 external skills (Web Design Guidelines, Composition Patterns)
7. Displays next-step guidance

---

### `/homepage-plugin:hp-design-sync`

**Syntax**: `/homepage-plugin:hp-design-sync [figma-file-url]`

**When to use**: After `hp-init`, when you have a Figma design file and want to extract design tokens for custom component generation. Optional — without this, `hp-gen` uses shadcn/ui defaults.

**Prerequisites**: Figma MCP server must be connected (remote `https://mcp.figma.com/mcp` or desktop plugin).

**What happens**:
1. Resolves Figma file key from URL argument, config, or user prompt
2. Verifies Figma MCP connection (exits with setup instructions if unavailable)
3. Discovers file structure (page-based or library-based)
4. Launches design-token-extractor agent to extract:
   - Color tokens, typography, spacing, border radius, shadows
   - Component definitions mapped to shadcn/ui equivalents
5. Writes `docs/design-system/design-tokens.json` and `docs/design-system/component-map.json`
6. Updates `.claude/homepage-plugin.json` with `figmaFileKey` and `figmaFileUrl`
7. Validates output and displays summary

**Re-run support**: Subsequent runs offer `replace` (fresh extraction) or `update` (merge with existing) modes.

---

### `/homepage-plugin:hp-plan`

**Syntax**: `/homepage-plugin:hp-plan [page-name]`

**When to use**: To define pages and sections for the homepage. Run before code generation.

**What happens**:
1. Asks about site purpose (company homepage, product landing, portfolio, etc.)
2. Asks for pages needed — suggests defaults based on site type
3. For each page, asks what content to show — user describes in natural language
4. Matches descriptions to 15 canonical section types from the section catalog
5. Proposes section composition per page, user confirms/modifies
6. Asks about shared layout (header/footer structure)
7. Accepts optional Figma reference (screenshot or URL) for design analysis
8. Launches page-planner agent to produce `page-plan.json` per page
9. Displays summary with pages, sections, shared components, and next steps

**Re-run support**: Can add new pages, replace all, or edit a specific page. With `[page-name]` argument, plans only that page.

---

### `/homepage-plugin:hp-gen`

**Syntax**: `/homepage-plugin:hp-gen [page-name]`

**When to use**: After `hp-plan` produces page plans.

**What happens**:
1. Validates page plans and checks for existing generation state (resume support)
2. Acquires a lock to prevent concurrent operations
3. Executes 3 phases sequentially, each in a separate agent session:

| Phase | Agent | What it does |
|-------|-------|-------------|
| Infrastructure | page-assembler | Layout, header/footer, SEO utils, i18n, styles, Content Collections |
| Sections & Pages | section-generator + page-assembler | .astro sections, React islands, page assembly (per page) |
| Verification | (direct) | TypeScript, ESLint, Astro build |

4. Tracks phase progress in `generation-state.json` for resume support
5. Releases the lock and updates progress

**Resume support**: If generation is interrupted, re-running `hp-gen` detects completed phases and offers to resume from the last incomplete phase/page.

---

### `/homepage-plugin:hp-verify`

**Syntax**: `/homepage-plugin:hp-verify [page-name]`

**When to use**: After code generation to verify correctness. Optional — you can go directly to `hp-review`.

**What happens**:
1. Runs TypeScript compiler (`tsc`)
2. Runs ESLint (auto-generates config from template if needed)
3. Runs Astro build (`astro build`)
4. Runs Lighthouse CI (performance/accessibility/SEO >= 90 target)
5. Reports pass/fail for each gate

---

### `/homepage-plugin:hp-review`

**Syntax**: `/homepage-plugin:hp-review [page-name]`

**When to use**: After code generation (or after fixing issues) to review code quality.

**What happens**:
1. Acquires a lock to prevent concurrent operations
2. **Stage 1 — SEO Review**: seo-reviewer agent checks metadata completeness, structured data, heading hierarchy, image optimization, sitemap/robots, performance indicators (6 dimensions, scored 0-10)
3. **Stage 2 — Quality Review** (only when SEO passes): quality-reviewer agent checks accessibility WCAG AA, responsive design, component composition, TypeScript strictness, i18n completeness, Astro conventions (6 dimensions, +1 Design Token Consistency when design system exists, scored 0-10)
4. Saves merged review report with issue details (severity, file, line, fixHint)
5. Releases the lock and updates progress

**Status outcomes**:
- Both pass clean → `done`
- Pass with warnings → `reviewed`
- Either fails → `review-failed`

---

### `/homepage-plugin:hp-fix`

**Syntax**: `/homepage-plugin:hp-fix <page-name>`

**When to use**: After `hp-review` finds issues.

**What happens**:
1. Validates prerequisites (page plan, review report, progress)
2. Acquires a lock to prevent concurrent operations
3. Launches review-fixer agent — applies direct fixes for all issues (no TDD classification since sections are presentational)
4. Runs verification after fixes (tsc + ESLint + astro build)
5. Displays fix report and guides re-review
6. Releases the lock and updates progress

**Fix rounds**: Warns after 3 rounds if issues persist. Suggests plan revision or manual intervention.

## Full Pipeline Workflow

### Step 1: Initialize

```
/homepage-plugin:hp-init
```

Sets content strategy (MDX/headless CMS), i18n locales, deploy target, and ESLint preference. Installs external skills for accessibility and composition patterns.

### Step 2: Sync Design Tokens (optional)

```
/homepage-plugin:hp-design-sync
```

If you have a Figma design file, extract design tokens and component definitions. This enables `hp-gen` to generate Figma-derived custom components instead of shadcn/ui defaults. Requires Figma MCP server connection.

### Step 3: Define Pages & Sections

```
/homepage-plugin:hp-plan
```

The page-planner agent synthesizes your natural language descriptions and optional Figma references into structured page plans. Each page plan maps:

- Page purpose → SEO metadata (title, description, OG tags, JSON-LD types)
- Content descriptions → canonical section types (15 built-in + custom)
- Interactive needs → React island classification (client:load vs client:visible)
- Shared elements → layout structure (header, footer, navigation)
- Translations → i18n namespace and key groups

### Step 4: Generate Code

```
/homepage-plugin:hp-gen
```

Executes 3 phases of code generation:
1. **Infrastructure** — shared layout, header/footer, SEO utilities, i18n setup, Content Collection config
2. **Sections & Pages** — per page: generate sections (.astro + React islands), assemble page with SEO metadata
3. **Verification** — TypeScript, ESLint, Astro build

### Step 5: Verify (optional)

```
/homepage-plugin:hp-verify
```

Full verification including Lighthouse CI performance budgets (target: 90+ on all categories).

### Step 6: Review

```
/homepage-plugin:hp-review
```

Two-stage review: SEO compliance first (metadata, structured data, images, performance), then code quality (accessibility, responsive, TypeScript, i18n, Astro conventions).

### Step 7: Fix & Re-Review

```
/homepage-plugin:hp-fix {page}
/homepage-plugin:hp-review {page}
```

Iterate until review passes. The fix skill applies direct fixes and verifies after each batch.

## Agents

### Design Token Extractor

**Role**: Figma MCP → design tokens + component map (`design-tokens.json`, `component-map.json`).

Connects to a Figma file via MCP to extract design tokens (colors, typography, spacing, shadows) and component definitions. Supports both page-based files (where Figma pages represent website pages) and library-based files (design system libraries). Outputs JSON files that `hp-gen` reads for custom component generation. Uses the Opus model.

### Page Planner

**Role**: User input analysis → page plan (`page-plan.json`).

Analysis-only agent — does not generate any source code. Synthesizes user's page descriptions, section selections, and optional Figma references into structured plans. Cross-references the section catalog for canonical patterns and detects shared sections across pages. Uses the Opus model.

### Section Generator

**Role**: `.astro` sections + React island generation.

Generates individual section components from the page plan. Creates static `.astro` files by default; adds React `.tsx` islands only for interactive elements (forms, carousels, accordions). Installs required shadcn/ui components and generates i18n translation keys.

### Page Assembler

**Role**: Section assembly → full pages + infrastructure.

Assembles generated sections into complete Astro pages with layout integration, SEO metadata (`generateMetadata` equivalent), JSON-LD structured data, and i18n wiring. On first page generation, creates shared infrastructure (layout, header/footer, SEO utilities, i18n setup, Content Collections config).

### SEO Reviewer

**Role**: SEO compliance review (6 dimensions).

Read-only agent that evaluates metadata completeness, structured data validity, heading hierarchy, image optimization, sitemap/robots coverage, and performance indicators. Scores each dimension 0-10 with enriched issues (severity, file, line, fixHint).

### Quality Reviewer

**Role**: Code quality + accessibility review (6 dimensions, +1 optional Design Token Consistency).

Read-only agent that evaluates accessibility (WCAG 2.1 AA), responsive design, component composition, TypeScript strictness, i18n completeness, and Astro convention compliance. When `docs/design-system/design-tokens.json` exists, adds a 7th dimension for Design Token Consistency. Only runs when SEO review passes.

### Review Fixer

**Role**: Direct fix for review issues.

Fixes SEO and quality issues identified by reviewers. All fixes are direct (no TDD classification) since homepage sections are primarily presentational. Maximum 3 retry rounds per issue. Escalates unresolvable issues.

## Skills

| Skill | Command | Description |
|-------|---------|-------------|
| Init | `/homepage-plugin:hp-init` | Plugin setup and external skill installation |
| Design Sync | `/homepage-plugin:hp-design-sync` | Figma design token extraction (optional, requires Figma MCP) |
| Plan | `/homepage-plugin:hp-plan` | Interactive page/section definition and planning |
| Gen | `/homepage-plugin:hp-gen` | Generate Astro pages and sections (3-phase pipeline) |
| Verify | `/homepage-plugin:hp-verify` | TypeScript, ESLint, Astro build, Lighthouse CI verification |
| Review | `/homepage-plugin:hp-review` | 2-stage code review (SEO + quality/accessibility) |
| Fix | `/homepage-plugin:hp-fix` | Fix review issues with direct fixes |

### External Skills (installed by init)

| Skill | Source | Description |
|-------|--------|-------------|
| Web Design Guidelines | `vercel-labs/agent-skills` | Accessibility/design audit (100+ rules) |
| Composition Patterns | `vercel-labs/agent-skills` | Component composition patterns (10 rules) |

## Configuration

The plugin uses `.claude/homepage-plugin.json` in the project directory (created by `/homepage-plugin:hp-init`):

```json
{
  "framework": "astro",
  "contentStrategy": "mdx",
  "i18nLocales": ["ko", "en"],
  "defaultLocale": "ko",
  "deployTarget": "aws",
  "eslintTemplate": true,
  "figmaFileKey": "abc123XYZ",
  "figmaFileUrl": "https://www.figma.com/design/abc123XYZ/..."
}
```

| Field | Description | Default |
|-------|-------------|---------|
| `framework` | Framework (reserved for future expansion) | `"astro"` |
| `contentStrategy` | Content management approach (`"mdx"` \| `"headless-cms"` \| `"both"`) | `"mdx"` |
| `i18nLocales` | Supported locale codes | `["ko", "en"]` |
| `defaultLocale` | Default locale for site and skill output language | `"ko"` |
| `deployTarget` | Deployment target (`"aws"` \| `"vercel"` \| `"netlify"` \| `"cloudflare"` \| `"static"`) | `"aws"` |
| `eslintTemplate` | Auto-generate ESLint config when none exists | `true` |
| `figmaFileKey` | (optional) Figma file key for design token extraction | — |
| `figmaFileUrl` | (optional) Full Figma file URL for reference | — |

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
│   ├── islands/                    ← React interactive components (client: directives)
│   ├── ui/                         ← shadcn/ui or Figma-derived custom components
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

## Section Catalog

15 canonical marketing sections available. Custom sections are also supported via `hp-plan`.

| Section | Type | Interactive Element |
|---|---|---|
| HeroSection | Static | — |
| FeaturesSection | Static | — |
| TestimonialsSection | Island (optional) | Carousel |
| CTASection | Static | — |
| PricingSection | Island (optional) | Monthly/yearly toggle |
| FAQSection | Island | Accordion |
| StatsSection | Static | — |
| LogoCloudSection | Static | — |
| NewsletterSection | Island | Email form |
| ContactSection | Island | Contact form + validation |
| TeamSection | Static | — |
| TimelineSection | Static | — |
| GallerySection | Island (optional) | Lightbox |
| FooterSection | Static | — |
| HeaderSection | Island | Mobile navigation |

**Static** = `.astro` component, rendered to static HTML at build time (zero JS).
**Island** = `.astro` wrapper + React `.tsx` component, hydrated via `client:load` or `client:visible`.

## Pipeline State Files

Design system files under `docs/design-system/` (created by `hp-design-sync`):

| File | Purpose |
|------|---------|
| `design-tokens.json` | Figma-extracted design tokens (colors, typography, spacing, shadows) |
| `component-map.json` | Figma component-to-code mapping (shadcn/ui equivalents) |

State files under `docs/pages/{page-name}/`:

| File | Purpose |
|------|---------|
| `page-plan.json` | Page plan with sections, SEO metadata, i18n config (input for hp-gen) |
| `.progress/{page-name}.json` | Pipeline progress tracking |
| `.implementation/homepage/generation-state.json` | Phase progress with timestamps (enables resume) |
| `.implementation/homepage/review-report.json` | Merged review results (SEO + quality) |
| `.implementation/homepage/fix-report.json` | Fix results with round tracking |
| `.implementation/homepage/.lock` | Concurrent execution prevention (auto-expires after 30 min) |

Shared layout plan: `docs/pages/_shared/layout-plan.json`

### Progress State Machine

```
planned → generated → verified → reviewed → done
             ↓    \       ↓         ↓
        gen-failed  \ verify-failed review-failed
                     \              ↓
                      → fixing → (re-review → reviewed/review-failed)
                        escalated
```

Additional transitions:
- `generated → reviewed | review-failed | done` — hp-verify is optional
- `gen-failed → verified | verify-failed` — run hp-verify after manual fixes
- `escalated → fixing | verified | reviewed` — after manual intervention, re-enter pipeline

### State File Safety

- **Lock mechanism**: Skills that modify state files acquire `.lock` before starting. Prevents concurrent execution of hp-gen/hp-fix/hp-review on the same page. Stale locks (>30 min) are auto-removed. Lock format: JSON with `lockedBy`, `lockedAt`, `pageName`.
- **Read-Modify-Write rule**: Always read latest file content before writing. Merge only changed fields — preserve all existing fields.
- **Resume support**: `generation-state.json` tracks completed phases/pages with timestamps for precise resume detection.
- **Staleness detection**: validate-pages.sh warns when page plans are edited after code generation.

## Hooks

The plugin registers two lifecycle hooks that run automatically:

### SessionStart — `session-init.sh`

Runs when a Claude Code session starts. Checks for:
- **Configuration**: Loads `.claude/homepage-plugin.json` and reports current settings
- **Missing skills**: Warns if any external skills are not installed
- **Pipeline status**: Scans all pages and reports their current state with next-step guidance:
  - `planned` → suggests `hp-gen`
  - `generated` → suggests `hp-verify` or `hp-review`
  - `gen-failed` → suggests retry `hp-gen`
  - `verify-failed` → suggests review errors
  - `review-failed` → suggests `hp-fix` then `hp-review`
  - `fixing` → suggests `hp-review` (re-review)
  - `escalated` → warns about manual intervention needed
  - `done` → reports completion

### PostToolUse — `validate-pages.sh`

Runs after every `Write` or `Edit` tool call. Only activates on files under `docs/pages/`:
- **Staleness detection**: If a page plan or state file is edited while implementation status is post-planned, warns that generated code may be out of sync

## Communication Language

Skills read `defaultLocale` from the configuration file. All user-facing output (summaries, questions, feedback, next-step guidance) is in the configured locale language.

Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese.

## Tips & Best Practices

- **Describe content, not structure** — When defining pages in `hp-plan`, describe what content you want to show ("customer testimonials", "pricing table") rather than HTML structure. The planner matches your descriptions to the section catalog.

- **Provide Figma references** — If you have Figma designs, pass a screenshot to `hp-plan`. The AI vision analysis extracts concrete details (colors, spacing, content) into section props.

- **Static by default** — Don't request React islands unless genuine interactivity is needed. Static `.astro` sections produce zero JavaScript and the best Lighthouse scores.

- **Review SEO before deploying** — Always run `hp-review` before deployment. The SEO review catches missing meta tags, broken structured data, and heading hierarchy issues that directly affect search rankings.

- **Don't skip re-review after fixes** — Always run `hp-review` after `hp-fix`. The fix-review cycle ensures no regressions.

- **Resume is safe** — If generation is interrupted, just re-run `hp-gen`. It detects completed phases and pages, then resumes from the last incomplete point.

- **Lock protects your state** — Don't run `hp-gen` and `hp-fix` on the same page simultaneously. The lock mechanism prevents state file corruption.

- **Add pages incrementally** — After initial generation, use `hp-plan {page-name}` to add new pages one at a time without affecting existing pages.

## Roadmap

- [x] Tech stack specification (Astro 5 + Tailwind + shadcn/ui)
- [x] Section catalog (15 canonical marketing sections)
- [x] Interactive page planning (hp-plan)
- [x] Code generation (3-phase pipeline)
- [x] SEO verification (Lighthouse CI)
- [x] 2-stage code review (SEO + quality/accessibility)
- [x] Fix skill (direct fixes)
- [x] State consistency (lock, timestamps, resume)
- [x] Hook handlers (session-init, page validation)
- [x] Figma MCP integration (automated design sync via hp-design-sync)
- [ ] Blog template library (pre-built MDX layouts)
- [ ] CMS adapter templates (Sanity, Contentful)
- [ ] Performance monitoring integration (Web Analytics, Sentry)

## Directory Structure

```
agents/          Agent definitions (design-token-extractor, page-planner, section-generator,
                 page-assembler, seo-reviewer, quality-reviewer, review-fixer)
skills/          Skill entry points (hp-init, hp-design-sync, hp-plan, hp-gen, hp-verify,
                 hp-review, hp-fix)
hooks/           Lifecycle hook configuration
scripts/         Hook handler scripts (session-init.sh, validate-pages.sh)
templates/       Template files (section-catalog, page-module, seo-checklist, eslint-config,
                 astro-conventions, custom-components)
docs/            Documentation
```

## Author

Justin Choi — Ohmyhotel & Co
