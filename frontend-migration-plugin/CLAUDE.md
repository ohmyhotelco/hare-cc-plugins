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

> Status: **feature-complete tooling (v1.2.0)** — all `fm-*` skills, agents, and templates are
> implemented. Runtime execution targets a v2 monorepo (`apps/` + `packages/`) that the migration
> project scaffolds; the PC end-to-end validation is the open follow-up.
>
> The version-by-version history that used to sit here lives in `docs/build-context.md`, which
> already carried the same narrative — along with the full build map, the decisions behind each
> rule, and the source-confirmed corrections. The **rules** those versions introduced are stated
> in their own sections below: "i18n Copy Parity", "Self-confirmation Hardening", "Artifact
> Provenance & Answer-key Sourcing", "Gate Cost & Preconditions", and "Gate Result Accounting".

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

## External Skills (shared with frontend-react-plugin)

The generic React/test knowledge is **not** re-authored here — it is the same upstream skill set
`frontend-react-plugin` uses, installed by `fm-init` (`externalSkills`, default on) through the same
`npx skills add … -a claude-code -y --copy` mechanism and vendored under `.claude/skills/`. This
keeps generated React consistent across the org. Migration-specific knowledge (Angular→React mapping,
Strangler Fig, WebView/SSO) stays in `templates/` — the dividing line is *generic → shared skill,
migration-specific → bundled template*.

| Skill | Source | Loaded by (per phase) | Notes |
| --- | --- | --- | --- |
| `react-router-framework-mode` | `remix-run/agent-skills` | `integration-generator`, `tdd-cycle-runner` (page), `quality-reviewer`, `migration-fixer`, `delta-modifier` | **framework mode** (not declarative/data) — matches the RR v7 + per-route SSR/SSG/SPA target |
| `vitest` | `antfu/skills` | every TDD phase (`tdd-cycle-runner`, `package-extractor`, fixers, `quality-reviewer` tests) | unit/component test patterns |
| `vercel-react-best-practices` | `vercel-labs/agent-skills` | `tdd-cycle-runner` (page), `quality-reviewer`, fixers | applied **SSR-aware** — framework mode is not a Vite SPA, so the SSR/RSC rules are **not** skipped (inversion vs `frontend-react-plugin`) |
| `vercel-composition-patterns` | `vercel-labs/agent-skills` | `tdd-cycle-runner` (component), `quality-reviewer`, fixers | component composition rules |

Loading is **guarded by existence, not by the flag**: each agent Reads a skill's `SKILL.md` only
when present, and none of them receives or reads `externalSkills`. So the flag governs whether
`fm-init` installs them and whether the session hook warns about their absence — **not** whether an
agent applies one it finds. Turning it off after an install, or in a project where another plugin
vendored the same skills, leaves them in use; remove the directories to actually stop that. A
non-blocking/declined install (or `externalSkills: false`) degrades gracefully — the skill is
skipped, never an error. `web-design-guidelines` and `agent-browser` (used by `frontend-react-plugin`)
are intentionally **not** adopted: UI fidelity here is judged by `fm-parity` against the legacy
baseline, and E2E runs on Playwright.

**Playwright trace analysis** is built into the CLI (`npx playwright show-trace`) — no skill
required; it is the primary evidence `fm-fix` (e2e-fix) reads to self-correct. Playwright's own
**test agents** (planner / generator / healer, `npx playwright init-agents --loop=claude` →
`.claude/agents/` + a Playwright MCP `.mcp.json`) are a separate subagent system, **not** a
loadable skill, and are **intentionally not adopted**: this plugin already has equivalents
(`migration-planner` / `e2e-test-runner` / `migration-fixer`) with the migration-specific **legacy
dual-run** the healer cannot do. Their value — trace-driven self-correction — is captured via
`show-trace` instead.

## Configuration

`fm-init` writes `.claude/frontend-migration-plugin.json`:

```jsonc
{
  "monorepoRoot": ".",
  "pluginRoot": "/Users/you/.claude/plugins/cache/…/frontend-migration-plugin/<version>",  // absolute; where scripts/ lives
  "packagesDir": "packages",
  "contractsDir": "docs/migration/api-contracts",   // optional; recorded only when the dir exists
  "currentApp": "pc",
  "workingLanguage": "ko",
  "i18n": {                                         // the PRODUCT's copy surface (not workingLanguage)
    "localesDir": "packages/shared-i18n/src/locales",
    "languages": ["KO", "EN", "JA", "ZH", "VI"],    // what "every supported language" resolves to
    "lookupFns": ["t", "tl"],
    "keyPrefix": "tl."
  },
  "externalSkills": true,
  "eslintTemplate": true,
  "prettierTemplate": true,
  "codexAudit": true,
  "codexAuditStages": ["analyze", "plan", "gen", "verify", "e2e", "parity", "route"],
  "apps": {
    "pc":     { "legacyDir": "apps/legacy-pc",     "targetDir": "apps/web-pc",     "appDir": "apps/web-pc",     "domain": "www.ohmyhotel.com",  "port": 30220, "legacyPort": 30210, "ssr": "mixed", "webview": false,     "sso": false, "flipMechanism": "nginx", "infraDir": "infra/nginx" },
    "mobile": { "legacyDir": "apps/legacy-mobile",  "targetDir": "apps/web-mobile", "appDir": "apps/web-mobile", "domain": "m.ohmyhotel.com",    "port": 30221, "legacyPort": 30211, "ssr": "mixed", "webview": true,      "sso": false, "flipMechanism": "nginx", "infraDir": "infra/nginx" },
    "hana":   { "legacyDir": "apps/legacy-mobile",  "targetDir": "apps/web-hana",   "appDir": "apps/web-hana",   "domain": "hana.ohmyhotel.com", "port": 30321, "legacyPort": 30311, "ssr": "spa",   "webview": "unknown", "sso": true,  "flipMechanism": "nginx", "infraDir": "infra/nginx" }
    // `flipMechanism` above is ILLUSTRATIVE, not a recommendation: `fm-init` asks per app, and a
    // `cloudfront` app records `cloudfrontDir` + `manifest` instead of `infraDir`.
  },
  "stagingConfig": {
    "baseUrl": "https://staging.ohmyhotel.com",
    "paymentGateways": { "nicePay": "", "eximbay": "", "kakaoPay": "" }
  }
}
```

