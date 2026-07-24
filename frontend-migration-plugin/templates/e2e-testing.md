# E2E Testing (Playwright) — Migration

Patterns for `e2e-test-runner` / `fm-e2e`. Playwright is the migration E2E tool (a deliberate
divergence from frontend-react-plugin's agent-browser) because the migration needs visual
baselines (`toHaveScreenshot`, used by `fm-parity`), legacy-vs-new dual-run, and staging
payment-gateway E2E.

## Scenario source
Scenarios come from `migration-plan.json.e2eScenarios[]` (mapped from legacy flows by
`migration-planner`). Each has `name`, `steps`, `legacyAnchor`, and `transactional` (+ `gateway`).

## Run modes
| Scenario | Mode | Network |
| --- | --- | --- |
| non-transactional | new app | **MSW** intercept (`VITE_ENABLE_MOCKS=true`) — deterministic |
| transactional (payment funnel) | **staging** | real PG **test** endpoints (OMH-459); never production |

The payment matrix to cover on staging (OMH-459): each gateway × method — KR card, KR bank,
Alipay (NicePay), Eximbay / international, OnePay / VN.

**SSR / loader network (RR v7 framework mode).** Loaders and actions run **server-side**, so the
browser MSW worker does **not** intercept their network calls — it only sees client-side fetches.
Mock by call site: the **browser** path via MSW / `page.route`; the **server (loader / SSR / BFF)**
path via the MSW **node** server (`mocks/server.ts`) or an E2E-only env flag that returns fixed
responses. PC is `ssr: "mixed"`, so a page with a loader needs **both**. Only mock what you control
(external gateways, third-party APIs) — never let an E2E hit a real external dependency.

## Auth & state setup
- **Reuse `storageState`.** Log in once via a Playwright **setup project** that saves
  `storageState` to `.auth/<role>.json`; specs load it instead of logging in inside each test
  (`foundation-generator` scaffolds the setup project). Multi-role pages get one state per role.
- **Start at the branch under test.** Pre-seed the prerequisite state via API / `storageState` so a
  scenario begins at the branch it verifies — do not replay shared prefixes (e.g. consent →
  phone-auth) in every test. This keeps tests independent (Playwright's guidance) and fast.
- The legacy AuthGuard **login-modal** UX (a scenario that exercises the gate itself) is a separate
  concern from the storageState shortcut — see Conventions.

## Reuse: page objects & helpers
Factor repeated selectors and flows into **page objects / helpers** under `e2e/` (auth,
state-setup, data factories) so specs across pages reuse them instead of duplicating — the
maintenance payoff compounds across a multi-page migration. Create them as scenarios need them and
reuse existing ones (read-modify-write; never clobber another page's helpers).

## Legacy dual-run (behavior parity)
Run the same scenario against the legacy Angular app (its base URL) and the new RR v7 app;
compare observable behavior (navigation, key outputs, success/error paths). The **legacy
behavior is the source of truth** — a divergence is a new-app failure, not a scenario to relax.

**Compare the displayed text, not just the flow.** For any scenario the plan marks
`assertsCopy: true` (every `copyBindings` failure surface), assert the **message the user actually
sees** on both sides and diff it. A flow can navigate identically while showing the wrong words:
an English backend string on a Korean screen, a raw `tl.*` key, or a literal `<br/>`. Those pass a
navigation-only comparison, which is exactly how they reached production (OMH-748). Run the copy
assertions in each language the scenario's plan scope covers (`gateAcceptance.scope` →
`i18n.languages`); a reduction there is an `openApprovals` item, not a default.

**Failure branches are first-class scenarios.** A wrong error string never appears in a successful
flow, so a happy-path-only suite is blind to the entire copy axis. Run the plan's failure scenarios
— wrong password, OTP/verification-code failure, blocked or duplicate email — on both apps. See
`templates/i18n-copy-parity.md`.

## Trace-first diagnostics
Playwright is configured (in `foundation-generator`) to retain **trace + video + screenshot on
failure** (`trace: 'retain-on-failure'`). A failed run is then a rich, structured artifact —
per-step network requests, console logs, DOM snapshots — not just a red line. `e2e-report.json`
records each failing scenario's paths under `artifacts` (trace/video/screenshot). This is the
primary evidence `fm-fix` (e2e-fix) reads to self-correct — open it with `npx playwright show-trace
<trace.zip>`, the way a developer opens DevTools. Diagnose from the trace before editing code.

## Conventions
- Resolve dynamic route params (`:id`) to fixture ids before navigation.
- Tag each spec with the scenario name + `legacyAnchor` for traceability.
- Stable selectors (role/label/test-id), not brittle CSS chains.
- Preserve the legacy AuthGuard **login-modal** UX in auth scenarios (modal, not hard redirect).
- WebView/SSO/telemetry assertions belong to `fm-parity` (AA-46), not here — this gate is
  behavior/flow.

## Flakiness prevention
The migration gate runs legacy + new **dual-run**, so the flake surface is doubled — catch flakes
at authoring time, before the PR, not after merge.
- **Burn-in.** Right after writing a spec, run it repeatedly (`npx playwright test <spec>
  --repeat-each=5`). A single failure across the runs means it is flaky — fix it now; merge-time
  flakes cost far more to chase than authoring-time ones.
- **Condition-based waits only.** Never `waitForTimeout` / fixed sleeps. Use Playwright
  auto-waiting and web-first assertions (`await expect(locator).toBeVisible()`, `expect.poll`) so a
  test waits exactly as long as needed.
- **Semantic selectors.** Query by role/label/text (see Conventions) so a design or DOM-structure
  change does not break the test.

## Gatekeeper rule
A failing or unrun scenario means the gate has not passed. `fm-route --flag-on` is blocked until
`e2e-report.json.result === "pass"` (and `fm-verify` + `fm-parity` pass). On failure, loop back
through `fm-fix` (e2e-fix mode), then re-run `fm-e2e`.

## Permissions
The runner executes as a sub-agent; session approvals do not transfer. `fm-e2e` ensures
`.claude/settings.json` `permissions.allow` includes the Playwright command
(`Bash(npx playwright *)`).
