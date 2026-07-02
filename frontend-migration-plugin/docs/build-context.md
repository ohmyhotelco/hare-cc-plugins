# Build Context

Cross-session context for the frontend-migration-plugin: how it was built, the decisions behind
it, and the state it is in. Read this first when picking the work back up in a new session.

## What this plugin is

A fully standalone Claude Code plugin that drives the OhMyHotel Angular 15 → React Router v7
migration (PC, Mobile, Hana), per the revised v2 migration plan. It owns its agents and pipeline
(no runtime dependency on `frontend-react-plugin`) but shares that plugin's stack conventions so
generated React is consistent. It is **tooling** — it does not contain the product apps; runtime
execution targets a v2 monorepo (`apps/` + `packages/`) that the migration project scaffolds.

## Status (2026-07-02)

- **Build complete — v0.8.0.** 16 `fm-*` skills, 15 agents, 12 templates, multilingual README,
  session hooks, state-machine/lock infrastructure. Version history: v0.2.1 added the ESLint (hard)
  / Prettier (advisory) lint & format gate; v0.4.0 added the **Codex independent-audit layer**
  (`fm-audit-codex` + `codex-auditor`; advisory second opinion at every stage; design in
  `docs/design/`) plus shared external-skill injection (fe-init parity); v0.4.1 aligned the fm-*
  skill↔agent contracts (7 mismatches); v0.5.0 hardened the **Playwright E2E harness** (trace-first
  reports, flakiness prevention, SSR-loader mocking, auth/state-setup + page-object reuse); v0.6.0
  made the confirmed backend contracts (`docs/migration/api-contracts/`, OMH-604/606/607) the
  **authoritative** zod schema source for `shared-types`/`shared-data` only — `package-extractor`
  transcribes the zod-in-markdown contracts (shared `ResponseEnvelopeSchema` /
  `CommonRequestParamsRqSchema` bases + per-endpoint `.extend()`) instead of reverse-engineering
  legacy `any`, behind the optional `contractsDir` config (legacy fallback when unset; the other
  four packages unchanged); v0.7.0 made the **Strangler Fig route-flip mechanism per-app
  configurable** (`apps.{app}.flipMechanism`: `nginx` default | `cloudfront`) — `fm-route` +
  `strangler-orchestrator` now implement two strategies under one interface (same gate guard, lock,
  tracker, 2-PR flow; only the edited ARTIFACT differs: nginx routing block + flag vs a
  version-controlled CloudFront behavior manifest `cloudfrontDir/<manifest>` that is PR'd, never
  pushed to AWS). Backward-compatible (absent `flipMechanism` → `nginx`); the per-app mechanism
  **mapping is project config, never plugin-baked** (the plugin defaults every app to `nginx`);
  v0.8.0 added the **simplicity / over-engineering** quality dimension (`quality-reviewer`
  dimension 7 with the `delete`/`stdlib`/`native`/`yagni`/`shrink` tag taxonomy and a
  legacy-parity guard — it judges *how* a behavior is implemented, never *whether* it should
  exist) and the GREEN-phase **reuse ladder** in `tdd-cycle-runner` (`@omh/shared-*` → stdlib /
  platform → shadcn/ui → installed dependency → new code; explicitly **no YAGNI rung** — legacy
  parity is the requirement). Adapted from the review-tag/ladder ideas in the ponytail skill set
  (DietrichGebert/ponytail); the always-on persona and test minimalism were deliberately not
  adopted (they conflict with the strict TDD pipeline).
  Design-validated against a real two-edge production topology (public hosts flipping at a CDN, an
  IP-whitelisted partner host that must stay on an entry nginx; OMH `v2-migration-infra.md` §11.4,
  OMH-698/OMH-652) — the concrete which-app-uses-which mapping lives in the consuming project's
  config, not here.
- **Not yet runtime-validated.** The skills run against a v2 monorepo that does not exist yet;
  the PC end-to-end validation is the open follow-up.