- `currentApp` — the active surface for skills that operate on one app. PC-first. **A skill that
  resolves an app must confirm `apps[app]` exists and carries the keys it is about to use** (at
  minimum `appDir`; plus `targetDir`/`legacyDir`/ports for the stage it runs). Config-file presence
  is not app presence: a `--app hana` on a config scaffolded for `pc` only would otherwise fail deep
  inside an agent with an unresolved path rather than at Step 0 with a clear message.
  **Every page-scoped command a skill, agent, or hook prints carries `--app {app}` whenever `app`
  is not `currentApp`** — the reader pastes it into a fresh invocation, which resolves the app from
  `--app` or `currentApp` and would otherwise act on a different app's page of the same name.
  `fm-analyze` Step 1.3 derives a page's counterparts at the same relative path under the other
  apps' `legacyDir`, so one key under several apps is the normal case, and the wrong-app run is not
  visible in its output. Stated once here rather than at each of the ~36 sites that print one.
  The `{app}` to interpolate is the one the *named page* lives under — `docs/migration/{app}/{page}/`
  — which is not always the printing skill's own `app`: `fm-extract` is one skill resolving one app
  while its dependent pages span all three.
- `pluginRoot` — the **absolute** path this plugin is installed at, written and refreshed by the
  SessionStart hook (`scripts/session-init.sh`), which is the only component that can know it. It is
  how `fm-verify`/`fm-e2e`/`fm-parity`/`fm-route`/`fm-progress` locate
  `scripts/gate-tree-hash.sh`. The hook rewrites it **every session**, never capturing it once —
  the cache path is version-pinned. Absent → those skills record no `tree` and report the freshness
  axis as `unverifiable`; they must not improvise an inline hash pipeline.
- `contractsDir` — **optional**. Path to the confirmed backend verification contracts
  (default `docs/migration/api-contracts`, OMH-604/606/607) that are the **authoritative**
  schema source for **`shared-types` and `shared-data` only** (migration plan §5 — the legacy
  `any` reverse-extraction is retired for the contract-covered surface). `fm-init` records the key
  **only when the directory exists**; absent → `fm-extract` falls back to legacy reverse-extraction
  (no regression). The other four packages (`config`/`i18n`/`domain`/`ui`) ignore it.
  `fm-extract` Step 3 states how the contracts are read; `templates/shared-package-spec.md`
  states what they cover.
- `workingLanguage` — `ko` | `en` | `vi`. All user-facing skill output is in this language.
  **Not** the set of languages the product serves — that is `i18n.languages`.
- `i18n` — **optional but gate-relevant**. Declares the product's copy surface so the gates can check
  it: `localesDir` (translation resources), `languages` (the supported set), `lookupFns` (the i18n
  lookup helpers whose key literals are checked, default `["t","tl"]`), `keyPrefix` (key convention,
  e.g. `tl.`). `languages` is what "every supported language" **resolves to**, and the planner writes
  it into **`gateAcceptance.visual.languages` and `gateAcceptance.e2e.languages`** — the fields the
  executors read. (`gateAcceptance.scope` is prose describing the scope; it is not where a language
  set is read from.) Absent → `foundation-generator` skips the i18n key-coverage spec and
  `fm-verify` reports it as `skipped`, never a silent pass. See "i18n Copy Parity" and
  `templates/i18n-copy-parity.md`.
- `externalSkills` — when `true` (default), `fm-init` installs the shared skills and verifies the
  Playwright CLI. Agents load each SKILL.md guarded by existence, so an absent one is skipped,
  never fatal. See "External Skills (shared with frontend-react-plugin)".
- `eslintTemplate` — when `true` (default), generators auto-scaffold `eslint.config.js` from
  `templates/eslint-config.md` where none exists; `false` skips ESLint entirely. See "Lint &
  Format Gate".
- `prettierTemplate` — when `true` (default), generators auto-scaffold `prettier.config.js` from
  `templates/prettier-config.md` where none exists; `false` skips formatting. Prettier is advisory
  (never blocks a gate). See "Lint & Format Gate".
- `codexAudit` — when `true` (default), the pipeline runs an independent **Codex audit** of each
  stage's artifact (advisory). Auto-skips if the Codex CLI/runtime is absent, so default-on is
  safe. See "Codex Independent Audit".
- `codexAuditStages` — which stages the in-loop Codex audit covers. **Absent → all seven** (the key
  narrows; it never means "none"). Every consumer applies that default.
