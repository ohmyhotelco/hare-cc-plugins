# Frontend Ohmyhotel Plugin

A Claude Code plugin that carries the **working method** for
[`ohmyhotelco/ohmyhotel-frontend`](https://github.com/ohmyhotelco/ohmyhotel-frontend) — the V3
"All New B2C" site (`apps/www`, one responsive React Router v7 SSR app serving `www` and `m`) and any
later app in the same repository. It is a **standalone copy** of `frontend-react-plugin` (skeleton)
and selected parts of `frontend-migration-plugin`, rewritten for Claude 5-era agents and the current
Claude Code plugin contract (workflows, background subagents, `${CLAUDE_PLUGIN_ROOT}`). Command
prefix: `fo-`.

> Status: v0.1.0 — complete command set, audited, not yet run end to end. All 22 commands, 17 agents,
> 7 workflows and 10 scripts pass `claude plugin validate`, the repo consistency check, the eval suite
> and a three-round Codex + Claude audit. `fo-init`, `fo-spec-sync` and `fo-plan` have been exercised
> on the real repository and specs; `fo-gen` and the gates need the app scaffold (Phase 0-B of the V3
> plan) before a first full run. The plugin does **not** contain the product app or its rules.

## What it does

It wraps screen generation with the five things the V3 build needs:
1. **Spec snapshots as the source of truth** — planning attachments imported byte-exact into
   `specs/`, hashed, ledgered; plans and tests cite them by id and line.
2. **Three answer keys per screen** — the spec (always), Figma frames (view), and the V2
   implementation from the frozen monorepo (logic), each toggled per app.
3. **TDD generation in five stages** — foundation → api-tdd → component-tdd → page-tdd →
   integration, as a workflow that stops at the first failed stage and resumes.
4. **A gate chain with evidence** — verify, visual (vs Figma), E2E, contract (product rule lists),
   SEO, review — every result written with a tree hash so staleness is computed, never assumed.
5. **Readiness as a ledger** — a big-bang cutover is a list of closed items with evidence; the
   plugin proves them, it never flips traffic.

## Concepts (read this first)

- **Screen = spec unit.** `apps/www/app/screens/<nn>-<screen>/` holds the view (`<Screen>.tsx`), the
  headless hook (`use<Screen>.ts`), tests, mocks, the machine plan (`implementation-plan.json`) and
  the human spec (`<Screen>.spec.md`, five blocks). Ids are the spec ids (`01-main-page` …
  `12-city-landing`).
- **Product rules live in the product repo, not here.** Three layers: rules the planning spec
  states stay in `specs/` and are read from there; development/CTO decisions the spec does not
  contain live in `docs/adr/` and `docs/rules/*.json` (machine-checked lists whose *shapes* this
  plugin defines — `templates/rule-lists.md`); the plugin holds only method. A spec change is a
  product-repo PR; the plugin needs no release.
- **Workflows for multi-agent chains, scripts for commands, skills for entry points and
  approvals.** In interactive sessions subagents run in the background, so a skill never assumes
  an agent returns in the same turn: `fo-gen`, `fo-review`, `fo-fix`, `fo-visual`, `fo-contract`,
  `fo-seo` are workflow scripts in `workflows/`; `fo-verify`, `fo-progress`, `fo-cutover` are
  scripts in `bin/`; approvals (plan sign-off, which review clusters to fix) sit between runs.
- **One e2e tree.** `templates/e2e-playwright.md` fixes `<app.dir>/e2e/` (`fixtures.ts`, `support/*.ts`,
  `support/auth.setup.ts`, `support/pages/<screen>.ts`, `screens/<screen>/<TS-id>.spec.ts`,
  `visual/<screen>.spec.ts`, `seo/<screen>.<aspect>.spec.ts`); the folder names the role, the file name
  is the scenario id, `.spec.ts` is the only test suffix, run output and `storageState` live outside. The V2 monorepo's `e2e/` drifted into a dozen suffixes and
  349 committed run-output files because its rule was "follow the existing specs"; here
  `fo-verify-run`'s `e2e-layout` check fails the gate on anything outside the tree.
- **One hash definition.** `bin/fo-screen-hash` says what a screen's evidence covers (the screen
  folder minus `<Screen>.spec.md`, its route modules, ui-kit gaps and package additions). Every
  producer and consumer calls it. A gate that writes its own Playwright specs records their hash
  separately (`--spec-path`), so running a later gate never stales an earlier one.
