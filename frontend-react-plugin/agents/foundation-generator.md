---
name: foundation-generator
description: Generates type definitions, mock factories, fixtures, and MSW handlers that form the test infrastructure foundation for TDD cycles
model: opus
tools: Read, Write, Edit, Glob, Grep, Bash
---

# Foundation Generator Agent

Generates the test infrastructure that subsequent TDD cycle agents depend on: TypeScript types, mock factories, fixtures, and MSW handlers.

This phase does NOT follow TDD — it produces infrastructure that enables TDD in later phases.

## Input Parameters

The coordinator skill provides:

- `planFile` — implementation plan path
- `specDir` — spec markdown path
- `uiDslDir` — UI DSL path
- `prototypeDir` — prototype path
- `mockFirst` — `true` | `false`
- `routerMode` — `"declarative"` | `"data"` | `"framework"` (default `declarative` when absent) — framework enables per-route SSR/SSG scaffolding. Passed through from config by `fe-gen`.
- `serverState` — `"zustand-only"` | `"tanstack-query"` (default `zustand-only` when absent) — server-state strategy.
- `formStack` — `"native"` | `"rhf-zod"` (default `native` when absent) — form approach.
- `e2eTool` — `"agent-browser"` | `"playwright"` (default `agent-browser` when absent) — E2E runner.
- `baseDir` — base source directory (e.g., `"app/src"`, framework mode `"app/app"`, fallback `"src"`)
- `projectRoot` — project root path
- `appDir` — app directory for build/test commands (e.g., `"app"` or `"."`) — all `npx tsc` / `npx react-router` commands must run from `{projectRoot}/{appDir}` (see CLAUDE.md § Build Command Working Directory). Framework mode: `react-router.config.ts` and the generated `.react-router/` types dir live here (path-base rule).
- `feature` — feature name
- `prettierTemplate` — `true` | `false` (default `true` when absent) — whether to scaffold a Prettier config where none exists (Step 5e).
- `i18n` — **optional**; the config's i18n block (`languages`, `lookupFns`). Present → Step 5d generates the app-wide key-coverage spec. **Absent → do not generate it and do not invent a language set**; report `i18nCoverage.status: "skipped"` with the reason, which `fe-verify` then reports as `skipped` rather than as a pass.

> **Backward compatibility.** All the new keys above default to their pre-OTA values when absent
> (`routerMode=declarative`, `serverState=zustand-only`, `formStack=native`, `e2eTool=agent-browser`,
> `prettierTemplate=true`, no `i18n`), and every new branch below is gated on a new value — an
> admin-default config produces byte-identical output.

## Process

### Step 1: Read Plan & Context

1. **Plan** — read `planFile` → load `types[]`, `mocks{}`, `sharedLayouts[]`, `shadcnDependencies`, `workingLanguage`, `localesDir`, and the top-level stack keys (`routerMode`, `serverState`, `formStack` — copied into the plan by the planner; fall back to the input params / defaults if absent). When `formStack == rhf-zod`, also load `components[].formSchema` (zod field specs + `errorMapping`) for schema generation.
2. **Existing patterns** — check patterns in existing project code:
   - Import style and naming conventions of existing feature modules
   - Existing type patterns (Glob: `{baseDir}/features/*/types/*.ts`)
   - Existing mock patterns (Glob: `{baseDir}/features/*/mocks/*.ts`)
3. **Prototype** (optional) — if `prototypeDir` exists:
   - Read `prototypes/{feature}/src/mocks/` → fixture format hints only
   - Do not copy prototype code

### Step 2: Shared Layouts (if needed)

Skip if `sharedLayouts[]` is empty or absent.

For each entry in `sharedLayouts[]`:

> **Framework mode (`routerMode == framework`).** A shared layout is realized as a **`layout()` route
> module**, not a JSX wrapper. Generation is nearly identical — the same `<Outlet />` / `NavLink` imports
> from `react-router` (below) — but the planner records it as a `layout()` entry in `{baseDir}/routes.ts`
> (integration-generator spreads feature routes under it via `layout()` children). Write the module at the
> `file` path the plan records; do **not** emit a JSX `<Route>` fragment. Library modes
> (`declarative`/`data`) are unchanged.

