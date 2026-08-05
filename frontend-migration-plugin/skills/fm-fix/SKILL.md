---
name: fm-fix
description: "Use when a migration gate fails (fm-verify, fm-e2e, or fm-parity) — auto-detects the fix mode from the latest failure report, applies targeted repairs via the migration-fixer agent, and re-runs the gate."
argument-hint: "<page> [--app pc|mobile|hana] [--mode verify|e2e|parity]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Fix a Failed Migration Gate

Closes the loop on a gate failure with the smallest change, then re-runs the gate. All
user-facing output in `workingLanguage` (default `ko`).

## Instructions

### Step 0: Config
Read config (absent → run `fm-init`; stop). Resolve `app` (`--app`/`currentApp`), `targetDir`,
`appDir`, `packagesDir`, `workingLanguage`.

### Step 1: Detect fix mode
If `--mode` is given, normalize its short form to the `-fix` value the fixer expects
(`verify`→`verify-fix`, `e2e`→`e2e-fix`, `parity`→`parity-fix`; an already-suffixed value passes
through). Otherwise auto-detect from the **most recently modified** failure
report under `docs/migration/{app}/{page}/`:
- `parity-report.json` (fail) → `parity-fix`
- `e2e-report.json` (fail) → `e2e-fix`
- otherwise (verify-failed / build/tsc/vitest) → `verify-fix`
Compare timestamps; the newest failing report wins. Report the chosen mode.

### Step 2: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min; JSON schema — `holder`/`pid`/ISO-8601 `acquiredAt` — in CLAUDE.md → Lock file).

### Step 3: Mark fixing
Update `tracker.json` (Read-Modify-Write): set `apps[app].pages[page].status = "fixing"`
(record `previousStatus`).

### Step 4: Run the fixer
Launch `migration-fixer` (Agent) with only its params: `mode`, `reportPath` (the failing
`e2e-report.json`/`parity-report.json`; omit for `verify-fix` — verify writes no report, its failing
summary is in `tracker.json`), `app`, `page`, `targetDir`, `appDir`, `packagesDir`, `workingLanguage`.

### Step 5: Resolve outcome
Read `fix-report.json`:
- `regenRequired: true` → set status `generated` and tell the user to re-run `fm-gen` (large
  delta), then continue the pipeline.
- gate re-run `pass` → set status back to the failed gate's **entry** state, so the gate itself can
  run again: `verify-fix` → `generated`, `e2e-fix` → `verified`, `parity-fix` → `e2e-passed`.
  **Never set the gate's passed state here.** The fixer's own re-run is a repair signal, not a gate
  result: the gate report on disk still records the old `fail` (the fixer writes `fix-report.json`
  only), and a passed state the gate did not issue is the fixer confirming its own work. The gate
  owns its passed state and rewrites its own report — `fm-fix` only returns the page to where that
  gate can be entered.
- gate re-run still `fail` → keep `fixing`; if repeated failures, escalate (`escalated`) for
  manual intervention. A page left at `fixing` is re-entered through `fm-fix`, not through a gate.
Release the lock.

### Step 6: Report
In `workingLanguage`: mode, files changed, the gate re-run result with evidence, and the next
step — re-run the failed gate (`fm-verify` / `fm-e2e` / `fm-parity`) to confirm, or `fm-gen` if
regeneration was recommended. That re-run is **required, not advisory**: until the gate runs and
rewrites its own report, the page's report still reads `fail` and `fm-route --flag-on` will refuse
the flip.
