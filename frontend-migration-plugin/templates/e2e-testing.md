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

## Legacy dual-run (behavior parity)
Run the same scenario against the legacy Angular app (its base URL) and the new RR v7 app;
compare observable behavior (navigation, key outputs, success/error paths). The **legacy
behavior is the source of truth** — a divergence is a new-app failure, not a scenario to relax.

## Conventions
- Resolve dynamic route params (`:id`) to fixture ids before navigation.
- Tag each spec with the scenario name + `legacyAnchor` for traceability.
- Stable selectors (role/label/test-id), not brittle CSS chains.
- Preserve the legacy AuthGuard **login-modal** UX in auth scenarios (modal, not hard redirect).
- WebView/SSO/telemetry assertions belong to `fm-parity` (AA-46), not here — this gate is
  behavior/flow.

## Gatekeeper rule
A failing or unrun scenario means the gate has not passed. `fm-route --flag-on` is blocked until
`e2e-report.json.result === "pass"` (and `fm-verify` + `fm-parity` pass). On failure, loop back
through `fm-fix` (e2e-fix mode), then re-run `fm-e2e`.

## Permissions
The runner executes as a sub-agent; session approvals do not transfer. `fm-e2e` ensures
`.claude/settings.json` `permissions.allow` includes the Playwright command
(`Bash(npx playwright *)`).