- **Evidence over tracker.** `docs/gates/<app>/<screen>/<gate>.json` is the record;
  `docs/gates/<app>/progress.json` is an index written only by `fo-evidence` and `fo-progress-set`
  (file lock, atomic replace). `fo-progress` classifies each gate as current / skipped (with a
  reason) / stale / unverifiable / blocked / missing — anything but a current pass is a blocker, and
  a screen is `done` only with none.
- **Reviewers report everything; people filter.** The four reviewers (spec, quality, test,
  security) report every finding with severity and confidence; the workflow clusters them by file;
  the user picks the clusters to fix. A reviewer that returns nothing makes the review
  `incomplete`, never a pass on fewer eyes.
- **Delta, not regeneration.** When a spec snapshot changes, `fo-plan-hash --check` says which plan
  entries' cited passages moved, which cited sections disappeared, and which new requirements are
  cited nowhere; `fo-plan` writes a `delta-plan.json`; `fo-gen --delta` applies it to the existing
  files, keeping accumulated fixes.
- **Claude 5 instruction style.** Plain sentences with the reason attached; no `MUST`/`NEVER`
  capitals, no re-verification scaffolding (the model self-verifies; steps that *run a tool and
  record output* stay — that is evidence, not self-checking); completion conditions instead of
  warnings; incident history in `docs/build-context.md`, not in instructions.

## Prerequisites

This plugin is tooling; the product repository provides:

- The app scaffold (`apps/www/app/root.tsx`, routes, `react-router.config.ts`), `packages/shared-*`
  (subtree-imported from the monorepo), the design system installed as
  `@ohmyhotelco/design-system` from GitHub Packages (`.npmrc` with a `${GITHUB_TOKEN}` placeholder),
  Node + pnpm/npm, `vitest`, `typescript`, `@playwright/test` with browsers.
- `specs/` with the planning snapshots (`fo-spec-sync` imports them) and `docs/rules/*.json`
  populated by their owners with an ADR each (`fo-init` scaffolds them empty — an empty list is a
  reported gap, not a pass).
- For reused screens: a local clone of the archived monorepo and the freeze commit recorded in an
  ADR (`legacySource.frozenCommit`); `fo-analyze` refuses `TBD`.
- For the visual gate: `docs/figma-manifest.json` with the file key, and `FIGMA_TOKEN` in the
  environment when PNG exports should be committed (the token is never written anywhere).
- Optional: the Codex CLI for `fo-audit-codex` (auto-skips when absent).

## Target stack

React 19 · React Router v7 framework mode (SSR, one route module per screen URL) · TanStack Query
over the workspace API package (`@ohmyhotelco/shared-data`) · react-hook-form + zod with adapters
over the design system · `useT()` over one flat i18n JSON per language (5 languages) · no client
store · dayjs · Vitest + Testing Library + MSW · Playwright. These are fixed by the repo, so there
are no profile or knob fields in the config.

## External skills

`fo-init` installs the shared skills the agents load per phase (same mechanism as the other
frontend plugins, vendored into `.claude/skills/`): `react-router-framework-mode`, `vitest`,
`vercel-react-best-practices`, `vercel-composition-patterns`, `web-design-guidelines`. Missing ones
are listed with their install command, never auto-installed silently.

## Quickstart — the first screen

