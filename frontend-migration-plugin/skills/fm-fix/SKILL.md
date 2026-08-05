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

**`gen-failed` is not a fix mode — stop and redirect.** If the page status is `gen-failed`, a
generation phase never completed, so there is no gate failure to repair and no verify summary to
read. Tell the user to re-run `/frontend-migration-plugin:fm-gen {page}`, which resumes from the
last incomplete phase (its Step 2). Falling through to `verify-fix` here would let a "pass" set the
page to `generated` — declaring generation complete for a page whose phases never ran.
Compare timestamps; the newest failing report wins. **But the page's status is the authority, not the
file mtime.** Gate reports are not cleared by regeneration, so a page now at `verify-failed` can
still carry an older failing `parity-report.json`; picking `parity-fix` there would repair the wrong
thing and return the page to `e2e-passed`, silently stepping over the current verify failure. So
derive the mode from the status first — `verify-failed` → `verify-fix`, `e2e-failed` → `e2e-fix`,
`parity-failed` → `parity-fix` — and use report mtime only to break a tie or when the status is
`fixing` (a re-entry, where the status no longer names the gate). Report the chosen mode and what
selected it.

### Step 2: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min; JSON schema — `holder`/`pid`/ISO-8601 `acquiredAt` — in CLAUDE.md → Lock file).

### Step 2b: Refuse a flipped page
If the status is `flipped`, stop and point the user at
`/frontend-migration-plugin:fm-route {page} --revert` — Step 3 would write `fixing` over a live page.

### Step 3: Mark fixing
Update `tracker.json` (Read-Modify-Write): set `apps[app].pages[page].status = "fixing"`
(record `previousStatus` — the state to return to, and the audit trail for a page that ends up
`escalated`; no skill branches on it).

### Step 4: Run the fixer
Launch `migration-fixer` (Agent) with only its params: `mode`, `reportPath` (the failing
`e2e-report.json`/`parity-report.json`; omit for `verify-fix` — verify writes no report, its failing
summary is in `tracker.json`), `app`, `page`, `targetDir`, `appDir`, `packagesDir`,
`outPath` = `docs/migration/{app}/{page}/fix-report.json`, `workingLanguage`.

### Step 5: Resolve outcome
Read `fix-report.json`:
- `regenRequired: true` → the fixer stopped **without changing code**, so generation has not been
  redone. Step 3 already wrote `fixing`, so restore the `previousStatus` it recorded there (the
  `*-failed` state this run entered from) and record `regenRequiredAt`, and tell the user
  to re-run `/frontend-migration-plugin:fm-gen {page} --force` (a full regeneration; the resume path
  would otherwise see a complete `generation-state.json` and do nothing). Setting `generated` here
  would claim a generation that never ran and point the session hook at `fm-verify`.
- gate re-run `pass` → set status back to the failed gate's **entry** state, so the gate itself can
  run again: `verify-fix` → `generated`, `e2e-fix` → `verified`, `parity-fix` → `e2e-passed`.
  **Never set the gate's passed state here.** The fixer's own re-run is a repair signal, not a gate
  result: the gate report on disk still records the old `fail` (the fixer writes `fix-report.json`
  only), and a passed state the gate did not issue is the fixer confirming its own work. The gate
  owns its passed state and rewrites its own report — `fm-fix` only returns the page to where that
  gate can be entered.
- gate re-run still `fail` → keep `fixing`; if repeated failures, escalate (`escalated`) for
  manual intervention. A page left at `fixing` is re-entered through `fm-fix`, not through a gate.

If this fix closed (or dismissed) a Codex finding recorded in `codex-audit.json`, record the
adjudication on that finding (Read-Modify-Write): `adjudication.state = "closed"` for a fix (or
`"rejected"` if judged not a defect), with `by: "fm-fix"`, `when` (ISO-8601), and a required `basis`
— the commit/`file:line` that closed it, or why it is not a defect. This is what lets
`fm-route --flag-on` (Step 1b) tell an already-fixed finding from a still-open one instead of
re-surfacing every finding forever. See `templates/codex-audit.md`.

Release the lock.

### Step 6: Report
In `workingLanguage`: mode, files changed, the gate re-run result with evidence, and the next
step — re-run the failed gate (`fm-verify` / `fm-e2e` / `fm-parity`) to confirm, or `fm-gen` if
regeneration was recommended. That re-run is **required, not advisory**: until the gate runs and
rewrites its own report, the page's report still reads `fail` and `fm-route --flag-on` will refuse
the flip.
