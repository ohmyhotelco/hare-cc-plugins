---
name: hp-plan
description: "Interactively define pages and sections for a homepage project, then generate page plans."
argument-hint: "[page-name]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Page Planning Skill (Interactive Definition)

Interactively gathers page and section definitions from the user, then launches the page-planner agent to produce structured plans.

Pages and sections are NOT predefined — this skill collects definitions through conversation.

## Instructions

### Step 0: Read Configuration

Read `.claude/homepage-plugin.json`. If not found, instruct the user to run `/homepage-plugin:hp-init` first and exit.

Read `defaultLocale` — all user-facing output must be in this language.

### Step 1: Check Existing Plans

Scan `docs/pages/*/page-plan.json` for existing page plans. If plans exist, show the current page list and ask if the user wants to:
- **Add a new page** — continue to Step 2 with the new page only
- **Replace all** — clear existing plans and start fresh
- **Edit a specific page** — re-plan one page

If the user provides a `[page-name]` argument, plan only that page (skip to Step 4 for that page).

### Step 2: Site Purpose

Ask: "What kind of site is this?"

Suggestions:
- Company homepage
- Product/service landing page
- Portfolio/showcase
- Corporate/enterprise site
- Startup landing page

The answer influences default page suggestions in Step 3.

### Step 3: Page Definition

Ask: "What pages do you need?"

Suggest defaults based on site purpose:
- **Company homepage**: Home, About, Services, Contact, Blog
- **Product landing**: Home, Features, Pricing, FAQ, Contact
- **Portfolio**: Home, Work, About, Contact
- **Corporate**: Home, About, Services, Team, Careers, Contact, Blog

The user can add, remove, or rename pages. Confirm the final page list.

### Step 4: Per-Page Section Definition

For each page, ask: "What content should this page show?"

The user describes content in natural language. Examples:
- "메인 슬로건과 CTA 버튼, 핵심 서비스 3개, 고객 후기, 상담 신청 유도"
- "Hero with company vision, timeline of our history, team member cards, partner logos"

Match descriptions to the section catalog (15 canonical types from `templates/section-catalog.md`):

| User Description | Matched Section |
|---|---|
| 메인 슬로건, hero, banner | HeroSection |
| 서비스 소개, features, 핵심 기능 | FeaturesSection |
| 고객 후기, testimonials, 리뷰 | TestimonialsSection |
| CTA, 상담 신청, 문의 유도 | CTASection |
| 가격, pricing, 요금제 | PricingSection |
| FAQ, 자주 묻는 질문 | FAQSection |
| 실적, 수치, stats | StatsSection |
| 파트너, 로고, clients | LogoCloudSection |
| 뉴스레터, 구독 | NewsletterSection |
| 문의 폼, contact form | ContactSection |
| 팀 소개, team | TeamSection |
| 연혁, timeline, history | TimelineSection |
| 갤러리, gallery, 포트폴리오 | GallerySection |

Propose the matched sections with order. The user can:
- Confirm the composition
- Reorder sections
- Add custom sections (describe what they need)
- Remove sections

Display the proposed composition:
```
┌─ Home Page ──────────────────────────────────┐
│  1. HeroSection      — Main slogan + CTA     │
│  2. FeaturesSection   — 3 core services       │
│  3. StatsSection      — Performance metrics   │
│  4. TestimonialsSection — Customer reviews     │
│  5. CTASection        — Consultation CTA      │
└──────────────────────────────────────────────┘
```

### Step 5: Shared Layout Definition

#### 5.1 Check for Figma-Extracted Layout

Read `docs/pages/_shared/layout-plan.json` if it exists.

If the file exists and contains `_figmaSource.populated === true`, the layout was pre-populated from Figma by `hp-design-sync`. Display the pre-populated layout to the user:

```
Layout pre-populated from Figma design:

Header:
  Logo: [extracted from Figma] ✓
  Nav items: Home, About, Services, Contact
  CTA: "Get Started"

Footer:
  Description: "Company tagline"
  Link groups: Product (4 links), Company (3 links)
  Social: Twitter, LinkedIn, GitHub
  Copyright: 2026
```

Ask the user to choose:
1. **Use as-is** — keep the Figma-extracted layout without changes
2. **Modify** — edit specific parts (nav items, links, social media URLs, etc.) while keeping the overall structure
3. **Start fresh** — discard the Figma-extracted layout and define from scratch

- If **Use as-is**: skip to Step 6 (no further layout questions)
- If **Modify**: present each section (header, footer) for editing. Pre-fill all fields with the Figma-extracted values. The user can:
  - Change nav item labels and add real href values (Figma-extracted hrefs are placeholders)
  - Add or remove nav items
  - Edit footer link groups, add/remove links
  - Add real social media URLs (Figma-extracted are `"#"` placeholders)
  - Change company name and description
  - Write the modified layout plan back to `docs/pages/_shared/layout-plan.json`, preserving `_figmaSource` metadata
- If **Start fresh**: proceed to Step 5.2

#### 5.2 Manual Layout Definition

If no Figma-extracted layout exists, or the user chose "Start fresh":

Ask: "How should the header and footer be structured?"

Gather:
- **Header**: logo, navigation menu items, optional CTA button, mobile nav toggle
- **Footer**: column structure, links, social media icons, copyright text

Write the layout plan to `docs/pages/_shared/layout-plan.json`.

### Step 6: Figma Reference (Optional)

Ask: "Do you have a Figma design for reference? (screenshot path or URL — optional)"

- If provided as a file path: the page-planner agent will analyze the image
- If provided as a URL: note for reference (no auto-fetch)
- If skipped: proceed with description-based planning

### Step 7: Launch Page Planner

For each page defined, launch the `page-planner` agent with:
- `pageName` — page identifier
- `pageDescription` — user's description
- `sections` — matched section list with descriptions
- `figmaRef` — Figma reference (if provided)
- `layoutPlan` — path to layout plan
- `projectRoot` — project root
- `outputFile` — `docs/pages/{page-name}/page-plan.json`
- `config` — homepage-plugin configuration

Create progress file at `docs/pages/{page-name}/.progress/{page-name}.json`:
```json
{
  "page": "{page-name}",
  "implementation": {
    "status": "planned",
    "plannedAt": "{ISO timestamp}"
  }
}
```

### Step 8: Display Summary

Show:
- Total pages planned
- Sections per page
- Shared sections (reused across pages)
- Interactive islands identified
- Next step: "Run `/homepage-plugin:hp-gen` to generate code."

If planning a single page: "Run `/homepage-plugin:hp-gen {page-name}` to generate this page."

## Communication Language

Read `defaultLocale` from `.claude/homepage-plugin.json`:
- `ko` → All questions, suggestions, and summaries in Korean
- `en` → All in English
- `vi` → All in Vietnamese