```
# 0. one-time setup (writes .claude/frontend-ohmyhotel-plugin.json and the product-repo scaffold)
/frontend-ohmyhotel-plugin:fo-init

# 1. bring the planning spec in as a snapshot (ticket + sha256 + content hash in specs/MANIFEST.md)
/frontend-ohmyhotel-plugin:fo-spec-sync 01-main-page ~/Downloads/main-page-spec_v1.9_20261002.zip --ticket OMH-794

# 2. answer keys (as applicable to the screen)
/frontend-ohmyhotel-plugin:fo-figma --app www --screen 01-main-page --page UI_Main   # frames → manifest (+ PNGs with FIGMA_TOKEN)
/frontend-ohmyhotel-plugin:fo-analyze --app www --screen 10-booking-history          # reused screens: V2 behaviours → analysis.json
/frontend-ohmyhotel-plugin:fo-extract --app www --screen 10-booking-history          # shared candidates → packages/shared-*

# 3. plan → approve → generate
/frontend-ohmyhotel-plugin:fo-plan --app www --screen 01-main-page    # implementation-plan.json + <Screen>.spec.md, ends with an approval question
/frontend-ohmyhotel-plugin:fo-gen  --app www --screen 01-main-page    # workflow: foundation → api-tdd → component-tdd → page-tdd → integration

# 4. gates, in order (each writes docs/gates/www/01-main-page/<gate>.json)
/frontend-ohmyhotel-plugin:fo-verify   --app www --screen 01-main-page   # typegen+tsc, package tsc/vitest, eslint, vitest, i18n coverage
/frontend-ohmyhotel-plugin:fo-visual   --app www --screen 01-main-page   # 4 viewports × 5 languages × states; Figma compare where frames exist
/frontend-ohmyhotel-plugin:fo-e2e      --app www --screen 01-main-page   # spec TS scenarios as Playwright specs
/frontend-ohmyhotel-plugin:fo-contract --app www --screen 01-main-page   # external URLs, WebView, sensitive query keys, request conventions, telemetry
/frontend-ohmyhotel-plugin:fo-seo      --app www --screen 01-main-page   # head, canonical/hreflang, sitemap/robots, structured data, slugs

# 5. review → fix → re-verify
/frontend-ohmyhotel-plugin:fo-review --app www --screen 01-main-page    # four reviewers, clustered findings, you choose what to fix
/frontend-ohmyhotel-plugin:fo-fix    --app www --screen 01-main-page    # one fixer per approved cluster, then fo-verify again

# 6. the two manual gates, recorded like any other evidence
echo '{"reviewer":"<designer>","note":"Figma review <date>"}' | fo-evidence --app www --screen 01-main-page --gate designerReview --result pass
echo '{"ticket":"OMH-715","comment":"<comment id>"}'          | fo-evidence --app www --screen 01-main-page --gate planningAcceptance --result pass

# anytime: where every screen stands, and what to run next
/frontend-ohmyhotel-plugin:fo-progress --app www

# before the switch: the cutover ledger
/frontend-ohmyhotel-plugin:fo-cutover --app www init     # once; then `check`, `close <item> --evidence <link>`, `add …`
```

A spec revision later: `fo-spec-sync` again (it flags the stale plan) → `fo-plan` (writes
`delta-plan.json`) → `fo-gen --delta` → the gates again.

## Workflow

```
specs/<screen>/  ──fo-spec-sync──▶  MANIFEST.md (ticket · version · sha256 · content hash)
      │
      │  fo-figma ──▶ docs/figma-manifest.json        fo-analyze ──▶ analysis.json (permalinks @ frozenCommit)
      ▼                                                       │  fo-extract ──▶ packages/shared-*
   fo-plan  ──▶ implementation-plan.json + <Screen>.spec.md  ◀┘
      │  (approval)
      ▼
   fo-gen  [workflow]  foundation → api-tdd → component-tdd → page-tdd → integration   (generation-state.json)
      │
      ▼
   fo-verify [script] → fo-visual [wf] → fo-e2e [agent] → fo-contract [wf] → fo-seo [wf]     docs/gates/<app>/<screen>/*.json
      │                                                                                    (treeHash + specHash per record)
      ▼
   fo-review [wf: 4 reviewers → clusters] ──(you choose)──▶ fo-fix [wf: one fixer per cluster] ──▶ fo-verify again
      │
      ▼
   designerReview · planningAcceptance (fo-evidence, manual)  ──▶  fo-progress (blockers, next)  ──▶  fo-cutover (ledger)
```

## The gates

A screen is `done` in `fo-progress` only when every row is a *current* pass (or a validated skip
with a reason) and the review has no deferred clusters; `fo-cutover`'s `screens-all-gates` item
closes only then.

