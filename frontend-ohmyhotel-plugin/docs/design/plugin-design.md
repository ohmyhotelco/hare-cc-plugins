# Design: frontend-ohmyhotel-plugin — repo-scoped development plugin for `ohmyhotelco/ohmyhotel-frontend`

> Status: **draft for CTO review** — target first release **v0.1.0**
> Prefix: `fo-` (`/frontend-ohmyhotel-plugin:fo-<command>`)
> Scope: a standalone plugin that carries the *working method* for every app in the
> `ohmyhotel-frontend` repository (first app: `apps/www`, the V3 "All New B2C" site). It is copied from
> `frontend-react-plugin` (skeleton) and `frontend-migration-plugin` (selected parts), rewritten for
> Claude 5-era agents and the current Claude Code plugin contract (workflows, background subagents,
> `${CLAUDE_PLUGIN_ROOT}` substitution). Product rules live in the product repository, not here.
> Out of scope: the V2 Strangler route flip, legacy pixel parity, Hana Card white-label.

## 1. Goal

The V3 plan (vault `plan/V3-구현-스펙-계획.md` v0.7c, decisions 1–14 closed 2026-10-02) fixes how the
new site is built: one React Router v7 SSR app serving `www` and `m`, the design system consumed as
`@ohmyhotelco/design-system`, business logic in `packages/shared-*` moved once by `git subtree`,
screens built from three answer keys (planning spec, V2 source, Figma), a per-screen gate chain, and a
single big-bang cutover. The two existing frontend plugins cover most of that method between them, but
neither fits as-is:

| Axis | `frontend-react-plugin` (v2.3.0) | `frontend-migration-plugin` (v1.5.1) | V3 needs |
|---|---|---|---|
| Target | greenfield feature in an existing app, four config knobs | Angular 15 page → RR v7 in the same monorepo | one repo, one or more apps, answer keys differ per app |
| Answer key | planning spec only | legacy render (style-spec, parity) | spec + Figma (+ V2 hooks for logic) — no legacy pixel parity |
| Cutover | none | per-path Strangler flip (`fm-route`) | big bang, checklist + ledger |
| Orchestration | skill drives six `Agent` calls, assumes they return synchronously | same | subagents run in the background; multi-agent chains belong in workflows |
| Product facts | in templates (`ota` profile) | in templates (`payment-flow-v2`, `webview-bridge`, `hana-sso`) | in the product repo (`specs/`, `docs/adr/`, `docs/rules/`) |
| Instruction style | "Iron Law", `MANDATORY`, re-verify tables | 499 × "never", 192 × `OMH-` incident references | plain instructions with reasons, no re-verification scaffolding |

This document records the decisions that shape the copy, the command set, the orchestration model, the
agent roster, and the order of work. It does not restate the V3 plan; it points to it.

## 2. Key decisions

