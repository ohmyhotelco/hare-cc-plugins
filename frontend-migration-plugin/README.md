# Frontend Migration Plugin

A Claude Code plugin that drives the migration of the OhMyHotel Angular 15 apps (PC, Mobile,
Hana) to **React Router v7**, following the revised v2 migration plan. It is **fully
standalone** — its own agents and pipeline — but shares the stack conventions of
`frontend-react-plugin` so the generated React is consistent across the org.

> Build status: feature-complete tooling (skills/agents/templates). Runtime execution targets a
> v2 monorepo (`apps/` + `packages/`) that is scaffolded by the migration project itself.

## What it does

Wraps code generation with the four things a migration needs:
1. **Angular source analysis** — read a legacy page/service/store and produce a structured plan.
2. **Shared-package extraction** — lift pure logic into framework-agnostic `packages/shared-*`.
3. **Legacy-parity gates** — prove the new page matches the old one before any traffic flips.
4. **Strangler Fig orchestration** — page-by-page route flip + progress tracking.

## Target stack

React Router v7 (framework mode) · TypeScript (strict) · Tailwind · shadcn/ui · TanStack Query ·
Zustand · axios · react-hook-form + zod · i18next · dayjs · Vitest + MSW · **Playwright** (E2E +
visual regression — a deliberate divergence from frontend-react-plugin's agent-browser).

## Getting started

```
/frontend-migration-plugin:fm-init
```
Detects the legacy Angular apps + the monorepo layout and writes
`.claude/frontend-migration-plugin.json` (per-app `legacyDir`/`targetDir`/`appDir`/`domain`/
`port`/`ssr`/`webview`/`sso`), then initializes `docs/migration/tracker.json`. PC-first;
Mobile/Hana are scaffolded and validated later.

## Workflow

```
/fm-init                       config + tracker (once)

[Phase 0]
/fm-secret-audit               inventory legacy secrets (client vs server) — OMH-477
/fm-analyze <target>           Angular → analysis.json
/fm-extract <candidate>        pure logic → packages/shared-*

[per-page loop]
/fm-analyze <page>   → /fm-plan → /fm-gen → /fm-verify
                                               │ fail → /fm-fix
                                     /fm-e2e   (Playwright gatekeeper; fail → /fm-fix)
                                     /fm-parity (visual/contract/webview/telemetry; fail → /fm-fix)
                                     /fm-route --flag-off (PR1) → --flag-on (PR2, gate-guarded)

/fm-delta <page>               re-migrate only the changed surface on legacy drift
/fm-progress                   per-app/per-page status + gate state (read-only)
```

Two hard gates run in series after generation — `fm-verify` (build/tsc/vitest) then `fm-parity`
(legacy equivalence) — with `fm-e2e` (Playwright) as the functional gatekeeper between them. A
route flip is allowed only when verify + e2e + parity all pass.

## Skills

| Skill | Purpose |
| --- | --- |
| `fm-init` | Initialize config + tracker |
| `fm-analyze` | Analyze a legacy Angular target → analysis.json |
| `fm-extract` | Lift logic into framework-agnostic `packages/shared-*` |
| `fm-plan` | analysis.json → migration-plan.json |
| `fm-gen` | Generate the RR v7 page via per-phase TDD |
| `fm-verify` | Technical gate: build / tsc / vitest |
| `fm-fix` | Targeted repair loop for verify/e2e/parity failures |
| `fm-e2e` | Playwright E2E gatekeeper (legacy dual-run, staging gateways) |
| `fm-parity` | Visual / contract / WebView / telemetry parity |
| `fm-route` | Strangler Fig route flip (2-PR feature flag) |
| `fm-progress` | Read-only migration dashboard |
| `fm-delta` | Incremental re-migration on legacy drift |
| `fm-clean-code` | Standalone code-quality audit |
| `fm-test-review` | Standalone test-quality audit |
| `fm-secret-audit` | Secret inventory + relocation guidance |

## Documentation

- `docs/workflow.md` — the per-page state machine, the gate chain, and the topology.
- `docs/skill-reference.md` — every skill and agent, with inputs/outputs and state effects.
- `CLAUDE.md` — conventions, state-file & lock rules, design principles (subagent isolation,
  evidence-before-claims), and the mapping/gate index.
- `templates/` — the Angular→React mapping catalog, shared-package spec/conventions, WebView
  bridge, Hana SSO, Strangler Fig routing, TDD rules, and the migration-plan schema.

Localized: `README.ko.md`, `README.vi.md`.