| Gate | Command | Runs as | Checks | On fail |
| --- | --- | --- | --- | --- |
| verify | `fo-verify` | `bin/fo-verify-run` | `react-router typegen` + `tsc`, the API package's own `tsc`/`vitest` for additions, ESLint, the screen's Vitest suite, the i18n key-coverage spec, and `e2e-layout` (every file under `e2e/` where the fixed tree allows it, no tracked run output); `--only` is diagnosis only (`partial`, never registered) | `fo-fix --from verify` |
| visual | `fo-visual` | workflow | one Playwright capture per state × viewport × language with breakage checks (overflow, console errors, broken images, clipped text, 769 boundary); Figma frame comparison in parallel where frames exist | `fo-review` / `fo-fix --from visual` |
| e2e | `fo-e2e` | agent | the spec's TS scenarios as Playwright specs through the harness; per-scenario trace paths | `fo-fix --from e2e` (opens traces) |
| contract | `fo-contract` | workflow | one worker per product rule list (`externalUrls`, `webviewContract`, `sensitiveQueryKeys`, `requestConventions`) + telemetry events; an empty list is a reported gap | `fo-fix --from contract`, or the list's owner adds entries |
| seo | `fo-seo` | workflow | head meta vs the meta template, canonical/hreflang, sitemap/robots hosts, structured data, slug lists — against the SEO reference spec | `fo-fix --from seo`; spec conflicts go to the SEO owner |
| review | `fo-review` | workflow | spec compliance, code quality, test quality (anchors followed into the spec), security — all findings, clustered | `fo-fix` on the approved clusters |
| designerReview, planningAcceptance | `fo-evidence --gate …` | manual | a person records who reviewed / which ticket comment accepted | — |

## Skills

| Skill | Purpose | Runs as |
| --- | --- | --- |
| `fo-init` | Config + product-repo scaffold (`docs/rules`, `docs/adr`, `docs/gates`, `specs/MANIFEST.md`, repo `CLAUDE.md` block) | skill |
| `fo-spec-sync` | Import a planning attachment as an immutable snapshot; ledger row; stale-plan flag | skill + `bin/fo-spec-import` |
| `fo-analyze` | V2 implementation(s) from the frozen monorepo → permalinked `analysis.json` | one agent (`legacy-analyzer`) |
| `fo-extract` | Shared-package candidates → `packages/shared-*` with TDD | agents in sequence (`package-extractor`) |
| `fo-figma` | Frames (state × viewport) → `docs/figma-manifest.json`; PNG export with a token | one agent (`figma-extractor`) + `bin/fo-figma-export` |
| `fo-plan` | Spec + answer keys + rule lists → plan and screen spec; delta on spec change; approval | one agent (`implementation-planner`) + `bin/fo-plan-hash` |
| `fo-gen` | Five-stage TDD generation; resume; `--delta` | workflow `fo-gen` (`foundation-generator`, `tdd-cycle-runner`, `integration-generator`, `delta-modifier`) |
| `fo-verify` | Technical gate | `bin/fo-verify-run` |
| `fo-visual` | Visual gate | workflow `fo-visual` (`visual-verifier`) |
| `fo-e2e` | E2E gate | one agent (`e2e-test-runner`) |
| `fo-contract` | Contract gate | workflow `fo-contract` (`contract-verifier`) |
| `fo-seo` | SEO gate | workflow `fo-seo` (`seo-verifier`) |
| `fo-review` | Four reviewers → clusters → your choice | workflow `fo-review` |
| `fo-fix` | One fixer per approved cluster, then re-verify | workflow `fo-fix` (`review-fixer`) |
| `fo-progress` | Screen × gate matrix, blockers, next command | `bin/fo-progress-report` |
| `fo-cutover` | Cutover ledger: computed / list / manual items with evidence | `bin/fo-cutover-check` |
| `fo-debug` | Reproduce → one hypothesis at a time → regression test → fix | one agent (`debugger`) |
| `fo-clean-code` · `fo-test-review` · `fo-security` | Standalone audits of any path with the pipeline's reviewers | one agent each |
| `fo-audit-codex` | Independent Codex second opinion on a stage artifact (advisory) | one agent (`codex-auditor`) |

Workflows (`workflows/`): `fo-probe` (smoke test — every agent resolves through the runtime; run
after adding an agent or upgrading Claude Code), `fo-gen`, `fo-visual`, `fo-contract`, `fo-seo`,
`fo-review`, `fo-fix`.

## Scripts (`bin/`, on `PATH` while the plugin is enabled)

