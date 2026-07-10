# Hare CC Plugins

> **Ohmyhotel & Co** Claude Code plugins mono-repo

A collection of Claude Code plugins that cover the full software delivery lifecycle — from functional specification through production code generation, marketing site creation, and legacy migration.

## Plugins

### [Planning Plugin](./planning-plugin/) `v1.5.1`

Automates functional specification creation through multi-agent collaboration. An analyst gathers requirements, a planner reviews UX/business logic, and a tester evaluates edge cases — iterating through review cycles until the spec converges. Supports multilingual output (en/ko/vi), UI DSL generation, Stitch wireframes, and clickable React prototypes.

**Pipeline**: `spec` → `design` (DSL + wireframes) → `prototype` → `review` → `translate` → `sync-notion`

**Key features**:
- 8-category structured requirements gathering
- Sequential planner → tester review cycles with convergence scoring
- UI DSL → Google Stitch wireframe → standalone React prototype pipeline
- Domain-specific design system generation (B2B Admin, Hotel/Travel)
- Notion page sync via MCP

---

### [Frontend React Plugin](./frontend-react-plugin/) `v2.0.0`

Generates production-ready React code from functional specifications using strict Test-Driven Development. Each feature goes through a 6-phase TDD pipeline (types → API → stores → components → pages → integration), followed by automated 2-stage code review and E2E browser testing. Serves two app profiles — **admin** (B2B admin SPA, the default) and **ota** (SEO-critical consumer app); the profile sets defaults for the stack knobs below, each independently overridable, with full backward compatibility.

**Pipeline**: `fe-plan` → `fe-gen` (TDD) → `fe-verify` → `fe-review` ↔ `fe-fix` → `fe-e2e`

**Key features**:
- Strict Red-Green-Refactor TDD with per-phase agent isolation
- 2-stage review: spec compliance (5 dimensions) + code quality (8 dimensions, incl. simplicity/over-engineering)
- Delta regeneration — incremental spec changes without full rebuild
- E2E testing via agent-browser (admin) or Playwright (ota)
- **admin**: React Router v7 (declarative/data, Vite SPA), Zustand + Axios, native forms, Intl
- **ota**: React Router v7 framework mode (per-route SSR/SSG/SPA), TanStack Query, RHF + zod, dayjs
- React 19, TypeScript, shadcn/ui, MSW v2, i18next across both profiles

---

### [Homepage Plugin](./homepage-plugin/) `v1.1.0`

Generates marketing homepage websites from interactive page/section definitions. Optimized for static-first content sites with Astro's islands architecture — zero JS by default, interactive components hydrated only where needed.

**Pipeline**: `hp-plan` → `hp-gen` → `hp-verify` (Lighthouse CI) → `hp-review` ↔ `hp-fix`

**Key features**:
- 15 canonical marketing sections (hero, pricing, FAQ, testimonials, etc.)
- SEO-first: static HTML, JSON-LD structured data, sitemap, meta tags
- Figma design system integration: optional MCP sync extracts design tokens and auto-generates custom components
- 3-stage review: SEO compliance (6 dimensions) + quality/accessibility (6+1 dimensions) + visual fidelity comparison against Figma screenshots (5 sub-dimensions, conditionally blocking)
- Astro 5, Tailwind CSS, shadcn/ui, Content Collections (MDX + optional headless CMS)
- Lighthouse CI auditing (target: 90+ on all categories)

---

### [Backend Spring Boot Plugin](./backend-springboot-plugin/) `v0.3.1`

Develops Spring Boot backend applications using CQRS architecture and strict Test-Driven Development. Features a full pipeline with verification gate, review-fix loop, systematic debugging, and pipeline state tracking — modeled after the frontend-react-plugin's mature orchestration patterns.

**Pipeline**: `be-init` → `be-crud` → `be-code` (TDD) → `be-verify` → `be-review` ↔ `be-fix` → `be-commit`