| # | Decision | Rationale |
|---|---|---|
| P1 | **Repo-scoped, not V3-scoped.** The config holds an `apps[]` list (initially `www` only). Every command takes `--app` (defaults to the single configured app). Trackers, state and locks are per app. | Future `apps/companion` / `apps/affiliate` share the repo, the design system and `shared-*`. Starting with the list costs one array; retrofitting it later means touching every skill. Naming the plugin after the repo (not `v3`) follows the same reasoning that renamed `ohmyhotel-v3` → `ohmyhotel-frontend`. |
| P2 | **Standalone copy.** Files are copied and renamed (`fe-`/`fm-` → `fo-`); nothing imports the source plugins and `dependencies` is not used. The source plugins keep serving the monorepo until it is archived. | The two sources will stop evolving when V2 is frozen; a shared base would couple a live tool to two retiring ones. The repo's consistency checker already treats plugins as independent corpora. |
| P3 | **Three-layer rule placement.** (a) Rules stated in the planning spec stay in `specs/` and are read from there — never transcribed. (b) Development and CTO decisions that the spec does not contain (WebView contract, external URL contract, `deviceTypeCode`, non-member token leak prevention, host rules, payment flow) live in the product repo under `docs/adr/` and `docs/rules/`; machine-checked lists use a fixed JSON shape that the plugin defines. (c) The plugin holds only method: TDD procedure, gate evidence, approval flow, Figma comparison, locks. `fo-init` scaffolds the empty rule files and the config records their paths. | Specs changed twice on 2026-10-02 alone. A rule copied into the plugin would force a plugin release, marketplace sync and per-developer update on every change, and the spec snapshot, rules and code could no longer change in one PR. Subagents receive the product repo's `CLAUDE.md` automatically, so pointing it at `docs/rules/` is enough to deliver the rules to every agent. |
| P4 | **Workflows for every multi-agent chain; skills for entry points and approvals.** `fo-gen`, `fo-review`, `fo-verify` fan-out, `fo-visual` and the `fo-cutover` check run as workflow scripts shipped in `workflows/` and started by the skill of the same name. A skill never starts more than one subagent on its own and never assumes an `Agent` call returns in the same turn. Human approvals (plan sign-off, review-fix acceptance, gate overrides) happen between workflow runs, in the skill. | In interactive sessions subagents run in the background and report by completion notification; `fe-gen`'s "Agent is synchronous" assumption no longer holds. Workflows fix stage order, retries and resume in code rather than in prose, which is where the two source plugins spend most of their instruction volume. Workflows cannot take input mid-run, so approvals must sit outside them. |
| P5 | **Every agent declares `model` and `effort`.** Initial values in §6; tuned with `claude plugin eval` once the first screens run. Workflow scripts omit `model` (inherit the session model) and set `effort` per stage. | Effort replaces the removed thinking instructions and is not portable across model generations (Opus 5.5 `medium` ≈ Opus 5 `high`). Sonnet 5.5 at `low` is known to skip real checks, so no verifying agent runs below `medium`. |
| P6 | **Claude 5 instruction style** (§7): plain imperative sentences with the reason attached; no `MUST`/`ALWAYS`/`NEVER` capitals, no "Iron Law" / "red-flag rationalization" tables, no "re-verify / double-check / use a subagent to confirm" steps; reviewers report every finding with a severity and a separate stage filters; orchestrating skills state the completion condition and the early-stop patterns to avoid; incident history moves to `docs/build-context.md`. | Current-generation models follow instructions literally and self-verify. Emphasis produces over-reaction, re-verification scaffolding produces over-verification and cost, and "only report traceable issues" measurably reduces recall. The official skill-authoring guidance says the same: explain the why, keep instructions lean, generalize beyond the incident that motivated a rule. |
| P7 | **Current plugin mechanics.** `Agent` (not `Task`); `${CLAUDE_PLUGIN_ROOT}` inside skill and agent bodies; executables in `bin/`; no SessionStart hook that records the install path; shared agent rules in a preloaded skill (`skills/fo-shared/`) referenced through agent `skills:` frontmatter, because a plugin-root `CLAUDE.md` is not loaded into context; `disallowed-tools: AskUserQuestion` on unattended skills; `SKILL.md` under 500 lines with `references/`; `claude plugin validate` plus `scripts/check-plugin-consistency.py` on every change. | Each item is a verified contract change since the source plugins were written (see vault session notes 2026-10-02). The migration plugin's `session-init.sh` + `.local.json` path recording exists only because `${CLAUDE_PLUGIN_ROOT}` once expanded in hooks alone. |
| P8 | **Gate chain per screen follows V3 plan §7:** DS verify green → `typecheck · lint · vitest` → visual gate (4 viewports × 5 languages; Figma comparison only where a frame exists, breakage check elsewhere) → E2E (spec test-scenarios) → designer review → planning acceptance. Each gate writes evidence (command, exit code, tree hash, artifact) the way `fm-verify` does. `fm-parity` (legacy pixel mirror) and `fm-cascade` are not carried over. | The answer key is Figma, not the legacy render. Evidence recording is a pipeline contract that survives the P6 cleanup: it produces artifacts, it does not ask the model to re-check itself. |
| P9 | **Cutover is a ledger, not a flip.** `fo-cutover` maintains the cutover checklist (per V3 plan D7/D9, decisions 12–14: app contract items, frozen-monorepo hotfix re-application list, external URL contract, Hana termination items, rollback rehearsal) and reports readiness; it never edits `infra/` intent files. `strangler-orchestrator`, `fm-route` and the flag ledger are not copied. | The V3 decision is a host-level big bang with the ALB/CloudFront switch done by operations; the plugin's job is to prove every item is closed. |
| P10 | **Three answer keys, toggled per app.** `spec` (always), `legacySource` (V2 hooks/domain from the frozen monorepo archive, referenced by commit permalink — the repo has no `archive/`), `figma` (`docs/figma-manifest.json`, only for screens that have frames). `www` has all three; a future app may have only `spec`. | Decision 8 reimplements reused screens with Figma for the view and V2 hooks for logic; the V3 repo deliberately omits legacy code (D9), so analysis reads the archive by permalink rather than a sibling folder. |

