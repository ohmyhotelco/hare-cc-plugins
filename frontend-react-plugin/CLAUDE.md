# Frontend React Plugin

A Claude Code plugin that applies tech stack and coding conventions for frontend React development.

## App Profiles

The plugin serves two greenfield profiles, selected by `appProfile` in `.claude/frontend-react-plugin.json`
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
`docs/design/ota-extension-phase1.md` (OTA extension, Phase 1).

## Tech Stack

### Runtime & Build
- Node.js 22.x LTS (>= 22.12)
- Package Manager: pnpm
- Build: Vite
- Language: TypeScript (strict)

### Core Framework
- React 19.x
- Routing: React Router v7 — mode is determined by the `routerMode` setting in `.claude/frontend-react-plugin.json` (default: declarative)
  - declarative: uses `<BrowserRouter>`, `<Routes>`, `<Route>` (Vite SPA)
  - data: uses `createBrowserRouter`, `RouterProvider`, loader/action (Vite SPA)
  - framework: file-based `routes.ts` + `react-router.config.ts`, per-route SSR/SSG/SPA (`react-router build`/`dev`, typegen). The ota-profile default. Build commands and test harness differ — see the **Router-mode command matrix** below.
  - import: `react-router` (not `react-router-dom`)
  - Detailed routing patterns: see `.claude/skills/react-router-{routerMode}-mode` (installed by `/frontend-react-plugin:fe-init`; `framework` → `react-router-framework-mode`)

### UI Layer
- Tailwind CSS
- shadcn/ui (Radix-based, code owned by the project)
- Icons: Lucide (`lucide-react`), consider adding Simple Icons when brand logos are needed

### State & Data
- Client State: Zustand (keep thin — auth token, user, permissions, UI/client state)
- Server State: determined by `serverState` (default `zustand-only`)
  - `zustand-only` — server data flows through Axios services + Zustand stores (admin default, current behavior)
  - `tanstack-query` — TanStack Query owns server state (caching, refetch, infinite lists, mutation + invalidation); Zustand holds **only** UI/client state, never server data (ota default). Layering + the loader↔query contract: `templates/server-state.md`.
- HTTP: Axios
  - request interceptor: inject JWT Authorization header
  - response interceptor: 401 → logout/re-authenticate, 403 → sync permissions
  - **framework mode**: the Axios setup splits into a **base client** (baseURL + typed methods, no browser deps — loader/`entry.server`-safe) and a **browser wrapper** (adds the JWT/localStorage interceptors, client-only). Loaders import only the base client. `VITE_*` is client-public; server-only config uses non-`VITE_` `process.env`.
- Mock: MSW v2 (dev & test) — network-level intercept, no production code changes. Framework mode adds `{baseDir}/mocks/node.ts` for dev-time SSR-loader interception (see Mock-First below).
- Forms: determined by `formStack` (default `native`)
  - `native` — native form handling / manual validation (admin default, current behavior)
  - `rhf-zod` — react-hook-form + zod (`@hookform/resolvers`); zod schemas derived from spec validation rules, `zodResolver`, shadcn Form primitives, `t()` error messages (ota default)
- (Future consideration) Auto-generate types/client when REST OpenAPI is available

### Internationalization (i18n)
- i18next + react-i18next
- Languages: ko / en / ja / vi
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
- Unit/Component: Vitest — detailed test patterns: see `.claude/skills/vitest` (installed by `/frontend-react-plugin:fe-init`)
- API mock with MSW server (Vitest integration) — reuse feature handlers in tests
- E2E: determined by `e2eTool` (default `agent-browser`)
  - `agent-browser` — AI-agent native browser automation (admin default). External skill `agent-browser`, permission `Bash(agent-browser *)`.
  - `playwright` — Playwright test runner (ota default): `playwright.config.ts` `webServer` owns the dev server, trace-first failure reports (`npx playwright show-trace`, CLI-built-in), fixture-based auth/state setup. No loadable skill; permission `Bash(npx playwright *)`. Ported from the migration plugin's harness minus legacy dual-run. See `templates/e2e-playwright.md`.
- Framework-mode page unit-tests target the extracted **page-body component** (Testing Library); `createRoutesStub` is used only for components using router hooks — never for route modules typed with generated `Route.*` types (RR documents that gap). The route module itself is covered by typegen + build + E2E smoke.