- **JIRA:** epic **AA-39** is in `Verification` (awaiting that runtime validation); child tasks
  AA-40–AA-51 and AA-53 are `Done`; AA-61 (Playwright harness hardening) is `In Progress` (PR #32).

## Build map (epic AA-39, project AA "AI Agent")

Each task = one work branch (`AA-NN-desc`) → one PR to `main`. Each AA ticket has a
"Development artifacts" comment with its PR/branch/commit.

| Task | PR | Delivered |
| --- | --- | --- |
| AA-40 | #17 | Foundation: plugin.json, `fm-init`, CLAUDE.md, state-file/lock conventions, state machine, two session hooks |
| AA-41 | #18 | `angular-analyzer` + `fm-analyze`; `angular-to-react-mapping.md`, `shared-package-spec.md` (the "brain") |
| AA-42 | #19 | `fm-extract` + `package-extractor`; `shared-package-conventions.md` (secret-boundary lint) |
| AA-43 | #20 | `fm-plan`/`fm-gen`/`fm-verify` + 4 generation agents; `migration-plan-schema.md`, `tdd-rules.md` |
| AA-44 | #21 | `fm-fix` + `migration-fixer` (verify/e2e/parity repair loop) |
| AA-45 | #22 | `fm-e2e` + `e2e-test-runner`; `e2e-testing.md` (Playwright gatekeeper) |
| AA-46 | #23 | `fm-parity` + `parity-verifier`; `webview-bridge.md`, `hana-sso.md` |
| AA-47 | #24 | `fm-route`/`fm-progress` + `strangler-orchestrator`; `strangler-fig.md` |
| AA-48 | #25 | `fm-delta` + `delta-modifier` + planner incremental mode |
| AA-49 | #26 | `fm-clean-code`/`fm-test-review` + `quality-reviewer`/`test-reviewer` |
| AA-50 | #27 | `fm-secret-audit` + `secret-auditor`; multilingual docs; v0.2.0 bump; root README/CLAUDE registration |
| AA-51 | #29 | `eslint-config.md`/`prettier-config.md` + lint/format gate wiring (fm-init flags, fm-verify ESLint hard / Prettier advisory, scaffolding, legacy exclusion); v0.2.1 bump |
| AA-53 | TBD | `fm-audit-codex` + `codex-auditor` + `codex-audit.md`; in-loop advisory Codex audit across all 7 stages; `fm-route --flag-on` soft ack; design doc; v0.3.0 bump |

## Key design decisions

- **Fully standalone** (own agents/pipeline) but reuses `frontend-react-plugin` conventions.
- **Playwright for E2E + visual regression** — a deliberate divergence from
  `frontend-react-plugin`'s agent-browser, required for visual baselines (`toHaveScreenshot`),
  legacy-vs-new dual-run, and staging payment-gateway E2E.
- **PC-first; Mobile/Hana scaffolded** — config, gates, and templates (WebView, Hana SSO) exist
  but are validated after PC.
- **Two hard gates in series after generation** — `fm-verify` (technical) then `fm-parity`
  (legacy equivalence) — with `fm-e2e` (Playwright) as the functional gatekeeper between. A route
  flip is refused unless all three pass.
- **2-PR feature flag** — code PR (flag OFF) → gate pass → one-line flag-ON PR. Rollback = flip OFF.
- **`shared-domain` secret boundary** — PG/OAuth secret reads and hash builders are lint-blocked
  in `shared-domain`; they move server-side (OMH-477).
- **Lint & format gate** — `templates/eslint-config.md` (ESLint v9 flat, composed per workspace:
  core / +react / +secret-boundary) and `templates/prettier-config.md` (Prettier 3, single-quote).
  ESLint is a **hard** `fm-verify` check; Prettier `--check` is **advisory**. Config flags
  `eslintTemplate`/`prettierTemplate` (default on) drive scaffold-once; deps are never auto-installed.
  See CLAUDE.md → "Lint & Format Gate".
- **Codex independent audit (v0.4.0)** — Codex used as an advisory **auditor**, not a port or
  bridge: Claude runs the pipeline and calls Codex (via the `codex` plugin's `codex-cli-runtime` /
  headless `codex exec`) for an independent second review at every stage, recorded in
  `codex-audit.json`. Default-on (`codexAudit`), auto-skips if Codex absent, never changes the FSM;
  the only soft gate is the high-severity acknowledgement at `fm-route --flag-on`. Design:
  `docs/design/codex-audit-layer.md`. See CLAUDE.md → "Codex Independent Audit".
- **Infra**: per-page state machine (`analyzed → … → flipped → done` + `*-failed`/`fixing`/
  `escalated`), `.lock` (30-min stale), Read-Modify-Write on state files, subagent isolation,
  "evidence before claims" 5-step gate.

## Source-confirmed corrections (from the codebase survey)

These corrected initial assumptions and are baked into the mapping catalog / analyzer:
- i18n is **angular-i18next** (`| i18next`, `tl.*` keys, Google Sheets remote) — not ngx-translate.
- Components reach NgRx only through a **Facade layer** (`*.facade.ts`) → maps to a custom hook.
- Universal API response envelope `{ succeedYn, errorMessage, result, transactionSetId, errorCode }`.
- Forms use a custom `Control[]` + `formControlService.toFormGroup()` + **ControlValueAccessor**
  inputs → React Hook Form + zod (CVA components wrapped in RHF `Controller`).
- Mobile **WebView** is primarily UA detection (`wv`/`ww`) + `universal-link.service` +
  `sessionStorage` (`cnoUser`), not the explicit `window.ohmyhotelAndroid` bridge the plan §11.7
  describes — AA-46's `webview-bridge.md` flags either form (reconcile per page).
- Secret reads anchored: `hotel-payment.component.ts:504/541/623`, `social-connect.component.ts:257/303`.
- Hana SSO: `app.module.ts:50` `initApp`, `auth-hana.service.ts:28-84` fail-open (`status===0`).

## Build conventions used

- One work branch per task `AA-NN-desc` from `main` (Git Branch Strategy v1.md §11); one commit
  per task (Conventional Commits + 50/72); PR to `main` with the six required fields (§13);
  delete the remote branch after merge (§12).
- A "Development artifacts" comment (PR/branch/commit/delivered) posted to each AA ticket.
- The Jira **Development** panel auto-populates from the issue key in branch/commit/PR (GitHub-for-
  Jira integration is connected).
- The JIRA convention source is `raw/jira-guide-1-product-dev.md` (English titles, no bracket
  prefixes, Action+Target+Outcome, lowercase_underscore labels, custom fields left blank).

## Pointers

- **Migration spec:** `frontend-migration-plugin/raw/v2-migration-plan-revised.md` — **local-only
  (the `raw/` folder is gitignored)**; not committed. Also `raw/jira-guide-1-product-dev.md`,
  `raw/Git Branch Strategy v1.md`.
- **JIRA:** epic **AA-39** (project AA); decision **OMH-454**; first consumer **OMH-455**;
  security remediation **OMH-477**; infra/nginx ownership **OMH-502**.
- **Convention source:** `frontend-react-plugin` (same monorepo).
- **Legacy source repos** (for analysis): `ohmyhotel-pc-analysis` (PC), `ohmyhotel-mobile`
  (Mobile + Hana).

## Open follow-up

Run the pipeline end-to-end on a real PC page (e.g. a Phase-1 CMS page) inside the v2 monorepo to
validate it, then move AA-39 `Verification → Done`. Mobile WebView and Hana SSO gates are
scaffolded but unvalidated.
