# frontend-v2-plugin — maintainer notes

This file is for people editing the plugin. It is **not loaded into any agent's context** (plugin-root
`CLAUDE.md` files are not injected); shared rules for agents live in `skills/v2-shared/SKILL.md` and are
preloaded through each agent's `skills:` frontmatter. Do not put agent-facing rules here.

- Plugin-relative paths in agent and skill bodies use `${CLAUDE_PLUGIN_ROOT}`; launches use
  `subagent_type: "frontend-v2-plugin:<agent>"`, because the Agent tool rejects a bare plugin agent name.
- After editing: `claude plugin validate frontend-v2-plugin` and `scripts/check-plugin-consistency.py frontend-v2-plugin`; bump `version` in `plugin.json`, the marketplace entry and the root README label together.

## Fork notes

Forked from `frontend-react-plugin` 2.4.3 for an **existing** multi-app React Router monorepo. The
sections below this one describe the inherited greenfield pipeline and still apply where nothing here
overrides them.

- Agent-facing monorepo rules are in `skills/v2-shared/SKILL.md` § Monorepo Rules (excluded paths,
  several apps in one config, per-app Node via `scripts/node-env.sh`, product rules in the product
  repo's `rulesDir`, Codex). `v2-shared` is close to the 20,000-character limit: new agent rules go to
  `skills/v2-shared/references/` with a pointer.
- `v2-init` Step 0 (`skills/v2-init/references/monorepo.md`) detects the apps and writes the per-app
  config. Examples there use invented names (`apps/web`, `@acme/ui`); keep it that way.
- Standalone reviews take `--base`; `scripts/changed-lines.sh` is the only place a diff is computed.
  Agents never run `git`.
- Added agents: `codex-auditor`, `secret-auditor` (adapted from `frontend-migration-plugin`).
- **No product facts in this plugin.** Paths, package names, ports, flows and rule text of a real
  product belong in that product's repo (`docs/rules/`, its committed config). Run the root
  `scripts/check-public-repo.sh` and the wider scan in the root `CLAUDE.md` before every PR, and read
  every hit.
- Change mode (ticket → change to existing code): `templates/change-plan.md` is the contract;
  `skills/v2-plan/references/change.md` drives it; v2-gen runs it through the delta path per owner.
- Run records: `{runsDir}/{feature}/` (default `docs/plugin-runs`), local unless `commitRuns: true`; `{specRoot}` resolves a
  planning-plugin spec or the run's own `spec/`. Gate records: `templates/gate-record.md`,
  `scripts/gate-record.sh`.
- Per-app layout: `apps.{app}.layout` (v2-shared § Monorepo Rules).

## App Profiles

The plugin serves two greenfield profiles, selected by `appProfile` in `.claude/frontend-v2-plugin.json`
(default `admin`). A profile only sets **defaults** for the individual stack knobs (`routerMode`,
`serverState`, `formStack`, `e2eTool`, date convention); every knob stays independently overridable.

| Profile | Target | Router | Server state | Forms | E2E | Dates |
| --- | --- | --- | --- | --- | --- | --- |
| **admin** (default) | B2B admin SPA | declarative / data (Vite SPA) | Zustand + Axios | native | agent-browser | Intl |
| **ota** | SEO-critical consumer app | **framework** (per-route SSR/SSG/SPA) | **TanStack Query** + thin Zustand | **RHF + zod** | **Playwright** | **dayjs** |

**Backward compatibility is a hard rule.** A config with none of the new keys reads as
`appProfile=admin`, `serverState=zustand-only`, `formStack=native`, `e2eTool=agent-browser` — every
existing admin project behaves exactly as before. New behavior is gated behind the new config values; no
existing branch changes. The full design and per-file spec is in
`frontend-react-plugin/docs/design/ota-extension-phase1.md` in the parent plugin (OTA extension, Phase 1).

## Tech Stack

### Runtime & Build
- Node.js 22.x LTS (>= 22.12)
- Package Manager: pnpm
- Build: Vite
- Language: TypeScript (strict)

### Core Framework
- React 19.x
- Routing: React Router v7 — mode is determined by the `routerMode` setting in `.claude/frontend-v2-plugin.json` (default: declarative)
  - declarative: uses `<BrowserRouter>`, `<Routes>`, `<Route>` (Vite SPA)
  - data: uses `createBrowserRouter`, `RouterProvider`, loader/action (Vite SPA)
  - framework: file-based `routes.ts` + `react-router.config.ts`, per-route SSR/SSG/SPA (`react-router build`/`dev`, typegen). The ota-profile default. Build commands and test harness differ — see the **Router-mode command matrix** in `skills/v2-shared/SKILL.md`.
  - import: `react-router` (not `react-router-dom`)
  - Detailed routing patterns: see `.claude/skills/react-router-{routerMode}-mode` (installed by `/frontend-v2-plugin:v2-init`; `framework` → `react-router-framework-mode`)

### UI Layer
- Tailwind CSS
- Component library: determined by `componentLibrary` (default `shadcn`)
  - `shadcn` — shadcn/ui (Radix-based, code owned by the project) + Lucide icons (`lucide-react`; consider Simple Icons for brand logos)
  - `external` — a published design-system package (`externalComponents.package`, optional `cssEntry` preset) plus an app-owned `{uiKitDir}/` for the primitives it lacks (planned as **gap** components). No shadcn, no lucide; `forbiddenImports[]` prefixes are convention violations. Design: the parent plugin's `docs/design/ota-extension-phase2.md` (D14).

### State & Data
- Client State: determined by `clientStore` (default `zustand`)
  - `zustand` — thin Zustand stores (auth token, user, permissions, UI/client state)
  - `none` — no store library: component state, URL state, or existing app contexts; the planner emits no `stores[]` and `store-tdd` is always skipped (D17)
- Server State: determined by `serverState` (default `zustand-only`)
  - `zustand-only` — server data flows through Axios services + Zustand stores (admin default, current behavior)
  - `tanstack-query` — TanStack Query owns server state (caching, refetch, infinite lists, mutation + invalidation); Zustand holds **only** UI/client state, never server data (ota default). Layering + the loader↔query contract: `templates/server-state.md`.
- API layer: determined by `apiLayer` (default `feature-local`)
  - `feature-local` — each feature generates its own Axios service (+ `api/queries.ts` under `tanstack-query`)
  - `workspace-package` — the app consumes a workspace package of data hooks (`apiPackage.package`); the planner reuses its exports first (`api[].reuse[]`) and writes only the missing endpoints **into the package** (`api[].additions[]`, tested with the package's own Vitest). App code never imports `axios` directly. Requires `tanstack-query` (D15).
- HTTP: Axios
  - request interceptor: inject JWT Authorization header
  - response interceptor: 401 → logout/re-authenticate, 403 → sync permissions
  - **framework mode**: the Axios setup splits into a **base client** (baseURL + typed methods, no browser deps — loader/`entry.server`-safe) and a **browser wrapper** (adds the JWT/localStorage interceptors, client-only). Loaders import only the base client. `VITE_*` is client-public; server-only config uses non-`VITE_` `process.env`.
- Mock: MSW v2 (dev & test) — network-level intercept, no production code changes. Framework mode adds `{baseDir}/mocks/node.ts` for dev-time SSR-loader interception (see Mock-First Development in `skills/v2-shared/SKILL.md`).
- Forms: determined by `formStack` (default `native`)
  - `native` — native form handling / manual validation (admin default, current behavior)
  - `rhf-zod` — react-hook-form + zod (`@hookform/resolvers`); zod schemas derived from spec validation rules, `zodResolver`, shadcn Form primitives, `t()` error messages (ota default)
- (Future consideration) Auto-generate types/client when REST OpenAPI is available

### Internationalization (i18n)
- Binding: determined by `i18nBinding` (default `react-i18next`)
  - `react-i18next` — `useTranslation(namespace)`, per-feature locale JSON, central config registration
  - `custom-hook` — a project-owned hook or language-first function (`i18nHook.hook` from `i18nHook.from`, shape `i18nHook.call`) over one flat resource file per language (`i18nHook.resourcesDir` + `resourceFile`); the integration phase **appends** new keys to those files under the app lock and registers nothing. Values are real copy, never `[LANG]` placeholders — languages without a spec translation are agent-translated and listed in `i18n-review.md` (D16/D19).
- i18next + react-i18next (default binding)
- Languages: ko / en / ja / vi (default; `i18n.languages` may add e.g. `zh`)
  > Note: planning-plugin supports 3 spec languages (en/ko/vi). The additional `ja` in the frontend i18n is for application UI only — Japanese specs are not supported by planning-plugin.
- Namespace separation (common, menu, per-feature)
- Lazy-load via Vite import.meta.glob
- Language selection: stored in localStorage
- Date/time: profile-aware — **admin**: `Intl.DateTimeFormat` / `Intl.RelativeTimeFormat` (targeting latest Chrome); **ota**: `dayjs` (+ `locale` ko/en/ja/vi, `utc`, `timezone` plugins) for check-in/out dates, hotel-local timezones, locale-aware ranges (D12). Currency is `Intl.NumberFormat` in both profiles.
- **SSR i18n (framework mode)**: a **per-request** `i18next.createInstance()` in `entry.server` (a module-scope instance leaks locale across concurrent SSR requests); locale precedence URL prefix > cookie > `Accept-Language`; the resolved locale + initial resources are serialized to the client so hydration matches; `meta` title/description keys are translated server-side with the same request instance.

### Auth / RBAC
- Server makes the final RBAC decision
- Frontend role: menu filtering, route guard (/forbidden), syncing with 401/403 server responses
- Do not implement permission logic on the frontend (UX guard level only)

### Testing
- Unit/Component: Vitest — detailed test patterns: see `.claude/skills/vitest` (installed by `/frontend-v2-plugin:v2-init`)
- API mock with MSW server (Vitest integration) — reuse feature handlers in tests
- E2E: determined by `e2eTool` (default `agent-browser`)
  - `agent-browser` — AI-agent native browser automation (admin default). External skill `agent-browser`, permission `Bash(agent-browser *)`.
  - `playwright` — Playwright test runner (ota default): `playwright.config.ts` `webServer` owns the dev server, trace-first failure reports (`npx playwright show-trace`, CLI-built-in), fixture-based auth/state setup. No loadable skill; permission `Bash(npx playwright *)`. Ported from the migration plugin's harness minus legacy dual-run. See `templates/e2e-playwright.md`.
- Framework-mode page unit-tests target the extracted **page-body component** (Testing Library); `createRoutesStub` is used only for components using router hooks — never for route modules typed with generated `Route.*` types (RR documents that gap). The route module itself is covered by typegen + build + E2E smoke.

## Architecture
- **Agents**:
  - `implementation-planner` — spec analysis → implementation plan (plan.json)
  - `foundation-generator` — types + mock infrastructure generation (no TDD)
  - `tdd-cycle-runner` — strict Red-Green TDD cycle per phase (api, store, component, page)
  - `integration-generator` — routes + i18n + MSW global setup + full verification
  - `spec-reviewer` — spec compliance review
  - `quality-reviewer` — code quality review (pipeline and standalone modes)
  - `security-auditor` — frontend security vulnerability audit (XSS, auth tokens, secrets, client-side data safety)
  - `test-reviewer` — test quality audit (assertion patterns, Testing Library, async, coverage, timing, anti-patterns)
  - `review-fixer` — TDD-disciplined review issue fixer (supports review and E2E fix modes)
  - `delta-modifier` — incremental spec change applier (modifies existing files per delta-plan.json)
  - `e2e-test-runner` — E2E test execution via `e2eTool` (agent-browser or Playwright)
  - `debugger` — systematic debugging
- **Skills**: `/frontend-v2-plugin:v2-init`, `/frontend-v2-plugin:v2-plan`, `/frontend-v2-plugin:v2-gen` (TDD coordinator), `/frontend-v2-plugin:v2-verify`, `/frontend-v2-plugin:v2-review` (reviews generated source code — not to be confused with `/planning-plugin:pp-review` which reviews the specification document), `/frontend-v2-plugin:v2-fix`, `/frontend-v2-plugin:v2-e2e` (E2E testing), `/frontend-v2-plugin:v2-debug`, `/frontend-v2-plugin:v2-progress` (pipeline status dashboard), `/frontend-v2-plugin:v2-security` (security audit), `/frontend-v2-plugin:v2-clean-code` (clean code audit), `/frontend-v2-plugin:v2-test-review` (test quality audit)
- **External Skills**: `react-router-*-mode` (from `remix-run/agent-skills`; `framework` → `react-router-framework-mode`), `vitest` (from `antfu/skills`), `vercel-react-best-practices` + `vercel-composition-patterns` + `web-design-guidelines` (from `vercel-labs/agent-skills`), `agent-browser` (from `vercel-labs/agent-browser`, installed only when `e2eTool == agent-browser`) — installed by init. Playwright ships no loadable skill (trace analysis is CLI-built-in).
- **Configuration**: `.claude/frontend-v2-plugin.json` (created by `/frontend-v2-plugin:v2-init`)
- **Templates**: `feature-module.md` (feature module structure + framework-mode variants), `tdd-rules.md` (TDD rules adapted from obra/superpowers), `eslint-config.md` (ESLint v9 fallback config), `prettier-config.md` (Prettier 3 fallback config — advisory), `i18n-key-coverage.md` (app-wide key-coverage spec contract), `e2e-testing.md` (agent-browser E2E patterns), `e2e-playwright.md` (Playwright E2E patterns), `framework-app-shell.md` (RR framework app shell: config/root/routes/entries), `server-state.md` (TanStack Query ↔ loader layering contract)

### Testing (Strict TDD)

TDD methodology adapted from [obra/superpowers](https://github.com/obra/superpowers). See `templates/tdd-rules.md` for full rules.

- **Test first**: No production code without a failing test first
- **Red-Green-Refactor**: Write test → verify failure → write minimal code → verify pass → refactor
- **Verify RED/GREEN**: Run vitest and check the output.
- **Phase-level TDD**: Each layer (api, store, component, page) runs a separate TDD cycle in its own agent session
- **Stub-first for imports**: Create minimal stubs so tests fail on assertions, not on MODULE_NOT_FOUND

Test infrastructure:
- Test file location: `{baseDir}/features/{feature}/__tests__/`
- Test types: api (MSW server), component (@testing-library/react), page (4-state coverage), store (unit)
- Factory usage: generate test data from `../mocks/factories`
- MSW server: import from `@/mocks/server`, setup with `beforeAll/afterEach/afterAll`
- Source tracking: reference spec test scenario with `// TS-nnn` comment in each test

Anti-patterns (from obra/superpowers testing-anti-patterns):
- Never test mock behavior — assert on component output or return values
- Never add test-only methods to production classes
- Never mock without understanding dependency side effects
- Never create incomplete mocks — MSW responses must match full TypeScript interfaces
- Mock only at network boundary (MSW) — use real stores, real components

### E2E Testing (Agent-Browser)

- agent-browser drives headless Chromium via CLI commands (snapshot, click, fill, get, wait, screenshot)
- MSW Service Worker intercepts API calls in the browser (`VITE_ENABLE_MOCKS=true`)
- E2E scenarios defined in `plan.json` `e2eTests[]`, mapped to TS-nnn from `test-scenarios.md`
- E2E results tracked in `progress.json` under `implementation.e2e`
- Dev server auto-started/stopped by `v2-e2e` skill
- 2-stage pipeline: review loop (code quality) completes first, then E2E loop (user flows)
- `v2-fix` auto-detects fix mode (review vs E2E) by comparing report timestamps
- After E2E fixes, if code changes were significant, consider re-running `v2-review`
- Dynamic route parameters (`:id`) must be resolved to fixture IDs before navigation — see `agents/e2e-test-runner.md` § Dynamic Route Parameter Resolution
- E2E scenario updates: when screens/routes change after initial plan, re-run `/frontend-v2-plugin:v2-plan {feature}` to regenerate `e2eTests[]` in plan.json, then `/frontend-v2-plugin:v2-e2e {feature}`. Manual edits to `e2eTests[]` are allowed but will be overwritten on next v2-plan run.
- E2E test reference: `templates/e2e-testing.md` (plugin patterns) + `.claude/skills/agent-browser/SKILL.md` (CLI commands)
- E2E permissions: `v2-init` adds `Bash(agent-browser *)` to `.claude/settings.json` `permissions.allow` — required because the e2e-test-runner runs as a sub-agent and session-level approvals do not transfer to sub-agents

Pipeline (2-stage loops):
- Loop 1 (Quality): `/frontend-v2-plugin:v2-gen` → `/frontend-v2-plugin:v2-verify` → `/frontend-v2-plugin:v2-review` ↔ `/frontend-v2-plugin:v2-fix` (until review passes)
- Loop 2 (E2E): `/frontend-v2-plugin:v2-e2e` ↔ `/frontend-v2-plugin:v2-fix` (until E2E passes) → done
- `/frontend-v2-plugin:v2-debug` remains for runtime bugs at any point
- `v2-fix` auto-detects fix mode (review vs E2E) by comparing report timestamps

### Delta Regeneration (Incremental Spec Changes)

When a spec is modified after code has been generated and reviewed, delta regeneration preserves accumulated fixes while applying only the changes.

- **Trigger**: `v2-plan` auto-detects existing plan.json + generated code → offers incremental mode
- **Detection**: implementation-planner compares old plan.json `source` fields against current spec → identifies added/modified/removed spec elements (FR-nnn, screen IDs, TS-nnn, etc.)
- **Delta file**: `{runsDir}/{feature}/delta-plan.json` — describes affected files with `create`/`modify`/`remove` operations per phase
- **Execution**: `v2-gen` detects delta-plan.json → executes only affected phases, skipping unchanged ones
  - `create` operations → tdd-cycle-runner (scoped to new files only)
  - `modify`/`remove` operations → delta-modifier agent (targeted Edit on existing files, TDD for behavioral changes)
- **Cascade**: changes cascade downward (types → api → stores → components → pages → routes/i18n). Implementation-planner computes the full cascade using plan.json cross-references.
- **Safety**: large deltas (>60% of files affected) trigger a warning suggesting full regeneration. User always chooses between incremental and full.
- **After delta**: plan.json is patched with `planJsonPatch`, delta-plan.json is archived as `delta-plan.{timestamp}.json`
- **Pipeline continues**: v2-verify → v2-review → v2-fix → v2-e2e (unchanged)

Delta pipeline:
```
spec change → v2-plan (incremental) → delta-plan.json
           → v2-gen (delta) → affected files only
           → v2-verify → v2-review → v2-fix → v2-e2e (normal pipeline)
```

Key files:
- `agents/delta-modifier.md` — modifies existing files per delta-plan.json (review-fixer pattern)
- `agents/implementation-planner.md` § Phase 3 — incremental mode spec diff + cascade computation

### Code Generation (TDD Phases)
- Feature spec source: `{specRoot}/` (planning-plugin output)
- **Standalone mode**: `v2-plan {feature} --standalone` for interactive requirements gathering — no planning-plugin required. Generates a minimal spec stub and plan.json. Limitations: no error codes, validation rules, test scenario references (TS-nnn), or UI DSL.
- Implementation plan: `{runsDir}/{feature}/plan.json` — includes `workingLanguage` and `localesDir` for downstream agents
- Generation state: `{runsDir}/{feature}/generation-state.json` (tracks phase progress, enables resume)
- UI DSL first: use structured data from `ui-dsl/` if available, otherwise infer from spec markdown
- Feature-based structure: `{baseDir}/features/{feature}/` (types, api, stores, components, pages, __tests__)
- Prototypes are for reference only: do not copy code from `prototypes/{feature}/` into production code
- TDD phase execution order:
  1. `foundation` — types + mocks (foundation-generator agent, no TDD)
  2. `api-tdd` — API tests → API services (tdd-cycle-runner agent)
  3. `store-tdd` — store tests → stores (tdd-cycle-runner agent)
  4. `component-tdd` — component tests → components (tdd-cycle-runner agent)
  5. `page-tdd` — page tests → pages (tdd-cycle-runner agent)
  6. `integration` — routes + i18n + MSW global + barrel (integration-generator agent)
- Each TDD phase runs in a separate agent session for context isolation
- Each phase runs isolated — see `skills/v2-shared/SKILL.md` § Design Principles, "Subagent isolation"
- External skills loaded per-phase (not all at once): vitest for TDD phases, composition-patterns for components, react-best-practices for pages, router for integration
- Resume support: if generation is interrupted, re-running v2-gen resumes from the last incomplete phase

### Shared Layouts
- Shared layout location: `{baseDir}/layouts/{PascalCaseLayoutId}.tsx`
- Mapping: `@layout: _shared/{layout-id}` in spec → `{baseDir}/layouts/{PascalCaseLayoutId}.tsx` in production
- Slot component → `<Outlet />` from react-router
- Features do NOT import layout directly — relationship expressed via React Router nested routes
- First feature: generates layout + feature code
- Subsequent features: reuses existing layout, optionally adds nav items

### Route & i18n Auto-Integration
- Each feature generates `routes.tsx` (route definitions) and `i18n.ts` (namespace registration) in its feature directory — under `i18nBinding: custom-hook` there is no `i18n.ts`; the integration phase appends the feature's flat keys to the shared resource files instead (D16)
- Integration-generator auto-integrates by adding import + spread to the central route file and i18n config (same pattern as MSW handler aggregation)
- Supports declarative mode (`<Route>` JSX fragments) and data mode (`RouteObject[]` arrays)
- Layout route nesting: spreads feature routes under existing layout route's children when present
- Graceful fallback: if the central file has unexpected structure, falls back to manual guidance
- The implementation-planner detects aggregation patterns, insertion anchors, and existing imports in plan.json

### Debug & Progress
- Debug report: `{runsDir}/{feature}/debug-report.json`
- Verification/review results: recorded in `implementation.verification`, `implementation.review` fields of `{runsDir}/{feature}/progress.json`
- Review report: `{runsDir}/{feature}/review-report.json`
- Fix report: `{runsDir}/{feature}/fix-report.json`
- E2E report: `{runsDir}/{feature}/e2e-report.json`
- Delta plan: `{runsDir}/{feature}/delta-plan.json` (active delta, archived as `delta-plan.{timestamp}.json` after execution)

### Standalone Audit Skills

Independent audit skills that run outside the pipeline. No progress tracking, no lock files, no feature context required.

| Skill | Purpose |
|-------|---------|
| `/frontend-v2-plugin:v2-security` | Security vulnerability audit (XSS, auth tokens, secrets, client-side data safety) |
| `/frontend-v2-plugin:v2-clean-code` | Clean code audit (8 quality dimensions — standalone mode of quality-reviewer) |
| `/frontend-v2-plugin:v2-test-review` | Test quality audit (assertions, Testing Library, async patterns, coverage, timing) |

Usage: `v2-security [path]`, `v2-clean-code [path]`, `v2-test-review [test-path]`

These skills are completely independent of the pipeline (v2-plan → v2-gen → v2-verify → v2-review → v2-fix → v2-e2e). They can be run at any time on any code, not just pipeline-generated features.

### Progress State Machine

- Progress state machine:
  ```
  planned → generated → verified → reviewed → done
               ↓    ↘       ↓         ↓    ↓
           gen-failed  ↘ verify-failed ↓  review-failed
                        ↘     ↓        ↓      ↓
                         → resolved  fixing → (re-review → reviewed/review-failed)
                           escalated    ↓  ↘ generated (regen-required → v2-gen)
                              ↓    escalated
                        (manual intervention)
  ```
  Additional transitions:
  - `generated → reviewed | review-failed | done` — v2-verify is optional, can go directly to v2-review
  - `verify-failed → reviewed | review-failed | done` — v2-review accepts verify-failed, user can review without fixing verification first
  - `gen-failed → generated | gen-failed` — re-run v2-gen (resume or restart)
  - `gen-failed → resolved | escalated` — v2-debug on partially generated code
  - `fixing → reviewed | review-failed` — after v2-fix, v2-review determines next status
  - `fixing → generated` — when regen-required issues exist, v2-gen re-run resets to generated
  - `resolved → verified | verify-failed` — re-verify after debug resolution
  - `resolved → reviewed | review-failed` — re-review after debug resolution
  - `resolved → fixing | escalated` — v2-fix after debug resolution (when review issues remain)
  - `resolved → generated | gen-failed` — re-run v2-gen after debug resolution (when previousStatus was gen-failed)
  - `escalated` — requires manual intervention, then re-enter pipeline via v2-fix, v2-verify, or v2-review
  - Status determination on partial generation: any skipped or failed phase → `gen-failed` (prevents incomplete code from entering review pipeline)

## File Structure

```
.claude-plugin/  - Plugin manifest
agents/          - Agent definitions
skills/          - Skill entry points
hooks/           - Hook configuration
scripts/         - Hook handler scripts
templates/       - Template files
docs/            - Documentation
```

### Generated Project Structure

```
{baseDir}/
├── layouts/           ← Shared layouts (cross-feature, uses <Outlet />)
├── features/{feature}/
│   ├── routes.tsx     ← Feature route definitions (auto-integrated)
│   ├── i18n.ts        ← Feature i18n registration (auto-integrated)
│   └── ...            ← types, api, stores, components, pages, __tests__
├── components/ui/     ← shadcn/ui components (componentLibrary: shadcn)
├── ui-kit/            ← app-owned primitives + form adapters (componentLibrary: external)
├── mocks/             ← Global MSW setup
├── locales/           ← i18n JSON files
└── ...
```

## Project-Level Configuration

`.claude/frontend-v2-plugin.json` (created by `/frontend-v2-plugin:v2-init`):
```json
{
  "appProfile": "admin",
  "routerMode": "declarative",
  "serverState": "zustand-only",
  "formStack": "native",
  "e2eTool": "agent-browser",
  "mockFirst": true,
  "baseDir": "app/src",
  "appDir": "app",
  "eslintTemplate": true,
  "prettierTemplate": true,
  "i18n": { "languages": ["ko", "en", "ja", "vi"], "lookupFns": ["t"] }
}
```

An **ota** config instead reads (with `renderingDefault` present only in framework mode):
```json
{
  "appProfile": "ota",
  "routerMode": "framework",
  "serverState": "tanstack-query",
  "formStack": "rhf-zod",
  "e2eTool": "playwright",
  "renderingDefault": "ssr",
  "devPort": 5173,
  "mockFirst": true,
  "baseDir": "app/app",
  "appDir": "app",
  "eslintTemplate": true
}
```

An ota app that owns an external design system, a workspace data package and a flat shared i18n bundle (Phase 2) adds:
```json
{
  "componentLibrary": "external",
  "externalComponents": { "package": "@acme/components", "cssEntry": "@acme/tailwind-preset", "uiKitDir": "app/app/ui-kit", "forbiddenImports": ["@acme/ui"] },
  "apiLayer": "workspace-package",
  "apiPackage": { "package": "@acme/data", "dir": "packages/data", "entry": "packages/data/src/index.ts", "clientImport": "~/lib/api-client" },
  "i18nBinding": "custom-hook",
  "i18nHook": { "hook": "useI18n", "from": "~/lib/i18n", "resourcesDir": "packages/i18n/src/locales", "resourceFile": "{LANG}/translation.json" },
  "clientStore": "none",
  "i18n": { "languages": ["ko", "en", "ja", "zh", "vi"], "lookupFns": ["t"] }
}
```

- `appProfile`: `"admin"` (default when absent) | `"ota"` — sets defaults for the knobs below; each stays overridable. See "App Profiles".
- `routerMode`: `"declarative"` (default) | `"data"` | `"framework"` — determines React Router v7 mode. `framework` enables per-route SSR/SSG/SPA (see the command matrix in `skills/v2-shared/SKILL.md`).
- `serverState`: `"zustand-only"` (default when absent) | `"tanstack-query"` — server-state strategy.
- `componentLibrary`: `"shadcn"` (default when absent) | `"external"` — with `externalComponents` (`package`, `cssEntry`, `uiKitDir`, `formAdapters`, `forbiddenImports[]`). Phase 2, D14/D18.
- `apiLayer`: `"feature-local"` (default when absent) | `"workspace-package"` — with `apiPackage` (`package`, `dir`, `entry`, `clientImport`). Requires `tanstack-query`. Phase 2, D15.
- `i18nBinding`: `"react-i18next"` (default when absent) | `"custom-hook"` — with `i18nHook` (`hook`, `from`, `call`, `resourcesDir`, `resourceFile`). `from` and `apiPackage.clientImport` may be an import specifier or a repo-relative file path; `call` is `hook` (default) or `language-first` — see `skills/v2-shared/SKILL.md` § Monorepo Rules, Import values. Phase 2, D16/D19.
- `clientStore`: `"zustand"` (default when absent) | `"none"`. Requires `tanstack-query`. Phase 2, D17.
- `formStack`: `"native"` (default when absent) | `"rhf-zod"` — form approach.
- `e2eTool`: `"agent-browser"` (default when absent) | `"playwright"` — E2E runner.
- `renderingDefault`: framework mode only — `"ssr"` (default) | `"ssg"` | `"spa"` — fallback rendering for a page whose plan does not specify one. Per-page decisions live in `plan.json` `pages[].rendering`.
- `mockFirst`: `true` (default) | `false` — whether to enable MSW v2 mock-first development
- `baseDir`: `"app/src"` (default) | custom path — base directory for generated source code. All `{baseDir}` references in documentation resolve to this value. Framework mode's RR source root is the `app/` dir (e.g. `app/app`). When absent, falls back to `"src"` for backward compatibility.
- `appDir`: auto-derived from `baseDir` — the directory containing `vite.config.*` / `react-router.config.ts`, `tsconfig.json`, and `package.json`. All build/test commands run from this directory. Derivation: strip a `/src` **or** `/app` suffix from `baseDir` (`app/src` → `app`, `app/app` → `app`, `src` → `"."`, `packages/web/src` → `packages/web`). When absent, falls back to `"."` (project root).
- `devPort`: optional, default `5173` — the dev-server port `v2-e2e` uses and (in Playwright mode) foundation's Step 5c bakes into `playwright.config.ts` `webServer`. One value, one source: v2-gen and v2-e2e both read it from config with the same default, so the scaffolded config and the runner always agree. Set it when 5173 is taken — with `reuseExistingServer`, an unrelated service already on the port would otherwise be treated as the app under test.
- `eslintTemplate`: `true` (default) | `false` — whether to auto-generate `eslint.config.js` from the bundled template when no ESLint config exists. Set to `false` to skip ESLint in projects without their own config.
- `prettierTemplate`: `true` (default) | `false` — whether to auto-generate `prettier.config.js` + `.prettierignore` from `templates/prettier-config.md` when no Prettier config exists. Formatting is **advisory** and never fails a gate. See "Lint & Format Gate" in `skills/v2-shared/SKILL.md`.
- `i18n`: **optional, no default** — the product's copy surface, which is not `workingLanguage`. `languages` is what "every supported language" resolves to for the key-coverage spec; `lookupFns` (default `["t"]`) are the helpers whose literal keys are checked. Absent → `foundation-generator` generates no key-coverage spec and `v2-verify` reports that axis as `skipped`, never a silent pass. Never inferred from the locale directory. See "i18n Key Coverage" in `skills/v2-shared/SKILL.md`.