## Conventions
- Use only shadcn/ui components (do not install alternative component libraries)
- 2-space indentation
- functional component + hooks
- Define TypeScript interface for all props/data
- icon-only button: aria-label required, decorative icon: aria-hidden="true"
- form control: must associate with <label> (htmlFor or wrapping)
- variable-length text: apply truncate / line-clamp-*
- full-page layout: set full height chain from html → body → #root → layout

### Mock-First Development
- `mockFirst: true` (default) — develop with MSW v2 without a backend
- Feature-level mock: `{baseDir}/features/{feature}/mocks/` (factories + fixtures + handlers)
- Factory + Fixture separation: factory generates data for tests, fixture provides fixed data for MSW handlers
- Hardcoded mock data — do not use external libraries like faker
- Environment variable toggle: activate only in dev mode with `VITE_ENABLE_MOCKS=true`
- Global MSW: `{baseDir}/mocks/` (browser.ts, server.ts, handlers.ts aggregator)

### Performance & Composition
- React performance patterns: see `.claude/skills/vercel-react-best-practices` (waterfall elimination, bundle optimization, re-render minimization)
  - **Router-mode conditional**: in `declarative`/`data` (Vite SPA) the server-side (RSC/SSR) rules do not apply — agent auto-skips. In `framework` mode the app is **not** a Vite SPA (per-route SSR/SSG), so the SSR/rendering-strategy rules **do apply** — do not skip them.
- Component composition patterns: see `.claude/skills/vercel-composition-patterns` (no boolean props, compound component, React 19 API)
- Web UI accessibility/design audit: see `.claude/skills/web-design-guidelines` (WebFetch latest guidelines during review)

### ESLint
- The plugin bundles a default ESLint v9 flat config template (`templates/eslint-config.md`)
- Config includes `strictTypeChecked` + `stylisticTypeChecked` presets, native flat config for react-hooks and react-refresh, and test file overrides
- When a project has no ESLint config (`.eslintrc*` or `eslint.config.*`), agents auto-generate `eslint.config.js` from the template
- `eslintTemplate` flag in `.claude/frontend-react-plugin.json` controls this behavior (`true` by default, `false` to opt out)
- Dependencies are NOT auto-installed — agents display `pnpm add -D ...` instructions and skip ESLint if packages are missing

### Routing Conventions
- Routes requiring authentication: wrap with `<ProtectedRoute>` → redirect to /login when unauthenticated (pass return destination via location.state.from)
- Routes requiring permissions: `<RoleRoute permissions={[...]}>` → redirect to /forbidden when unauthorized
- NavLink active state: use shadcn/ui `cn()` + `isActive` callback
- Axios 401 interceptor → /login redirect: use navigate ref pattern (do not directly import useNavigate)
- URL searchParams ↔ Zustand: bidirectional sync via useEffect + store subscription
- Internal navigation: use react-router `<Link>`, `<NavLink>`, `useNavigate` (do not use `<a>`, `window.location`)

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
- **Skills**: `/frontend-react-plugin:fe-init`, `/frontend-react-plugin:fe-plan`, `/frontend-react-plugin:fe-gen` (TDD coordinator), `/frontend-react-plugin:fe-verify`, `/frontend-react-plugin:fe-review` (reviews generated source code — not to be confused with `/planning-plugin:pp-review` which reviews the specification document), `/frontend-react-plugin:fe-fix`, `/frontend-react-plugin:fe-e2e` (E2E testing), `/frontend-react-plugin:fe-debug`, `/frontend-react-plugin:fe-progress` (pipeline status dashboard), `/frontend-react-plugin:fe-security` (security audit), `/frontend-react-plugin:fe-clean-code` (clean code audit), `/frontend-react-plugin:fe-test-review` (test quality audit)
- **External Skills**: `react-router-*-mode` (from `remix-run/agent-skills`; `framework` → `react-router-framework-mode`), `vitest` (from `antfu/skills`), `vercel-react-best-practices` + `vercel-composition-patterns` + `web-design-guidelines` (from `vercel-labs/agent-skills`), `agent-browser` (from `vercel-labs/agent-browser`, installed only when `e2eTool == agent-browser`) — installed by init. Playwright ships no loadable skill (trace analysis is CLI-built-in).
- **Configuration**: `.claude/frontend-react-plugin.json` (created by `/frontend-react-plugin:fe-init`)
- **Templates**: `feature-module.md` (feature module structure + framework-mode variants), `tdd-rules.md` (TDD rules adapted from obra/superpowers), `eslint-config.md` (ESLint v9 fallback config), `e2e-testing.md` (agent-browser E2E patterns), `e2e-playwright.md` (Playwright E2E patterns), `framework-app-shell.md` (RR framework app shell: config/root/routes/entries), `server-state.md` (TanStack Query ↔ loader layering contract)

