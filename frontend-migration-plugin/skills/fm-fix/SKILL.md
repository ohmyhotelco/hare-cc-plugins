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

**Confirm `apps[app]` before using it** (CLAUDE.md → Configuration): the app entry must exist and carry the keys this stage reads. Config-file presence is not app presence — `mobile`/`hana` are scaffolded, and a `--app` naming an unconfigured one must stop here with a clear message rather than fail deep inside an agent on an unresolved path.

### Step 1: Detect fix mode
**Entry precondition.** This skill only closes a failed gate, so it accepts exactly
`verify-failed`, `e2e-failed`, `parity-failed`, `fixing` (a re-entry), and **`escalated`**. Refuse
every other status, `--mode` included: on a healthy page (`generated` … `parity-passed`) the
fall-through below would pick `verify-fix`, Step 3 would write `fixing` over it, and Step 5 would
"restore" it to `generated` — demoting a page that had nothing wrong with it. `gen-failed` has its
own redirect below.

**`escalated` is accepted, not refused** — it is the state manual intervention exits *through*.
`CLAUDE.md` → Per-page State Machine, `fm-progress`, and both hooks all route an escalated page here
after the human has intervened; refusing it would close the only exit and leave the operator running
the command the hook keeps recommending, forever. On `escalated` the status no longer names a gate,
so derive the mode the same way a `fixing` re-entry does — from `previousStatus` if recorded, else
report mtime — and say which selected it.

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

### Step 1b: Refuse a flipped, done, or flip-in-flight page
If the status is `flipped`, stop and point the user at
`/frontend-migration-plugin:fm-route {page} --revert` — Step 3 would write `fixing` over a live page.

**Also refuse `done`, and refuse while a flip is in flight.**
- `done` is past `flipped` — the edge serves v2 *and* the legacy page has been deleted — so there is
  nothing to roll back to and `--revert` refuses it too. Require **manual intervention**; do not
  point at `--revert`.
- `flipPrOpenedAt` present means the flip artifact was prepared and PR2 handed to the operator
  (`CLAUDE.md` → Per-page State Machine defines the field). Refuse and point at `fm-route --revert`,
  the only clearer: a rewrite underneath it leaves PR2 describing code that no longer exists, and the
  timestamp survives every read-modify-write, so the session hook later reads it and recommends
  `--confirm-live` on superseded code.

### Step 2: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min; JSON schema — `holder`/`pid`/ISO-8601 `acquiredAt` — in CLAUDE.md → Lock file).

### Step 3: Mark fixing
Update `tracker.json` (Read-Modify-Write): set `apps[app].pages[page].status = "fixing"` and record
`previousStatus` — the `*-failed` state this fix run entered from, which Step 5 restores on
`regenRequired` and which is the audit trail for a page that ends up `escalated`.

**Write `previousStatus` only when the current status is neither `fixing` nor `escalated`.** Both
are re-entry states that do not name a gate: Step 1 derives the mode from `previousStatus` on both
paths, and Step 5 restores it on `regenRequired`. Writing it unconditionally would overwrite the
original `*-failed` value with `"fixing"` or `"escalated"` — and `"escalated"` is worse than useless,
because it *is* "recorded", so the `else report mtime` fallback never fires and the mode selector is
left with a value naming no gate. Step 5 would then restore `fixing`, leaving the tracker
saying "fix in progress" while this skill's own report tells the user to run `fm-gen --force` — two
different next steps for one page. Preserve the existing value instead.

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

**Refresh `sourcePaths` from `fix-report.json.filesChanged`** (Read-Modify-Write: add files the
fixer created, drop ones it removed). `sourcePaths[]` is axis 1 of the page's watch paths, and
only `fm-gen`/`fm-delta` used to maintain it — so a fixer refactor that renamed files left the
gate watching paths that no longer exist and *not* watching the replacements. When every
recorded path disappears that way, `fm-route` Step 1a blocks (correctly, but on a page nobody
changed maliciously); keeping the list current is what stops that.

Release the lock.

### Step 6: Report
In `workingLanguage`: mode, files changed, the gate re-run result with evidence, and the next
step — re-run the failed gate (`fm-verify` / `fm-e2e` / `fm-parity`) to confirm, or `fm-gen` if
regeneration was recommended. That re-run is **required, not advisory**: until the gate runs and
rewrites its own report, the page's report still reads `fail` and `fm-route --flag-on` will refuse
the flip.
