# E2E Testing (Playwright)

Patterns for `e2e-test-runner` / `fo-e2e`. Playwright is the repo's only E2E tool.
Ported from the migration plugin's harness **minus** the migration-specific pieces (no legacy dual-run,
no visual-regression parity, no staging payment gateways).

Why Playwright: visual baselines (`toHaveScreenshot`, used by `fo-visual`), staging payment E2E,
and trace-first self-correction — all Playwright-only. Binding the tool to the profile now avoids
generating suites on another tool that would be thrown away later.

## Scenario source
Scenarios come from `implementation-plan.json testScenarios[]` entries with `kind: "e2e"` (TS ids from the
spec snapshot's `*test-scenarios*.md`, chosen by `implementation-planner`); the runner reads each TS
section's steps and expected results from the snapshot and realizes them as Playwright specs.
Only the realization differs.

## The e2e tree — fixed, one per app

The V2 monorepo's `e2e/` folders drifted because the only rules were a file suffix and "follow the
existing specs": every gate invented its own suffix (`.e2e.ts`, `.parity.e2e.ts`, `.baseline.ts`,
`nonvisual-*.mjs`), helpers landed in four different places, and run output got committed. Here the
**folder names the role**, the **file name is the spec id**, there is **one suffix**, and
`fo-verify-run`'s `e2e-layout` check fails the gate on anything outside this tree. "Follow the repo"
applies to code style inside a file, never to where a file goes or what it is called.

```
<app.dir>/playwright.config.ts            projects by directory: functional · visual · seo (+ setup); testMatch = **/*.spec.ts
<app.dir>/e2e/
  fixtures.ts                             the harness: test/expect extensions, storageState per role, mock reset hook
  tsconfig.json                           optional, e2e-scoped TS config
  support/
    auth.setup.ts                         the setup project's test: log in per role, save storageState (the only *.setup.ts kind)
    auth.ts · mocks.ts · locale.ts        shared helpers — only here (lower-case first letter; a screen id here is a page object in the wrong place)
    global-setup.ts                       optional Playwright globalSetup
    pages/<screen>.ts                     one page object per screen — only here (e.g. pages/01-main-page.ts)
  screens/<screen>/<TS-id>.spec.ts        functional scenarios from the spec snapshot (fo-e2e)
  visual/<screen>.spec.ts                 capture + breakage spec (fo-visual)
  visual/__snapshots__/                   toHaveScreenshot baselines when used — committed, reviewed like code
  seo/<screen>.<aspect>.spec.ts           head · links · sitemap · structuredData · slugs (fo-seo)
<app.dir>/test-results/ · playwright-report/ · .auth/   run output and storageState — outside e2e/, ignored (fo-init writes the .gitignore lines)
```

What is **not** allowed under `e2e/`: any other extension (`.mjs`, `.sh`, `.py`, `.js`, `.e2e.ts`,
`.baseline.ts`, `.fixtures.ts` …), a spec whose name is not a scenario id (`TS-nnn`, `TS-nnn-n`,
`E2E-nnn`), any file at the root other than `fixtures.ts` and `tsconfig.json`, any directory other
than `support/`, `screens/`, `visual/`, `seo/`, tracked run output (`.artifacts/`, `.auth/`,
`test-results/`, traces, `test-failed-*.png`), captures or reports — those belong under
`docs/gates/<app>/<screen>/` (captures, reports: committed) and `.claude/frontend-ohmyhotel/`
(traces: ignored). Legacy comparison code has no place here; this repo has no legacy app.

