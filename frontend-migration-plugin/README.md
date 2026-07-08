# Frontend Migration Plugin

A Claude Code plugin that drives the migration of the OhMyHotel Angular 15 apps (PC, Mobile,
Hana) to **React Router v7**, following the revised v2 migration plan. It is **fully standalone**
— its own agents and pipeline — but shares the stack conventions of `frontend-react-plugin` so the
generated React is consistent across the org.

> Status: feature-complete tooling (v0.10.0). The plugin does **not** contain the product apps —
> it operates on a v2 monorepo (`apps/` + `packages/`) that the migration project scaffolds.

## What it does

It wraps code generation with the four things a migration needs:
1. **Angular source analysis** — read a legacy page/service/store and produce a structured plan.
2. **Shared-package extraction** — lift pure logic into framework-agnostic `packages/shared-*`.
3. **Legacy-parity gates** — prove the new page matches the old one before any traffic flips.
4. **Strangler Fig orchestration** — page-by-page route flip + progress tracking.

## Concepts (read this first)

New to the migration? These terms recur throughout:

- **Strangler Fig** — migrate page-by-page. The edge layer routes each path to either the legacy
  Angular app or the new React app; you "strangle" the old app one route at a time, never a
  big-bang rewrite. The flip happens at each app's configured edge — an app-layer / entry **nginx**
  routing block, or a **CloudFront** behavior — selected per app (`flipMechanism`, default `nginx`).
- **The per-page loop** — every page goes through the same sequence: `analyze → style-spec → plan →
  gen → verify → e2e → parity → route`. One page at a time.
- **Three parity gates** — after a page is generated it must pass, in order: `fm-verify`
  (technical: build/types/unit tests + ESLint; Prettier is advisory), `fm-e2e` (does it behave
  like legacy?), `fm-parity`
  (does it look/contract/track like legacy?). A route flip is **blocked** until all three pass.
- **Legacy dual-run** — `fm-e2e` runs the same scenario against both the legacy app and the new
  app and compares. The legacy behavior is the source of truth.
- **Shared packages** — pure logic (validators, date math, DTOs, i18n) is extracted once into
  `packages/shared-*` and imported by all three apps; React-free where possible. When the project
  has confirmed backend contracts (`contractsDir`, default `docs/migration/api-contracts/`,
  OMH-604/606/607), those zod-in-markdown contracts are the **authoritative** schema source for
  `shared-types` and `shared-data` only — `fm-extract` transcribes them instead of
  reverse-engineering the legacy `any` DTOs. Absent that config, it falls back to legacy
  extraction (no regression); the other four packages always extract from legacy.
- **2-PR feature flag** — a page ships in two PRs: a code PR with the flag **OFF** (users still
  get legacy), then a one-line flag-**ON** PR after the gates pass. Rollback = flip the flag back.
- **State machine + tracker** — every page's status lives in `docs/migration/tracker.json`
  (`analyzed → style-specced → planned → generated → verified → e2e-passed → parity-passed → flipped → done`).
- **Codex independent audit** — when enabled (default), every audited stage (analyze/plan/gen/verify/
  e2e/parity/route — not fm-style-spec) also gets a second, independent review from **Codex**
  (advisory), recorded in `codex-audit.json`. It never changes a page's
  status; the only soft gate is `fm-route --flag-on`, which asks you to acknowledge any unresolved
  high-severity Codex findings before flipping. Requires the Codex CLI; auto-skips if absent.

## Prerequisites

This plugin is **tooling**; it assumes the migration project has set up the workspace:

- A **v2 monorepo** with: `apps/legacy-*` (the Angular apps under migration), `apps/web-*` (the
  new React Router v7 apps), and `packages/` (the shared packages).
- **Node + pnpm** (pnpm workspaces), and **Playwright browsers** installed (`npx playwright
  install`) for the E2E and visual gates.
- The **legacy Angular source** reachable for analysis.
- *(Optional)* the confirmed **backend verification contracts** at `docs/migration/api-contracts/`
  (`responses/` + `requests/`, OMH-604/606/607) — when present, `fm-init` records them as the
  authoritative schema source for `shared-types`/`shared-data`. Absent → legacy extraction (no
  regression).
- The plugin **configured** — run `fm-init` once (writes `.claude/frontend-migration-plugin.json`
  + `docs/migration/tracker.json`).

> If the v2 monorepo does not exist yet, that scaffolding is the migration project's Phase 0
> infrastructure work (see OMH-455 / OMH-502), not something this plugin creates.