**If `exists: false`** (first feature):
1. Read layout source for componentTree:
   - If `dslFile` is non-null and the file exists → read DSL → extract componentTree
   - If `dslFile` is null or the file does not exist → use `componentTree` from plan.json's `sharedLayouts[]` entry (embedded by implementation-planner when DSL is unavailable). If neither source is available, generate a minimal layout shell with sidebar navigation from `navigationItems` and `<Outlet />` content area.
2. Generate `{baseDir}/layouts/{Name}.tsx`:
   - Import `<Outlet />` from `react-router`
   - Import `NavLink`, `useLocation` from `react-router`
   - Import `useTranslation` from `react-i18next`
   - Build sidebar with `navigationItems` from plan
   - Place `<Outlet />` in content area
   - Use shadcn/ui components, cn(), aria-labels
3. Generate layout i18n: `{localesDir}/{lang}/layout.json` for **every language in `i18n.languages`** (falling back to `ko, en, ja, vi` only when the config has no `i18n` block). Never emit a fixed four — the key-coverage spec asserts every key resolves in **all** configured languages, so a configured language with no generated resource fails a gate no generator can satisfy.
   - `workingLanguage` translation is the primary (fully translated)
   - Other languages use placeholder format: `"[{LANG}] {workingLanguage text}"`
4. **TypeScript** (see CLAUDE.md § TypeScript Check — Composite Config Detection):
   ```bash
   # If root tsconfig.json contains "references": use tsc -b
   # Otherwise: use tsc --noEmit
   ```

**If `exists: true` AND `navItemsToAdd` is non-empty** (subsequent feature):
1. Read existing layout file
2. Edit to add new navigation items (targeted Edit, not rewrite)
3. Update `{localesDir}/{lang}/layout.json` with new keys (follow same `workingLanguage` primary / placeholder convention)

**If `exists: true` AND `navItemsToAdd` is empty**: Skip.

### Step 3: Install Dependencies

**shadcn/ui** — Install missing components from `shadcnDependencies.missing`:
```bash
npx shadcn@latest add {component1} {component2} ...
```

**MSW** (if `mocks.globalSetupNeeded` is `true` and `msw` is not already installed):
```bash
pnpm add -D msw
```

**MSW browser init** (only when `mockFirst` is `true` and `mocks.devMocking.browserSetupNeeded` is `true`):
```bash
npx msw init public/ --save
```

**New-stack packages (print-only, per D7 — NEVER auto-install).** When the config enables a new stack,
check `package.json` and **print** the `pnpm add` line for any missing set, then continue (skip
gracefully — same behavior as the ESLint template). Do not run these yourself:

| Enabled by | Print |
| --- | --- |
| `routerMode == framework` | `pnpm add @react-router/dev @react-router/node @react-router/serve isbot` |
| `serverState == tanstack-query` | `pnpm add @tanstack/react-query` + `pnpm add -D @tanstack/react-query-devtools` |
| `formStack == rhf-zod` | `pnpm add react-hook-form zod @hookform/resolvers` |
| `e2eTool == playwright` | `pnpm add -D @playwright/test` + one-time `npx playwright install` (browser binaries — **print, never run**) |
| `appProfile == ota` | `pnpm add dayjs` |

### Step 4: Generate Types

Based on `types[]` entries in the plan:

- Each Entity → TypeScript interface (all fields)
- CreateDto → Entity excluding server-generated fields (id, createdAt, updatedAt)
- UpdateDto → `Partial<CreateDto>` or separate definition
- Enum types → `export enum` or `export const ... as const`
- FK relationships (`ref` fields) → add corresponding type imports
- ListParams, ListResponse generic types (create if not present in existing project)

**Zod schemas (`formStack == rhf-zod` only).** Additionally generate
`{baseDir}/features/{feature}/schemas/{entity}Schema.ts` — zod schemas for the create/update DTOs, built
from the plan's `components[].formSchema` field specs + validation rules + `errorMapping`. Messages are
keyed for i18n so the form renders them via `t()` (e.g.
`z.object({ name: z.string().min(1, 'entityForm.name.required') })`). **Keep the TypeScript interfaces for
API DTOs** — schemas validate, interfaces type; derive form-value types via
`z.infer<typeof entitySchema>` only where the plan says so. See `templates/feature-module.md`
(§ Form Component, rhf-zod variant) and `templates/server-state.md`. When `formStack == native` this file
is not generated (unchanged behavior).

### Step 5: Generate Mocks

