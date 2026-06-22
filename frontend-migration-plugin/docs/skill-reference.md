# Skill & Agent Reference

Every `fm-*` skill, the agent it drives, its key inputs/outputs, and the tracker state it sets.
State files live under `docs/migration/{app}/{page}/`; the global tracker is
`docs/migration/tracker.json`. Skills that mutate state take the page `.lock` (stale after
30 min); audits and `fm-progress` are read-only and take no lock.

| Skill | Agent | Input → Output | State set |
| --- | --- | --- | --- |
| `fm-init` | — | detect layout → `.claude/frontend-migration-plugin.json` + `tracker.json` | — |
| `fm-analyze` | `angular-analyzer` | legacy target → `analysis.json` | `analyzed` |
| `fm-extract` | `package-extractor` | analysis candidates (+ `contractsDir` for `shared-types`/`shared-data`) → `packages/shared-*` (+ tests) | `tracker.packages` |
| `fm-plan` | `migration-planner` | `analysis.json` + catalog → `migration-plan.json` | `planned` |
| `fm-gen` | `foundation-generator`, `tdd-cycle-runner`, `integration-generator` | plan → RR v7 page (TDD) | `generated` (resume via `generation-state.json`) |
| `fm-verify` | — | build / tsc / vitest from `appDir` | `verified` / `verify-failed` |
| `fm-e2e` | `e2e-test-runner` | plan `e2eScenarios` → Playwright (dual-run, staging) → `e2e-report.json` | `e2e-passed` / `e2e-failed` |
| `fm-parity` | `parity-verifier` | visual/contract/webview/telemetry → `parity-report.json` | `parity-passed` / `parity-failed` |
| `fm-fix` | `migration-fixer` | failing gate report → targeted edits → `fix-report.json` | `fixing` → passed / `generated` / `escalated` |
| `fm-route` | `strangler-orchestrator` | flagPlan + gate reports → nginx routing + flag | `flipped` (flag-on, gate-guarded) |
| `fm-progress` | — | `tracker.json` → dashboard (read-only) | — |
| `fm-delta` | `migration-planner` (incremental) + `delta-modifier` | legacy drift → `delta-plan.json` → targeted edits | `generated` (re-enter gates) |
| `fm-clean-code` | `quality-reviewer` | generated code → quality report (read-only) | — |
| `fm-test-review` | `test-reviewer` | generated tests → test-quality report (read-only) | — |
| `fm-secret-audit` | `secret-auditor` | legacy `environment.*.ts` → `secret-audit-report.json` (read-only) | — |
| `fm-audit-codex` | `codex-auditor` | stage artifacts → independent Codex review → `codex-audit.json` (advisory) | `pages[page].codexAudit[stage]` |

## Agents

- **angular-analyzer** — parses component/template, facade+NgRx, RxJS, HTTP/DTO, routing/guards/
  init; emits analysis with shared candidates, 3-app diff, required gates + triggers.
- **package-extractor** — TDD extraction into `packages/shared-*`; reconciles 3 apps; enforces the
  `shared-domain` secret boundary (rejects PG/OAuth secret reads, hash builders). For `shared-types`
  / `shared-data`, when `contractsDir` (`docs/migration/api-contracts/`, OMH-604/606/607) is set it
  **transcribes** the confirmed zod-in-markdown contracts as the authoritative schema source
  (shared `ResponseEnvelopeSchema` / `CommonRequestParamsRqSchema` bases + per-endpoint
  `.extend()`) instead of reverse-engineering legacy `any`; legacy stays the anchor only for
  `shared-data` wiring and contract-excluded schemas (`DataLayerEvent` + tracker events). Falls
  back to legacy when `contractsDir` is unset.
- **migration-planner** — plan (component tree, rendering, gates, flag, e2e scenarios) + an
  incremental mode that emits `delta-plan.json`.
- **foundation-generator** — types + MSW + per-app Playwright/Vitest/MSW harness (no TDD).
- **tdd-cycle-runner** — strict Red-Green per phase (api/store/component/page), applies the
  mapping catalog, imports `@omh/shared-*`.
- **integration-generator** — RR v7 routes + i18n + MSW global (graceful manual-guidance fallback).
- **migration-fixer** — smallest-change repair for verify/e2e/parity failures; TDD for behavior.
- **e2e-test-runner** — Playwright specs; legacy dual-run; staging payment for transactional pages.
- **parity-verifier** — visual regression, contract freeze, WebView round-trip, telemetry dual-fire.
- **strangler-orchestrator** — nginx routing + feature flag; refuses flag-on unless all gates pass.
- **delta-modifier** — applies `delta-plan.json` ops; preserves prior fm-fix edits; cascade order.
- **quality-reviewer** / **test-reviewer** — standalone code/test quality audits.
- **secret-auditor** — legacy secret inventory + exposure classification (posture only; OMH-477).
- **codex-auditor** — independent Codex review of one stage's artifact via the `codex-cli-runtime`
  contract (headless `codex exec`); records `codex-audit.json`. Advisory; never migrates or changes
  pipeline state. See CLAUDE.md → "Codex Independent Audit".

## Templates

`angular-to-react-mapping.md`, `shared-package-spec.md`, `shared-package-conventions.md`,
`migration-plan-schema.md`, `tdd-rules.md`, `e2e-testing.md`, `webview-bridge.md`, `hana-sso.md`,
`strangler-fig.md`, `eslint-config.md` (ESLint v9 flat config, composed per workspace),
`prettier-config.md` (Prettier 3, advisory), `codex-audit.md` (per-stage Codex audit rubric). See
CLAUDE.md → "Lint & Format Gate" and "Codex Independent Audit".