- `apps.*.appDir` — the directory containing each app's `vite.config.*`, `tsconfig.json`,
  `package.json`. All build/test commands run from this directory (see "Build Command
  Working Directory"). Per-app because this is a monorepo with multiple target apps.
- `apps.*.port` / `apps.*.legacyPort` — the new app's serving/dev port and the **legacy** app's
  upstream port for this surface. `fm-route` resolves both and passes them to
  `strangler-orchestrator`, which routes `guardsPath` to `port` on flag-on and lets unmatched paths
  fall through to `legacyPort` (the legacy app). Values mirror `templates/strangler-fig.md`.
- `apps.*.webview` / `apps.*.sso` / `apps.*.ssr` — **informational only. Do not branch on these
  three.** The gate set comes from `analysis.json` `requiredGates`/`gateTriggers`; the rendering
  mode is decided per page in `migration-plan.json`.
- `apps.*.flipMechanism` — `nginx` (default) | `cloudfront`. Which edge layer the Strangler Fig
  route flip is prepared at **for this app**. The flip *semantics* are identical across mechanisms;
  only the **edited artifact** differs. An app with no `flipMechanism` is treated as `nginx`.
  - `nginx` → `apps.*.infraDir` (default `infra/nginx`): the in-repo nginx host/path routing block
    + flag entry `fm-route` edits.
  - `cloudfront` → `apps.*.cloudfrontDir` (default `infra/cloudfront`) + `apps.*.manifest`
    (default `v2-routes.json`): a **version-controlled** CloudFront behavior manifest that maps
    `guardsPath` path-patterns to the v2 origin. `fm-route` edits only this in-repo manifest, for
    a PR the user opens — it **never pushes to AWS**.

  Which app uses which is project config, decided at `fm-init`. See `templates/strangler-fig.md`.
- `apps.*.infraDir` — nginx flip only (default `infra/nginx`). Ignored when
  `flipMechanism` is `cloudfront`.
- `apps.*.cloudfrontDir` / `apps.*.manifest` — cloudfront flip only (defaults `infra/cloudfront` /
  `v2-routes.json`). Ignored when `flipMechanism` is `nginx`.
- `stagingConfig` — the staging base URL and payment-gateway **test** endpoints (`nicePay` /
  `eximbay` / `kakaoPay`, OMH-459) that `fm-e2e` passes to `e2e-test-runner` for transactional
  scenarios. Transactional E2E runs against these, never production. Scaffolded empty (PC-first);
  filled in when the first transactional page is reached.

PC is fully configured; `mobile`/`hana` entries are scaffolded — recognized now, validated
in later phases.

## Migration Workflow

```
/fm-init                  → write config + initialize docs/migration/tracker.json (once)

[Phase 0]  /fm-secret-audit → /fm-analyze → /fm-extract       (shared packages)

[per-page loop, repeated per page]
  /fm-analyze → /fm-style-spec → /fm-plan → /fm-gen → /fm-verify
                                        │ (fail → /fm-fix)
                              /fm-cascade (stylesheet-level diff vs legacy; needs legacy's CSS,
                                           not a running legacy host. Run it for any page that
                                           injects markup it does not author — CMS rich text,
                                           i18n values containing HTML, editor output; advisory —
                                           fm-route reports a missing run, it does not block on one)
                              /fm-e2e   (Playwright gatekeeper; fail → /fm-fix)
                              /fm-parity (visual / contract / WebView / telemetry; fail → /fm-fix)
                              /fm-route --flag-off (PR1) → --flag-on (PR2) → --confirm-live

/fm-delta                 → re-migrate only the changed surface when legacy source updates
/fm-progress              → per-app / per-page status + gate state (always available)
```

Two hard gates run in series after generation: `fm-verify` (technical: build / tsc /
Vitest / ESLint, plus an advisory Prettier check) then `fm-parity` (legacy equivalence).
`fm-e2e` (Playwright) is the functional gatekeeper between them. A route flip (`fm-route --flag-on`) is permitted only when
`fm-verify`, `fm-e2e`, and `fm-parity` all pass for the page.

`fm-cascade` sits between `fm-verify` and `fm-e2e` and is **evidence, not a status** — it does not
advance the page. It exists because the other stages share a structural blind spot: `fm-style-spec`
is element-indexed (it probes what `analysis.json.styleSurface` names), generated unit tests run in
jsdom (which applies no CSS at all), and `fm-parity` needs both hosts live and is the stage most
often blocked. Markup the page does not author — CMS rich text, i18n values containing HTML, editor
output — falls through all three: hundreds of nodes that no index can enumerate, and when
`fm-parity` is blocked the page ships with zero style evidence for most of its DOM. `fm-cascade`
covers it with legacy's compiled CSS alone. Each divergence it finds is fixed, or recorded in
`owner-decisions.md` with a reason; `fm-route --flag-on` refuses while unresolved, unrecorded ones
remain — the same handling as Codex `high` findings. See `docs/design/cascade-diff-gate.md`.

## Per-page State Machine

Each migrated page advances through these states, tracked in `tracker.json` and the
per-page state directory:

```
analyzed → style-specced → planned → generated → verified → e2e-passed → parity-passed → flipped → done
                 ↓            ↓          ↓           ↓            ↓             ↓
          (each stage may enter) *-failed → fixing → generated → (re-run the whole chain)
                                       ↓
                                  escalated   (needs manual intervention)
```

- **`gen-failed` is not a gate failure and `fm-fix` has no mode for it.** A generation phase that
  never completed goes back to `fm-gen`, which resumes from the incomplete phase. The SessionStart
  hook and `fm-progress` both carve it out ahead of the `*-failed` wildcard.
- A gate failure sets `{stage}-failed`; `fm-fix` moves it to `fixing` and, on success, to
  **`generated`** — the whole chain re-runs from `fm-verify`, and `fm-fix` clears `gateEvidence`,
  the legacy `*At` fields and `routePrepared`/`flagKey` exactly as `fm-gen` and `fm-delta` do.
  **A fix changes code, so it invalidates every gate, not just the one it repaired**, and **only
  the gate issues its own passed state** — a fixer never promotes a page. Large fixes (>60% files)
  suggest full `fm-gen`.
- **`flipped` means the edge is serving v2, and `flipPrOpenedAt` is the hand-over, not a PR the
  plugin can see.** `fm-route --flag-on` edits the in-repo routing artifact **for** PR2 — the user
  opens the PR, as they do the code PR on `--flag-off` — records `flipPrOpenedAt`, and leaves the
  status at `parity-passed`. Only `--flag-on --confirm-live`, run by a human after the merge and
  deploy have propagated, sets `flipped`. Nothing here deploys or can see a forge, so nothing here
  can claim either on its own. Provenance resolves a capture's `side` from this status.
- **No skill writes a status over `flipped` or `done` except `fm-route --revert` on `flipped`,**
  which is the sanctioned rollback and must be able to leave that state. `done` has **no** such
  exception: the legacy page has been deleted, so there is nothing to roll back to and no legacy
  source left to diff against — reopening a `done` page is a manual decision, not a skill
  transition. A refusal must name `done` explicitly, because "at least `generated`"-style monotonic
  comparisons satisfy it silently.
- **No skill writes a status, or rewrites the page's code, while `flipPrOpenedAt` is present —
  except `fm-route`'s own `--confirm-live` and `--revert`.** Those two are the field's only legal
  consumers: `--confirm-live` *requires* it (it is what proves a flip is in flight) and clears it
  while writing `flipped`; `--revert` clears it while rolling back. Repeated `--flag-off` or a plain
  `--flag-on` on a page that already has it are refused — that would prepare a second flip over an
  in-flight one. Every other status writer refuses and points at `fm-route --revert`, for an
  in-flight flip and for `flipped`; **`done` gets manual intervention instead**, since `--revert`
  refuses it too. `--flag-off` keeps the status, so it is never the way out of `flipped`.
- No gate accepts `fixing` as an entry state. A page at `fixing` is re-entered through `fm-fix`
  (or `escalated` for manual intervention) — never by invoking a gate directly.
- `fm-delta` re-enters from `generated` or beyond when legacy source drifts (a `planned` page has
  no generated files to modify — use `fm-gen`).
- `escalated` requires manual intervention, then re-entry via `fm-fix`/`fm-gen`.
- `flipped` is where the `fm-*` pipeline ends; no skill advances past it. **`done` is set by hand**,
  once the legacy page is deleted — retiring legacy code is outside this plugin's scope.
  `fm-progress` and the SessionStart hook print no next command for either.

## State Files & Lock Convention

State files keep the multi-skill pipeline resumable. Layout:

```
docs/migration/
├── tracker.json                       ← global: per-app/per-page status, package extraction
├── .packages.lock                    ← fm-extract (package-scope lock; same JSON schema as the
│                                        page `.lock` below, but guards `packages/shared-*` work,
│                                        which is not page-scoped)
└── {app}/{page}/
    ├── analysis.json                  ← fm-analyze
    ├── style-spec.json                ← fm-style-spec
    ├── migration-plan.json            ← fm-plan
    ├── generation-state.json          ← fm-gen (resume)
    ├── cascade-diff.json              ← fm-cascade (classified; fm-route reads its `real` rows)
    ├── cascade-diff.raw.json          ← fm-cascade (the differ script's raw measurement)
    ├── e2e-report.json                ← fm-e2e
    ├── parity-report.json             ← fm-parity
    ├── fix-report.json                ← fm-fix
    ├── delta-plan.json                ← fm-delta (active; archived as delta-plan.{ts}.json)
    ├── migration-plan.next.json       ← fm-delta staging: the planner's PROPOSED baseline. Step 5
    ├── analysis.next.json               promotes both over the canonical files after the delta
    │                                    applies; the Full branch and Step 0 delete them. Their mere
    │                                    presence is not a baseline.
    ├── gate-tree/{gate}.tsv           ← fm-verify / fm-e2e / fm-parity: the per-file manifest behind
    │                                    gateEvidence.{gate}.tree, so fm-route can name WHICH files
    │                                    moved. Excluded from the hash it describes.
    └── .lock                          ← held by a writing skill
```

### Read-Modify-Write rule

When updating any state JSON:
1. Read the **latest** file content immediately before writing — never use data cached
   earlier in the session.
2. Merge only the fields being changed; preserve all existing fields.
3. Write the complete merged object.

### Lock file

A skill that mutates state acquires `{app}/{page}/.lock` before work and
releases it on completion or failure. **Every exit after a successful acquire releases every lock
this run holds — including a refusal, an agent that refuses, a failed verification, and a stop the
skill's own text prescribes.** A per-step release sentence is a reminder, never the whole rule.
A *failed* acquire does not release **that** lock — it belongs to someone else — but the run still
releases every lock it did acquire.

**Re-verify, under the lock, every precondition you read before taking it.** Page skills refuse on
status or route state and acquire the lock further down, so the state can move in between; the
checks are cheap and the first write has not happened yet. The lock is JSON with at least these
fields:

**Three lock scopes, and one of them is not optional.**

| Lock | Scope | Held by |
| --- | --- | --- |
| `docs/migration/{app}/{page}/.lock` | one page's work | the 11 page skills + `codex-auditor` |
| `docs/migration/.packages.lock` | `packages/shared-*` work | `fm-extract` |
| **`docs/migration/.tracker.lock`** | **every Read-Modify-Write of `tracker.json`** | **all of the above** |
| **`docs/migration/.app.lock`** | **every Read-Modify-Write of an app-wide file** — the RR v7 route table, the i18n namespace registration, the MSW handler aggregation, and the `infraDir`/`cloudfrontDir` routing artifact | **`integration-generator`, `strangler-orchestrator`, `foundation-generator`, `delta-modifier`** |

The page lock does **not** protect `tracker.json`: no lock is common to a page skill and
`fm-extract`, and two page locks do not exclude each other. Two pages in flight is a supported
state, so two concurrent RMWs of that one file is too.

**Ordering is mandatory and one-directional: page lock (or `.packages.lock`) → `.app.lock` → `.tracker.lock`.**
Never the reverse, or two sessions deadlock. Hold `.tracker.lock` only across the read-modify-write
itself — open it, re-read `tracker.json`, apply your change, write, release — never across an agent
launch, a gate run, or any other long step. Same JSON schema and same 30-minute staleness rule as
the other two.

```json
{ "holder": "fm-parity", "pid": 49402, "acquiredAt": "2026-07-31T15:21:04+09:00" }
```

- `acquiredAt` — ISO-8601 **with time**, not date-only. Once the holder is gone, a date-only or
  unparseable value is **immediately sweepable**; it never makes a live holder's lock removable.
- `pid` — the id of a process that lives as long as the work does. **`$$` from a skill's one-shot
  Bash call is useless** — that pid is already dead and soon recycled. Record the enclosing session
  process, or omit `pid` entirely, which is honest. When absent, `acquiredAt` alone decides.
- **Guard against pid reuse.** Confirm the running process is plausibly the holder (its command
  matches `holder`); if it clearly is not, treat the lock as holder-less and apply the age rule.
- **The 30-minute rule is a ghost-lock sweep, not a timeout. Never break a lock whose `pid` is
  still alive, however old it is** — gates legitimately run past 30 minutes. Check `pid` first;
  only when it is absent or dead does `acquiredAt` decide.
- Optional context (`purpose`, `precondition`, `app`, `page`) — recommended, not required.

A lock may be removed only when its **holder is gone**: `pid` absent, or no live process with that
id, or a live process whose identity does not match `holder`. `acquiredAt` older than **30 minutes**
is the *additional* condition for removing a holder-less lock — never a reason on its own. See the
`pid` bullet above; the two rules are one rule, and age alone never breaks a live gate. Interrupt-style
skills (e.g. a future `fm-debug`) are the only exception and do not take the lock.

## Design Principles

These apply to every agent and skill in this plugin.

- **Subagent isolation.** Subagents never inherit session history. A coordinator
  constructs only the parameters each agent needs — no conversation context leaks between
  phases. This prevents context pollution and ensures fresh judgement per task.
- **Evidence before claims, always.** Never report a result you have not observed. Use the
  5-step gate: **IDENTIFY** the target → **RUN** the tool → **READ** the full output (exit
  code, counts) → **VERIFY** the output matches the claim → **CLAIM** citing evidence.

  **The gate is not limited to tool output.** A statement about the *state of the evidence* —
  "both sides were measured", "only one side was observed", "M of N locales are covered" — is
  itself a claim, so it needs the same treatment: enumerate the artifacts and quote their values.
  Deducing evidence coverage from configuration or deployment topology is **not** observation
  (routing decides what a URL serves; it does not decide what a capture aimed at a local build was
  able to measure).

  **Provenance first — a file name is not evidence of origin.** Which side a captured artifact
  counts as evidence for (`legacy` or `v2`) is decided **only** by its recorded provenance. File
  names, directory locations, and report prose are not grounds. Every capture artifact records
  `origin` (URL incl. host:port), `side`, `authState`, `renderSource`, `responseSource`,
  `captureMode`, and `capturedAt`, and those values are written by the **code that performs the
  capture** — not by the agent that later reports on it. Gates resolve `side` from the host:port
  against config (`apps.*.legacyPort` / `apps.*.port` / declared hosts) and the path's flip state,
  never from the name. An artifact whose side does not resolve is treated as **absent**, not as the
  side its name claims. The full field set, the ordered resolution rules, and the
  new-captures-only scope are in `templates/capture-provenance.md`; this rule governs captures taken
  from here on — existing artifacts are not retro-filled and already-passed pages are not
  re-adjudicated.

  Verification red flags (these thoughts mean you are rationalizing):

  | Thought | Reality |
  | --- | --- |
  | "Should work" / "probably fine" | Run the tool. Evidence or silence. |
  | "The change is small, no need to verify" | Small changes cause big bugs. |
  | "I already verified earlier" | That observation is stale — the code changed since. Cite a current run, not a remembered one. |
  | "tsc passed, so the build will too" | Different tools catch different errors. |
  | "Tests passed, so it matches legacy" | Parity is a separate gate. Run it. |
  | "The file is named `legacy-*`, so it is a legacy render" | A file name is a claim. Read the recorded provenance. |
  | "The file exists and opens, so I observed it" | Existence is not origin. Opening an artifact and confirming where it came from are different acts. |
  | "Routing sends only /ko to v2, so only /ko could be measured" | Routing decides what a URL serves. It does not decide what a capture against a local build can measure. |
  | "I know what is in that artifact without opening it" | A coverage statement is a claim. Enumerate the files and quote the values. |

  In this plugin a false pass is especially costly: `fm-e2e` and `fm-parity` are the only
  thing standing between a regression and production.
- **Gate criteria are codified, not reinterpretable.** Each gate's acceptance criteria live in
  `migration-plan.json.gateAcceptance` (`templates/migration-plan-schema.md`) and bind every
  level verbatim — skill delegation prompt, verifier agent, orchestrator summary. A criterion
  that cannot be met is a **fail or an explicit approval request — never a silent pass**; scope
  reduction at any level is a gate failure.
  Scope moves in both directions. Reduction is the failure this rule was written for; widening is the
  same failure mirrored — do not add gates, criteria, files, or behavior the plan does not call for,
  and do not apply your own judgement about what the task should have been. In a parity migration an
  unrequested addition is not merely extra work, it is a divergence from legacy, which is the thing
  the gates exist to catch. If the plan looks wrong, say so in a sentence and execute it as written;
  amending it is the decision owner's job (`criterionAmendment`), never the executor's.
- **Communication language.** Read `workingLanguage` from config (default `ko`). All
  user-facing output — summaries, questions, next-step guidance — is in that language.
  Code, identifiers, and committed `.md` files are always English.
  Keep that output to the length the result needs: lead with the outcome (gate pass/fail, what
  changed, what is blocked), then the evidence it rests on, then the next step. The JSON report is
  the complete record — the final message is a readout of it, not a second copy of it.
- **SKILL.md frontmatter.** Every skill declares `name`, `description`, `argument-hint`,
  `user-invocable`, `allowed-tools`.
- **Delegation is named, not improvised.** Every phase that delegates names its agent explicitly
  (`fm-gen` → the `buildOrder` agents, `fm-parity` → `parity-verifier`, and so on); launch it with
  the `Agent` tool and only its declared params. Do not spawn an agent the skill did not name — in
  particular, never spawn a reviewer or a second agent to verify or double-check work a gate already
  covers. Verification belongs to the gate that owns it; `fm-clean-code` and `fm-test-review` are
  standalone audits a human invokes, not steps a pipeline phase adds for itself. When a skill does
  name several independent agents, send them in one message so they run concurrently, and keep the
  count to what the skill lists — **unless the skill says otherwise, and some do.** `fm-audit-codex`
  runs its stages **sequentially** on purpose: `codex-auditor` takes the page `.lock` to
  Read-Modify-Write `codex-audit.json`, so parallel auditors on one page contend for a single lock
  that one of them holds until it finishes. Agents that share a lock or a write target are not
  independent, whatever the fan-out looks like. The skill's own text wins over this paragraph.

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

## Codex Independent Audit

An **advisory** layer that uses **Codex as an independent auditor** of Claude's migration work. For
every **audited** artifact the pipeline produces (the seven stages in Coverage below — not
`fm-style-spec`), Codex gives a second, independent review recorded alongside
Claude's own gate results. Codex reads and evaluates only — it never migrates. This is **neither a
port nor a bridge**: Claude runs the pipeline as always and calls Codex as a second opinion through
the `codex` plugin's `codex-cli-runtime` contract (headless `codex exec`). Full design:
`docs/design/codex-audit-layer.md`; rubric: `templates/codex-audit.md`.

**Components.** `fm-audit-codex` (manual/re-run entry), `codex-auditor` (the agent that delegates
to Codex), `templates/codex-audit.md` (per-stage rubric + schema), `codex-audit.json` (per-page
state), tracker `pages[page].codexAudit` (per-stage verdict summary).

**Coverage.** All seven stages: `analyze`, `plan`, `gen`, `verify`, `e2e`, `parity`, `route`.
The `style-spec` stage (`fm-style-spec`, v0.9.0) is **deliberately not** in the audit set: its
artifact is a legacy-extraction answer key whose correctness is re-checked downstream when
`fm-parity` reuses the same baseline, so a separate Codex pass would be redundant. (Adding a
`style-spec` audit stage remains a possible follow-up — see `docs/design/style-spec-generation.md`.)

**In-loop invocation.** When `codexAudit` is enabled **and the stage is listed in
`codexAuditStages`**, each audited artifact-producing skill (`fm-analyze`/`fm-plan`/`fm-gen`/
`fm-verify`/`fm-e2e`/`fm-parity` — not `fm-style-spec`, per Coverage above), **after** it records its
own result and releases the lock, spawns `codex-auditor` for that stage. A stage the config excludes
is not spawned at all — `codexAuditStages` is the narrowing knob, and a skill that checks only
`codexAudit` would run every stage regardless of it.

**Availability is the auditor's call, not the caller's.** The skill spawns whenever config allows;
it does not pre-check whether the Codex CLI is installed. `codex-auditor` step 1 does that check and,
when Codex is absent, records `verdict: "skipped"` for the stage under the page lock. If the caller
short-circuited instead, no artifact would be written and `codex-audit.json` would silently have no
entry for that stage — indistinguishable from "never audited". The auditor gathers the
stage inputs, runs Codex, reads the real output, and Read-Modify-Writes `codex-audit.json` +
the tracker. The skill surfaces the verdict (advisory) in its report.

**Advisory semantics.** A Codex verdict (`pass|concerns|fail|error|skipped`) **never** changes the
per-page FSM state and never sets a `*-failed` state. The single consumer that gates on it is
`fm-route --flag-on`, which surfaces unresolved **high-severity** findings and requires an explicit
**acknowledgement** before flipping (a soft gate — a human can override; Codex stays advisory).

**Independence & skip.** The auditor passes Codex only the artifacts + legacy source (never Claude's
reasoning). If the Codex CLI/runtime is absent the audit is `skipped` (never a failure); a failed/
unparseable `codex exec` is `error` (advisory). Codex prompts and `codex-audit.json` are English;
user-facing summaries are in `workingLanguage`.

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
`templates/hana-sso.md`) are authored in **AA-46**. `webview-bridge.md` drives the `fm-parity`
webview check; `hana-sso.md` is a generation contract, not a gate — `sso` has no verifier and no
report slot, so it is never placed in `requiredGates`, and the `?ts` flow is verified through the
page's `e2eScenarios`.
The Strangler Fig routing template (`templates/strangler-fig.md`, authored in **AA-47**) drives
`fm-route`: the per-app flip topology (nginx host/path routing **or** a CloudFront behavior
manifest, selected by `apps.*.flipMechanism`), the 2-PR flag flow, and the gate-guarded flip.

