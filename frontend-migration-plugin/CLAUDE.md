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

> Status: **feature-complete tooling (v0.14.3)** — all `fm-*` skills, agents, and templates are
> implemented (JIRA epic **AA-39**, tasks AA-40–AA-51, plus the post-build Codex audit layer
> (AA-53), Playwright E2E harness hardening (AA-61), the per-app route-flip mechanism
> (`nginx` | `cloudfront`, v0.7.0), the simplicity/over-engineering quality dimension +
> GREEN-phase reuse ladder (v0.8.0), the codified per-gate acceptance criteria
> (`gateAcceptance`) hardening the parity gates against scope reinterpretation (v0.8.1), the
> full-matrix coverage binding for gateAcceptance authoring — sampling needs explicit approval
> (v0.8.2), the visual-parity-checklist closing the cross-framework visual-gate completeness
> gap that let spacing/icon regressions pass (v0.8.3), and the analyze→plan behavioral-coverage
> reconciliation (`behavioralVariants` + `openApprovals`) that stops the planner silently
> narrowing an analysis-discovered variant set — e.g. a locale-filtered social-login provider
> list — into the default-environment subset (v0.8.4), and the **`fm-style-spec` stage** that
> extracts the legacy style answer key (live legacy computed values via a Playwright probe + asset
> inventory + markup structure) up front so `fm-gen` builds to real values instead of eyeballing
> them — closing the generation-side style gap that the v0.8.3 gate only caught after the fact
> (v0.9.0), and the **transform-fidelity** rule (v0.10.0) — the logic-axis companion to `style-spec`:
> a ported **pure transform** (sanitizer/formatter/serializer/URL-builder) is pinned by a **golden
> test** to the legacy function's full output rather than a few behavior spot-checks, the mapping
> catalog now ports DOMPurify options (`RETURN_DOM`/`WHOLE_DOCUMENT`/`FORCE_BODY` change output shape,
> not security strength) **verbatim**, and `fm-parity` requires a content-independent output-pin test
> for data-driven transforms — closing the generation-side logic gap where a dropped `RETURN_DOM`
> silently changed a sanitizer's output shape and erased a `<body>`-level style while every gate
> stayed green (OMH-708; design in `docs/design/transform-fidelity-generation.md`), and the
> **request-schema fidelity** rule (v0.11.0) — the request-body companion: a generated request-body
> builder returns its body **parsed through the endpoint's zod schema** (non-strict, so it strips a
> field the schema `.omit()`s) and is pinned by a **body-shape test**, because a
> `...getCommonRequestParams()` spread can re-add an omitted root field that TypeScript's
> excess-property check never sees; `fm-parity`'s contract gate verifies the actual body against the
> **live/staging backend**, not a contract doc's prose — closing the gap where a login body carried a
> root `stationTypeCode` the real backend strict-rejected (400) while typecheck, MSW-vitest, and
> MSW/legacy e2e all passed (OMH-748; design in `docs/design/request-schema-fidelity-generation.md`),
> and the **i18n copy fidelity** rule (v0.12.0) — the fourth axis, the words the user reads: a new
> `i18n` config block declares the product's copy surface (`localesDir` / `languages` / `lookupFns`),
> which is what `gateAcceptance.scope`'s "every supported language" finally **resolves to**;
> `foundation-generator` scaffolds a per-app **key-coverage spec** that `fm-verify`'s existing vitest
> step turns into a hard gate (missing key / locale gap / missing `{{param}}`, with dynamic keys
> counted as `uncheckable`); `copySources[]` → `copyBindings[]` records where each screen's text comes
> from so a generator stops rendering the EN-hardcoded response `errorMessage` (OMH-784); failure
> branches become `assertsCopy` dual-run scenarios that compare displayed text; and the visual gate
> captures every planned **state** (error shown, session expired) across the language set — closing
> the axis where a raw `tl.login.otp-subject` shipped in an email subject and broke password reset
> while every gate stayed green (OMH-748; design in `docs/design/i18n-copy-fidelity-generation.md`),
> and the **self-confirmation hardening** set (v0.13.0) — the mechanism under all four prior axes:
> tests and implementation are generated from one reading of the legacy source, so a misreading makes
> them agree and the gate stays green. Four defenses + a scope note: (A) the i18n render-mode rule
> now covers HTML **entities** (`&apos;`) not just markup, and is machine-checked in the generated
> key-coverage spec rather than left as prose; (B) tests asserting legacy behavior carry a
> `// legacy: file:line` anchor into the **legacy source** (not analysis/plan), scoped to
> legacy-behavior tests; (C) the Codex `gen`/`verify` audits receive the legacy source at those
> anchors and check whether each cited line's real condition matches the test's assumption; (D) a
> one-shot **mutation check** ends the TDD Green step (break the just-written behavior, confirm red,
> revert — a hollow test dies here); and `fm-plan` calls for confirming scope before generation —
> closing the structural gap where OMH-749 passed every gate yet shipped 5 defects (design in
> `docs/design/self-confirmation-hardening.md`), and **artifact provenance + answer-key sourcing**
> (v0.14.0) — the layer under the gates' *judgement basis*: the 5-step gate and the
> no-reinterpretation rule both address command execution, so a **captured artifact** passed them by
> existing and opening, with its file name standing in for a statement of origin (measured: 561
> captured png, 139 named `legacy*`, **5** with a recorded origin; `capturedFrom` defined 2 values and
> carried 5 hand-written ones). Three defenses: (A) every capture carries a `provenance` block written
> by the capturing code (`templates/capture-provenance.md`) and its `side` is **resolved** from
> host:port + flip state, never from the filename — an artifact that does not resolve counts as
> **absent**, not as the side it is named after (new captures only; no retro-fill, no re-adjudication);
> (B) statements about the *evidence itself* ("both sides measured", "M of N locales") are claims under
> the same 5-step gate — deducing evidence scope from routing/topology is not observation; (C)
> `gateAcceptance` gains `expectedValueSource` (a criterion asserting a v2-side expected value cites
> where that value comes from, "searched, none found" included) plus a formal `criterionAmendment`
> block, because a wrong answer key fails the gate on **correct** code and that manufactures the
> reinterpretation pressure the verbatim rule forbids — closing the gap where two gates issued passes
> that had to be retracted (OMH-758; design in `docs/design/artifact-provenance.md`)), and **gate
> cost & preconditions** (v0.14.1) — the cost axis (the fidelity axes are all accuracy: "green gate,
> defect shipped"; this is "accurate gate that starts work it cannot finish"). OMH-749's fm-parity
> ran a **contract** capture for ~45 min across two rounds on a page whose response DTOs are
> deferred-`unknown` (nothing to freeze) and whose `requiredGates` omits contract — the instructions
> went from the contract heading straight into the diff with no premise check. Three fixes, all docs:
> (A) the contract gate confirms its premise (a **concrete** v2 DTO shape — not `unknown`, not vacuous
> `any`; `contractsDir` not required) before the response-DTO capture and records `not-run`/`reason`
> only under an `openApprovals` entry that is `status: "approved"` with a named `owner` (a `pending`
> entry the pipeline writes itself, or a bare plan note, is not enough), else `fail` — gating the
> **response-DTO diff only**, so the request-body-vs-live-backend check (OMH-748) still runs on
> `unknown`-typed write pages; (B) the
> `.lock` gets a schema (`holder`/`pid`/ISO-8601 `acquiredAt`) so the "stale after 30 min" rule is
> computable and a malformed timestamp is immediately stale, not a permanent deadlock; (C) an optional
> per-gate `gateAcceptance.{gate}.budgetSeconds` records `not-run` on overrun rather than failing or
> hard-killing. The gate-set derivation and the "always visual + contract" wording are deliberately
> left alone (design in `docs/design/gate-cost-and-preconditions.md`)), and **gate result accounting**
> (v0.14.3) — the same missing-decision-field pattern as the v0.14.1 lock, in two more places: a gate
> holds a judgement rule but the artifact has no field to record the *basis*, so the rule falls to
> ad-hoc fields invented per session (measured on my-coupon: 48 Codex findings, 14 `high`, 2
> adjudicated; four ad-hoc fields, 0 defined in the plugin). Three doc-only fixes: (D) each Codex
> finding gains an optional `adjudication` (`open`/`closed`/`rejected`, absent = `open`, written by
> `fm-fix`/human not the discovering audit) so `fm-route`'s "unresolved high-severity" is countable
> instead of re-surfacing every finding forever; (E) `fm-verify`/`fm-e2e`/`fm-parity` record
> `gateEvidence.{gate}` with an ISO-8601 `at` + a `commit` (`<sha>+dirty` on a dirty tree), and
> `fm-route --flag-on` expires a gate whose commit is behind `HEAD` on the page's watch paths — a PASS
> proves nothing about code committed after it (OMH-754 PR #184 shipped a `visual: PASS` 21 commits
> stale); (F) the watch paths include the plan's shared-package deps and `fm-progress` surfaces
> `parity-passed` pages whose evidence a `packages/shared-*` change has outdated — Codex stays advisory
> and no existing artifact is retro-filled (design in `docs/design/gate-result-accounting.md`).
> Runtime
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