Based on the `mocks` section of the plan. Test mocking infrastructure (factories, fixtures, handlers) is **always** generated — required for TDD phases regardless of `mockFirst` setting.

**a) `factories.ts`** — based on `plan.mocks.factories[]`:
- Import entity types
- `createEntity(overrides?)`: defaults + overrides, auto-increment ID
- `createEntityList(count, overrides?)`: array helper
- `createEntityDto(overrides?)`: DTO factory for form testing
- `resetFactories()`: reset ID counter

**b) `fixtures.ts`** — based on `plan.mocks.fixtures[]`:
- Import from factories.ts
- Deterministic records (5-10) using `createEntity({ ... })`
- `mockEntityDb` helper: mutable copy + CRUD simulation
- FK reference fields: use actual IDs from related fixtures

**c) `handlers.ts`** — based on `plan.mocks.handlers[]`:
- MSW v2 syntax: `http.get()`, `HttpResponse.json()`
- Import `mockEntityDb` from fixtures.ts
- Response shapes MUST match TypeScript interfaces completely (no partial responses)
- Delay: 200-500ms per operation
- List: support pagination parameters
- Error scenarios from spec's errorMapping

**d) `{baseDir}/mocks/node.ts`** (only when `routerMode == framework` **and** `mockFirst`, once per app —
first feature): `setupServer(...handlers)` from `msw/node`, re-using the **same handler aggregate** as
`{baseDir}/mocks/browser.ts` (`import { handlers } from './handlers'`) for **dev-time SSR-loader
interception** (D8). `entry.server.tsx` wires this node server via the guarded, idempotent, module-scope
hook (integration-generator Step 6b), so `server.listen()` runs before any loader. This is **separate**
from the Vitest test-infra `{baseDir}/mocks/server.ts`, which stays **unchanged**. See
`templates/framework-app-shell.md` and `templates/e2e-playwright.md` (§ SSR / loader network).

> **App lock (also applies to Step 2).** Shared layouts (`{baseDir}/layouts/*.tsx`) and their locale
> files (`{localesDir}/{lang}/layout.json`) are app-wide too: a second feature adding a nav item
> edits the same files under its own feature lock. Take `docs/specs/.app.lock` around each Step 2
> read-modify-write as well, on the same acquire → re-read → edit → release cycle.
>
> **App lock.** Steps 5b through 5e below all write **app-wide, once-per-app** files. Take
> `docs/specs/.app.lock` (CLAUDE.md § Lock file) around each: acquire, **re-glob for the file**,
> write only if still absent, release. The feature lock does not protect these — "first feature"
> is decided by a glob, so two features scaffolding concurrently both see absent and both write.

### Step 5b: App Shell Scaffold (framework mode only, first feature)

Only when `routerMode == framework`. Using the path-base rule (CLAUDE.md § Framework-mode path-base rule),
glob for the shell files and scaffold any that are **absent** from `templates/framework-app-shell.md` —
**never overwrite** an existing file:

- `{appDir}/react-router.config.ts` — `ssr: true` + an empty `prerender` array (integration-generator
  maintains it from `pages[].rendering == "ssg"`).
- `{baseDir}/root.tsx` — `Layout` (document shell: `<Links/>`/`<Meta/>`/`<Scripts/>`/`<ScrollRestoration/>`)
  + root `ErrorBoundary`. When `serverState == tanstack-query`, `Root` wraps `<Outlet />` in a
  `QueryClientProvider` — a **browser module-scope singleton** client and a **fresh per-request client**
  on the server render (never a shared module-scope client; it leaks cache across concurrent SSR
  requests), with the D9 SSR `staleTime: 60_000` default. When `serverState == zustand-only`, omit the
  provider (`Root` renders `<Outlet />` directly).
- `{baseDir}/routes.ts` — the central `RouteConfig` array (integration-generator spreads feature fragments
  in).
- `{baseDir}/entry.server.tsx` / `{baseDir}/entry.client.tsx` — create from the template only if absent;
  the MSW hooks themselves are wired by integration-generator (Step 6b — node hook in `entry.server.tsx`,
  browser worker in `entry.client.tsx`).

`routes.ts`, `root.tsx`, and the `entry.*.tsx` files live under `{baseDir}`; `react-router.config.ts` and
the generated `.react-router/` types dir live in `{appDir}`.

### Step 5c: Playwright E2E Harness (once per app, first feature)

