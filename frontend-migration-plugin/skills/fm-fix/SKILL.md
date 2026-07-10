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
If `--mode` is given, use it. Otherwise auto-detect from the **most recently modified** failure
report under `docs/migration/{app}/{page}/`:
- `parity-report.json` (fail) → `parity-fix`
- `e2e-report.json` (fail) → `e2e-fix`
- otherwise (verify-failed / build/tsc/vitest) → `verify-fix`
Compare timestamps; the newest failing report wins. Report the chosen mode.

### Step 2: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min).

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
- gate re-run `pass` → set status back to the gate's passed state (`verified` / `e2e-passed` /
  `parity-passed`).
- gate re-run still `fail` → keep `fixing`; if repeated failures, escalate (`escalated`) for
  manual intervention.
Release the lock.

### Step 6: Report
In `workingLanguage`: mode, files changed, the gate re-run result with evidence, and the next
step — re-run the failed gate (`fm-verify` / `fm-e2e` / `fm-parity`) to confirm, or `fm-gen` if
regeneration was recommended.