Loading is **guarded by existence**: each agent Reads a skill's `SKILL.md` only when present, so a
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
  },
  "stagingConfig": {
    "baseUrl": "https://staging.ohmyhotel.com",
    "paymentGateways": { "nicePay": "", "eximbay": "", "kakaoPay": "" }
  }
}
```

- `currentApp` — the active surface for skills that operate on one app. PC-first.
- `contractsDir` — **optional**. Path to the confirmed backend verification contracts
  (default `docs/migration/api-contracts`, OMH-604/606/607) that are the **authoritative**
  schema source for **`shared-types` and `shared-data` only** (migration plan §5 — the legacy
  `any` reverse-extraction is retired for the contract-covered surface). The contracts are
  **zod-in-markdown** (zod inside Markdown `ts` code fences, not `.ts` files) under `responses/` (OMH-606) and
  `requests/` (OMH-607), sharing two base schemas defined once in `shared-types` —
  `ResponseEnvelopeSchema` (responses) and `CommonRequestParamsRqSchema` (requests) — that each
  per-endpoint schema `.extend()`s. `fm-init` defaults the path to `docs/migration/api-contracts`
  but records the key **only when the directory exists**; when absent the key is omitted and
  `fm-extract` falls back to the existing legacy reverse-extraction (no regression). The other
  four packages (`config`/`i18n`/`domain`/`ui`) ignore this and extract from legacy as before.
  See "Mapping Catalog & Gate Definitions", `templates/shared-package-spec.md`, and `fm-extract`.
- `workingLanguage` — `ko` | `en` | `vi`. All user-facing skill output is in this language.
  **Not** the set of languages the product serves — that is `i18n.languages`.
- `i18n` — **optional but gate-relevant**. Declares the product's copy surface so the gates can check
  it: `localesDir` (translation resources), `languages` (the supported set), `lookupFns` (the i18n
  lookup helpers whose key literals are checked, default `["t","tl"]`), `keyPrefix` (key convention,
  e.g. `tl.`). `languages` is what `gateAcceptance.scope`'s "every supported language" **resolves
  to** — without this block that criterion cannot be enforced. The helper names are per-app project
  config, never plugin-baked (same principle as `flipMechanism`). When the block is absent,
  `foundation-generator` skips the i18n key-coverage spec and `fm-verify` reports it as `skipped`
  (never a silent pass). See "i18n Copy Parity" and `templates/i18n-copy-parity.md`.
- `externalSkills` — when `true` (default), `fm-init` installs the shared skills via
  `npx skills add … --copy` (same mechanism as `frontend-react-plugin`): **React Router framework
  mode** (`remix-run/agent-skills`), **Vitest** (`antfu/skills`), and **Vercel React best-practices
  + composition** (`vercel-labs/agent-skills`); it also verifies the **Playwright** CLI (E2E/visual,
  installed separately). Agents load each SKILL.md **per phase**, guarded by existence — an absent
  skill is skipped, never fatal. Best-practices is applied **SSR-aware** (framework mode, not a Vite
  SPA — the SSR rules are *not* skipped, the deliberate inversion vs `frontend-react-plugin`). See
  "External Skills (shared with frontend-react-plugin)".
- `eslintTemplate` — when `true` (default), generators auto-scaffold `eslint.config.js` from
  `templates/eslint-config.md` where none exists; `false` skips ESLint entirely. See "Lint &
  Format Gate".
- `prettierTemplate` — when `true` (default), generators auto-scaffold `prettier.config.js` from
  `templates/prettier-config.md` where none exists; `false` skips formatting. Prettier is advisory
  (never blocks a gate). See "Lint & Format Gate".
- `codexAudit` — when `true` (default), the pipeline runs an independent **Codex audit** of each
  stage's artifact (advisory). Auto-skips if the Codex CLI/runtime is absent, so default-on is
  safe. See "Codex Independent Audit".
- `codexAuditStages` — which stages the in-loop Codex audit covers (default: all seven).
- `apps.*.appDir` — the directory containing each app's `vite.config.*`, `tsconfig.json`,
  `package.json`. All build/test commands run from this directory (see "Build Command
  Working Directory"). Per-app because this is a monorepo with multiple target apps.
- `apps.*.port` / `apps.*.legacyPort` — the new app's serving/dev port and the **legacy** app's
  upstream port for this surface. `fm-route` resolves both and passes them to
  `strangler-orchestrator`, which routes `guardsPath` to `port` on flag-on and lets unmatched paths
  fall through to `legacyPort` (the legacy app). Values mirror `templates/strangler-fig.md`.
- `apps.*.webview` — `true` for surfaces loaded inside a native WebView (mobile),
  `false` for PC, `"unknown"` for Hana (pending stakeholder confirmation).
- `apps.*.sso` — `true` for Hana (external `?ts` SSO; migration plan §7).
- `apps.*.flipMechanism` — `nginx` (default) | `cloudfront`. Which edge layer the Strangler Fig
  route flip is prepared at **for this app**. Per-app because one migration can flip different
  surfaces at different layers — an app-layer / entry nginx vs a CDN (CloudFront). The flip
  *semantics* are identical across mechanisms (2-PR flag flow, gate-guarded flag-on, revert =
  rollback); only the **edited artifact** differs. **Backward-compatible**: an app with no
  `flipMechanism` is treated as `nginx`, so existing nginx-only configs keep working unchanged.
  - `nginx` → `apps.*.infraDir` (default `infra/nginx`): the in-repo nginx host/path routing block
    + flag entry `fm-route` edits.
  - `cloudfront` → `apps.*.cloudfrontDir` (default `infra/cloudfront`) + `apps.*.manifest`
    (default `v2-routes.json`): a **version-controlled** CloudFront behavior manifest that maps
    `guardsPath` path-patterns to the v2 origin. `fm-route` edits only this in-repo manifest and
    opens a PR — it **never pushes to AWS** (governance = detect / PR, not apply).

  The per-app mechanism **mapping** (which app uses which) is **project config**, decided at
  `fm-init` and never hardcoded in this plugin — the plugin ships `nginx` as the neutral default.
  See `templates/strangler-fig.md` and `fm-route`.
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
analyzed → style-specced → planned → generated → verified → e2e-passed → parity-passed → flipped → done
                 ↓            ↓          ↓           ↓            ↓             ↓
          (each stage may enter) *-failed → fixing → (re-run the failed gate)
                                       ↓
                                  escalated   (needs manual intervention)
```

