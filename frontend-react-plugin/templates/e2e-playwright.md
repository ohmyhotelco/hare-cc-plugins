# E2E Testing (Playwright)

Patterns for `e2e-test-runner` / `fe-e2e` when `e2eTool == playwright` (the ota-profile default).
Ported from the migration plugin's harness **minus** the migration-specific pieces (no legacy dual-run,
no visual-regression parity, no staging payment gateways — those arrive in later OTA phases). When
`e2eTool == agent-browser`, use `e2e-testing.md` instead.

Why Playwright for OTA: visual baselines (`toHaveScreenshot`, Phase 3), staging payment E2E (Phase 4),
and trace-first self-correction — all Playwright-only. Binding the tool to the profile now avoids
generating agent-browser suites that get thrown away later.

## Scenario source
Scenarios come from `plan.json e2eTests[]` (mapped from `test-scenarios.md` TS-nnn by
`implementation-planner`). The step schema (`navigate`/`fill`/`click`/`verify`/`wait` + `target`/`value`/
`expect`) is **tool-neutral** — the same entries realize as agent-browser sequences or Playwright specs.
Only the realization differs.

## Harness (scaffolded once per app by `foundation-generator`)
- `playwright.config.ts` — `testDir: 'e2e'`, `trace: 'on-first-retry'`, `webServer` runs the mode-aware
  dev command (from the CLAUDE.md command matrix) with `VITE_ENABLE_MOCKS=true` and `reuseExistingServer`.
  Framework mode → `npx react-router dev --port {port}`; library modes → `npx vite --port {port}`.
- `e2e/fixtures.ts` — auth/state-setup helpers and page-object base.

## Spec realization
- One spec per scenario: `{appDir}/e2e/{feature}/{TS-nnn}.spec.ts`, tagged with the scenario name + TS-nnn.
- Step mapping: `navigate`→`page.goto`; `fill`→`getByLabel`/`getByRole().fill`; `click`→`getByRole().click`;
  `verify`→`expect(...)` **web-first assertions** (auto-retry) — never bare `waitForTimeout`; `wait`→a
  web-first assertion on the awaited condition.
- Stable selectors (role/label/test-id), not brittle CSS chains.
- Resolve dynamic route params (`:id`) to fixture ids before navigation.

## SSR / loader network (framework mode)
Loaders and actions run **server-side**, so the browser MSW worker does **not** intercept their calls —
it only sees client-side fetches. A framework-mode page with a loader needs **both** paths mocked: the
browser path via MSW (`VITE_ENABLE_MOCKS=true`) and the server (loader) path via the MSW **node** server
(`{baseDir}/mocks/node.ts`, wired in `entry.server.tsx`). Only mock what you control — never let an E2E
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
`trace: 'on-first-retry'` retains a trace on failure. `e2e-report.json` records each failing scenario's
trace path under `artifacts`. This is the primary evidence `fe-fix` (e2e-fix) reads — open it with
`npx playwright show-trace <trace.zip>` (CLI-built-in, no skill) and diagnose from the trace before
editing code.

## Run
From `{appDir}` (webServer manages the dev server — no manual start/stop):
```bash
npx playwright test e2e/{feature} 2>&1
```
`e2e-report.json` schema is unchanged from the agent-browser path (per-scenario pass/fail + evidence), so
`fe-progress` / `fe-fix` consumers are untouched.