**Key features**:
- CQRS scaffold generation (Entity, Command/Query, Executor/Processor, Controller, Migration)
- Strict RED-GREEN TDD with work document scenario tracking
- Verification gate (build + checkstyle + tests) before review
- Review-fix loop: 6-dimension code review + TDD-disciplined auto-fix + re-review
- Systematic debugging with 4-phase hypothesis-test methodology
- Pipeline state machine with feature-level progress tracking
- Java 21, Spring Boot 4.x, Gradle, PostgreSQL, JPA, Flyway, JUnit 5

---

### [Frontend Migration Plugin](./frontend-migration-plugin/) `v0.11.0`

Drives the migration of legacy Angular 15 apps (OhMyHotel PC, Mobile, Hana) to React Router v7 using the Strangler Fig pattern. Analyzes Angular source, extracts framework-agnostic shared packages, generates RR v7 pages via TDD, and gates each page on legacy parity before flipping traffic page-by-page. Fully standalone — its own agents and pipeline — sharing the frontend-react-plugin stack conventions.

**Pipeline**: `fm-init` → `fm-analyze` → `fm-extract` → (`fm-style-spec` → `fm-plan` → `fm-gen` → `fm-verify` → `fm-e2e` → `fm-parity` → `fm-route`) ↔ `fm-fix`

**Key features**:
- Angular→React mapping catalog grounded in the real source (Facade→hook, NgRx Effect→TanStack Query, NgbModal→shadcn Dialog, ControlValueAccessor→RHF, `| i18next`→`t()`)
- Three legacy-parity gates: technical (build/tsc/vitest), Playwright E2E (legacy dual-run + staging payment gateways), and parity (visual regression/contract freeze/WebView/telemetry)
- Strangler Fig route flip with 2-PR feature flags, refused until all gates pass
- Incremental re-migration (`fm-delta`) on legacy drift; `shared-domain` secret boundary enforced by lint
- Playwright for E2E + visual regression (matching frontend-react-plugin's ota profile; the admin profile there defaults to agent-browser)

---

## How They Work Together

```
planning-plugin                 frontend-react-plugin
     │                                │
     ├── spec + screens + tests ──────┤
     ├── UI DSL ──────────────────────┤
     └── prototype (reference) ───────┘
                                      │
                                      └── production React code (TDD)

planning-plugin                 backend-springboot-plugin
     │                                │
     └── (independent) ───────────────┘
                                      │
                                      └── Spring Boot API (CQRS + TDD)

planning-plugin                 homepage-plugin
     │                                │
     └── (independent) ───────────────┘
                                      │
                                      └── marketing site (Astro)
```

- **planning-plugin → frontend-react-plugin**: Specs, UI DSL, and prototypes flow from planning to frontend code generation. The frontend plugin can also run standalone without planning-plugin.
- **backend-springboot-plugin**: Operates independently with its own work document system and TDD workflow. Does not require planning-plugin.
- **homepage-plugin**: Operates independently with its own interactive planning. Does not require planning-plugin.

## Installation

```
# 1. Register this repo as a marketplace source
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. Install plugins (project scope)
/plugin install planning-plugin@ohmyhotelco --scope project
/plugin install frontend-react-plugin@ohmyhotelco --scope project
/plugin install backend-springboot-plugin@ohmyhotelco --scope project
/plugin install homepage-plugin@ohmyhotelco --scope project
/plugin install frontend-migration-plugin@ohmyhotelco --scope project
```

## Management

```
# Update marketplace to get latest plugin versions
/plugin marketplace update ohmyhotelco

# Uninstall a plugin
/plugin uninstall planning-plugin@ohmyhotelco --scope project
```

Open `/plugin` for the full management UI (Discover, Installed, Marketplaces tabs).

> **Note**: planning-plugin bundles Figma and Notion MCP servers. After installation, run `/mcp` and authenticate each server via OAuth. See the [planning-plugin README](./planning-plugin/) for details.

## License

MIT License
