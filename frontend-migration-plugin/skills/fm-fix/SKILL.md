---
name: fm-fix
description: "Use when a migration gate fails (fm-verify, fm-e2e, or fm-parity) — auto-detects the fix mode from the latest failure report, applies targeted repairs via the migration-fixer agent, and re-runs the gate. Also use with --mode review to fix PR review findings or QA defects on a gated, flip-prepared or flipped page."
argument-hint: "<page> [--app pc|mobile|hana] [--mode verify|e2e|parity] | <page> --mode review --findings <file> [--base <branch>] [--app pc|mobile|hana]"
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

### Step 0b: Review mode (`--mode review`) — a separate lane
`--mode review` fixes review findings or QA defects, not a failed gate (CLAUDE.md → Per-page State
Machine → In-flight window). It skips Steps 1–5 below and runs this lane instead:

1. **Entry.** Require `--findings <file>` (the findings: id, text, cited files — the reviewer's list
   or a QA ticket's, transcribed as data). Accept a page at `generated`, `verified`, `e2e-passed`,
   `parity-passed` (with or without `flipPrOpenedAt`) or `flipped`. Refuse `done` (manual
   intervention), every `*-failed` state and `fixing`/`escalated` (a failed gate goes through the
   gate modes below — say which), and anything below `generated`.
2. **Resolve** `pluginRoot` (`.claude/frontend-migration-plugin.local.json`; absent → stop, the
   records check and gate impact cannot run and this lane exists for them) and the base branch the
   PR targets, the same way `fm-route` Step 0b does (`--base`, config `defaultBaseBranch`,
   `origin/HEAD`).
3. **Lock** as Step 2 does. Write **no** status here — this lane never writes `fixing`.
4. **Run the fixer.** Launch `migration-fixer` (Agent) with `mode = "review-fix"`, `findingsPath`,
   `baseRef`, `pluginRoot`, `app`, `page`, `targetDir`, `appDir`, `packagesDir`,
   `outPath = docs/migration/{app}/{page}/review-fix-report.json`, `workingLanguage`.
5. **Resolve.** Read `review-fix-report.json`.
   - `outOfScope[]` non-empty → the fixer stopped at a new surface. Report each path and that it
     needs its own ticket and plan; record nothing, and leave the edits for the operator to split.
   - Any finding without one of `fixed` + `redProof`, `deferred` + a ledger row, or `rejected` +
     `basis` → the run is incomplete; report the open ids and record nothing.
   - Otherwise, refresh `sourcePaths` from `filesChanged`/`filesRemoved` as Step 5 does, and record
     the adjudication of any Codex finding it closed. Then:
     - **page below the flip** (no `flipPrOpenedAt`, not `flipped`) → exactly Step 5's pass branch:
       status `generated`, every trace the code change invalidated cleared, the chain re-runs from
       `fm-verify`;
     - **in-flight or flipped page** → **no status write**. The recorded evidence is now stale by
       content (the gates hash what they watched), so the next step is `fm-verify {page} --regate`,
       then `fm-e2e --regate`, then `fm-parity --regate`.
6. **Report** in `workingLanguage`: each finding and how it closed, the class sweep, the claims swept,
   the `check-records.sh` result, the `gate-impact.sh` output (other in-flight pages it lists need
   their own `--regate`), and the next step. Then **print the updated PR title and body** from
   `templates/pr-body.md` — including Gate impact and Claims swept — for the operator to paste: a
   body left unchanged across fix rounds is a finding of its own (`templates/pr-body.md` → Rules).

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
If the status is `flipped`, stop — Step 3 would write `fixing` over a live page. For a code fix on the
live page, point at `--mode review` (Step 0b), which writes no status; to take the page off v2, at
`/frontend-migration-plugin:fm-route {page} --revert`.

**Also refuse `done`, and refuse while a flip is in flight.**
- `done` is past `flipped` — the edge serves v2 *and* the legacy page has been deleted — so there is
  nothing to roll back to and `--revert` refuses it too. Require **manual intervention**; do not
  point at `--revert`.
- `flipPrOpenedAt` present means the flip artifact was prepared and PR2 handed to the operator
  (`CLAUDE.md` → Per-page State Machine defines the field). The gate modes refuse it: they write
  `fixing` and then `generated`, which would demote a page whose flip is in flight. Point at the
  status-free lane instead — `fm-fix {page} --mode review --findings <file>` for a code fix, then
  `--regate` on the gates — or at `fm-route --revert` to abandon the flip.

### Step 2: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale only when its holder is gone — see CLAUDE.md → Lock file; JSON schema — `holder`/`pid`/ISO-8601 `acquiredAt` — in CLAUDE.md → Lock file).

### Step 3: Mark fixing

**Tracker lock.** Take `docs/migration/.tracker.lock` around every `tracker.json` write
**anywhere in this skill**, after the page lock (CLAUDE.md → Lock file). Write it per CLAUDE.md → Serialization.

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
- gate re-run `pass` → **set the status to `generated` and clear every trace the fix invalidated**:
  `gateEvidence` (all gates), the legacy `verifiedAt` / `e2ePassedAt` / `parityPassedAt`,
  `routePrepared` / `flagKey`, plus the `cascade` record and the page's `cascade-diff*.json` files
  (`fm-route` reads that file directly; a pre-fix report — clean or not — describes a tree this
  fix just changed) — the set `fm-gen` Step 5.3 and `fm-delta` Step 5 also clear, for
  exactly the same reason: **this skill changed code.** **Do not clear `regenRequiredAt`**: it
  means a full `fm-gen` is owed, and this skill does not perform one. Its `verify-fix` mode cannot
  produce the i18n key-coverage spec at all (`fm-verify` Step 7), so clearing it would drop the
  only signal that routes the user to the remedy. The whole gate chain re-runs from
  `fm-verify`. **Never set any gate's passed state here** — the fixer's own re-run is a repair
  signal, not a gate result: the gate report on disk still records the old `fail` (the fixer writes
  `fix-report.json` only), and a passed state the gate did not issue is the fixer confirming its own
  work.

  **Why the full chain and not just the failed gate.** An earlier revision returned the page to the
  failed gate's *entry* state (`parity-fix` → `e2e-passed`) and left the upstream evidence standing.
  That was unreachable by construction: `gateEvidence.{gate}.tree` is content-keyed, the fix changed
  the content, so `verify` and `e2e` were **always** stale afterwards and `fm-route` Step 1a — a hard
  gate with no acknowledgement path — blocked **every** post-fix flip. The only documented escape
  was re-running `fm-verify`, which silently demoted the page anyway. Leaving `routePrepared` was the
  same defect one field along: a flip could then skip the fresh `--flag-off` and the route-stage
  Codex audit that the *fixed* code never received.

  The real added cost is one e2e run after a `parity-fix` — `verify` is the cheap gate, and after an
  `e2e-fix` or a `verify-fix` parity had not passed yet. A code change that could not affect
  behaviour is not a thing this pipeline can assert, so that run is owed.
- gate re-run still `fail` → keep `fixing`; if repeated failures, escalate (`escalated`) for
  manual intervention. A page left at `fixing` is re-entered through `fm-fix`, not through a gate.

If this fix closed (or dismissed) a Codex finding recorded in `codex-audit.json`, record the
adjudication on that finding (Read-Modify-Write): `adjudication.state = "closed"` for a fix (or
`"rejected"` if judged not a defect), with `by: "fm-fix"`, `when` (ISO-8601), and a required `basis`
— the commit/`file:line` that closed it, or why it is not a defect. This is what lets
`fm-route --flag-on` (Step 1b) tell an already-fixed finding from a still-open one instead of
re-surfacing every finding forever. See `templates/codex-audit.md`.

**Refresh `sourcePaths` from `fix-report.json`** (Read-Modify-Write: add every `filesChanged[]`
entry, drop every `filesRemoved[]` entry — a rename appears in both; skip a path
`git check-ignore -q` accepts, CLAUDE.md → Gate Result Accounting F). `sourcePaths[]` is axis 1 of the page's watch paths, and
only `fm-gen`/`fm-delta` used to maintain it — so a fixer refactor that renamed files left the
gate watching paths that no longer exist and *not* watching the replacements. When every
recorded path disappears that way, `fm-route` Step 1a blocks (correctly, but on a page nobody
changed maliciously); keeping the list current is what stops that.

Release the lock.

### Step 6: Report
In `workingLanguage`: mode, files changed, the gate re-run result with evidence, and the next
step. On a successful fix the page is at `generated`, so the next step is the **whole chain**:
`/frontend-migration-plugin:fm-verify {page}` → (`fm-cascade` when the page injects markup it does
not author — fm-verify's report says when) → `fm-e2e` → `fm-parity` → `fm-route --flag-off`.
Say that plainly, including that a prior `--flag-off` no longer counts (`routePrepared` was
cleared) — the fixed code needs its own code PR and its own route-stage audit. On `regenRequired`
the next step is `fm-gen {page} --force` instead. Those re-runs are **required, not advisory**:
until each gate runs and rewrites its own report, the reports on disk still describe pre-fix code.