### Communication Language
- Feature-level skills (fe-plan, fe-gen, fe-verify, fe-review, fe-fix, fe-e2e, fe-debug, fe-progress) read `workingLanguage` from `docs/specs/{feature}/.progress/{feature}.json`
- All user-facing output (summaries, questions, feedback, next-step guidance) must be in the working language
- Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

### Testing (Strict TDD)

TDD methodology adapted from [obra/superpowers](https://github.com/obra/superpowers). See `templates/tdd-rules.md` for full rules.

- **Iron Law**: No production code without a failing test first
- **Red-Green-Refactor**: Write test → verify failure → write minimal code → verify pass → refactor
- **Verify RED/GREEN are MANDATORY**: Actually run vitest and check the output. Never skip.
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
- Dev server auto-started/stopped by `fe-e2e` skill
- 2-stage pipeline: review loop (code quality) completes first, then E2E loop (user flows)
- `fe-fix` auto-detects fix mode (review vs E2E) by comparing report timestamps
- After E2E fixes, if code changes were significant, consider re-running `fe-review`
- Dynamic route parameters (`:id`) must be resolved to fixture IDs before navigation — see `agents/e2e-test-runner.md` § Dynamic Route Parameter Resolution
- E2E scenario updates: when screens/routes change after initial plan, re-run `/frontend-react-plugin:fe-plan {feature}` to regenerate `e2eTests[]` in plan.json, then `/frontend-react-plugin:fe-e2e {feature}`. Manual edits to `e2eTests[]` are allowed but will be overwritten on next fe-plan run.
- E2E test reference: `templates/e2e-testing.md` (plugin patterns) + `.claude/skills/agent-browser/SKILL.md` (CLI commands)
- E2E permissions: `fe-init` adds `Bash(agent-browser *)` to `.claude/settings.json` `permissions.allow` — required because the e2e-test-runner runs as a sub-agent and session-level approvals do not transfer to sub-agents

Pipeline (2-stage loops):
- Loop 1 (Quality): `/frontend-react-plugin:fe-gen` → `/frontend-react-plugin:fe-verify` → `/frontend-react-plugin:fe-review` ↔ `/frontend-react-plugin:fe-fix` (until review passes)
- Loop 2 (E2E): `/frontend-react-plugin:fe-e2e` ↔ `/frontend-react-plugin:fe-fix` (until E2E passes) → done
- `/frontend-react-plugin:fe-debug` remains for runtime bugs at any point
- `fe-fix` auto-detects fix mode (review vs E2E) by comparing report timestamps

### Delta Regeneration (Incremental Spec Changes)

When a spec is modified after code has been generated and reviewed, delta regeneration preserves accumulated fixes while applying only the changes.

- **Trigger**: `fe-plan` auto-detects existing plan.json + generated code → offers incremental mode
- **Detection**: implementation-planner compares old plan.json `source` fields against current spec → identifies added/modified/removed spec elements (FR-nnn, screen IDs, TS-nnn, etc.)
- **Delta file**: `docs/specs/{feature}/.implementation/frontend/delta-plan.json` — describes affected files with `create`/`modify`/`remove` operations per phase
- **Execution**: `fe-gen` detects delta-plan.json → executes only affected phases, skipping unchanged ones
  - `create` operations → tdd-cycle-runner (scoped to new files only)
  - `modify`/`remove` operations → delta-modifier agent (targeted Edit on existing files, TDD for behavioral changes)
- **Cascade**: changes cascade downward (types → api → stores → components → pages → routes/i18n). Implementation-planner computes the full cascade using plan.json cross-references.
- **Safety**: large deltas (>60% of files affected) trigger a warning suggesting full regeneration. User always chooses between incremental and full.
- **After delta**: plan.json is patched with `planJsonPatch`, delta-plan.json is archived as `delta-plan.{timestamp}.json`
- **Pipeline continues**: fe-verify → fe-review → fe-fix → fe-e2e (unchanged)

Delta pipeline:
```
spec change → fe-plan (incremental) → delta-plan.json
           → fe-gen (delta) → affected files only
           → fe-verify → fe-review → fe-fix → fe-e2e (normal pipeline)
```

Key files:
- `agents/delta-modifier.md` — modifies existing files per delta-plan.json (review-fixer pattern)
- `agents/implementation-planner.md` § Phase 3 — incremental mode spec diff + cascade computation

### Code Generation (TDD Phases)
- Feature spec source: `docs/specs/{feature}/` (planning-plugin output)
- **Standalone mode**: `fe-plan {feature} --standalone` for interactive requirements gathering — no planning-plugin required. Generates a minimal spec stub and plan.json. Limitations: no error codes, validation rules, test scenario references (TS-nnn), or UI DSL.
- Implementation plan: `docs/specs/{feature}/.implementation/frontend/plan.json` — includes `workingLanguage` and `localesDir` for downstream agents
- Generation state: `docs/specs/{feature}/.implementation/frontend/generation-state.json` (tracks phase progress, enables resume)
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
- **Subagent isolation principle**: subagents never inherit session history. The coordinator constructs only the parameters each agent needs — no conversation context leaks between phases. This prevents context pollution and ensures fresh judgment per task.
- External skills loaded per-phase (not all at once): vitest for TDD phases, composition-patterns for components, react-best-practices for pages, router for integration
- Resume support: if generation is interrupted, re-running fe-gen resumes from the last incomplete phase

### Shared Layouts
- Shared layout location: `{baseDir}/layouts/{PascalCaseLayoutId}.tsx`
- Mapping: `@layout: _shared/{layout-id}` in spec → `{baseDir}/layouts/{PascalCaseLayoutId}.tsx` in production
- Slot component → `<Outlet />` from react-router
- Features do NOT import layout directly — relationship expressed via React Router nested routes
- First feature: generates layout + feature code
- Subsequent features: reuses existing layout, optionally adds nav items

### Route & i18n Auto-Integration
- Each feature generates `routes.tsx` (route definitions) and `i18n.ts` (namespace registration) in its feature directory
- Integration-generator auto-integrates by adding import + spread to the central route file and i18n config (same pattern as MSW handler aggregation)
- Supports declarative mode (`<Route>` JSX fragments) and data mode (`RouteObject[]` arrays)
- Layout route nesting: spreads feature routes under existing layout route's children when present
- Graceful fallback: if the central file has unexpected structure, falls back to manual guidance
- The implementation-planner detects aggregation patterns, insertion anchors, and existing imports in plan.json

### Debug & Progress
- Debug report: `docs/specs/{feature}/.implementation/frontend/debug-report.json`
- Verification/review results: recorded in `implementation.verification`, `implementation.review` fields of `docs/specs/{feature}/.progress/{feature}.json`
- Review report: `docs/specs/{feature}/.implementation/frontend/review-report.json`
- Fix report: `docs/specs/{feature}/.implementation/frontend/fix-report.json`
- E2E report: `docs/specs/{feature}/.implementation/frontend/e2e-report.json`
- Delta plan: `docs/specs/{feature}/.implementation/frontend/delta-plan.json` (active delta, archived as `delta-plan.{timestamp}.json` after execution)

### Standalone Audit Skills

Independent audit skills that run outside the pipeline. No progress tracking, no lock files, no feature context required.

| Skill | Purpose |
|-------|---------|
| `/frontend-react-plugin:fe-security` | Security vulnerability audit (XSS, auth tokens, secrets, client-side data safety) |
| `/frontend-react-plugin:fe-clean-code` | Clean code audit (8 quality dimensions — standalone mode of quality-reviewer) |
| `/frontend-react-plugin:fe-test-review` | Test quality audit (assertions, Testing Library, async patterns, coverage, timing) |

Usage: `fe-security [path]`, `fe-clean-code [path]`, `fe-test-review [test-path]`

These skills are completely independent of the pipeline (fe-plan → fe-gen → fe-verify → fe-review → fe-fix → fe-e2e). They can be run at any time on any code, not just pipeline-generated features.

### State File Safety

State files (progress, generation-state, review-report, fix-report, debug-report) are critical for pipeline continuity.

**Read-Modify-Write rule**: When updating state JSON files:
1. Read the **latest** file content immediately before writing (do not use data cached earlier in the session)
2. Merge only the fields being changed — preserve all existing fields
3. Write the complete merged object

**Lock file**: Skills that modify state files must acquire `docs/specs/{feature}/.implementation/frontend/.lock` before starting work. Release on completion or failure. Stale locks (older than 30 minutes) are automatically removed.

**Exception**: `fe-debug` intentionally does NOT acquire a lock — it serves as an interrupt tool usable at any pipeline stage, even when another operation holds the lock. The debugger writes `debug-report.json` and updates `implementation.status` without locking.

- Progress state machine:
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
  Additional transitions:
  - `generated → reviewed | review-failed | done` — fe-verify is optional, can go directly to fe-review
  - `verify-failed → reviewed | review-failed | done` — fe-review accepts verify-failed, user can review without fixing verification first
  - `gen-failed → generated | gen-failed` — re-run fe-gen (resume or restart)
  - `gen-failed → resolved | escalated` — fe-debug on partially generated code
  - `fixing → reviewed | review-failed` — after fe-fix, fe-review determines next status
  - `fixing → generated` — when regen-required issues exist, fe-gen re-run resets to generated
  - `resolved → verified | verify-failed` — re-verify after debug resolution
  - `resolved → reviewed | review-failed` — re-review after debug resolution
  - `resolved → fixing | escalated` — fe-fix after debug resolution (when review issues remain)
  - `resolved → generated | gen-failed` — re-run fe-gen after debug resolution (when previousStatus was gen-failed)
  - `escalated` — requires manual intervention, then re-enter pipeline via fe-fix, fe-verify, or fe-review
  - Status determination on partial generation: any skipped or failed phase → `gen-failed` (prevents incomplete code from entering review pipeline)

### Verification Philosophy

A principle applied across all agents and skills: **"Evidence before claims, always"**

#### Build Command Working Directory

All build/test tool commands (`npx vite`, `npx react-router`, `npx vitest`, `npx tsc`, `npx eslint`, `npx playwright`) must run from `{appDir}` — the directory containing `vite.config.*` / `react-router.config.ts` and `package.json`.

- Read `appDir` from `.claude/frontend-react-plugin.json`
- If `appDir` is `"."` or absent → run from project root (no prefix needed)
- Otherwise → prefix commands with `cd {projectRoot}/{appDir} &&`

Example: `baseDir: "app/src"`, `appDir: "app"` → `cd {projectRoot}/app && npx vite build 2>&1`

This applies to all agents and skills. Skills pass `appDir` to agents as a parameter.

**Framework-mode path-base rule.** `react-router.config.ts` and the generated `.react-router/` types
directory live in `{appDir}` (siblings of `vite.config.*`/`package.json`) — every scaffold, glob, check,
and edit of them resolves against `{appDir}`, never the repo root. `routes.ts`, `root.tsx`, and the
`entry.*.tsx` files live under `{baseDir}`.

#### Router-mode command matrix (single source of truth)

All agents/skills read this table instead of hard-coding a command; branch on `routerMode`.

| Concern | `declarative` / `data` (Vite SPA) | `framework` (SSR/SSG) |
| --- | --- | --- |
| Dev server | `npx vite --port {port}` | `npx react-router dev --port {port}` |
| Build | `npx vite build` | `npx react-router build` |
| Typecheck | composite-aware `tsc -b` \| `tsc --noEmit` | `npx react-router typegen` **then** the composite-aware tsc |
| Route integration target | `App.tsx` / `router.tsx` (JSX / `RouteObject[]`) | `{baseDir}/routes.ts` (+ `{appDir}/react-router.config.ts` `prerender` array) |
| Loading state | in-page `loading` state | `HydrateFallback` + `useNavigation` pending UI |
| Error state | in-page `error` state | route module `ErrorBoundary` |
| Page unit-test target | page component (`MemoryRouter`) | page-body component via Testing Library; `createRoutesStub` only for router-hook components; route module via typegen/build + E2E |
| SSR rules (vercel skill) | skip | apply |

**Runtime assumptions (framework mode, Phase 1).** Node ≥ 22; the built app runs locally via
`npx react-router-serve ./build/server/index.js`; server-only config comes from non-`VITE_`
`process.env`. The plugin verifies up to a green build + a local serve smoke and configures **no**
deployment target.

#### TypeScript Check — Composite Config Detection

Vite projects commonly use composite tsconfig with `references`. Agents must detect this and use the correct command:

1. Read `tsconfig.json` in `{appDir}` (not project root)
2. If it contains a `references` array → `npx tsc -b 2>&1`
3. Otherwise → `npx tsc --noEmit 2>&1`

> `tsc -b` checks all referenced tsconfig projects (e.g., tsconfig.app.json + tsconfig.node.json).
> `tsc --noEmit` only checks the root config scope, missing errors in build tool configs.

5-Step Gate:
1. IDENTIFY — identify the target to verify
2. RUN — execute verification tools (tsc, build, vitest, etc.)
3. READ — review the full output (exit code, error count)
4. VERIFY — determine whether the output matches the claim
5. CLAIM — report the result citing evidence

Verification Red Flags — these thoughts mean you're rationalizing (all agents):

| Thought | Reality |
|---------|---------|
| "Should work" / "probably fine" / "seems correct" | Evidence or silence. Run the tool. |
| "The change is small, no need to verify" | Small changes cause big bugs. Verify always. |
| "I already verified this earlier" | That was then. Code changed since. Verify again. |
| "tsc passed, so the build will too" | tsc ≠ vite build. Different tools catch different errors. |
| "Tests passed, so it's correct" | Tests cover what was written, not what was missed. Check the spec. |
| "I'll verify at the end" | Errors compound. Verify at each step. |
| "The error is unrelated to my change" | Prove it. Run the verification. |

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
├── components/ui/     ← shadcn/ui components
├── mocks/             ← Global MSW setup
├── locales/           ← i18n JSON files
└── ...
```

## Project-Level Configuration

`.claude/frontend-react-plugin.json` (created by `/frontend-react-plugin:fe-init`):
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
  "eslintTemplate": true
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
  "mockFirst": true,
  "baseDir": "app/app",
  "appDir": "app",
  "eslintTemplate": true
}
```

- `appProfile`: `"admin"` (default when absent) | `"ota"` — sets defaults for the knobs below; each stays overridable. See "App Profiles".
- `routerMode`: `"declarative"` (default) | `"data"` | `"framework"` — determines React Router v7 mode. `framework` enables per-route SSR/SSG/SPA (see the command matrix).
- `serverState`: `"zustand-only"` (default when absent) | `"tanstack-query"` — server-state strategy.
- `formStack`: `"native"` (default when absent) | `"rhf-zod"` — form approach.
- `e2eTool`: `"agent-browser"` (default when absent) | `"playwright"` — E2E runner.
- `renderingDefault`: framework mode only — `"ssr"` (default) | `"ssg"` | `"spa"` — fallback rendering for a page whose plan does not specify one. Per-page decisions live in `plan.json` `pages[].rendering`.
- `mockFirst`: `true` (default) | `false` — whether to enable MSW v2 mock-first development
- `baseDir`: `"app/src"` (default) | custom path — base directory for generated source code. All `{baseDir}` references in documentation resolve to this value. Framework mode's RR source root is the `app/` dir (e.g. `app/app`). When absent, falls back to `"src"` for backward compatibility.
- `appDir`: auto-derived from `baseDir` — the directory containing `vite.config.*` / `react-router.config.ts`, `tsconfig.json`, and `package.json`. All build/test commands run from this directory. Derivation: strip a `/src` **or** `/app` suffix from `baseDir` (`app/src` → `app`, `app/app` → `app`, `src` → `"."`, `packages/web/src` → `packages/web`). When absent, falls back to `"."` (project root).
- `eslintTemplate`: `true` (default) | `false` — whether to auto-generate `eslint.config.js` from the bundled template when no ESLint config exists. Set to `false` to skip ESLint in projects without their own config.