- A gate failure sets `{stage}-failed`; `fm-fix` moves it to `fixing` and, on success, back to that
  gate's **entry** state (`verify-fix` → `generated`, `e2e-fix` → `verified`, `parity-fix` →
  `e2e-passed`) so the gate can be re-run. Only the gate issues its own passed state — a fixer that
  promoted the page itself would leave the gate's report reading `fail` while the status claimed
  otherwise, and `fm-route --flag-on` reads both. Large fixes (>60% files) suggest full `fm-gen`.
- No gate accepts `fixing` as an entry state. A page at `fixing` is re-entered through `fm-fix`
  (or `escalated` for manual intervention) — never by invoking a gate directly.
- `fm-delta` re-enters from `planned`/`generated` when legacy source drifts.
- `escalated` requires manual intervention, then re-entry via `fm-fix`/`fm-gen`.

## State Files & Lock Convention

State files keep the multi-skill pipeline resumable. Layout:

```
docs/migration/
├── tracker.json                       ← global: per-app/per-page status, package extraction
└── {app}/{page}/
    ├── analysis.json                  ← fm-analyze
    ├── style-spec.json                ← fm-style-spec
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
releases it on completion or failure. The lock is JSON with at least these fields:

```json
{ "holder": "fm-parity", "pid": 49402, "acquiredAt": "2026-07-31T15:21:04+09:00" }
```

- `acquiredAt` — ISO-8601 **with time**, not date-only. The 30-minute rule below is computed from
  this field, so a date-only or unparseable `acquiredAt` is treated as **immediately stale** — a
  malformed timestamp must never let a lock become a permanent deadlock.
- `pid` — the holder's process id, to tell a live holder from a dead session's ghost lock. When
  absent, fall back to `acquiredAt` alone.
- Optional context (`purpose`, `precondition`, `app`, `page`) — recommended, not required.

A lock whose `acquiredAt` is older than **30 minutes** is stale and may be removed. Interrupt-style
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
  | "I already verified earlier" | Code changed since. Verify again. |
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

**In-loop invocation.** When `codexAudit` is enabled and Codex is available, each audited
artifact-producing skill (`fm-analyze`/`fm-plan`/`fm-gen`/`fm-verify`/`fm-e2e`/`fm-parity` — not
`fm-style-spec`, per Coverage above), **after** it records its own result and releases the lock,
spawns `codex-auditor` for that stage. The auditor gathers the
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
`templates/hana-sso.md`) are authored in **AA-46** and drive the `fm-parity` webview/sso checks.
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
  `uncheckable`). `fm-verify`'s existing `npx vitest run` makes it hard; `fm-verify` only asserts the
  spec exists and reports the `uncheckable` count. No separate gate step.
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
  The "stale after 30 min" rule computes off `acquiredAt`; a date-only or unparseable timestamp is
  immediately stale, so a malformed lock is never a permanent deadlock.
- **C (per-gate budget).** Optional `gateAcceptance.{gate}.budgetSeconds`; on overrun the verifier
  records `not-run` + `reason: "budget exceeded"` and proceeds — never `fail`, never a hard-kill.
  Per-gate, not per-round (`visual` runs long by design; a `contract` overrun signals nothing to
  freeze).

Deliberately untouched: the gate-set derivation and the "always visual + contract" wording — changing
them would drop contract on the 10-of-12 monorepo plans that omit it from `requiredGates` yet must
freeze a contract. That is a separate plan-quality axis.

## Gate Result Accounting

The **accounting** axis (v0.14.3) — the same missing-decision-field pattern as the v0.14.1 lock, in
two more places. A gate holds a judgement rule (`unresolved` findings, gate freshness), but the
artifact has no field to record the *basis*, so the rule falls to the executing session's improvisation
(measured on my-coupon: 48 Codex findings, 14 `high`, only 2 adjudicated; four resolution fields used
in the artifact, 0 defined in the plugin). Three doc-only fixes — design in
`docs/design/gate-result-accounting.md`:

- **D (finding adjudication).** Each Codex finding gains an optional `adjudication`
  (`state: open|closed|rejected`, `when`, `by`, `basis`) in `templates/codex-audit.md`. It is **never
  written by the discovering audit** — Codex reports; resolution is a downstream fact written by
  `fm-fix` (Step 5, when a repair closes a finding) or a human. Absent `adjudication` reads as **`open`**
  (the safe default), and `fm-route --flag-on` Step 1b defines `unresolved` = absent or `state: open`.
  `closed` (fixed) is kept apart from `rejected` (not a defect) so the next audit round does not re-raise
  a dismissed one; `basis` is required for both. Existing `codex-audit.json` are not retro-filled (all
  read `open` — the honest state), the same no-retro decision `capture-provenance.md` made.
- **E (gate-pass commit).** `fm-verify`/`fm-e2e`/`fm-parity` record `gateEvidence.{gate} = { at:
  <ISO-8601>, commit: <sha> }` in `tracker.json` (`commit` = `git rev-parse --short HEAD`; a dirty tree
  → `<sha>+dirty`, honest imprecision over a clean-looking lie). Legacy `verifiedAt`/`e2ePassedAt`/
  `parityPassedAt` stay for compatibility; `gateEvidence` wins when present. `fm-route --flag-on`
  Step 1a expires any gate with an intervening commit on the page's watch paths — a PASS proves nothing
  about code committed after it (OMH-754 PR #184 shipped a `visual: PASS` 21 commits stale). `at` is
  ISO-8601 with time, the same regulation as the lock schema; a date-only value is a rule violation.
- **F (shared-dependency freshness).** The gate is per-page, so a `packages/shared-*` change outdates
  the evidence of every page importing it and nothing per-page catches it. E's watch paths therefore
  include the `migration-plan.json` **shared-package deps** (an existing field, reused), and
  `fm-progress` gains a stale-evidence view listing `parity-passed` pages a watch-path commit has
  outdated. The goal is visibility before flip, not forced re-verification. Depends on E.

Advisory unchanged: Codex still `reads and evaluates only` (D counts findings, it does not give Codex a
veto). Absent `gateEvidence` (pages verified before the field) is `unverifiable`, never a block — no
retro-adjudication.

## Skills

All skills are implemented (v0.14.0). The "Built in" column records the task that delivered each
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
scripts/         - Hook handler scripts
templates/       - Mapping catalog, package spec, gate templates
docs/            - Documentation
```

## Version Sync Rule

When changing `version`, `keywords`, or `description` in
`.claude-plugin/plugin.json`, update the corresponding entry in the root
`.claude-plugin/marketplace.json` **in the same commit** (repo-wide rule in the root
`CLAUDE.md`).
