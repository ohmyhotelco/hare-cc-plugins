# Frontend Migration Plugin

A Claude Code plugin that drives the migration of the OhMyHotel Angular 15 apps to
React Router v7, following the revised v2 migration plan. It is **fully standalone** —
it carries its own agents and pipeline and does not depend on `frontend-react-plugin`
at runtime — but it deliberately **shares that plugin's stack conventions** so the
generated React code is consistent across the org.

The plugin's distinctive value over a greenfield generator is the four things wrapped
around code generation: **(1) Angular source analysis**, **(2) framework-agnostic
shared-package extraction**, **(3) legacy-parity gates**, and **(4) Strangler Fig
orchestration and tracking**.

> Scope today: this repository is being built task-by-task under JIRA epic **AA-39**.
> `fm-init` and the foundation conventions below ship in **AA-40**. Other `fm-*` skills
> are defined here as the target surface but are implemented in later tasks (see
> "Skills" below for the owning task of each).

## Target Stack

Aligned with `frontend-react-plugin`, with one deliberate divergence (E2E tool).

| Area | Choice | Notes |
| --- | --- | --- |
| Framework | React Router v7 (framework mode) | Per-route SSR / SSG / SPA decision (migration plan §5 / OMH-454 §5) |
| Language | TypeScript (strict) | Match legacy `tsconfig` strictness |
| Styling | Tailwind CSS | + `tailwind-merge`, `clsx` |
| UI primitives | shadcn/ui (+ bespoke domain) | Replaces ng-bootstrap; bespoke for HotelCard, RoomTypeCard, date-range picker, counter, payment-form bridges |
| Server state | TanStack Query | Replaces NgRx Effects' API-caching role |
| Client state | Zustand (thin) | UI state, search-form input, locale |
| HTTP | axios + interceptors | Replicates `HttpHelperService` session-expiry behaviour |
| Forms | react-hook-form + zod | DTO schemas shared in `shared-types` |
| i18n | i18next + react-i18next | Reuses the existing Google Sheets pipeline |
| Date | dayjs | + locale plugins |
| Unit / component | Vitest + Testing Library | |
| Network mock | MSW v2 | |
| **E2E / visual** | **Playwright** | **Divergence from `frontend-react-plugin` (agent-browser).** Required for visual-regression baselines (`toHaveScreenshot`), legacy-vs-new dual-run, and staging payment-gateway E2E |

## Configuration

`fm-init` writes `.claude/frontend-migration-plugin.json`:

```jsonc
{
  "monorepoRoot": ".",
  "packagesDir": "packages",
  "currentApp": "pc",
  "workingLanguage": "ko",
  "externalSkills": true,
  "apps": {
    "pc":     { "legacyDir": "apps/legacy-pc",     "targetDir": "apps/web-pc",     "appDir": "apps/web-pc",     "domain": "www.ohmyhotel.com",  "port": 30220, "ssr": "mixed", "webview": false,     "sso": false },
    "mobile": { "legacyDir": "apps/legacy-mobile",  "targetDir": "apps/web-mobile", "appDir": "apps/web-mobile", "domain": "m.ohmyhotel.com",    "port": 30221, "ssr": "mixed", "webview": true,      "sso": false },
    "hana":   { "legacyDir": "apps/legacy-mobile",  "targetDir": "apps/web-hana",   "appDir": "apps/web-hana",   "domain": "hana.ohmyhotel.com", "port": 30321, "ssr": "spa",   "webview": "unknown", "sso": true }
  }
}
```