## Target stack

React Router v7 (framework mode) · TypeScript (strict) · Tailwind · shadcn/ui · TanStack Query ·
Zustand · axios · react-hook-form + zod · i18next · dayjs · Vitest + MSW · **Playwright** (E2E +
visual regression — a deliberate divergence from frontend-react-plugin's agent-browser).

## External skills (shared with frontend-react-plugin)

Generic React/test knowledge is not re-authored here — `fm-init` installs the same upstream skills
`frontend-react-plugin` uses, via `npx skills add … --copy` (vendored into `.claude/skills/`), so
generated React stays consistent across the org. Migration-specific knowledge (Angular→React
mapping, Strangler Fig, WebView/SSO) lives in `templates/` instead.

| Skill | Source | Purpose |
| --- | --- | --- |
| `react-router-framework-mode` | `remix-run/agent-skills` | RR v7 **framework-mode** routing (loader/action, per-route SSR/SSG/SPA) |
| `vitest` | `antfu/skills` | Unit/component test patterns |
| `vercel-react-best-practices` | `vercel-labs/agent-skills` | React performance — applied **SSR-aware** (framework mode, not a Vite SPA) |
| `vercel-composition-patterns` | `vercel-labs/agent-skills` | Component composition patterns |

Agents load each per phase, guarded by existence — a declined/absent install (or
`externalSkills: false`) is skipped, never fatal. `web-design-guidelines` and `agent-browser`
(used by frontend-react-plugin) are intentionally not adopted: UI fidelity is judged by `fm-parity`
against the legacy baseline, and E2E runs on Playwright.

## Quickstart — migrate your first page

After the prerequisites are met:

```
# 0. one-time setup
/frontend-migration-plugin:fm-init
#    detects legacy/monorepo layout, writes config + tracker. PC-first.

# 1. (Phase 0) security pre-work + extract shared logic the page will need
/frontend-migration-plugin:fm-secret-audit            # inventory legacy secrets (posture; OMH-477)
/frontend-migration-plugin:fm-analyze hotel-booking-info   # → analysis.json (deps, gates, shared candidates)
/frontend-migration-plugin:fm-extract --from hotel-booking-info   # pure logic → packages/shared-*

# 2. the per-page loop
/frontend-migration-plugin:fm-style-spec hotel-booking-info   # → style-spec.json (live legacy computed values + assets)
/frontend-migration-plugin:fm-plan hotel-booking-info     # → migration-plan.json (tree, rendering, gates, e2e scenarios)
/frontend-migration-plugin:fm-gen hotel-booking-info      # RR v7 page via TDD → status: generated
/frontend-migration-plugin:fm-verify hotel-booking-info   # build/tsc/vitest → verified   (gate 1)
/frontend-migration-plugin:fm-e2e hotel-booking-info      # Playwright + dual-run → e2e-passed   (gate 2)
/frontend-migration-plugin:fm-parity hotel-booking-info   # visual/contract/webview/telemetry → parity-passed   (gate 3)

# 3. flip the route (two PRs)
/frontend-migration-plugin:fm-route hotel-booking-info --flag-off   # code PR (flag OFF)
/frontend-migration-plugin:fm-route hotel-booking-info --flag-on    # one-line flip PR (only if all gates pass)

# anytime: see where every page stands
/frontend-migration-plugin:fm-progress
```

Each step writes its artifact under `docs/migration/{app}/{page}/` and advances the page's status
in the tracker. If a gate fails, run `fm-fix <page>` (it auto-detects which gate) and re-run that
gate.

## Workflow

```
/fm-init                       config + tracker (once)

[Phase 0]
/fm-secret-audit               inventory legacy secrets (client vs server) — OMH-477
/fm-analyze <target>           Angular → analysis.json
/fm-extract <candidate>        pure logic → packages/shared-*

[per-page loop]
/fm-analyze <page>   → /fm-style-spec → /fm-plan → /fm-gen → /fm-verify
                                               │ fail → /fm-fix
                                     /fm-e2e   (Playwright gatekeeper; fail → /fm-fix)
                                     /fm-parity (visual/contract/webview/telemetry; fail → /fm-fix)
                                     /fm-route --flag-off (PR1) → --flag-on (PR2, gate-guarded)

/fm-delta <page>               re-migrate only the changed surface on legacy drift
/fm-progress                   per-app/per-page status + gate state (read-only)
```

## The gates

A route flip (`fm-route --flag-on`) is refused unless all three pass for the page.

| Gate | Skill | Checks | On fail |
| --- | --- | --- | --- |
| 1 · technical | `fm-verify` | build, `tsc` (composite-aware), Vitest, ESLint (hard); Prettier `--check` (advisory) | `fm-fix` (verify-fix) |
| 2 · functional | `fm-e2e` | Playwright user flows; legacy dual-run; staging payment gateways | `fm-fix` (e2e-fix) |
| 3 · parity | `fm-parity` | visual regression vs legacy baseline, API contract freeze, WebView bridge round-trip, telemetry dual-fire | `fm-fix` (parity-fix) |

## Skills

| Skill | Purpose |
| --- | --- |
| `fm-init` | Initialize config + tracker |
| `fm-analyze` | Analyze a legacy Angular target → analysis.json |
| `fm-style-spec` | Extract the legacy style answer key (live computed + assets + structure) → style-spec.json |
| `fm-extract` | Lift logic into framework-agnostic `packages/shared-*` |
| `fm-plan` | analysis.json + style-spec.json → migration-plan.json |
| `fm-gen` | Generate the RR v7 page via per-phase TDD |
| `fm-verify` | Technical gate: build / tsc / vitest / eslint (hard); prettier --check (advisory) |
| `fm-fix` | Targeted repair loop for verify/e2e/parity failures |
| `fm-e2e` | Playwright E2E gatekeeper (legacy dual-run, staging gateways) |
| `fm-parity` | Visual / contract / WebView / telemetry parity |
| `fm-route` | Strangler Fig route flip (2-PR feature flag; per-app nginx or CloudFront edge) |
| `fm-progress` | Read-only migration dashboard |
| `fm-delta` | Incremental re-migration on legacy drift |
| `fm-clean-code` | Standalone code-quality audit |
| `fm-test-review` | Standalone test-quality audit |
| `fm-secret-audit` | Secret inventory + relocation guidance |
| `fm-audit-codex` | Independent Codex audit of each audited stage — the seven, not fm-style-spec (advisory second opinion) |

See `docs/skill-reference.md` for each skill's inputs/outputs, the agent it drives, and the
tracker state it sets.

## Troubleshooting / FAQ

- **A gate failed.** Run `/frontend-migration-plugin:fm-fix <page>` — it auto-detects the mode
  (verify/e2e/parity) from the latest failing report, applies the smallest fix, and re-runs the
  gate. Then re-run that gate to confirm.
- **The legacy page changed after I migrated it.** Run `/frontend-migration-plugin:fm-delta
  <page>` — it re-migrates only the changed surface and preserves your accumulated fixes (large
  deltas fall back to a full `fm-gen`). The PostToolUse hook warns you when this happens.
- **`fm-gen` was interrupted.** Re-run it — it resumes from the last incomplete phase via
  `generation-state.json`.
- **"Another operation is in progress."** A page `.lock` is held; if it is older than 30 minutes
  it is stale and auto-cleared.
- **`fm-gen` says a shared package is missing.** The plan flagged an unextracted dependency — run
  `/frontend-migration-plugin:fm-extract` for it first.
- **Where does everything stand?** `/frontend-migration-plugin:fm-progress` (read-only) shows
  per-app/per-page status, gate results, and the suggested next command.
- **Secrets / payment.** PG `merchantKey` and OAuth `client_secret` reads are blocked in
  `shared-domain` and move server-side (tracked under OMH-477); `fm-secret-audit` inventories them.

## Documentation

- `docs/workflow.md` — the per-page state machine, the gate chain, and the topology.
- `docs/skill-reference.md` — every skill and agent, with inputs/outputs and state effects.
- `docs/build-context.md` — how the plugin was built, the design decisions, and cross-session
  context for picking the work back up.
- `CLAUDE.md` — conventions, state-file & lock rules, design principles, and the mapping/gate index.
- `templates/` — the Angular→React mapping catalog, shared-package spec/conventions, WebView
  bridge, Hana SSO, Strangler Fig routing, TDD rules, the migration-plan schema, the
  visual-parity checklist (`visual-parity-checklist.md` — the visual-gate axis list + the
  cross-framework pixel-diff fallback protocol), and the ESLint/Prettier lint & format gate
  configs (`eslint-config.md`, `prettier-config.md`).

Localized: `README.ko.md`, `README.vi.md`.
