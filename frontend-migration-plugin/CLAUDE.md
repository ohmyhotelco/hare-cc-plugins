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

> Status: **build complete (v0.2.1)** — all `fm-*` skills, agents, and templates are implemented
> (JIRA epic **AA-39**, tasks AA-40–AA-51). The plugin is feature-complete tooling; runtime
> execution targets a v2 monorepo (`apps/` + `packages/`) that the migration project scaffolds,
> and the PC end-to-end validation is the open follow-up. For the full build map, decisions, and
> source-confirmed corrections, see `docs/build-context.md`.

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
  "eslintTemplate": true,
  "prettierTemplate": true,
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
- `eslintTemplate` — when `true` (default), generators auto-scaffold `eslint.config.js` from
  `templates/eslint-config.md` where none exists; `false` skips ESLint entirely. See "Lint &
  Format Gate".
- `prettierTemplate` — when `true` (default), generators auto-scaffold `prettier.config.js` from
  `templates/prettier-config.md` where none exists; `false` skips formatting. Prettier is advisory
  (never blocks a gate). See "Lint & Format Gate".
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
Vitest / ESLint, plus an advisory Prettier check) then `fm-parity` (legacy equivalence).
`fm-e2e` (Playwright) is the functional gatekeeper between them. A route flip (`fm-route --flag-on`) is permitted only when
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

## Lint & Format Gate

ESLint and Prettier specs live in `templates/eslint-config.md` and `templates/prettier-config.md`.
This is the shared contract every skill/agent that scaffolds or checks them follows — they
reference this section rather than redefining the logic.

**Roles.** ESLint is a **hard** check (code quality + the `shared-domain` secret boundary);
Prettier is **advisory** (formatting only — reported, never blocks a gate or a route flip).
`eslint-config-prettier` keeps the two from conflicting.

**Scaffold-once layout** (monorepo, pnpm workspaces):
- Root, once: `eslint.config.base.js`, `prettier.config.js`, `.prettierignore`.
- Per app (`apps/web-*`): `eslint.config.js` leaf (core + react), scaffolded by
  `foundation-generator`.
- Per package (`packages/shared-*`): `eslint.config.js` leaf, scaffolded by `package-extractor`
  (`shared-domain` composes the secret-boundary block — see `shared-package-conventions.md`).

**Detection / scaffold / skip (uniform across `foundation-generator`, `package-extractor`,
`integration-generator`, `fm-verify`, `migration-fixer`):**
1. Glob for an existing config (`eslint.config.*` / `.eslintrc*`; `prettier.config.*` /
   `.prettierrc*`). If present → use it as-is.
2. If absent and the flag (`eslintTemplate` / `prettierTemplate`) is `true` or unset →
   generate from the template (root + the relevant leaf).
3. If absent and the flag is `false` → skip silently.
4. **Never auto-install deps.** If required packages (see each template's dependency list) are
   missing → skip the run, print the `pnpm add -D -w …` command, and mark `skipped` (not a
   failure).

**Commands** (from `{appDir}` / package dir — see "Build Command Working Directory"):
- ESLint: `npx eslint . 2>&1` — exit ≠ 0 is a **gate failure**.
- Prettier: `npx prettier --check . 2>&1` — exit ≠ 0 is an **advisory warning only**.

**Legacy is out of scope (required).** The gate applies to v2 surfaces only (`apps/web-*`,
`packages/shared-*`) — never to the legacy Angular apps (`apps/legacy-*`), which are being
strangled out, not maintained to the new rules. Three things enforce this:
1. Gate commands run from the new app's `appDir`/package dir, never from the monorepo root.
2. The shared ESLint file is `eslint.config.base.js` (an explicit import), **not** a root
   `eslint.config.js` — flat-config auto-discovery finds nothing at the root, and `apps/legacy-*`
   get no leaf config, so legacy is never linted.
3. `.prettierignore` lists the `legacyDir` paths from config (`apps/legacy-*`), so even a manual
   root `prettier` run or format-on-save skips legacy.
Never scaffold an ESLint/Prettier config inside a legacy app, and never promote
`eslint.config.base.js` to a root `eslint.config.js`.

**Secret-boundary exception.** The `shared-domain` `no-restricted-syntax`/`no-restricted-imports`
hit is always a hard rejection regardless of flags — the piece is routed to `fm-secret-audit`, not
shipped (OMH-477).

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

The WebView bridge and Hana SSO templates (`templates/webview-bridge.md`,
`templates/hana-sso.md`) are authored in **AA-46** and drive the `fm-parity` webview/sso checks.
The Strangler Fig routing template (`templates/strangler-fig.md`, authored in **AA-47**) drives
`fm-route`: the nginx host/path topology, the 2-PR flag flow, and the gate-guarded flip.

The lint/format templates (`templates/eslint-config.md`, `templates/prettier-config.md`) define the
monorepo's ESLint v9 flat config (composed per workspace, with the `shared-domain` secret boundary)
and the Prettier 3 config; they drive the scaffolding and checks described in "Lint & Format Gate".

Gate definitions (owning task):
- **verify** (AA-43): build, `tsc`, Vitest, and ESLint (hard) pass from `appDir`; Prettier
  `--check` runs as an advisory warning (non-blocking). See "Lint & Format Gate".
- **e2e** (AA-45): Playwright user-flow suite; legacy dual-run; staging for transactional pages.
- **parity** (AA-46): visual regression vs legacy baseline, API contract freeze diff,
  WebView bridge round-trip, telemetry dual-fire parity.

## Skills

All skills are implemented (v0.2.1). The "Built in" column records the task that delivered each
(provenance) — see `docs/skill-reference.md` for inputs/outputs and `docs/build-context.md` for
the full build map.

| Skill | Purpose | Built in |
| --- | --- | --- |
| `fm-init` | Initialize config + tracker | AA-40 |
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