Each gate writes only in its own folder and records that folder's hash with `fo-evidence
--spec-path`, so running a later gate never stales an earlier one and the shared screen hash
(`fo-screen-hash`) can leave `e2e/**` out.

## Harness (scaffolded once per app by `foundation-generator`)
- `playwright.config.ts` — top level: `testMatch: '**/*.spec.ts'`, `outputDir: 'test-results'`
  (written down so nobody moves it), `snapshotPathTemplate:
  '{testDir}/__snapshots__/{testFileName}/{arg}{-projectName}{-snapshotSuffix}{ext}'` (so a
  `toHaveScreenshot` anywhere lands in that project's `__snapshots__/`, never beside the spec),
  `trace: 'retain-on-first-failure'`, `webServer` running `npx react-router dev --port {devPort}` with
  `VITE_ENABLE_MOCKS=true` and `reuseExistingServer` (which trusts whatever already answers on that
  port — set `devPort` when 5173 is taken). Projects:
  `{ name: 'setup', testDir: 'e2e/support', testMatch: /.*\.setup\.ts/ }` — the only project whose
  `testMatch` differs; `{ name: 'functional', testDir: 'e2e/screens', dependencies: ['setup'] }`,
  `{ name: 'visual', testDir: 'e2e/visual', dependencies: ['setup'] }`, `{ name: 'seo', testDir: 'e2e/seo' }`.
  `toHaveScreenshot` baselines are a `visual` project concern; functional specs assert behaviour, not pixels.
- `e2e/support/auth.setup.ts` — the setup test: logs in per role and saves `storageState` to
  `path.resolve(__dirname, '../../.auth/<role>.json')` (= `<app.dir>/.auth/`, outside `e2e/`, ignored);
  a cwd-relative `.auth/` would land wherever Playwright was launched from.
- `e2e/fixtures.ts` — `test`/`expect` extended with auth/state-setup fixtures (loading that
  `storageState`) and the mock reset hook. It exports; it holds no `test()` of its own.
- `e2e/support/{auth,mocks,locale}.ts` and an empty `e2e/support/pages/` — created so the first screen
  has an obvious place to put its page object.
- The run-output `.gitignore` lines are written by `fo-init` at the repo root (one owner);
  `foundation-generator` checks they exist.

## Spec realization
- One spec per scenario: `<app.dir>/e2e/screens/<screen>/<TS-nnn>.spec.ts` (`app.dir` = the app package, e.g. `apps/www`, where `playwright.config.ts` lives; not `appDir` = `apps/www/app`), tagged with the scenario name + TS id; the screen's page object at `e2e/support/pages/<screen>.ts`. - Step mapping: `navigate`→`page.goto`; `fill`→`getByLabel`/`getByRole().fill`; `click`→`getByRole().click`;
  `verify`→`expect(...)` **web-first assertions** (auto-retry) — never bare `waitForTimeout`; `wait`→a
  web-first assertion on the awaited condition.
- Stable selectors (role/label/test-id), not brittle CSS chains.
- Resolve dynamic route params (`:id`) to fixture ids before navigation.

## SSR / loader network (framework mode)
Loaders and actions run **server-side**, so the browser MSW worker does **not** intercept their calls —
it only sees client-side fetches. A framework-mode page with a loader needs **both** paths mocked: the
browser path via MSW (`VITE_ENABLE_MOCKS=true`) and the server (loader) path via the MSW **node** server
(`<appDir>/mocks/node.ts`, wired in `entry.server.tsx`). Only mock what you control — never let an E2E
hit a real external dependency.

## Auth & state setup
- **Reuse `storageState`.** Log in once in `support/auth.setup.ts` (the setup project) and save
  `storageState` to `<app.dir>/.auth/<role>.json` (resolved from `__dirname`, outside `e2e/`, ignored);
  specs load it through the fixture instead of logging in per test. Multi-role pages get one state per
  role.
- **Start at the branch under test.** Pre-seed prerequisite state via API / `storageState` so a scenario
  begins where it verifies — don't replay shared prefixes in every test (Playwright's independence
  guidance).

## Mock-state reset (process-global MSW)
The MSW-node server is process-global. To prevent leakage across SSR loader requests and parallel workers:
- Handlers are **stateless by default**.
- The mutable fixture DB (`mockEntityDb`) is reset in the harness `beforeEach` (dev-only reset hook).
- Specs that **mutate** mock state run **serially** (a dedicated project or `test.describe.serial`) —
  parallel workers must not share mutated state.

## Reuse: page objects & helpers
One page object per screen at `e2e/support/pages/<screen>.ts`; cross-screen helpers (auth, mock state,
locale/currency) in `e2e/support/*.ts`. Read-modify-write when extending a shared helper; never add a
second place for the same kind of thing (no `page-objects/`, no `.po.ts`, no `helpers/`).

## Trace-first diagnostics
`trace: 'retain-on-first-failure'` keeps a trace for a scenario that fails on its **first** run.
**Not `on-first-retry`** — Playwright does not retry by default, and that mode only records during a
retry, so with `retries: 0` an ordinary failure produces no trace at all while the runner and
`fo-fix` both require one. (`on-first-retry` is correct only alongside an explicit `retries: 1`;
retries also mask flakiness, so the first-failure mode is the better default here.)

`e2e-report.json` records each failing scenario's trace path under **`scenarios[].trace`** — the one
field name the runner, `fo-e2e`, and `fo-fix` all read. Do not write it under `artifacts` or `evidence`;
a report that puts the path somewhere else is a report `fo-fix` cannot use. This is the primary
evidence `fo-fix` (e2e-fix) reads — open it with `npx playwright show-trace <trace.zip>`
(CLI-built-in, no skill) and diagnose from the trace before editing code.

## Run
From `<app.dir>` (webServer manages the dev server — no manual start/stop):
```bash
npx playwright test e2e/screens/{screen} 2>&1
```
`e2e-report.json` carries per-scenario pass/fail + trace paths; `fo-e2e` records it as the gate's evidence and `fo-fix --from e2e` reads it.
