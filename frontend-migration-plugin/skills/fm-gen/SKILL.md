---
name: fm-gen
description: "Use after fm-plan to generate the RR v7 page from migration-plan.json via a strict per-phase TDD pipeline (foundation -> api -> store -> component -> page -> integration), with resume and demotion safety."
argument-hint: "<page> [--app pc|mobile|hana]"
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
(missing → run `fm-plan {page}`; stop). Read `targetDir`, `appDir`, `packagesDir`, `monorepoRoot`,
`routerMode`, `workingLanguage`, `eslintTemplate`, `prettierTemplate`, and the plan's `buildOrder`
+ `blockers`.

### Step 1: Blockers
If the plan has unresolved `blockers` (unextracted shared candidates), stop and tell the user to
run `/frontend-migration-plugin:fm-extract` first.

### Step 2: Resume / demotion
- If `generation-state.json` exists, offer to resume from the last incomplete phase.
- Demotion warning: if the page status is `verified`/`e2e-passed`/`parity-passed`, warn that
  re-generating resets it to `generated` and discards downstream gate progress. Confirm before
  proceeding.

### Step 3: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min).

### Step 4: Run phases (sequential)
For each phase in `buildOrder`, launch the right agent (Agent tool), passing only its params
(subagent isolation), and inspect the result before the next:
- `foundation` → **foundation-generator** (types + MSW + harness + lint/format config scaffold;
  pass `monorepoRoot`, `legacyDirs` (every `apps.*.legacyDir`), `eslintTemplate`, `prettierTemplate`)
- `api` / `store` / `component` / `page` → **tdd-cycle-runner** (Red-Green per unit)
- `integration` → **integration-generator** (routes + i18n + MSW global + ESLint on generated
  code; pass `eslintTemplate`)

After each phase, update `generation-state.json` (Read-Modify-Write): mark the phase
`done`/`failed`, record `currentPhase`. On a phase failure, stop and report — the page status
becomes `gen-failed`.

### Step 5: Record
1. Set `generatedAt` and, if all phases succeeded, `tracker.json`
   `apps[app].pages[page].status = "generated"`; any skipped/failed phase → `gen-failed`.
2. Release the lock.

### Step 6: Report
In `workingLanguage`: phases completed, files created, total tests with RED/GREEN evidence from
each TDD phase, harness status, and any manual integration steps. Next step:
`/frontend-migration-plugin:fm-verify {page}`.