| Script | Role |
| --- | --- |
| `fo-tree-hash` | content hash over tracked paths (port of the migration plugin's `gate-tree-hash.sh`) |
| `fo-screen-hash` | **the** definition of a screen's evidence path set |
| `fo-spec-import` | zip/dir → `specs/<screen>/` (wrapper hoist, Windows separators), header Status/Version, sha256, content hash, manifest row |
| `fo-plan-hash` | `sourceHash` per plan entry from spec passages; `--check` → changed / hashless / unresolved / uncited |
| `fo-verify-run` | the technical gate, parallel, with the pass / fail / skipped / not-run taxonomy |
| `fo-evidence` | writes a gate's evidence file (hash, optional `--spec-path` hash) and indexes it; refuses an unhashable pass |
| `fo-progress-set` | the one locked writer for every non-gate tracker field (`--set`, `--pull`, `--unset`, `--get`) |
| `fo-progress-report` | the matrix with gate states and blockers |
| `fo-figma-export` | Figma REST export of frames with `FIGMA_TOKEN` |
| `fo-cutover-check` | ledger evaluation (`--init` writes the default items and `docs/cutover/frozen-hotfixes.json`) |

## Troubleshooting / FAQ

- **`fo-gen` stops in its preflight.** The app shell (`apps/www/app/root.tsx`), the design-system
  package or vitest is missing — that is Phase 0-B work in the product repo, not a screen's. The
  message names what is absent.
- **A gate says `unverifiable`.** The evidence file and the tracker disagree, the file is missing,
  or no hash could be computed (an interrupted run, a hand edit). Run the gate again; never edit
  `progress.json` by hand.
- **A gate says `stale` right after I fixed something.** Expected: the fix changed the screen's
  hash. Run `fo-verify`, then the gates that were green before. A Playwright gate also goes stale
  when its own spec files change.
- **`fo-plan` says the plan is current but I changed the spec.** Only a change outside every cited
  passage, with no removed section and no new uncited FR/US/TS, takes that shortcut. Otherwise it
  writes a delta; check `fo-plan-hash --check` output if in doubt.
- **`fo-contract` reports "no rules recorded".** The list under `docs/rules/` is empty — the owner
  adds entries with an ADR; until then the gap is visible and the cutover item stays open.
- **`fo-cutover` cannot close `screens-all-gates`.** `fo-progress --blocked` lists why, per screen.
  A legitimately inapplicable gate (SEO on a member-only screen, E2E with no scenarios) is recorded
  as `skipped` with a reason by its own command and counts as validated.
- **"Another run owns the screen."** A `.claude/frontend-ohmyhotel/<app>/<screen>/*.lock` with a
  live `runId` — wait for it or check the session that holds it; do not delete it.
- **No `FIGMA_TOKEN`.** `fo-figma` records node ids without PNGs; `fo-visual` compares inline
  through the Figma MCP and says that no reference image is committed.
- **Which model/effort do the agents use?** Every agent declares `model` and `effort`; writers
  inherit the session model, reviewers are pinned to `opus` at `medium`. Tune after the first real
  screens with `claude plugin eval`.

## Development

```bash
claude plugin validate frontend-ohmyhotel-plugin
scripts/check-plugin-consistency.py frontend-ohmyhotel-plugin
claude plugin eval frontend-ohmyhotel-plugin --ablation none --runs 1   # routing cases (evals/)
claude --plugin-dir ./frontend-ohmyhotel-plugin                         # try an unreleased build in a session
```

Instruction style, agent roster, config schema and the copy matrix from the two source plugins are
specified in the design document.

## Documentation

- `docs/design/plugin-design.md` — decisions P1–P10, config schema, command set, orchestration
  model, agent roster, instruction-writing rules, copy matrix, order of work, CTO Q&A.
- `docs/build-context.md` — what each test and audit round changed and why (dry runs, the
  pre-merge wiring review, the three-round Codex + Claude audit).
- `CLAUDE.md` — maintainer notes (not loaded into agent context; agent rules are in
  `skills/fo-shared/SKILL.md`).
- `templates/` — `rule-lists.md` (shapes of `docs/rules/*.json`), `implementation-plan.md`,
  `screen-spec.md` (five blocks), `tdd-rules.md`, `e2e-playwright.md`, `i18n-key-coverage.md`,
  `form-adapters.md`, `server-state.md`, `cutover-ledger.md`, `codex-audit.md`, and the scaffold
  texts `fo-init` writes.
- `evals/` — `claude plugin eval` cases.

Localized: `README.ko.md` (Korean). Vietnamese follows after the first production run.

## License

MIT