The lint/format templates (`templates/eslint-config.md`, `templates/prettier-config.md`) define the
monorepo's ESLint v9 flat config (composed per workspace, with the `shared-domain` secret boundary)
and the Prettier 3 config; they drive the scaffolding and checks described in "Lint & Format Gate".

**Transform fidelity (v0.10.0)** is the logic-axis companion to the style answer key: a ported
**pure transform** (sanitizer/formatter/serializer/URL-builder) is pinned by a **golden test** to the
legacy function's full output, not a few behavior spot-checks (`templates/tdd-rules.md` → "pure
transforms", enforced by `tdd-cycle-runner`); the mapping catalog's `safeHtml`/DomSanitizer rows now
require porting the DOMPurify options **verbatim** (`RETURN_DOM`/`WHOLE_DOCUMENT`/`FORCE_BODY` change
the output *shape*, not security strength); and `parity-verifier` requires a content-independent
output-pin test for any data-driven transform (the backstop). Design:
`docs/design/transform-fidelity-generation.md`.

**Request-schema fidelity (v0.11.0)** is the request-body companion: a generated request-body builder
**returns its body parsed through the endpoint's zod schema** (non-strict, so it strips a field the
schema `.omit()`s) and is pinned by a **body-shape test** (`templates/tdd-rules.md` → "request
bodies", `shared-package-spec.md` → shared-data, enforced by `tdd-cycle-runner` api phase) — because a
`...getCommonRequestParams()` spread can re-add an omitted root field that TypeScript's
excess-property check never sees. The mapping catalog's `getCommonRequestParams()` row
(`angular-to-react-mapping.md` → http) spells out this spread/excess-property trap and the
non-strict-parse fix (the specific hole). `parity-verifier`'s contract gate verifies the actual body against
the **live/staging backend**, not a contract doc's prose (a doc can be wrong about behavior; the live
backend is the arbiter). Design: `docs/design/request-schema-fidelity-generation.md`.

