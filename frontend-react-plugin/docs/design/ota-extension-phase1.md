# Design: OTA Extension — Phase 1 (Core Stack)

> Status: **implementation-ready — independent Codex review, 4 rounds converged** — target version **v2.0.0**
> Scope: React Router v7 **framework mode** (per-route SSR/SSG/SPA) + **TanStack Query** + **RHF + zod**
> + **Playwright E2E** (ota profile) + **dayjs** (ota profile)
> Out of scope (later phases): design-system pipeline (Phase 2), SEO / visual-fidelity gates (Phase 3),
> payment staging + secret classification + monorepo/shared-* (Phase 4).

## 1. Goal

Extend `frontend-react-plugin` from a greenfield **B2B admin SPA** generator into a plugin that can also
generate a **brand-new OTA app** (SEO-critical, data-heavy, form/transaction-heavy). Phase 1 delivers the
core stack shift; everything else builds on it.

Reference implementation for the framework-mode mechanics is `frontend-migration-plugin` (RR v7 framework
mode, SSR-aware review rules, SSR-loader mocking) — Phase 1 ports those mechanics **without** the
migration-specific machinery (no parity gates, no legacy analysis).

## 2. Key decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | New config key `appProfile: "admin" \| "ota"` (default `"admin"`). A profile only sets **defaults** for the other knobs; every knob remains individually overridable. | Keeps the existing admin capability first-class; no fork. |
| D2 | `routerMode` gains `"framework"` (existing: `declarative`, `data`). Profile defaults: admin → `declarative`, ota → `framework`. | SSR/SSG requires framework mode; library modes stay for admin SPAs. |
| D3 | New config key `serverState: "zustand-only" \| "tanstack-query"`. Defaults: admin → `zustand-only` (today's behavior), ota → `tanstack-query`. | OTA needs server-state caching (search results, availability, infinite lists). Aligned with fm's stack. |
| D4 | New config key `formStack: "native" \| "rhf-zod"`. Defaults: admin → `native` (today's behavior), ota → `rhf-zod`. | Booking/payment/guest forms need schema validation. Aligned with fm (RHF + zod). |
| D5 | Per-page rendering decision lives in **plan.json** (`pages[].rendering: "ssr" \| "ssg" \| "spa"`), not in config. Config holds only `renderingDefault` (framework mode). SSG is realized via the `prerender` array in `react-router.config.ts`; SPA pages use `clientLoader` only. **Phase 1 constraint: `ssg` is allowed only for parameterless AND loader-less routes** (pure static shells) — `prerender` needs concrete URLs and **executes loaders at build time**, where the D8 MSW hook does not apply (it is dev-server-only); a loader-carrying ssg candidate is demoted to `ssr` by the planner. Dynamic-segment enumeration and build-time data sourcing (`pages[].staticPaths`) are deferred together (O5). | Mirrors fm's per-route SSR/SSG/SPA decision (migration plan §5), but driven by the spec instead of legacy. The static-shell-only constraint keeps mock-first builds green with no backend and caps Phase 1 scope without blocking dynamic SSG later. |
| D6 | New config key `e2eTool: "agent-browser" \| "playwright"`, defaulted by profile: admin → `agent-browser` (today's behavior), ota → `playwright`. The Playwright realization ports fm's harness patterns (trace-first reports, auth/state setup, page-object reuse, MSW integration) **without** the migration-specific legacy dual-run and parity checks. | Decided (was O4): OTA needs `toHaveScreenshot` visual baselines later (Phase 3) and staging payment E2E (Phase 4) — both Playwright-only. Binding the switch to the profile now avoids generating agent-browser suites that get thrown away in Phase 3. |
| D7 | Dependencies are **never auto-installed** (existing rule). fe-init and generators print the `pnpm add` command and skip gracefully. | Consistent with the ESLint template behavior. |
| D8 | MSW in framework mode: browser worker unchanged for client fetches (bootstrapped in `entry.client.tsx` — the framework-mode equivalent of the `main.tsx` wiring); **dev-time server-side loaders** get MSW node via a guarded hook in `entry.server.tsx` only (`mocks/node.ts`, `VITE_ENABLE_MOCKS`). The hook is **module-scope and idempotent** (`globalThis` guard against HMR double-`listen()`), so `server.listen()` completes before any loader can run. **Fallback:** if the §8 interception assertion fails in any mode/build, move the MSW bootstrap to a custom dev-server entry (documented in the app-shell template) instead of weakening the guard. Unit tests keep the existing `mocks/server.ts` (msw/node) — unchanged. | Without this, mock-first development breaks the moment a loader runs on the server (fm hardened the same surface in v0.5.0). The idempotency guard is required because Vite dev re-evaluates the server entry on HMR; the ordering claim is an assumption about RR's server pipeline, hence the explicit fallback. |
| D9 | TanStack Query ↔ loader layering (v1 convention, template-documented): **SSR/SSG routes** — loader fetches via the **server-safe** API service (D13) and returns data; the component consumes `loaderData`, passing it as `initialData` to `useQuery` only when live refetch is needed. The handoff is only sound with three accompanying rules (all enforced via `templates/server-state.md`): **(a)** loader and hook share the same `queryOptions` factory (one query key, one fetcher **definition** — never hand-written twice; the factory is **fetch-client-agnostic** and receives the D13 client as an argument: loaders inject the base client, hooks the browser wrapper — so rule (a) and D13's import boundary compose rather than conflict); **(b)** loader-fed queries set an explicit `staleTime` > 0 (default 60s) — with the TanStack default `staleTime: 0`, `initialData` is immediately stale and the hook refetches on mount, reintroducing the double-fetch this contract exists to prevent; **(c)** the loader passes `initialDataUpdatedAt` (its fetch timestamp) so a previously-populated cache entry is not overwritten by staler loader data. **SPA routes, mutations, infinite lists** — pure TanStack Query. Full `dehydrate`/`HydrationBoundary` hydration is deliberately deferred (open question O2); escalate to it when nested routes must share one cache entry. | Avoids double-fetch and hydration machinery in v1 while keeping one obvious home per data need — but only with rules (a)-(c); the bare `initialData` pattern without them is a known refetch/staleness trap. |
| D10 | 4-state page pattern re-mapping in framework mode: `loading` → `HydrateFallback` + `useNavigation` pending UI; `error` → route module `ErrorBoundary`; `empty`/`success` unchanged inside the component. **Test split:** the route module is a **thin wrapper** (loader/meta/ErrorBoundary/HydrateFallback + a default export that delegates to an extracted page-body component taking loader data as props). page-tdd unit-tests the **body component** (plain Testing Library render; `createRoutesStub` only where router hooks are used — RR documents it as unsuitable for route modules with generated `Route.*` types); the route module itself is covered by typegen + `tsc` + build and the Playwright E2E smoke. | The 4 mandatory states survive; only their realization moves to route-module exports. The wrapper/body split keeps strict TDD possible where RR's test harness has a documented gap. |
| D11 | Zustand scope under `tanstack-query`: stores hold **UI/client state only** (search-form input, locale, UI toggles) — server data never enters a store. The planner enforces this at plan time. | fm's "thin Zustand" principle; prevents the query cache and stores from fighting. |
| D12 | **dayjs** (+ `locale` ko/en/ja/vi, `utc`, `timezone` plugins) is the date convention for the ota profile — check-in/out dates, hotel-local timezones, locale-aware ranges. The admin profile keeps the existing Intl-only convention. Currency stays `Intl.NumberFormat` in both profiles. | Decided (was O1): aligned with fm's stack; OTA date math (nights, ranges, hotel-local cutoffs) outgrows bare Intl, and the Phase 2 date-range picker will build on it. |
| D13 | **Server-safe API client.** The shared Axios setup is split in framework mode: a **base client** (baseURL + typed methods, no browser dependencies) usable from loaders, and a **browser wrapper** that adds the JWT/localStorage interceptors for client code. Loaders/`entry.server` code may import only the base client; `VITE_*` env vars are client-public by definition — server-only config uses non-`VITE_` `process.env` (full secret classification is Phase 4). | The existing admin interceptors touch `localStorage` and `window` — importing them in a loader crashes the server render. This is the minimum split that makes D9's "loader fetches via the API service" true. |

## 3. Configuration schema (`.claude/frontend-react-plugin.json`)

```jsonc
{
  "appProfile": "ota",              // NEW — "admin" (default when absent) | "ota"
  "routerMode": "framework",        // "declarative" | "data" | "framework" (NEW value)
  "serverState": "tanstack-query",  // NEW — "zustand-only" | "tanstack-query"
  "formStack": "rhf-zod",           // NEW — "native" | "rhf-zod"
  "e2eTool": "playwright",          // NEW — "agent-browser" | "playwright"
  "renderingDefault": "ssr",        // NEW — framework mode only: "ssr" | "ssg" | "spa"
  "mockFirst": true,
  "baseDir": "app/app",             // framework mode: the RR `app/` source dir (see below)
  "appDir": "app",
  "eslintTemplate": true
}
```

**Backward compatibility (hard requirement):** a config with none of the new keys behaves exactly as
today — `appProfile=admin`, `routerMode` as written, `serverState=zustand-only`, `formStack=native`.
Every new behavior branches off a new value; no existing branch changes.

**`baseDir`/`appDir` derivation extension:** framework mode's source root is the RR `app/` directory
inside the Vite project. New derivation rule (additive): if `baseDir` ends with `/app`, strip it for
`appDir` (`app/app` → `app`, `web/app` → `web`, bare `app` → `"."`). The existing `/src` rule is untouched.

**Path-base rule (framework mode):** `react-router.config.ts` and the generated `.react-router/` types
directory live in **`{appDir}`** — the same directory as `vite.config.*`/`package.json`; every scaffold,
glob, check, and edit of them resolves against `{appDir}`, never the repo root. `routes.ts`, `root.tsx`,
and the entry files live under `{baseDir}`.

**Dependency sets (print-only, per D7):**

| Enabled by | Packages |
|---|---|
| `routerMode: framework` | `@react-router/dev @react-router/node @react-router/serve isbot` |
| `serverState: tanstack-query` | `@tanstack/react-query` (+ `@tanstack/react-query-devtools` dev) |
| `formStack: rhf-zod` | `react-hook-form zod @hookform/resolvers` |
| `e2eTool: playwright` | `@playwright/test` (dev) + one-time `npx playwright install` (browser binaries — print, never run) |
| `appProfile: ota` | `dayjs` |

## 4. plan.json schema changes (implementation-planner)

- **Top level**: `routerMode` may now be `"framework"`; new `serverState`, `formStack` (copied from config
  so downstream agents don't re-read config).
- **`pages[]`** (currently `implementation-planner.md:715-731`): new fields
  - `rendering: "ssr" | "ssg" | "spa"` + `renderingReason` (one line).
    Planning heuristics: public, SEO-relevant content (search results, hotel/room detail, landing) → `ssr`;
    **parameterless, loader-less** content that changes rarely → `ssg` (D5 Phase 1 constraint — the
    planner must demote a dynamic-segment **or loader-carrying** ssg candidate to `ssr` and say so in
    `renderingReason`); authenticated/checkout/my-page → `spa`. `staticPaths` is **reserved** in the
    schema for the future dynamic-SSG contract (O5) and must stay unset in Phase 1.
  - `loader: { data: [apiRefs], params: [routeParams] } | null` — what the route loader fetches.
  - `meta: { titleKey }` — minimal `meta` export (full SEO gate is Phase 3).
- **`api[]`** (`:667-684`): new sibling block per entity when `serverState=tanstack-query`:
  `queries: { keysFactory, hooks: [{ name, type: "query"|"infinite"|"mutation", source, invalidates[] }] }`.
- **`components[]`**: form components gain `formSchema` (zod field specs derived from spec validation
  rules + `errorMapping`).
- **`stores[]`** (`:685-694`): under `tanstack-query` the planner must **exclude server data** (`list`,
  `selected`, `loading`, `error` of server origin) from store shapes; a page with no client-only state gets
  no store, and `store-tdd` is skipped for it (fe-gen already skips phases with no files — make this
  explicit in the phase spec).
- **`routes{}`** (`:749-772`): framework variant — `mode: "framework"`, `routesFile: "{baseDir}/routes.ts"`,
  `configFile: "react-router.config.ts"`, entries carry `file` (route module path) instead of JSX element
  refs, `autoIntegration` anchors target the `RouteConfig[]` array and the `prerender` array.
- **`buildOrder[]`** (`:911-961`): integration phase `skills: ["react-router-framework-mode"]`; verify
  gains `typegen` before `tsc`; build command is mode-aware (§6).
- **`e2eTests[]`** (`:882-910`): the step schema (`navigate`/`fill`/`click`/`verify`/`wait` +
  `target`/`value`/`expect`) is **tool-neutral and stays unchanged** — the same plan entries are realized
  either as agent-browser command sequences (today) or as Playwright specs (`e2eTool: playwright`). Only
  the realization layer (§5.9) branches.

## 5. Per-file change specification

### 5.1 `skills/fe-init/SKILL.md`

| Step | Change |
|---|---|
| NEW Step 1b | **App profile** question: `admin` (B2B admin SPA — current behavior) / `ota` (SEO-critical consumer app). Sets defaults for Steps 2, 2e, 2f, 2g. |
| Step 2 (L27-37) | Add option `framework` — "file-based `routes.ts`, per-route SSR/SSG/SPA — for SEO-critical apps". Default: by profile. |
| NEW Step 2e/2f/2g | `serverState`, `formStack`, and `e2eTool` confirmations (pre-filled by profile; admin profile keeps them silent-default to preserve the current UX). |
| Step 3 (L85-102) | Write new keys; apply the `/app` strip rule to `appDir` derivation (L88-91). |
| Step 4 (L104-125) | Skill table row L115 already interpolates `react-router-{routerMode}-mode` — works for `framework` as-is; extend the reconfig cleanup (L108-111) to the framework skill dir. |
| NEW Step 4b | **App shell check (framework only)**: glob `{appDir}/react-router.config.ts` (path-base rule, §3), `{baseDir}/root.tsx`, `{baseDir}/routes.ts`. If absent, offer to scaffold from `templates/framework-app-shell.md` (§5.10) or point to `npx create-react-router@latest`. Print the dependency `pnpm add` lines (§3) for any missing packages — never install. |
| Step 4 permissions (L127-148) | Keyed on `e2eTool`: `agent-browser` → `Bash(agent-browser *)` (as today); `playwright` → `Bash(npx playwright *)` instead. The version check (L150-158) becomes tool-aware (`npx playwright --version`). |
| Step 5-6 | Echo the new config keys in the confirmation output. |

### 5.2 `agents/implementation-planner.md`

- Input params (L21): accept `routerMode: framework`, plus `serverState`, `formStack`, `renderingDefault`.
- §2.6 / Phase 1 step 4 (L88-101): framework-mode anchor detection — central file is `{baseDir}/routes.ts`
  (RouteConfig array; spread/`prefix()` aggregation), plus `react-router.config.ts` `prerender` anchor.
  `autoIntegration=null` fallback rules unchanged.
- New §: rendering decision per page (heuristics in §4), loader planning, query-hook planning
  (`queries` block), form-schema planning (`formSchema`).
- Store planning rule (D11): server data is planned into queries, not stores.
- plan JSON example (L640-981): add the new fields; `routes.mode: "framework"` example.

### 5.3 `agents/foundation-generator.md`

- Layouts (L41-72): in framework mode a "shared layout" is realized as a **layout route module** — same
  `<Outlet />`/`NavLink` imports from `react-router` (L52-53 unchanged), but the planner records it as a
  `layout()` entry in `routes.ts` instead of a JSX wrapper. Generation itself is nearly identical.
- Types (L91-101): when `formStack=rhf-zod`, additionally generate `schemas/{entity}Schema.ts` — zod
  schemas for create/update DTOs (fields + validation from the plan); TS types may derive via `z.infer`
  where the plan says so (keep interfaces for API DTOs — schemas validate, interfaces type).
- Mocks (L102-125): when `routerMode=framework` and `mockFirst`, additionally generate
  `{baseDir}/mocks/node.ts` (`setupServer` re-using the same handler aggregate) for dev-time SSR-loader
  interception (D8). Test-infra `mocks/server.ts` unchanged.
- NEW: **Playwright harness, once per app** (when `e2eTool=playwright`, first feature only — fm's
  foundation pattern): `playwright.config.ts` (webServer = mode-aware dev command from §6 with
  `VITE_ENABLE_MOCKS=true`, trace `on-first-retry`, `e2e/` testDir) + `e2e/fixtures.ts` (auth/state-setup
  helpers) — ported from fm's harness minus legacy dual-run. **Mock-state reset policy:** handlers are
  stateless by default; the mutable fixture DB (`mockEntityDb`) is reset between tests via a dev-only
  reset hook in the harness `beforeEach`, and specs that mutate mock state run serially (dedicated
  project or `mode: 'serial'`) — the MSW-node instance is process-global, so parallel workers must not
  share mutated state.
- Deps (L74-89): print `pnpm add` lines for the §3 dependency sets when missing.

### 5.4 `agents/tdd-cycle-runner.md`

- `routerMode` param note (L26) changes from "(for page phase)" to "(page phase; framework mode also
  affects api-tdd loader targets)".
- **api-tdd** (L151-154): when `serverState=tanstack-query`, the phase covers the axios service (unchanged)
  **plus** `api/queries.ts` — query-key factory + `queryOptions` + hooks per the plan's `queries` block.
  Tests: `renderHook` with a `QueryClientProvider` wrapper (retry off, fresh client per test) against MSW.
  Reuse-ladder note: never fetch in `useEffect` when a query hook exists.
- **store-tdd** (L156-159): add the D11 scope rule ("server data lives in the query cache — a store holding
  it is a planning bug; stop and report"). Phase is skippable when the plan has no store for the feature.
- **component-tdd** (L151-157 area): when `formStack=rhf-zod` — forms use `useForm` +
  `zodResolver(schema)` + shadcn form primitives; error messages via `t()`; tests drive validation through
  `userEvent` and assert rendered messages (never call the resolver directly).
- **page-tdd** (L159-164): framework mode — the page splits into a **thin route module**
  (`loader`/`clientLoader`, `meta`, `ErrorBoundary`, `HydrateFallback`, default export) and an extracted
  **page-body component** that receives loader data as props (D10). The TDD cycle targets the body
  component: plain Testing Library render; `createRoutesStub` only for components that use router hooks
  (`useNavigation`, `Link` state) — never for the route module itself (RR documents `createRoutesStub` as
  unsuitable for modules typed with generated `Route.*` types). The route module wrapper is verified by
  typegen + tsc + build (fe-verify) and the E2E smoke, not unit tests. 4-state mapping per D10. Load
  `.claude/skills/react-router-framework-mode/SKILL.md`.
- External skills (L49): change "skip RSC/SSR" to **conditional** — skip only when `routerMode` is a
  library mode; in framework mode apply the SSR rules (same inversion fm documents).

### 5.5 `agents/integration-generator.md`

- Step 2 (L41-78): third variant — framework. Feature fragment is `features/{feature}/routes.ts` exporting
  a `RouteConfig[]` built with `route()`/`index()`/`layout()`/`prefix()` from `@react-router/dev/routes`;
  auth/permission wrapping stays in the route module components (`ProtectedRoute`/`RoleRoute` inside the
  module, not the config file). **Path rule:** route-module `file` values are always **app-root-relative**
  (exactly as recorded in plan.json) — never relative to the fragment file. RR resolves split config paths
  against the app root; a generator that emits fragment-relative paths produces broken routes (RR's
  `relative()` helper exists for hand-written configs; the generator does not need it because the planner
  already holds root-relative paths).
- Step 3 (L80-99): central integration edits `{baseDir}/routes.ts` (import + spread; layout nesting via
  `layout()` children). New: maintain the `prerender` array in `{appDir}/react-router.config.ts` (path-base
  rule, §3) from `pages[].rendering == "ssg"` entries (loader-less by D5).
- NEW Step 6b (framework + mockFirst): wire the guarded MSW-node hook into `{baseDir}/entry.server.tsx`
  (module-scope so `server.listen()` precedes any loader, `import.meta.env.DEV && VITE_ENABLE_MOCKS`,
  idempotent via a `globalThis` flag — Vite dev re-evaluates the server entry on HMR); create from
  template if the file is absent. `entry.client.tsx` gets only the **browser** worker bootstrap (D8) —
  never the node hook.
- NEW Step 6c (`serverState=tanstack-query`, **library modes**): wire the root `QueryClientProvider`
  into `{baseDir}/main.tsx` (same guarded-edit + manual-fallback pattern as the MSW bootstrap). Framework
  mode gets the provider via the app-shell `root.tsx` (§5.10). This closes the D1 override matrix — any
  router mode may enable tanstack-query.
- Step 8 verification (L171-220): build command becomes mode-aware — framework: `npx react-router build`;
  typecheck prefixed by `npx react-router typegen` (generated types in `.react-router/`). Library modes
  unchanged (`npx vite build`).
- Checklist L284-285 ("RSC/SSR Skip — Vite SPA"): make conditional on router mode.

### 5.6 `skills/fe-verify/SKILL.md`

- Step 2.1 (L83-104): framework mode — run `npx react-router typegen 2>&1` before the composite-aware tsc.
- Step 2.3 (L136-143): framework mode — `npx react-router build 2>&1` instead of `npx vite build`.
- Everything else (ESLint, vitest, status transitions, lock) unchanged.

### 5.7 `agents/quality-reviewer.md`, `agents/spec-reviewer.md`

- quality-reviewer Phase 0-P (L37-42): load `react-router-{routerMode}-mode` — already interpolated; add:
  in framework mode **do not skip** the RSC/SSR rules of `vercel-react-best-practices` (L39 becomes
  conditional). New convention checks under 1.6/1.2: route-module export shape (thin wrapper + body
  component per D10); no server-only imports reachable from client components; **no browser-only globals
  (`localStorage`, `window`) reachable in the server-render path** — loaders import only the base client
  (D13); `serverState=tanstack-query` → no `useEffect` fetching, no server data in Zustand stores,
  loader-fed queries carry explicit `staleTime`/`initialDataUpdatedAt` (D9 a-c); `formStack=rhf-zod` →
  forms use zodResolver (no ad-hoc validation); ota profile → date handling via dayjs, no hand-rolled
  date math (D12).
- Standalone mode Phase 0-S (L49-58): read the new config keys.
- spec-reviewer: no change (route coverage logic is mode-agnostic).

### 5.8 Small mode-aware touches

| File | Change |
|---|---|
| `agents/review-fixer.md` (L26, 65-66, 201) | framework skill load; conditional SSR-skip; mode-aware build cmd |
| `agents/delta-modifier.md` (L25, 81-82, 214) | same |
| `agents/debugger.md` (L21, 32, 125) | same |
| `skills/fe-gen/SKILL.md` (L19, 212, 243, 274, 481, 543) | pass `serverState`/`formStack`/`rendering` through to phase agents; empty-store-phase skip rule |
| `skills/fe-plan/SKILL.md` (L17, 191, 257, 279) | pass new config keys to planner |
| `scripts/session-init.sh` (L24, 31) | verify no enum validation blocks `framework` (interpolation at L31 already generic) |

### 5.9 E2E toolchain (`e2eTool`) — `skills/fe-e2e/SKILL.md`, `agents/e2e-test-runner.md`, `skills/fe-fix/SKILL.md`

Ported from fm's Playwright harness (e2e-test-runner + `templates/e2e-testing.md`), **excluding** the
legacy dual-run, parity hooks, and staging payment gateways (payments arrive in Phase 4).

- **`skills/fe-e2e/SKILL.md`** — branch on `e2eTool`:
  - `agent-browser` (admin default): unchanged, except the dev-server launch (L134) becomes mode-aware
    (framework → `VITE_ENABLE_MOCKS=true npx react-router dev --port {port}`).
  - `playwright` (ota default): no manual dev-server management — `playwright.config.ts` `webServer`
    owns it. Run `npx playwright test e2e/{feature} 2>&1` from `{appDir}`; on failure, collect the trace
    paths from the report for fe-fix. e2e-report.json schema stays the same (per-scenario pass/fail +
    evidence), so `fe-progress`/`fe-fix` consumers are untouched.
- **`agents/e2e-test-runner.md`** — playwright mode: realize `plan.json e2eTests[]` steps as Playwright
  specs under `{appDir}/e2e/{feature}/{TS-nnn}.spec.ts` (step mapping: `navigate`→`page.goto`,
  `fill`→`getByLabel/getByRole().fill`, `click`→`getByRole().click`, `verify`→`expect(...)`,
  `wait`→web-first assertions, never bare timeouts); reuse `e2e/fixtures.ts` for auth/state setup;
  page-object reuse per fm's pattern; dynamic route params resolved from fixtures (existing rule kept).
  Trace-first evidence: cite the trace file in the report.
- **`skills/fe-fix/SKILL.md`** (e2e-fix mode, L190 area): when `e2eTool=playwright`, the failure evidence
  is the Playwright trace (`npx playwright show-trace` is CLI-built-in — fm's primary self-correction
  input); review-fixer receives trace-derived failure context instead of agent-browser logs.
- **`fe-init` / CLAUDE.md**: agent-browser external skill installed only when `e2eTool=agent-browser`;
  the E2E reference template is `templates/e2e-playwright.md` (§5.10) for the playwright path.

### 5.10 Templates

- **`templates/feature-module.md`** — add framework-mode variants: route-module page example
  (loader + `meta` + `ErrorBoundary` + `HydrateFallback` + default export), feature `routes.ts` fragment,
  central `routes.ts` + `react-router.config.ts` examples; add `api/queries.ts` example (key factory +
  `queryOptions` + hooks + invalidation); **replace** the form example (L159-215) with the `rhf-zod`
  variant when `formStack=rhf-zod` (zodResolver + shadcn Form + `t()` errors), keeping the native variant
  for admin; thin-store example without server data (D11); page test example with `createRoutesStub`
  (L842 stays for library modes).
- **NEW `templates/framework-app-shell.md`** — minimal `react-router.config.ts` (ssr + prerender),
  `{baseDir}/root.tsx` (Layout/Links/Meta/Scripts; when `serverState=tanstack-query`, a root
  **`QueryClientProvider`** — browser: module-scope singleton client; server render: a fresh client per
  request, never a shared module-scope one — with the D9 SSR defaults), `{baseDir}/routes.ts`,
  `entry.server.tsx` (guarded idempotent MSW-node hook per D8 + **per-request i18n instance** per R2) and
  `entry.client.tsx` (browser MSW worker bootstrap only + client i18n init). Includes the runtime note:
  built server runs via `npx react-router-serve ./build/server/index.js` on Node ≥ 22 (§6).
- **NEW `templates/server-state.md`** — the D9 layering contract: query-key factory conventions,
  `queryOptions` sharing between loader and hook (rule a — one key, one fetcher), `initialData` +
  `initialDataUpdatedAt` handoff with explicit `staleTime` defaults (rules b/c — the bare `initialData`
  pattern is a refetch trap), mutation + invalidation map, infinite query pattern, "no useEffect
  fetching" rule, the D13 base-client/browser-wrapper split for loader-safe fetching (with the
  fetch-client injection contract — factories take the client as an argument, D9 rule a), the
  `QueryClientProvider` wiring for both router-mode families (framework: app-shell `root.tsx`; library
  modes: `main.tsx`, §5.5 Step 6c), and the escalation criterion to `dehydrate`/`HydrationBoundary` (O2).
- **NEW `templates/e2e-playwright.md`** — ported from fm's `templates/e2e-testing.md` minus legacy
  dual-run and staging gateways: spec structure per TS-nnn, fixtures/auth setup, web-first assertions,
  trace-first failure reports. The existing `templates/e2e-testing.md` (agent-browser) remains for the
  admin path.
- `templates/tdd-rules.md` — unchanged.

### 5.11 Docs & versioning

- `CLAUDE.md`: Tech Stack (routing modes incl. framework; State & Data gains TanStack Query under
  `serverState`; new Forms subsection; Date/time becomes profile-aware — Intl for admin, dayjs +
  locale/utc/timezone plugins for ota per D12, currency via `Intl.NumberFormat` in both), profile
  concept, replace the blanket "RSC/SSR rules do not apply" (L73) with the conditional rule,
  Verification Philosophy build-command matrix per mode, config reference (§3), external skills row for
  framework mode, E2E section split by `e2eTool`.
- `README.md` / `README.ko.md` / `README.vi.md`: profile + new stack, config table, mode matrix.
- Version: **2.0.0** in `plugin.json` + root `marketplace.json` (same commit, sync rule).

## 6. Command matrix (single source of truth)

| Concern | declarative / data | framework |
|---|---|---|
| Dev server | `npx vite --port {port}` | `npx react-router dev --port {port}` |
| Build | `npx vite build` | `npx react-router build` |
| Typecheck | `tsc -b` \| `tsc --noEmit` (composite-aware) | `npx react-router typegen` **then** composite-aware tsc |
| Route integration target | `App.tsx` / `router.tsx` (JSX / RouteObject[]) | `{baseDir}/routes.ts` (+ `react-router.config.ts` prerender) |
| Loading state | in-page `loading` state | `HydrateFallback` + `useNavigation` |
| Error state | in-page `error` state | route `ErrorBoundary` (+ per-section states) |
| SSR rules (vercel skill) | skip | apply |
| E2E runner¹ | agent-browser CLI (manual dev server) | `npx playwright test` (webServer-managed) |
| Page unit-test target | page component (`MemoryRouter`) | page-body component via Testing Library — `createRoutesStub` only for router-hook components; route module via typegen/build + E2E (D10) |

¹ The E2E row is keyed on `e2eTool` (profile default), not on `routerMode` — the columns show the
default pairing (admin/declarative ↔ agent-browser, ota/framework ↔ playwright).

**Runtime assumptions (framework mode, Phase 1):** Node ≥ 22 (existing plugin baseline); the built app
runs locally via `npx react-router-serve ./build/server/index.js`; server-only config comes from
`process.env` (non-`VITE_` — D13); the plugin verifies up to a green build + local serve smoke and
deliberately configures no deployment target (O3).

## 7. Risks

- **R1 — SSR breaks localStorage-based auth.** The current admin JWT/localStorage + interceptor pattern is
  client-only. Phase 1 rules: authenticated routes render as `spa` with `clientLoader` only (D5
  heuristic); **nothing in the server-render path may touch `localStorage`/`window`** (auth store
  initialization is client-only; loaders import only the D13 base client — quality-reviewer enforces
  both); cookie/session-based SSR auth is the explicit precondition for any authenticated `ssr`/`ssg`
  route and is deferred to Phase 4 (with payments).
- **R2 — i18next under SSR.** Current i18n lazy-loads via `import.meta.glob` client-side; SSR-rendered
  pages need server-side i18next or they render raw keys. Phase 1 contract (app-shell template): a
  **per-request `i18next.createInstance()`** in `entry.server` — a module-scope instance leaks locale
  across concurrent SSR requests; locale precedence **URL prefix > cookie > `Accept-Language`**; the
  resolved locale + initial resources are serialized to the client so hydration matches; `meta`
  title/description keys are translated server-side with the same request instance. Flagged as the
  highest technical risk of the phase — validate first in the dry run (§8).
- **R3 — double-fetch loader vs query.** Mitigated by the D9 contract + `templates/server-state.md`;
  quality-reviewer checks for `useEffect` fetching.
- **R4 — mock-first in SSR dev.** Covered by D8 (`mocks/node.ts` + entry.server hook); without it the
  first loader page breaks the mock-first workflow.
- **R5 — blast radius.** ~20 files touch `routerMode`/build commands (see §5.8 map), plus the E2E
  toolchain branch (§5.9). Mitigation: the command matrix (§6) is written once in CLAUDE.md and
  referenced, not copied, by agents.
- **R6 — Playwright browser binaries.** `@playwright/test` needs a one-time `npx playwright install`
  (large download) that the plugin never runs itself (D7) — fe-init and fe-e2e must detect missing
  binaries and print the command instead of failing opaquely mid-suite.

## 8. Validation plan (for the plugin change itself)

1. **Regression (admin profile)**: run the existing pipeline (fe-init declarative → fe-plan → fe-gen →
   fe-verify → fe-review) on a sample admin feature with a no-new-keys config — must be byte-for-byte
   behavior-identical.
2. **Dry run (ota profile)**: scaffold an RR framework app, then fe-init (ota) → fe-plan `--standalone`
   for a `hotel-search` feature (ssr list + detail pages, one parameterless loader-less ssg landing
   page, spa checkout stub) → fe-gen → fe-verify →
   fe-e2e (Playwright suite green against the MSW-mocked webServer). Gate: typegen + build green,
   **first SSR request's loader is actually intercepted by MSW-node** (assert on the mock response, not
   just "no error" — D8; if this fails, apply the D8 fallback), a **local serve smoke** — boot
   `npx react-router-serve ./build/server/index.js`, GET one ssr page, assert HTTP 200 (closes the §6
   runtime promise), i18n renders translated SSR HTML with the request's locale (R2), no
   `localStorage`/`window` access during server render (R1), traces produced on a forced failure
   (fe-fix input, §5.9).
3. **Review pass**: fe-review on the dry-run output — SSR rules applied, no `useEffect` fetch, thin stores.

## 9. Open questions

Resolved: ~~O1~~ → dayjs adopted for the ota profile (D12). ~~O4~~ → E2E tooling is gated by
`appProfile` now, via `e2eTool` (D6, §5.9).

- **O2** — full TanStack SSR hydration (`dehydrate`/`HydrationBoundary`) vs the v1 `initialData` handoff
  (D9). Revisit when a page needs shared cache across nested routes.
- **O3** — deploy target for SSR (custom server vs edge). Phase 1 states its runtime assumptions in §6
  (Node ≥ 22, `react-router-serve` local run, `process.env` server config) and stops there; anything
  beyond a green build + local serve smoke is out of plugin scope.
- **O5** — dynamic-segment SSG (`pages[].staticPaths` enumeration contract: build-time data source,
  locale-variant URLs, failure behavior). Reserved in the plan schema; Phase 1 restricts `ssg` to
  parameterless, loader-less routes (D5).
