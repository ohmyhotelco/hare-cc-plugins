# E2E Testing (Playwright)

Patterns for `e2e-test-runner` / `fo-e2e`. Playwright is the repo's only E2E tool.
Ported from the migration plugin's harness **minus** the migration-specific pieces (no legacy dual-run,
no visual-regression parity, no staging payment gateways — those arrive in later OTA phases). When

Why Playwright: visual baselines (`toHaveScreenshot`, used by `fo-visual`), staging payment E2E,
and trace-first self-correction — all Playwright-only. Binding the tool to the profile now avoids
generating suites on another tool that would be thrown away later.

## Scenario source
Scenarios come from `implementation-plan.json testScenarios[]` entries with `kind: "e2e"` (TS ids from the
spec snapshot's `*test-scenarios*.md`, chosen by `implementation-planner`); the runner reads each TS
section's steps and expected results from the snapshot and realizes them as Playwright specs.
Only the realization differs.

## Harness (scaffolded once per app by `foundation-generator`)
- `playwright.config.ts` — `testDir: 'e2e'`, `trace: 'retain-on-first-failure'`, `webServer` runs the mode-aware
  dev command (`npx react-router dev`) on the config `devPort` (default `5173`) with `VITE_ENABLE_MOCKS=true` and `reuseExistingServer` — which trusts whatever already answers on that port, so a port collision means testing the wrong server; set `devPort` when 5173 is taken.
  Framework mode → `npx react-router dev --port {port}`; library modes → `npx vite --port {port}`.
- `e2e/fixtures.ts` — auth/state-setup helpers and page-object base.

## Spec realization
- One spec per scenario: `<app.dir>/e2e/<screen>/<TS-nnn>.spec.ts` (`app.dir` = the app package, e.g. `apps/www`, where `playwright.config.ts` lives; not `appDir` = `apps/www/app`), tagged with the scenario name + TS id. - Step mapping: `navigate`→`page.goto`; `fill`→`getByLabel`/`getByRole().fill`; `click`→`getByRole().click`;
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
- **Reuse `storageState`.** Log in once via a Playwright **setup project** that saves `storageState` to
  `.auth/<role>.json`; specs load it instead of logging in per test. Multi-role pages get one state per
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
Factor repeated selectors and flows into page objects / helpers under `e2e/` (auth, state-setup, data
factories) and reuse across specs (read-modify-write; never clobber another feature's helpers).

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
npx playwright test e2e/{screen} 2>&1
```
`e2e-report.json` carries per-scenario pass/fail + trace paths; `fo-e2e` records it as the gate's evidence and `fo-fix --from e2e` reads it.