## i18n Copy Parity

The copy axis of legacy parity (v0.12.0) — `templates/i18n-copy-parity.md` is the contract. The i18n
lookup resolves `language → fallback → the key itself` and **never throws**; that is deliberate
legacy-i18next parity, so the runtime is never "fixed" — the checks live in generation and the gates.
Four placements:

- **verify** — `foundation-generator` scaffolds a **key-coverage spec once per app** (every literal
  key resolves in **all** `i18n.languages`; `{{param}}` values get params; dynamic keys counted as
  `uncheckable`). `fm-verify`'s existing `npx vitest run` makes it hard; `fm-verify` asserts the
  spec's results appear in that run — file existence is not the test — and reports the
  `uncheckable` count. No separate gate step.
- **plan** — `analysis.json.copySources[]` → `migration-plan.json.copyBindings[]` records where each
  surface's text comes from (`localized-key` / `errorCode-map` / `empty-string` / `server-message`)
  plus `renderMode`. A `mustPreserve` copy source must be bound or land in `openApprovals[]` — the
  same reconciliation `behavioralVariants` uses. This is what stops a generator rendering the
  response `errorMessage`, which the backend resolves in a hardcoded EN locale (OMH-784).
- **e2e** — failure branches are required scenarios, marked `assertsCopy`, and the legacy dual-run
  compares the **displayed text** per language, not just navigation.