- `currentApp` — the active surface for skills that operate on one app. PC-first.
- `workingLanguage` — `ko` | `en` | `vi`. All user-facing skill output is in this language.
- `externalSkills` — when `true`, `fm-init` installs Playwright, Vitest, and React Router skills.
- `apps.*.appDir` — the directory containing each app's `vite.config.*`, `tsconfig.json`,
  `package.json`. All build/test commands run from this directory (see "Build Command
  Working Directory"). Per-app because this is a monorepo with multiple target apps.
- `apps.*.webview` — `true` for surfaces loaded inside a native WebView (mobile),
  `false` for PC, `"unknown"` for Hana (pending stakeholder confirmation).
- `apps.*.sso` — `true` for Hana (external `?ts` SSO; migration plan §7).

PC is fully configured; `mobile`/`hana` entries are scaffolded — recognized now, validated
in later phases.

## Migration Workflow

```
/fm-init                  → write config + initialize docs/migration/tracker.json (once)

[Phase 0]  /fm-secret-audit → /fm-analyze → /fm-extract       (shared packages)

[per-page loop, repeated per page]
  /fm-analyze → /fm-plan → /fm-gen → /fm-verify
                                        │ (fail → /fm-fix)
                              /fm-e2e   (Playwright gatekeeper; fail → /fm-fix)
                              /fm-parity (visual / contract / WebView / telemetry; fail → /fm-fix)
                              /fm-route --flag-off (PR1) → --flag-on (PR2)

/fm-delta                 → re-migrate only the changed surface when legacy source updates
/fm-progress              → per-app / per-page status + gate state (always available)
```

Two hard gates run in series after generation: `fm-verify` (technical: build / tsc /
Vitest) then `fm-parity` (legacy equivalence). `fm-e2e` (Playwright) is the functional
gatekeeper between them. A route flip (`fm-route --flag-on`) is permitted only when
`fm-verify`, `fm-e2e`, and `fm-parity` all pass for the page.

## Per-page State Machine

Each migrated page advances through these states, tracked in `tracker.json` and the
per-page state directory:

```
analyzed → planned → generated → verified → e2e-passed → parity-passed → flipped → done
              ↓          ↓           ↓            ↓             ↓
          (each stage may enter) *-failed → fixing → (re-run the failed gate)
                                       ↓
                                  escalated   (needs manual intervention)
```

- A gate failure sets `{stage}-failed`; `fm-fix` moves it to `fixing` and, on success,
  back to the gate's passed state. Large fixes (>60% files) suggest full `fm-gen`.
- `fm-delta` re-enters from `planned`/`generated` when legacy source drifts.
- `escalated` requires manual intervention, then re-entry via `fm-fix`/`fm-gen`.

## State Files & Lock Convention

State files keep the multi-skill pipeline resumable. Layout:

```
docs/migration/
├── tracker.json                       ← global: per-app/per-page status, package extraction
└── {app}/{page}/
    ├── analysis.json                  ← fm-analyze
    ├── migration-plan.json            ← fm-plan
    ├── generation-state.json          ← fm-gen (resume)
    ├── e2e-report.json                ← fm-e2e
    ├── parity-report.json             ← fm-parity
    ├── fix-report.json                ← fm-fix
    ├── delta-plan.json                ← fm-delta (active; archived as delta-plan.{ts}.json)
    └── .lock                          ← held by a writing skill
```

**Read-Modify-Write rule.** When updating any state JSON:
1. Read the **latest** file content immediately before writing — never use data cached
   earlier in the session.
2. Merge only the fields being changed; preserve all existing fields.
3. Write the complete merged object.

**Lock file.** A skill that mutates state acquires `{app}/{page}/.lock` before work and
releases it on completion or failure. A lock older than **30 minutes** is stale and may be
removed. Interrupt-style skills (e.g. a future `fm-debug`) are the only exception and do
not take the lock.

## Design Principles

These apply to every agent and skill in this plugin.

- **Subagent isolation.** Subagents never inherit session history. A coordinator
  constructs only the parameters each agent needs — no conversation context leaks between
  phases. This prevents context pollution and ensures fresh judgement per task.
- **Evidence before claims, always.** Never report a result you have not observed. Use the
  5-step gate: **IDENTIFY** the target → **RUN** the tool → **READ** the full output (exit
  code, counts) → **VERIFY** the output matches the claim → **CLAIM** citing evidence.

  Verification red flags (these thoughts mean you are rationalizing):

  | Thought | Reality |
  | --- | --- |
  | "Should work" / "probably fine" | Run the tool. Evidence or silence. |
  | "The change is small, no need to verify" | Small changes cause big bugs. |
  | "I already verified earlier" | Code changed since. Verify again. |
  | "tsc passed, so the build will too" | Different tools catch different errors. |
  | "Tests passed, so it matches legacy" | Parity is a separate gate. Run it. |

  In this plugin a false pass is especially costly: `fm-e2e` and `fm-parity` are the only
  thing standing between a regression and production.
- **Communication language.** Read `workingLanguage` from config (default `ko`). All
  user-facing output — summaries, questions, next-step guidance — is in that language.
  Code, identifiers, and committed `.md` files are always English.
- **SKILL.md frontmatter.** Every skill declares `name`, `description`, `argument-hint`,
  `user-invocable`, `allowed-tools`.
- **Agent vs Task.** Use the `Agent` tool for strictly sequential, dependent phases
  (TDD steps where each depends on the previous). Use `Task` for independent work that can
  run in parallel.

## Build Command Working Directory

All build/test commands (`npx vite`, `npx vitest`, `npx tsc`, `npx playwright`,
`npx eslint`) run from the target app's `appDir` (from config). This is a monorepo, so
`appDir` is per-app (e.g. `apps/web-pc`).

- If `appDir` is `"."` → run from the monorepo root (no prefix).
- Otherwise → prefix with `cd {monorepoRoot}/{appDir} && …`.

**TypeScript check — composite config detection.** Vite projects commonly use a composite
`tsconfig` with `references`:
1. Read `tsconfig.json` in `{appDir}`.
2. If it has a `references` array → `npx tsc -b 2>&1`.
3. Otherwise → `npx tsc --noEmit 2>&1`.

## Mapping Catalog & Gate Definitions

The Angular→React mapping catalog and the shared-package spec live under `templates/`
(authored in **AA-41**):
- `templates/angular-to-react-mapping.md` — idiom-by-idiom mapping grounded in the real PC /
  Mobile / Hana source, with `file:line` anchors. Sections carry stable ids the analyzer
  references via `analysis.json.mappingNotes[].catalogRef`.
- `templates/shared-package-spec.md` — the six `packages/` and the purity classification.

Source-confirmed corrections folded into the catalog: legacy i18n is **angular-i18next**
(`| i18next`, `tl.*` keys, Google Sheets remote) — React reuses i18next; components reach the
NgRx store only through a **Facade layer** (`*.facade.ts`) → maps to a custom hook; the Mobile
**WebView** surface is primarily UA detection (`wv`/`ww`) + `universal-link.service` +
`sessionStorage`, not an explicit `window.ohmyhotelAndroid` bridge (AA-46 reconciles).

The WebView bridge and Hana SSO templates are authored in **AA-46**
(`webview-bridge.md`, `hana-sso.md`); the Strangler Fig routing template in **AA-47**
(`strangler-fig.md`).

Gate definitions (owning task):
- **verify** (AA-43): build, `tsc`, Vitest pass from `appDir`.
- **e2e** (AA-45): Playwright user-flow suite; legacy dual-run; staging for transactional pages.
- **parity** (AA-46): visual regression vs legacy baseline, API contract freeze diff,
  WebView bridge round-trip, telemetry dual-fire parity.

## Skills

| Skill | Purpose | Owning task |
| --- | --- | --- |
| `fm-init` | Initialize config + tracker | AA-40 (this) |
| `fm-analyze` | Analyze a legacy Angular target → analysis.json | AA-41 |
| `fm-extract` | Lift logic into framework-agnostic `packages/shared-*` | AA-42 |
| `fm-plan` / `fm-gen` / `fm-verify` | Generate an RR v7 page via TDD | AA-43 |
| `fm-fix` | Targeted repairs that close the gate loops | AA-44 |
| `fm-e2e` | Playwright E2E gatekeeper | AA-45 |
| `fm-parity` | Visual / contract / WebView / telemetry parity | AA-46 |
| `fm-route` / `fm-progress` | Strangler Fig routing + progress dashboard | AA-47 |
| `fm-delta` | Incremental re-migration on legacy drift | AA-48 |
| `fm-clean-code` / `fm-test-review` | Code-quality / test-quality audit | AA-49 |
| `fm-secret-audit` | Secret inventory + relocation guidance | AA-50 |

## File Structure

```
.claude-plugin/  - Plugin manifest (plugin.json)
CLAUDE.md        - This file (conventions, state machine, design principles)
skills/          - Skill entry points (fm-*)
agents/          - Agent definitions
hooks/           - Hook configuration (hooks.json)
scripts/         - Hook handler scripts
templates/       - Mapping catalog, package spec, gate templates
docs/            - Documentation
```

## Version Sync Rule

When changing `version`, `keywords`, or `description` in
`.claude-plugin/plugin.json`, update the corresponding entry in the root
`.claude-plugin/marketplace.json` **in the same commit** (repo-wide rule in the root
`CLAUDE.md`).