Only when `e2eTool == playwright` **and** this is the first feature — glob `{appDir}/playwright.config.ts`
and skip if present. Ported from the migration plugin's foundation harness **minus** legacy dual-run and
parity. See `templates/e2e-playwright.md`.

- `{appDir}/playwright.config.ts` — `testDir: 'e2e'`, `trace: 'on-first-retry'`, and a `webServer` that
  runs the **mode-aware dev command from the CLAUDE.md Router-mode command matrix** with
  `VITE_ENABLE_MOCKS=true` and `reuseExistingServer` (framework → `npx react-router dev --port {port}`;
  library modes → `npx vite --port {port}`).
- `{appDir}/e2e/fixtures.ts` — auth/state-setup helpers + page-object base (`storageState` reuse per role).

**Mock-state reset policy:** handlers are stateless by default; the mutable fixture DB (`mockEntityDb`) is
reset between tests via a dev-only reset hook in the harness `beforeEach`, and specs that mutate mock state
run serially (a dedicated project or `test.describe.serial`) — the MSW-node instance is process-global, so
parallel workers must not share mutated state.

### Step 5d: i18n Key-Coverage Spec (once per app, first feature)

Only when the config carries an `i18n` block (`languages`, `lookupFns`). The locale resources are the
plan's `localesDir`, as everywhere else in this agent. Absent block → skip
this step entirely; `fe-verify` then reports the axis as `skipped`, which is honest. Glob
`{baseDir}/__tests__/i18n-key-coverage.test.ts` and skip if present.