- **parity** — the visual gate compares every axis in every planned **state**
  (`gateAcceptance.visual.states`: default, error shown, session expired, empty) across
  `.languages`; an uncaptured planned state is an incomplete gate.

Coverage across states × languages defaults to the full matrix; any reduction is an `openApprovals`
item, never an author's default. Design: `docs/design/i18n-copy-fidelity-generation.md`.

## Self-confirmation Hardening

Tests and implementation are both generated from **one reading** of the legacy source, so a
misreading makes them agree and the gate goes green (the plugin names this bias in
`templates/i18n-copy-parity.md`). v0.13.0 adds four defenses that make the reading checkable, plus a
scope note — design in `docs/design/self-confirmation-hardening.md`:

- **A (entity render, machine-checked).** `i18n-copy-parity.md` render-mode covers markup **or HTML
  entity**; the generated key-coverage spec (`foundation-generator` 3b) fails a markup/entity value
  on the plain-text path. Was prose-only, which is why `&apos;` shipped (OMH-749).
- **B (legacy anchors).** A test asserting legacy behavior carries `// legacy: file:line` into the
  legacy source, not `analysis`/`plan` — scoped to legacy-behavior tests (`tdd-cycle-runner`,
  `tdd-rules`, `test-reviewer`).
- **C (Codex cross-read).** `codex-audit.md` `gen`/`verify` receive the legacy source at those
  anchors; `verify` states whether each cited line's condition matches the test's assumption. B+C
  interlock (B makes the reading an artifact, C is the second reader).
- **D (one-shot mutation).** End of TDD Green: break the just-written behavior, confirm red, revert
  (`tdd-cycle-runner`, `tdd-rules`). A hollow test dies here. Scoped to the one behavior, not a suite.

The i18n runtime fallback is untouched (legacy-i18next parity); all defenses live in generation/gates.

The style template (`templates/style-spec.md`, v0.9.0) defines `style-spec.json` — the legacy style
answer key `fm-style-spec` captures **before** generation (live legacy computed values via a
Playwright probe, asset inventory, markup structure) so `fm-gen` builds to real values instead of
eyeballing them. It shares the visual axes with `templates/visual-parity-checklist.md`: the spec is
the generation **target** (front), the checklist is the parity **gate** (back), one legacy-truth
source. See `docs/design/style-spec-generation.md`.

**Containment fidelity** (v1.2.0) closes the class of style defect the answer key structurally could
not carry: properties that do nothing until the content overflows. On OMH-912 mobile `/event/:seq` the
raw probe read `overflow-x: auto` on the city-tab strip, the spec curated it away because the measured
board had **one** tab and the strip could not overflow, and the page shipped — through verify, e2e and
parity — with **337px** of horizontal page scroll (`document.scrollWidth` 748 on a 412 viewport) and
the pills hanging past the right edge. Three mechanisms, three fixes: a `containment` axis captured
**verbatim** with a `contentDependent` flag for unrepresentative instances (curation is correct for
`typography` and is a defect generator for `overflow`); `nonComputable[]` for rules with no
`getComputedStyle` surface at all (`::-webkit-scrollbar` and friends, source-resolved even on a live
capture, via the **overflow twin rule**); and a containment stylesheet composed **into** any injected
document, since no parent sheet crosses a nested browsing context — legacy's own attempt at it is dead
code. The gate item is a page **invariant**
(`documentElement.scrollWidth <= clientWidth`, under a synthetic overload), not another probe value:
it catches the failure without knowing which element caused it. Design:
`docs/design/containment-fidelity-generation.md`.

