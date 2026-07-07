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
- **Style refresh first (in-lock — do NOT nest `fm-style-spec`).** If `delta-plan.json.styleDrift`
  is set (the incremental planner detected changed classes / structure / assets in `styleSurface`):
  1. **Patch `analysis.json.styleSurface` BEFORE extracting.** The extractor reads
     `analysis.json.styleSurface` to know which elements/states/assets to probe — but the baseline
     `analysis.json` still holds the *old* surface (Step 5 only rebaselines after apply). So first
     Read-Modify-Write the current surface from `delta-plan.json.styleDrift.styleSurface` (the
     planner recorded it) into `analysis.json.styleSurface`, or the refresh would re-probe the stale
     element set and miss the very elements that drifted.
  2. Refresh the answer key **without re-running the `fm-style-spec` skill** — that skill acquires
     this same page `.lock` (this skill already holds it from Step 1), so nesting it would deadlock.
     Instead launch `style-spec-extractor` (Agent) **directly**, resolving `legacyUrl` the way
     `fm-style-spec` Step 2 does (config `stagingConfig.baseUrl` / app `domain` +
     `analysis.target.routePath` / `legacyUrlCandidates`, or `null` → source-cascade fallback), and
     passing the extractor's own params (see `agents/style-spec-extractor.md`): `app`, `page`,
     `analysisPath` (now holding the patched surface),
     `outPath` = `docs/migration/{app}/{page}/style-spec.json`, `legacyUrl`, `legacyDir`,
     `targetDir`, `appDir`, `workingLanguage`. It Read-Modify-Writes `style-spec.json` (its
     `outPath`) so the delta's style ops build to the **fresh** values. (A visual-only legacy change
     is a real delta — the planner flags it via `styleDrift` even with no behavioral op.)
- **Incremental** → launch `delta-modifier` (Agent) with only its params: `app`, `page`,
  `deltaPlanPath` = `docs/migration/{app}/{page}/delta-plan.json`,
  `styleSpecPath` = `docs/migration/{app}/{page}/style-spec.json`, `targetDir`, `appDir`,
  `packagesDir`, `workingLanguage` (create/style ops use `tdd-cycle-runner` semantics — build to the
  style-spec, no eyeballing). It applies ops in cascade order and preserves fm-fix edits.
- **Full** → tell the user to run `fm-gen {page}` (the skill stops here).

### Step 5: Record
- Patch `migration-plan.json`/`analysis.json` with the new baseline; archive the delta as
  `delta-plan.{timestamp}.json`.
- Update `tracker.json` (Read-Modify-Write): set status back to `generated` (the page must re-pass
  the gates), record `deltaAppliedAt`.
- Release the lock.

### Step 6: Report
In `workingLanguage`: ops applied, tests pass/fail with evidence, confirmation that prior fixes
were preserved, and the re-entry point — `/frontend-migration-plugin:fm-verify {page}` → fm-e2e →
fm-parity.