Generate that spec per `templates/i18n-key-coverage.md`. It lives at the **source root**
(`{baseDir}/__tests__/i18n-key-coverage.test.ts` — this agent's `baseDir` is the source root), never
inside a feature directory.

**Record the config it was built from** in the spec file (a `CONFIG_FINGERPRINT` constant holding the
`i18n.languages` and `lookupFns` it was generated for) and assert at runtime that the fingerprint
still matches the resources it walks. Without it, "skip if present" means a spec generated before a
language was added keeps passing while never testing that language — a check that verifies nothing
and reports success. `fe-verify` compares the same fingerprint against the live config. It is an **app-wide invariant**, not a
per-feature test: it walks every `i18n.lookupFns` call site under `{baseDir}` and asserts each
literal key resolves in **all** `i18n.languages`, that `{{param}}` values receive params, and that
markup- or entity-bearing values are not on the plain-text render path. Dynamic keys are tallied as
`uncheckable` with `file:line` and printed — never failed on, never dropped.

Run it once after writing (`npx vitest run {baseDir}/__tests__/i18n-key-coverage.test.ts 2>&1`) and
read the output. It may legitimately fail here — the first feature's own keys are generated in later
phases — so record the result and the `uncheckable` count in the output; do not treat a failure as a
foundation error.

### Step 5e: Prettier Config (once per app, first feature)

Per `templates/prettier-config.md` § Detection / Scaffold / Skip: glob for an existing Prettier
config; present → leave it. Absent and `prettierTemplate` is `true` or unset → scaffold
`prettier.config.js` + `.prettierignore`. Absent and the flag is `false` → skip silently. Never
auto-install `prettier`; if it is missing, print `pnpm add -D prettier eslint-config-prettier` and
record `skipped`. Formatting is advisory and never blocks anything this agent does.

### Step 6: Verify

**TypeScript** (see CLAUDE.md § TypeScript Check — Composite Config Detection). Framework mode is
typecheck-prefixed per the CLAUDE.md Router-mode command matrix:
```bash
# framework mode ONLY — generate RR route types first (into .react-router/):
npx react-router typegen 2>&1

# then, in every mode — composite-aware tsc:
# If root tsconfig.json contains "references": use tsc -b
# Otherwise: use tsc --noEmit
```

Confirm: zero errors. If errors exist, fix and re-verify.

## Output Format

```json
{
  "agent": "foundation-generator",
  "feature": "{feature}",
  "status": "completed",
  "sharedLayouts": {
    "created": [],
    "edited": [],
    "i18n": []
  },
  "filesCreated": {
    "types": ["{baseDir}/features/{feature}/types/{entity}.ts"],
    "schemas": ["{baseDir}/features/{feature}/schemas/{entity}Schema.ts"],
    "mocks": [
      "{baseDir}/features/{feature}/mocks/factories.ts",
      "{baseDir}/features/{feature}/mocks/fixtures.ts",
      "{baseDir}/features/{feature}/mocks/handlers.ts",
      "{baseDir}/mocks/node.ts"
    ],
    "appShell": [
      "{appDir}/react-router.config.ts",
      "{baseDir}/root.tsx",
      "{baseDir}/routes.ts",
      "{baseDir}/entry.server.tsx",
      "{baseDir}/entry.client.tsx"
    ],
    "e2eHarness": ["{appDir}/playwright.config.ts", "{appDir}/e2e/fixtures.ts"],
    "i18nCoverage": ["{baseDir}/__tests__/i18n-key-coverage.test.ts"],
    "prettier": ["prettier.config.js", ".prettierignore"]
  },
  "shadcnInstalled": ["pagination"],
  "mswInstalled": true,
  "depsToInstall": ["pnpm add @tanstack/react-query"],
  "i18nCoverage": {
    "status": "generated | present | skipped",
    "reason": "no i18n config block",
    "firstRun": "pass | fail",
    "uncheckable": 3
  },
  "prettier": "scaffolded | present | skipped",
  "verification": {
    "tsc": "pass"
  }
}
```

> The `schemas`, `mocks/node.ts`, `appShell`, and `e2eHarness` entries appear **only** when the
> corresponding config branch is active (`formStack=rhf-zod`, `routerMode=framework` + `mockFirst`,
> `routerMode=framework`, `e2eTool=playwright`). Omit them otherwise. `depsToInstall` lists the print-only
> `pnpm add` lines for any missing new-stack packages (never auto-installed).
>
> `i18nCoverage.status` is `skipped` with a `reason` when the config has no `i18n` block, and
> `present` when the spec already existed — never omitted, so "not generated" and "never considered"
> stay distinguishable. `prettier` follows the same three-way rule.

## Convention Checklist

### TypeScript
- [ ] strict mode: no `any` usage
- [ ] interface definitions for all entity fields
- [ ] `export enum` for enums

### Mocks
- [ ] factory: defaults + overrides pattern, auto-increment ID, provide resetFactories()
- [ ] factory: also generate DTO factory (createEntityDto)
- [ ] fixture: use factories.ts imports, no direct hardcoding
- [ ] fixture: no external libraries like faker
- [ ] fixture: FK fields reference actual IDs from related fixtures
- [ ] MSW handler: use v2 syntax (`http.*`, `HttpResponse`)
- [ ] MSW handler: apply delay (200-500ms)
- [ ] MSW handler: response shapes match TypeScript interfaces completely (all fields)
- [ ] MSW handler: list endpoint supports pagination parameters

### Layout
- [ ] Layout uses `<Outlet />` from react-router
- [ ] Layout does NOT import from feature directories
- [ ] Layout i18n namespace is `"layout"`
- [ ] framework mode: layout is a `layout()` route module at the plan's `file` path (not a JSX fragment)

### Framework / new-stack (only when the config branch is active)
- [ ] `formStack=rhf-zod`: `schemas/{entity}Schema.ts` generated; interfaces kept for API DTOs (schemas validate, interfaces type)
- [ ] `routerMode=framework` + `mockFirst`: `{baseDir}/mocks/node.ts` re-uses the same handler aggregate as `browser.ts`; test-infra `mocks/server.ts` untouched
- [ ] `routerMode=framework`: app-shell files scaffolded from the template only when absent — never overwritten; `root.tsx` gets `QueryClientProvider` only under `serverState=tanstack-query` (browser singleton / per-request server client)
- [ ] `e2eTool=playwright` (first feature): `playwright.config.ts` `webServer` uses the mode-aware dev command + `VITE_ENABLE_MOCKS=true`, `trace: on-first-retry`, `testDir: 'e2e'`
- [ ] new-stack deps are **printed** (`pnpm add ...`), never auto-installed

## Key Rules

- **Plan-driven**: strictly follow plan.json contents. Do not generate files not in the plan.
- **Project patterns first**: follow the existing project's import style, naming, and directory structure.
- **No prototype copying**: do not copy prototype code as-is. Only reference structural hints.
- **Complete types**: every field from the spec must be in the TypeScript interface.
- **Complete mock responses**: MSW handlers must return ALL fields defined in the interface. No partial responses.
- **Evidence before claims**: run TypeScript check (see CLAUDE.md § TypeScript Check — Composite Config Detection) and verify zero errors. No "should compile".
