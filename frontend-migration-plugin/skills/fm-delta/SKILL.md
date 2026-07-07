---
name: fm-delta
description: "Use when the legacy Angular source for an already-migrated page changes (the staleness hook flags drift) — re-migrate only the changed surface via a delta plan, preserving accumulated fixes, then re-enter the gates."
argument-hint: "<page> [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Incremental Re-migration

Re-migrates only what changed when the legacy source drifts, instead of regenerating the whole
page — preserving the fixes accumulated through earlier gate loops. All user-facing output in
`workingLanguage`.

## Instructions

### Step 0: Config & state
Read config (absent → run `fm-init`; stop). Resolve `app`, `targetDir`, `appDir`, `packagesDir`,
`legacyDir`, `workingLanguage`. The page should already be at `generated` or beyond (else this is
a first migration → use `fm-analyze`/`fm-style-spec`/`fm-plan`/`fm-gen`).

### Step 1: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min).

### Step 2: Compute the delta (planner incremental mode)
Launch `migration-planner` (Agent) with only its params: `mode: "incremental"`, `app`, `page`,
`analysisPath`, `planPath` (= `migration-plan.json`, the baseline), `legacyDir`,
`outPath = docs/migration/{app}/{page}/delta-plan.json`, `workingLanguage`. It diffs the current
legacy source against the `analysis.json` / `migration-plan.json` baseline and writes
`delta-plan.json` (added/modified/removed ops + cascade).

### Step 3: Offer incremental vs full
Read `delta-plan.json.summary`. Present:
- the change counts (added/modified/removed);
- **if the delta touches > 60% of the page files**, recommend full regeneration (`fm-gen`)
  instead;
otherwise default to incremental. Let the user choose.

### Step 4: Apply

**Style-surface prerequisite (both branches).** If `delta-plan.json.styleDrift` is set (the planner
detected changed classes / structure / assets), first **replace `analysis.json.styleSurface`
wholesale** with `delta-plan.json.styleDrift.styleSurface` — the **complete current** surface (every
element + structure, not the drifted subset; a merge would leave removed elements behind). Whatever
re-extracts styles reads `analysis.json.styleSurface`, and the baseline still holds the old surface
until Step 5, so this patch must land before any re-extraction on **either** branch.

- **Incremental** →
  1. **Refresh the answer key in-lock — do NOT nest the `fm-style-spec` skill** (it acquires this
     same page `.lock`, which this skill holds from Step 1 → deadlock). When `styleDrift` was set,
     launch `style-spec-extractor` (Agent) **directly**, resolving `legacyUrl` the way `fm-style-spec`
     Step 2 does (config `stagingConfig.baseUrl` / app `domain` + `analysis.target.routePath` /
     `legacyUrlCandidates`, or `null` → source-cascade fallback), passing the extractor's own params
     (see `agents/style-spec-extractor.md`): `app`, `page`, `analysisPath` (now holding the patched
     surface), `outPath` = `docs/migration/{app}/{page}/style-spec.json`, `legacyUrl`, `legacyDir`,
     `targetDir`, `appDir`, `workingLanguage`. It refreshes `style-spec.json` so the delta's style
     ops build to **fresh** values. (Skip when `styleDrift` is unset.)
  2. Launch `delta-modifier` (Agent) with only its params: `app`, `page`, `deltaPlanPath` =
     `docs/migration/{app}/{page}/delta-plan.json`, `styleSpecPath` =
     `docs/migration/{app}/{page}/style-spec.json`, `targetDir`, `appDir`, `packagesDir`,
     `workingLanguage` (create/style ops use `tdd-cycle-runner` semantics — build to the style-spec,
     no eyeballing). It applies ops in cascade order and preserves fm-fix edits.

  Then continue to Step 5.
- **Full** → **release the page `.lock` first** (do NOT fall through to Step 5 holding it — the
  skills you point the user to need that same lock), then tell the user to run `fm-gen {page}`; if
  `styleDrift` was set, run `/frontend-migration-plugin:fm-style-spec {page}` first — it reads the
  now-patched `analysis.json.styleSurface`, so the full re-gen builds to fresh style values. The
  skill **stops here**; Step 5 (which records an applied incremental delta) does not run.

### Step 5: Record (incremental path only)
- Patch `migration-plan.json`/`analysis.json` with the new baseline (the `styleSurface` is already
  current from Step 4); archive the delta as `delta-plan.{timestamp}.json`.
- Update `tracker.json` (Read-Modify-Write): set status back to `generated` (the page must re-pass
  the gates), record `deltaAppliedAt`.
- Release the lock.

### Step 6: Report (incremental path)
In `workingLanguage`: ops applied, tests pass/fail with evidence, confirmation that prior fixes
were preserved, and the re-entry point — `/frontend-migration-plugin:fm-verify {page}` → fm-e2e →
fm-parity. (On the **Full** path the skill already ended in Step 4 after releasing the lock and
printing the `fm-style-spec`/`fm-gen` next-steps — that instruction is its report.)