## 3. Configuration (`.claude/frontend-ohmyhotel-plugin.json`)

Written by `fo-init`; every path is repo-relative.

```jsonc
{
  "repo": "ohmyhotelco/ohmyhotel-frontend",
  "apps": [
    {
      "name": "www",
      "dir": "apps/www",
      "appDir": "apps/www/app",
      "screensDir": "apps/www/app/screens",          // V3 plan D9: <screen>/ = spec unit
      "routesDir": "apps/www/app/routes",
      "uiKitDir": "apps/www/app/ui-kit",
      "hosts": ["www.ohmyhotel.com", "m.ohmyhotel.com"],
      "answerKeys": {
        "spec": { "dir": "specs", "manifest": "specs/MANIFEST.md" },
        "legacySource": {                             // optional
          "archiveRepo": "ohmyhotelco/ohmyhotel-monorepo",
          "frozenCommit": "<sha recorded in ADR at freeze>",
          "apps": ["apps/web-pc", "apps/web-mobile"]
        },
        "figma": { "manifest": "docs/figma-manifest.json" }   // optional
      },
      "cutover": "big-bang",                          // "big-bang" | "launch"
      "devPort": 5173
    }
  ],
  "designSystem": {
    "package": "@ohmyhotelco/design-system",
    "cssEntries": ["preset.css", "styles.css"],
    "responsiveRules": "node_modules/@ohmyhotelco/design-system/docs/responsive-rules.md"
  },
  "sharedPackages": {
    "dir": "packages",
    "api": { "package": "@ohmyhotelco/shared-data", "entry": "packages/shared-data/src/index.ts" },
    "i18n": { "hook": "useT", "from": "~/lib/i18n",
              "resourcesDir": "packages/shared-i18n/src/locales", "resourceFile": "{LANG}/translation.json" }
  },
  "languages": ["ko", "en", "ja", "zh", "vi"],
  "viewports": [360, 768, 1024, 1440],
  "rules": {
    "adrDir": "docs/adr",
    "rulesDir": "docs/rules",
    "lists": {                                        // machine-checked, fixed JSON shapes (templates/rule-lists.md)
      "externalUrls": "docs/rules/external-urls.json",
      "sensitiveQueryKeys": "docs/rules/sensitive-query-keys.json",
      "webviewContract": "docs/rules/webview-contract.json",
      "requestConventions": "docs/rules/request-conventions.json"
    }
  },
  "gates": { "evidenceDir": "docs/gates", "designerReview": "manual", "planningAcceptance": "manual" },
  "codexAudit": { "enabled": false }
}
```

Fixed by the repo, therefore **not** knobs (they were knobs in `frontend-react-plugin` Phase 2):
`appProfile=ota`, `routerMode=framework`, `serverState=tanstack-query`, `formStack=rhf-zod`,
`e2eTool=playwright`, `componentLibrary=external`, `apiLayer=workspace-package`,
`i18nBinding=custom-hook`, `clientStore=none`. The copied skills keep only those branches.

State and evidence:

| What | Where | Committed |
|---|---|---|
| transient run state (`generation-state.json`, locks, workflow run ids) | `.claude/frontend-ohmyhotel/<app>/<screen>/` | no |
| gate evidence (per gate: command, exit code, tree hash, artifact paths, timestamp) | `docs/gates/<app>/<screen>/` | yes — reviewed in the screen PR |
| progress tracker | `docs/gates/<app>/progress.json` | yes |
| cutover ledger | `docs/gates/<app>/cutover-ledger.json` | yes |
| screen implementation spec (5 blocks, V3 plan D9) | `<screensDir>/<screen>/<Screen>.spec.md` | yes |

## 4. Command set