Gate definitions (owning task):
- **verify** (AA-43): build, `tsc`, Vitest, and ESLint (hard) pass from `appDir`; Prettier
  `--check` runs as an advisory warning (non-blocking). See "Lint & Format Gate".
- **e2e** (AA-45): Playwright user-flow suite; legacy dual-run; staging for transactional pages.
- **parity** (AA-46): visual regression vs legacy baseline, API contract freeze diff,
  WebView bridge round-trip, telemetry dual-fire parity.

## Artifact Provenance & Answer-key Sourcing

The gates' **judgement basis** (v0.14.0) — one layer under the four fidelity axes and the
self-confirmation defenses. Those all assume the object being compared is the right object and the
criterion states the right expectation. OMH-758 broke both assumptions, and the existing rules did not
catch it because they address command execution: a command's exit code proves its own origin, while a
`.png` proves nothing beyond existing and opening. Measured: 561 captured png artifacts, 139 named
`legacy*`, **5** with a recorded origin. Design: `docs/design/artifact-provenance.md`.

- **A (provenance decides side).** `templates/capture-provenance.md` defines one `provenance` block —
  `origin` / `side` / `authState` / `renderSource` / `responseSource` / `captureMode` / `capturedAt` /
  `viewport` / `partial` — written by the **capturing code**. `side` is **resolved** (localhost +
  `apps.*.legacyPort`/`port`; a declared legacy host only while `tracker.json` shows the path un-flipped,
  since the production host serves v2 afterwards), never read off a filename. An artifact that does not
  resolve is **absent**, so its axes are uncovered = incomplete gate. Applied by
  `style-spec.md`/`style-spec-extractor` (`legacySource.provenance`; `capturedFrom` deprecated →
  `renderSource` + `authState` + `partial`), `visual-parity-checklist` **step 0**, `parity-verifier`,
  `e2e-testing`/`e2e-test-runner` (per dual-run leg), `fm-parity` check 1, `fm-style-spec` tracker
  record. **New captures only** — no retro-fill, no re-adjudication of passed pages.
- **B (evidence-state statements are claims).** "Both sides measured", "M of N locales" fall under the
  same 5-step gate: enumerate artifacts, quote values. Deducing evidence scope from routing or
  deployment topology is not observation.
- **C (answer-key sourcing + amendment).** `gateAcceptance.expectedValueSource` is required when a
  criterion asserts a v2-side expected value (cite the prior decision and the branch it lives on;
  "searched, none found" counts, unrecorded searching does not) — `fm-plan` Step 4 returns a plan
  without it. A mis-authored criterion is corrected by the decision owner through `criterionAmendment`
  (13 fields incl. `coverageUnchanged`, `priorDecisionLocation`, `fence`), never narrowed by the
  executor who hits it; a pass under one carries `amendedCriterion: true` + `priorWhy`. Rationale: a
  wrong answer key fails the gate on **correct** code, which manufactures exactly the reinterpretation
  pressure the verbatim-enforcement rule forbids.

## Gate Cost & Preconditions

The **cost** axis (v0.14.1) — everything above is accuracy ("green gate, defect shipped"); this is a
gate that is accurate but starts work it cannot finish. OMH-749's fm-parity spent ~45 min over two
rounds on a **contract** capture for a page whose response DTOs are deferred-`unknown` (nothing to
freeze) and whose `requiredGates` does not even list contract, because `parity-verifier.md`'s contract
section went from its heading straight into the diff. Three doc-only fixes — design in
`docs/design/gate-cost-and-preconditions.md`:

- **A (premise before capture).** The response-DTO diff freezes the v2 response shape against the
  legacy analysis DTOs, so its one premise is a **concrete v2 DTO shape** — not `unknown`, and not a
  vacuous `any` (`any` passes a naive typed-check but the diff against it matches everything, a false
  pass; treat it like `unknown`). `contractsDir` is optional infra and is **not** required (requiring it
  would `not-run` the diff on every page of a project without `docs/migration/api-contracts/`). The
  premise is read off the `api` phase response hooks; a concrete DTO carrying an `any`-typed **field**
  stays concrete (diff runs, that field excluded and named in `evidence`). Concrete → run.
  `unknown`/`any` → split on why: an **approved sign-off** (an `openApprovals[]` entry with
  `status: "approved"` and a named `owner`, not `TBD`) → `result: "not-run"` + `reason` (a fourth
  honest fact alongside skipped-by-plan / attempted-but-unfinished); no such entry → `result: "fail"`,
  never a silent `not-run`. A `pending` entry and a bare free-text typing note are **equally** not
  enough — `fm-plan` writes `pending` entries itself, so either would let the pipeline approve its own
  skip; a contract skip is a coverage reduction, and this plugin routes every coverage reduction
  through an approved `openApprovals` entry. A precondition, not a plan flag: it runs again on its own
  when the deferral resolves, and a plan carrying the deferral only as a typing note must promote it to
  an approved entry first. Gates the **response-DTO diff only** — the request-body-vs-live-backend
  check (OMH-748) does not depend on typed response DTOs and keeps running on every write page.
- **B (lock schema).** `.lock` is JSON with `holder` / `pid` / ISO-8601 `acquiredAt` (see "Lock file").
  The ghost-lock sweep computes off `acquiredAt` (it applies only once the holder is gone); a
  date-only or unparseable timestamp is treated as immediately sweepable, so a malformed lock left
  by a dead holder is never a permanent deadlock.
- **C (per-gate budget).** Optional `gateAcceptance.{gate}.budgetSeconds`; on overrun the verifier
  records `not-run` + `reason: "budget exceeded"` and proceeds — never `fail`, never a hard-kill.
  Per-gate, not per-round (`visual` runs long by design; a `contract` overrun signals nothing to
  freeze).

Deliberately untouched: the gate-set derivation and the "always visual + contract" wording — changing
them would drop contract on the 10-of-12 monorepo plans that omit it from `requiredGates` yet must
freeze a contract. That is a separate plan-quality axis.

## Gate Result Accounting

Where a gate's judgement rule needs a recorded basis. Design and history:
`docs/design/gate-result-accounting.md`.

