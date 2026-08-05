---
name: fm-gen
description: "Use after fm-plan to generate the RR v7 page from migration-plan.json via a strict per-phase TDD pipeline (foundation -> api -> store -> component -> page -> integration), with resume and demotion safety."
argument-hint: "<page> [--app pc|mobile|hana] [--force]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Generate a Page Migration (TDD Coordinator)

Executes `migration-plan.json` phase by phase. Each phase runs in a separate agent session
(`Agent` tool — phases are strictly sequential, each depends on the previous). All user-facing
output in `workingLanguage`.

## Instructions

### Step 0: Config & plan
Read config (absent → run `fm-init`; stop). Require `docs/migration/{app}/{page}/migration-plan.json`
(missing → run `fm-plan {page}`; stop) **with `gateAcceptance`** (absent → the plan is incomplete;
re-run `fm-plan {page}`; stop). Require `docs/migration/{app}/{page}/style-spec.json` (missing → run
`fm-style-spec {page}`; stop) — the foundation phase copies its assets and the component/page phases
build to its style values. Read `targetDir`, `appDir`, `packagesDir`, `monorepoRoot`, `legacyDir`,
`workingLanguage`, `eslintTemplate`, `prettierTemplate`, and the plan's `buildOrder` + `blockers`.

### Step 1: Blockers
If the plan has unresolved `blockers` (unextracted shared candidates), stop and tell the user to
run `/frontend-migration-plugin:fm-extract` first.

### Step 2: Resume / demotion
- If `generation-state.json` exists, offer to resume from the last incomplete phase. With `--force`
  (how `fm-fix` sends a page back after `regenRequired`), ignore it and regenerate every phase from
  the start — a completed state file would otherwise make the resume path a no-op.
- Demotion warning: if the page status is `verified`/`e2e-passed`/`parity-passed`, warn that
  re-generating resets it to `generated` and discards downstream gate progress. Confirm before
  proceeding.
- **`flipped` is refused, not warned.** If the page status is `flipped`, stop and tell the user to
  run `/frontend-migration-plugin:fm-route {page} --revert` first — **`--revert`, not `--flag-off`**:
  flag-off prepares the routing artifact with the flag OFF and *keeps the current status*
  (`fm-route` Step 4), so it would leave the page at `flipped` and this refusal would repeat forever.
  `--revert` is the rollback that takes the path out of rotation and returns the page to
  `parity-passed`. The path is serving production
  traffic, so regenerating it is a rewrite under live load — and the status reset would desync the
  two facts that must agree: the tracker's `flipped` and the edge flag `fm-route` owns. Provenance
  resolves a capture's `side` from that status (`templates/capture-provenance.md`), so a demoted-but-
  still-flipped page makes a capture from the production domain — which is serving v2 — resolve as
  `legacy`. That is the wrong-side baseline the v0.14.0 provenance layer exists to stop, and unlike
  `unresolved` it is *accepted as evidence*.

### Step 3: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min; JSON schema — `holder`/`pid`/ISO-8601 `acquiredAt` — in CLAUDE.md → Lock file).

### Step 4: Run phases (sequential)
For each phase in `buildOrder`, launch the right agent (Agent tool), passing only its params
(subagent isolation), and inspect the result before the next:
- `foundation` → **foundation-generator** (types + MSW + harness + **style-spec assets copied** +
  lint/format config scaffold; pass `styleSpecPath`, `legacyDir`, `monorepoRoot`, `legacyDirs`
  (every `apps.*.legacyDir`), `eslintTemplate`, `prettierTemplate`)
- `api` / `store` / `component` / `page` → **tdd-cycle-runner** (Red-Green per unit; pass
  `styleSpecPath` — the component/page phases build to the legacy style values)
- `integration` → **integration-generator** (routes + i18n + MSW global + ESLint on generated
  code; pass `monorepoRoot`, `eslintTemplate`)

Pass the config's **`i18n` block** to `foundation-generator` along with its other params. Its task 3b
(the key-coverage spec) reads `localesDir`, `languages`, `lookupFns`, and `keyPrefix`, and cannot
infer any of them: unlike the plan-derived `languages` that `parity-verifier` and `e2e-test-runner`
can read, these exist only in config. Omitting them would skip the spec on a project that *has* i18n
configured, and `fm-verify` Step 4a makes an absent spec a hard failure whose only remedy is
re-running this phase — which would fail the same way.

After each phase, update `generation-state.json` (Read-Modify-Write): mark the phase
`done`/`failed`, record `currentPhase`. On a phase failure, stop and report — the page status
becomes `gen-failed`.

### Step 5: Record
1. Set `generatedAt` and, if all phases succeeded, `tracker.json`
   `apps[app].pages[page].status = "generated"`; any skipped/failed phase → `gen-failed`.
2. Record `apps[app].pages[page].sourcePaths` — the repo-relative paths of the files the phases
   created or modified under `appDir`, collected from each phase's own report. This is the page's
   **watch-path** set: `fm-route --flag-on` (Step 1a) and `fm-progress` diff it against a gate's
   recorded commit to tell a still-fresh PASS from a stale one, and neither can derive it otherwise
   — `componentTree` carries component *names*, not paths. Rewrite the list on every run so a
   removed file leaves it (see CLAUDE.md → "Gate Result Accounting").
3. Clear any `apps[app].pages[page].gateEvidence` — the page's code has been regenerated, so every
   prior gate PASS now rests on code that no longer exists. Leaving it would let a later freshness
   check compare against a commit that predates this generation and read as fresh.
4. Release the lock.

### Step 5b: Codex audit (advisory) — see CLAUDE.md → "Codex Independent Audit"
If `codexAudit` is enabled, this stage is in `codexAuditStages`, and generation succeeded, after the
lock is released spawn `codex-auditor` (Agent) for the `gen` stage (params: `app`, `page`, `stage="gen"`,
`appDir`, `legacyDir`, the generated diff + `planPath`, `outPath = docs/migration/{app}/{page}/codex-audit.json`,
`workingLanguage`). Codex checks mapping fidelity, RR v7 idioms, and secret-boundary violations.
Advisory — never changes the page status. Surface its verdict in the report.

### Step 6: Report
In `workingLanguage`: phases completed, files created, total tests with RED/GREEN evidence from
each TDD phase, harness status, and any manual integration steps. Next step:
`/frontend-migration-plugin:fm-verify {page}`.