| Stage | Command | Does | Runs as | Copied from |
|---|---|---|---|---|
| Setup | `fo-init` | writes config, app list, empty rule files + `docs/rules/README.md`, progress tracker | skill | `fe-init` + `fm-init` |
| | `fo-spec-sync` | imports a spec snapshot into `specs/<nn>-<screen>/`, updates `MANIFEST.md` (ticket, version, sha256, date), tags, and lists screens whose spec changed since their last plan | skill | new |
| Analysis | `fo-analyze` | reads V2 PC + mobile implementations of a screen from the archive permalink and emits `analysis.json` (hooks, API calls, behaviors, divergences) | skill → 1 agent | `fm-analyze` / `angular-analyzer`, read from archive |
| | `fo-extract` | extracts a shared-package candidate into `packages/shared-*` with TDD | skill → 1 agent | `fm-extract` / `package-extractor` |
| | `fo-figma` | resolves `figma-manifest.json` entries for a screen, exports frame screenshots and token references into `docs/gates/<app>/<screen>/figma/` | skill → 1 agent | new (uses `homepage-plugin` Figma MCP agent pattern) |
| Build | `fo-plan` | spec + `analysis.json` + Figma → `implementation-plan.json`; if a plan exists and the spec changed, emits `delta-plan.json` instead | skill → 1 agent, then approval | `fe-plan`; delta from `fe-plan`/`fm-delta` |
| | `fo-gen` | foundation → api-tdd → component-tdd → page-tdd → integration (store stage removed) | skill → **workflow** | `fe-gen` + agents |
| Gates | `fo-verify` | DS verify, typecheck, lint, vitest, i18n key coverage, rule-list checks; writes evidence | skill → **workflow** (checks in parallel) | `fe-verify` + `fm-verify` evidence |
| | `fo-visual` | renders 4 × 5 states, compares with Figma where frames exist, breakage check elsewhere; writes evidence | skill → **workflow** | `fm-parity` visual part + `homepage-plugin` `visual-fidelity-reviewer`, rewritten |
| | `fo-e2e` | realizes spec test-scenarios as Playwright specs and runs them | skill → 1 agent | `fe-e2e` |
| | `fo-contract` | request conventions, external URL contract, WebView contract, telemetry, SEO head; reads the rule lists from config | skill → **workflow** | `parity-verifier` contract parts + new |
| | `fo-review` → `fo-fix` | spec / quality / test / security reviewers in parallel → merged findings → approval → fixer per cluster | skill → **workflow** → approval → **workflow** | `fe-review` / `fe-fix` + agents |
| Whole app | `fo-progress` | per-screen status × gate matrix, blockers, stale evidence | skill (no agent) | `fm-progress` |
| | `fo-cutover` | cutover ledger + readiness check (P9) | skill → **workflow** (checks) | `fm-route` ledger ideas only |
| Support | `fo-debug`, `fo-clean-code`, `fo-test-review`, `fo-security` | debugging, independent audits | skill → 1 agent | `fe-*` |
| | `fo-audit-codex` | optional independent Codex audit of a stage artifact | skill → 1 agent | `fm-audit-codex` / `codex-auditor` |

Folded rather than separate: spec deltas live inside `fo-plan` (react style); contract checks are one
command (`fo-contract`) — split out `fo-seo` later only if the SEO list grows its own owner.

## 5. Orchestration model (P4)

```
skill fo-gen --app www --screen 01-main
  ├─ preflight (inline): config, lock, plan approved, spec hash matches plan
  ├─ Workflow({ name: "frontend-ohmyhotel-plugin:fo-gen", args: {app, screen, resumeFrom?} })
  │     stage foundation   agent(…, {agentType: "frontend-ohmyhotel-plugin:foundation-generator", effort: "medium"})
  │     stage api-tdd      agent(…, {agentType: "…:tdd-cycle-runner", effort: "medium"})
  │     stage component-tdd …
  │     stage page-tdd     …
  │     stage integration  agent(…, {agentType: "…:integration-generator", effort: "medium"})
  │     each stage: reads generation-state.json, returns {stage, status, evidence[]} via schema
  └─ on notification: present result, update tracker, release lock, name the next command
```

Rules that follow from it:

- **A skill does not end its turn between stages.** When a single agent is running it waits for the
  completion notification; when a workflow is running it waits for the task notification. The skill
  text names the early-stop patterns to avoid ("do not end the turn after presenting the plan; do not
  summarize a stage result as if the chain were complete") instead of listing forbidden rationalizations.
- **Approvals are turn boundaries by design.** `fo-plan` ends with the plan and asks; `fo-review` ends
  with merged findings and asks; `fo-fix` starts from the approved subset. Nothing inside a workflow
  asks the user.
- **Resume comes from two places.** Workflow `resumeFromRunId` replays unchanged stages from cache;
  `generation-state.json` lets a fresh run skip stages whose evidence is still valid (tree hash
  unchanged). Both are recorded in the tracker so `fo-progress` can show where a screen stopped.
- **Fan-out is bounded.** Reviewers run four-wide; verify checks run as many as there are commands;
  nothing spawns per-file agents. Agents' `tools:` lists exclude `Agent`, so they cannot re-delegate.
- **Dry run before anything else is built:** a one-stage plugin workflow calling
  `agentType: "frontend-ohmyhotel-plugin:<agent>"` with a `schema`. The workflow reference documents
  `agentType` as resolved from the same registry as the `Agent` tool; it has not been exercised from a
  plugin-shipped workflow in this repo yet. If it fails, the fallback is a skill that starts one agent
  per turn and advances on notification (option 가 from the 2026-10-02 review).

## 6. Agent roster (initial `model` / `effort`)

| Agent | From | Role | model | effort | tools |
|---|---|---|---|---|---|
| `implementation-planner` | react | spec + analysis + Figma → plan / delta | `opus` | `medium` | Read, Glob, Grep, Write |
| `foundation-generator` | react | types, fixtures, MSW handlers, form adapters | `sonnet` | `medium` | Read, Write, Edit, Glob, Grep, Bash |
| `tdd-cycle-runner` | react | one Red-Green phase | `inherit` | `medium` | Read, Write, Edit, Glob, Grep, Bash |
| `integration-generator` | react | routes, i18n append, MSW aggregation, full verify | `sonnet` | `medium` | Read, Write, Edit, Glob, Grep, Bash |
| `delta-modifier` | react | apply `delta-plan.json` | `inherit` | `medium` | Read, Write, Edit, Glob, Grep, Bash |
| `spec-reviewer` | react | spec compliance — reports everything with severity | `opus` | `medium` | Read, Glob, Grep |
| `quality-reviewer` | react | code quality dimensions | `opus` | `medium` | Read, Glob, Grep |
| `test-reviewer` | react | test quality | `sonnet` | `medium` | Read, Glob, Grep, Bash |
| `security-auditor` | react + migration `secret-auditor` | XSS, token handling, secrets, query-key leaks (C18 list) | `opus` | `medium` | Read, Glob, Grep |
| `review-fixer` | react | fix an approved cluster | `inherit` | `medium` | Read, Write, Edit, Glob, Grep, Bash |
| `e2e-test-runner` | react | Playwright scenarios | `sonnet` | `medium` | Read, Write, Glob, Grep, Bash |
| `debugger` | react | 4-phase debugging | `inherit` | `high` | Read, Write, Edit, Glob, Grep, Bash |
| `legacy-analyzer` | migration `angular-analyzer` | V2 PC/mobile → `analysis.json` from archive permalink | `sonnet` | `medium` | Read, Glob, Grep, Write, Bash |
| `package-extractor` | migration | shared-* extraction with TDD | `inherit` | `medium` | Read, Write, Edit, Glob, Grep, Bash |
| `figma-extractor` | new (homepage `design-token-extractor` pattern) | manifest → frames, tokens | `sonnet` | `medium` | Read, Write, Glob, Bash, Figma MCP |
| `visual-verifier` | new (homepage `visual-fidelity-reviewer` + fm-parity capture) | 4×5 render, Figma compare, breakage | `opus` | `medium` | Read, Write, Glob, Bash, Figma MCP |
| `contract-verifier` | migration `parity-verifier` (contract parts) | rule-list checks, WebView, telemetry, SEO head | `sonnet` | `medium` | Read, Glob, Grep, Bash, Write |
| `codex-auditor` | migration | optional independent audit | n/a (Codex) | — | Read, Glob, Grep, Bash, Write |

Not copied: `strangler-orchestrator`, `style-spec-extractor`, `cascade-differ`, `migration-planner`,
`migration-fixer` (merged into `review-fixer`), `parity-verifier` visual part (replaced by
`visual-verifier`). `model: inherit` on the writing agents keeps them on whatever the developer runs the
session with; reviewers are pinned so review quality does not drift with the session model.

## 7. Instruction-writing rules for this plugin (P6)

Applied while copying; `scripts/check-plugin-consistency.py` gains a lint for the first three.

1. **Plain sentences, reason attached.** "Run the package's own Vitest for additions, because the app's
   config does not see package sources" — not "CRITICAL: You MUST run …".
2. **No re-verification scaffolding.** Delete "double-check", "re-verify", "do not rationalize" tables,
   "final verification step" instructions. Keep every step that *runs a tool and records its output*;
   that is evidence, not self-checking.
3. **Reviewers report everything.** Replace "only report issues clearly traceable to the spec" with
   "report every finding with `severity` and `confidence`; the merge stage filters". Filtering is a
   workflow stage, not a prompt adjective.
4. **Completion conditions, not warnings.** Each orchestrating skill ends with a short "Done when" list
   and two or three named early-stop patterns to avoid.
5. **No incident history in instructions.** `OMH-…` references and "this happened on page X" narratives
   move to `docs/build-context.md`; the rule stays with a one-line reason.
6. **No reasoning dumps.** Never ask an agent to "write out your reasoning" or "think step by step";
   effort is the control.
7. **Size limits.** `SKILL.md` ≤ 500 lines (split into `references/`), `description` + `when_to_use`
   ≤ 1,536 characters together, pushy wording in descriptions avoided.
8. **Scope sentence kept.** "Deliver what the plan asks; if something adjacent needs work, say so in
   one sentence and continue" is already aligned with current guidance and stays.

## 8. Plugin layout

```
frontend-ohmyhotel-plugin/
├── .claude-plugin/plugin.json          name, version 0.1.0, description, keywords (synced to marketplace + root README label)
├── README.md · README.ko.md · README.vi.md
├── CLAUDE.md                           maintainer notes only — not loaded into agent context (P7)
├── agents/                             §6
├── skills/
│   ├── fo-shared/                      preloaded via agents' `skills:` — locks, state files, evidence format, reporting format
│   ├── fo-init/ … fo-cutover/          §4; each SKILL.md ≤ 500 lines + references/
├── workflows/                          fo-gen.js · fo-verify.js · fo-visual.js · fo-contract.js · fo-review.js · fo-fix.js · fo-cutover-check.js
├── templates/                          method templates only: tdd-rules, e2e-playwright, i18n-key-coverage, form-adapters,
│                                       framework-app-shell, server-state, rule-lists (JSON shapes for docs/rules/*.json), screen-spec-5-blocks
├── bin/                                gate-tree-hash.sh · fo-evidence.sh (on PATH while the plugin is enabled)
├── hooks/hooks.json                    PostToolUse staleness check only (no SessionStart path recording)
├── scripts/                            validate-implementation.sh, check-staleness.sh (hook targets)
└── docs/
    ├── design/plugin-design.md         this file
    ├── build-context.md                incident history and rationale moved out of instructions (P6-5)
    ├── workflow.md · skill-reference.md
```

## 9. Copy matrix

| Source | Take | Change | Drop |
|---|---|---|---|
| `frontend-react-plugin` skills | `fe-init/plan/gen/verify/e2e/review/fix/progress/debug/clean-code/test-review/security` | rename; `Task`→`Agent`; remove admin/shadcn/zustand/react-i18next branches (fixed by repo); `fe-gen` body → `workflows/fo-gen.js` + a ≤150-line skill; `fe-review` → workflow; split 847-line `fe-gen` and 1,259-line `implementation-planner` into `references/` | profile selection, knob defaults, Phase 1 backward-compatibility text |
| `frontend-react-plugin` agents | all 12 | add `model`/`effort`/`skills: [fo-shared]`; P6 rewrite; `spec-reviewer` reporting rule; planner reads three answer keys and the rule lists | — |
| `frontend-react-plugin` templates | `tdd-rules`, `e2e-playwright`, `i18n-key-coverage`, `form-adapters`, `framework-app-shell`, `server-state`, `eslint/prettier-config` | paths from config | `feature-module` (replaced by screen folder shape from V3 plan D9), `e2e-testing` (agent-browser path) |
| `frontend-migration-plugin` | `fm-progress` tracker + gate accounting; `fm-verify` evidence recording; `gate-tree-hash.sh`; artifact provenance; `angular-analyzer`; `package-extractor`; `codex-auditor`; `parity-verifier` contract sections; owner-approval model for gate overrides | analyzer reads the archive permalink; evidence paths from config; provenance drops legacy-render fields; incident text → `docs/build-context.md` | `fm-route`, `strangler-orchestrator`, `fm-parity` visual, `fm-cascade`, `fm-style-spec`, `fm-delta` (folded), `fm-secret-audit` (merged), `hana-sso`, `payment-flow-v2`, `webview-bridge` templates (→ product repo `docs/rules/`), `session-init.sh` path recording, `pluginRoot` `.local.json` |
| `homepage-plugin` | `design-token-extractor` and `visual-fidelity-reviewer` patterns | rewritten for screen states × viewports × languages | Astro specifics |

## 10. Order of work

Sequence only; dates belong to the V3 plan §7 (Phase 0-B scaffold, screen group A from mid-October).
The plugin has to carry `fo-plan` and `fo-gen` for the first screen (01-main) before group A starts.

1. **Skeleton + dry run.** `plugin.json`, marketplace entry, README label, `fo-shared`, one agent, one
   workflow with `agentType` + `schema`; `claude plugin validate`; consistency script clean. Decides P4's
   fallback question.
2. **`fo-init`, `fo-spec-sync`, rule-list templates.** Scaffold the product repo (`docs/rules/`,
   `docs/gates/`, `specs/MANIFEST.md`), import the 13 current spec snapshots.
3. **`fo-plan` + `implementation-planner`** reading spec, `analysis.json` (optional), Figma manifest,
   rule lists; delta path.
4. **`fo-gen` workflow** with the five stages and `generation-state.json`; `fo-verify` workflow with
   evidence.
5. **`fo-visual`, `fo-e2e`, `fo-contract`.**
6. **`fo-review` / `fo-fix` workflows**, `fo-progress`.
7. **`fo-analyze`, `fo-extract`, `fo-figma`** (needed from the first reused screen, not from 01-main).
8. **`fo-cutover`**, `fo-audit-codex`, `docs/build-context.md`, `claude plugin eval` suite.

Each step is one PR on this repo with `feat(frontend-ohmyhotel): …` scope and a version bump only
when the plugin becomes usable for the next V3 step.

## 11. Open questions for the CTO

| # | Question | Default if unanswered |
|---|---|---|
| Q1 | Dry run of `agentType` from a plugin workflow (step 1). If it fails, accept the notification-driven skill fallback? | yes, fallback |
| Q2 | Keep the optional Codex audit (`fo-audit-codex`)? It costs a Codex runtime per audited stage. | keep, disabled by default |
| Q3 | Gate evidence committed under `docs/gates/` (reviewable in PRs) vs kept in `.claude/` (not committed)? | committed |
| Q4 | Reviewer agents pinned to `opus`, writers `inherit` (§6)? | as in §6 |
| Q5 | `fo-contract` as one command, or `fo-seo` separate from day one? | one command |
| Q6 | Keep a maintainer `CLAUDE.md` at the plugin root although agents never see it? | keep, marked maintainer-only |

## 12. Sources

- Vault: `1-Projects/assets/2026-09 Ohmyhotel V3 All New B2C/plan/V3-구현-스펙-계획.md` v0.7c (D1–D9, §4 C1–C18, §7 gates and capacity, §8 Q1–Q17), `PROJECT_MEMORY-V3.md`, folder `CLAUDE.md` rules 1–9.
- Repo: `frontend-react-plugin/CLAUDE.md`, `docs/design/ota-extension-phase2.md` (D14–D19); `frontend-migration-plugin/CLAUDE.md`, `docs/workflow.md`, `docs/skill-reference.md`, `docs/design/*`.
- Claude Code docs (read 2026-10-02): `sub-agents`, `skills`, `plugins-reference`, `workflows`; workflow authoring reference (`agent()` options incl. `agentType`, `effort`, `schema`; `pipeline`/`parallel`; resume).
- Prompting guidance (read 2026-10-02): `claude-prompting-best-practices`, `prompting-claude-opus-5-5`, `prompting-claude-opus-5`, `prompting-claude-sonnet-5-5`, `prompting-claude-fable-5-1`; official `skill-creator` skill.