- **D (finding adjudication).** Each Codex finding carries an optional `adjudication`
  (`state: open|closed|rejected`, `when`, `by`, `basis`) — schema in `templates/codex-audit.md`.
  - **Never written by the discovering audit.** Codex reports; resolution is written later by
    `fm-fix` (Step 5) or a human. `basis` is required for `closed` and `rejected` alike.
  - Absent `adjudication` reads as **`open`**. `fm-route --flag-on` Step 1b defines `unresolved` as
    absent or `state: open`. Existing `codex-audit.json` are not retro-filled.
  - **A re-audit carries adjudications across.** Re-running a stage rewrites its `findings[]`, so
    `codex-auditor` reads the prior array first: an `adjudication` moves onto a new finding matching
    on `area` + `evidence`; a prior adjudicated finding matching nothing is preserved verbatim under
    `{stage}.priorAdjudicated[]`. Matching is conservative — a non-match means "could not be
    matched", never "resolved". `fm-route` Step 1b shows those entries beside the current findings.
- **E (gate-pass evidence = the *content* the gate ran on).** `fm-verify`/`fm-e2e`/`fm-parity` record
  `gateEvidence.{gate} = { at: <ISO-8601>, commit: <sha>, tree: <hash> }` in `tracker.json`.
  - **`tree` decides freshness; `commit` is audit trail only.** `commit` =
    `git rev-parse --short HEAD`, `<sha>+dirty` on a dirty tree, and is **never passed to `git`**.
  - **One executable, never reimplemented inline:**

    ```sh
    {pluginRoot}/scripts/gate-tree-hash.sh [--manifest] \
        --exclude docs/migration/{app}/{page}/gate-tree/{gate}.tsv -- <watch path>...
    ```

    Producers and consumers pass the **same `--exclude` and the same `--`**, or the two hashes are
    incomparable. The script's own file documents how it records each entry; do not restate it here.
  - It exits **2** printing `unverifiable` when no watch path resolves, and **1** writing nothing on
    any other error. `unverifiable` on a page that **has** a recorded `tree` is a *change*:
    `fm-route` Step 1a blocks on it, and grandfathers only the never-recorded case.
  - Gate skills also save the `--manifest` output to
    `$(git rev-parse --show-toplevel)/docs/migration/{app}/{page}/gate-tree/{gate}.tsv` (create the
    directory first) and pass that repo-relative path back as `--exclude`. Write it to a temp file
    and promote it only when the pass records — on a pre-run/record-time mismatch the previous
    manifest must survive, or the recorded `tree` and the on-disk file list describe different
    trees. The redirect target must
    be the real repo root — gate skills run from `{appDir}`, and `{monorepoRoot}` defaults to `"."`.
  - `fm-route --flag-on` Step 1a is a **hard** gate on a `tree` mismatch: re-run the chain from
    `fm-verify`.
  - **A gate records a pass only if its watch paths did not move while it ran.** Compute `tree`
    before the first tool and again at record time; if they differ, record no pass and say to re-run.
  - A record with no `tree`, or a computation that returned `unverifiable`, is non-blocking — no
    retro-adjudication. Legacy `verifiedAt`/`e2ePassedAt`/`parityPassedAt` stay for compatibility;
    `gateEvidence` wins when present. `at` is ISO-8601 with time; date-only is a rule violation.
- **F (watch paths).** Three axes, hashed as one set:
  1. `tracker.json` `sourcePaths[]` — the files the generation phases wrote under `appDir`,
     recorded by `fm-gen` Step 5 and `fm-delta` Step 5.
  2. each `migration-plan.json` `sharedDeps[]` entry `@omh/<package>:<symbol>`, mapped to the
     directory `{packagesDir}/<package>` — the symbol is not a path.
  3. the page's `migration-plan.json` itself.

  `fm-route` Step 1a and `fm-progress` resolve them identically; a consumer resolving fewer can
  never match a producer. **`fm-gen` and `fm-delta` clear `gateEvidence` together with the legacy
  `verifiedAt`/`e2ePassedAt`/`parityPassedAt` and the route fields `routePrepared`/`flagKey`** —
  clearing `gateEvidence` alone leaves `fm-route` Step 1 and Step 1-pre re-authorizing the flip.
  A page missing `sourcePaths` is `unverifiable` on axis 1, still checkable on 2 and 3, and must
  report which axes it checked.

Codex stays advisory: D counts findings, it does not give Codex a veto.

## Skills

All skills are implemented. The "Built in" column records the task that delivered each
(provenance) — see `docs/skill-reference.md` for inputs/outputs and `docs/build-context.md` for
the full build map.

| Skill | Purpose | Built in |
| --- | --- | --- |
| `fm-init` | Initialize config + tracker | AA-40 |
| `fm-analyze` | Analyze a legacy Angular target → analysis.json | AA-41 |
| `fm-style-spec` | Extract the legacy style answer key (live computed + assets + structure) → style-spec.json | v0.9.0 |
| `fm-extract` | Lift logic into framework-agnostic `packages/shared-*` | AA-42 |
| `fm-plan` / `fm-gen` / `fm-verify` | Generate an RR v7 page via TDD | AA-43 |
| `fm-fix` | Targeted repairs that close the gate loops | AA-44 |
| `fm-e2e` | Playwright E2E gatekeeper | AA-45 |
| `fm-parity` | Visual / contract / WebView / telemetry parity | AA-46 |
| `fm-route` / `fm-progress` | Strangler Fig routing + progress dashboard | AA-47 |
| `fm-delta` | Incremental re-migration on legacy drift | AA-48 |
| `fm-clean-code` / `fm-test-review` | Code-quality / test-quality audit | AA-49 |
| `fm-secret-audit` | Secret inventory + relocation guidance | AA-50 |
| `fm-audit-codex` | Independent Codex audit of each audited stage (the seven, not fm-style-spec; advisory) | AA-53 |

## File Structure

```
.claude-plugin/  - Plugin manifest (plugin.json)
CLAUDE.md        - This file (conventions, state machine, design principles)
skills/          - Skill entry points (fm-*)
agents/          - Agent definitions
hooks/           - Hook configuration (hooks.json)
scripts/         - Hook handlers (session-init.sh, check-staleness.sh) + gate-tree-hash.sh
                   (the gate-evidence content hash — one implementation, run by fm-verify /
                   fm-e2e / fm-parity when recording and by fm-route / fm-progress when checking)
templates/       - Mapping catalog, package spec, gate templates
docs/            - Documentation
```

## Version Sync Rule

When changing `version`, `keywords`, or `description` in
`.claude-plugin/plugin.json`, update the corresponding entry in the root
`.claude-plugin/marketplace.json` **in the same commit** (repo-wide rule in the root
`CLAUDE.md`).
