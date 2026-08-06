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

**Confirm `apps[app]` before using it** (CLAUDE.md → Configuration): the app entry must exist and carry the keys this stage reads. Config-file presence is not app presence — `mobile`/`hana` are scaffolded, and a `--app` naming an unconfigured one must stop here with a clear message rather than fail deep inside an agent on an unresolved path.

**Refuse `fixing` and `escalated` too.** A fix is in progress or awaiting manual intervention;
Step 5 resets the page to `generated`, which discards the accumulated repairs and the
`previousStatus` the fix loop needs. Send the user to `fm-fix` (after the manual step, for
`escalated`) and let the gate re-run first.

**Refuse a `flipped` page, a `done` page, or one with a flip prepared and handed over.** `done` is past
`flipped` — the legacy page has been deleted, so there is no legacy source left to diff a delta
against and no rollback target; refuse and require manual intervention — **not** `--revert`, which
refuses a `done` page too. A present `flipPrOpenedAt` means the flip artifact is prepared and PR2
handed over against the current code: refuse and point at `fm-route --revert` first.
If the status is `flipped`, stop and tell the user to run
`/frontend-migration-plugin:fm-route {page} --revert` first — **`--revert`, not `--flag-off`**:
flag-off keeps the current status (`fm-route` Step 4), so it would leave the page at `flipped` and
this refusal would repeat with no exit. `--revert` is the rollback that returns it to
`parity-passed`. Step 5 resets the status to
`generated` while the edge flag stays ON — nothing here touches routing — so the tracker would say
"not flipped" while the production domain serves v2. Provenance resolves a capture's `side` from
exactly that status (`templates/capture-provenance.md`), so the next capture from the production
host would be labelled `legacy` and accepted as the legacy baseline. Beyond the provenance damage,
applying a delta to a page under live traffic is a change in production; taking it out of rotation
first is the correct order.

**Stale staging is cleared in Step 2, under the lock — not here.** Deleting it before the lock
would let a second session destroy the staged baseline of a delta that is *currently running*: that
run then reaches Step 5, finds its files gone, and aborts having already rewritten the code, leaving
a page whose tracker still says `parity-passed` over code the delta changed. Step 5's
integrity check is that they *exist*, so an abandoned pair from a previous run would sail through it
and promote a baseline describing a delta nobody applied — the same reason the Full branch deletes
them, which is the only abort path that was covered.

### Step 1: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min; JSON schema — `holder`/`pid`/ISO-8601 `acquiredAt` — in CLAUDE.md → Lock file). If it is held and fresh, report who holds it and stop — do not delete anything, and do not wait.

### Step 2: Clear stale staging, then compute the delta (planner incremental mode)
**Under the lock**, delete any `migration-plan.next.json` / `analysis.next.json` left by an earlier
run that aborted between Step 2 and Step 5. Holding the lock is what makes this safe: the only
staged files that can exist here are orphans, because any live delta holds this lock. Step 5's
integrity check is that the staged pair *exists*, so an abandoned pair would otherwise sail
through it and promote a baseline describing a delta nobody applied.

Then launch the planner:
Launch `migration-planner` (Agent) with only its params: `mode: "incremental"`, `app`, `page`,
`analysisPath`, `planPath` (= `migration-plan.json`, the baseline), `legacyDir`,
`outPath = docs/migration/{app}/{page}/delta-plan.json`, `workingLanguage`. It diffs the current
legacy source against the `analysis.json` / `migration-plan.json` baseline and writes
`delta-plan.json` (added/modified/removed ops + cascade).

### Step 3: Offer incremental vs full
Read `delta-plan.json.summary`. Present:
- the change counts (added/modified/removed);
- **if the delta touches > 60% of the page's files (denominator = `tracker.json` `sourcePaths[]`, the list `fm-gen` recorded; absent → report the ratio as unavailable rather than guessing)**, recommend full regeneration (`fm-gen`)
  instead;
otherwise default to incremental. Let the user choose.

### Step 4: Apply

**Style-surface prerequisite — incremental branch only.** If `delta-plan.json.styleDrift` is set (the planner
detected changed classes / structure / assets), first **replace `analysis.json.styleSurface`
wholesale** with `delta-plan.json.styleDrift.styleSurface` — the **complete current** surface (every
element + structure, not the drifted subset; a merge would leave removed elements behind). Whatever
re-extracts styles reads `analysis.json.styleSurface`, and the baseline still holds the old surface
until Step 5, so this patch must land before any re-extraction. It must **not** land before the
Step 3 choice: the Full branch stops without running Step 5, so a `styleSurface` already replaced
there leaves the canonical `analysis.json` describing post-drift structure while the tracker still
says `parity-passed` over pre-drift code and evidence. Patch it inside the incremental branch,
after the user has chosen it.

- **Incremental** →
  1. **Refresh the answer key in-lock — do NOT nest the `fm-style-spec` skill** (it acquires this
     same page `.lock`, which this skill holds from Step 1 → deadlock). Because the skill is bypassed,
     its **Step 2b is bypassed too**: ensure `.claude/settings.json` `permissions.allow` includes the
     Playwright command (e.g. `Bash(npx playwright *)`) here, or the sub-agent probe cannot launch and
     the refresh silently degrades to `source-derived` — defeating the point of refreshing the answer
     key. When `styleDrift` was set,
     launch `style-spec-extractor` (Agent) **directly**, resolving `legacyUrl` the way `fm-style-spec`
     Step 2 does (config `stagingConfig.baseUrl` / app `domain` + `analysis.target.routePath` /
     `legacyUrlCandidates`, or `null` → source-cascade fallback), passing the extractor's own params
     (see `agents/style-spec-extractor.md`): `app`, `page`, `analysisPath` (now holding the patched
     surface), `outPath` = `docs/migration/{app}/{page}/style-spec.json`, `legacyUrl`, `legacyDir`,
     `targetDir`, `appDir`, the app's `legacyPort` / `port` / `domain` and the page's flip state
     (the extractor resolves each capture's `provenance.side` from those —
     `templates/capture-provenance.md`; bypassing `fm-style-spec` bypasses its param list too, and an
     unresolved side counts as absent, so the refreshed baseline would be unusable by `fm-parity`),
     `workingLanguage`. It refreshes `style-spec.json` so the delta's style
     ops build to **fresh** values. (Skip when `styleDrift` is unset.)
  2. Launch `delta-modifier` (Agent) with only its params: `app`, `page`, `deltaPlanPath` =
     `docs/migration/{app}/{page}/delta-plan.json`, `styleSpecPath` =
     `docs/migration/{app}/{page}/style-spec.json`, `targetDir`, `appDir`, `packagesDir`,
     `workingLanguage` (create/style ops use `tdd-cycle-runner` semantics — build to the style-spec,
     no eyeballing). It applies ops in cascade order and preserves fm-fix edits.

  Then continue to Step 5.
- **Full** → the page needs re-planning, not just re-generation. **Release the page `.lock` first**
  (do NOT fall through to Step 5 holding it — the skills you point the user to need that same lock),
  **clear the page's gate authorization** — `gateEvidence`, the legacy
  `verifiedAt`/`e2ePassedAt`/`parityPassedAt`, and `routePrepared`/`flagKey` (take
  `.tracker.lock` for that write) — because the drift that brought you here means the recorded
  passes describe legacy the page no longer matches, and legacy source is **not** a watch-path
  axis, so nothing else will notice. Then tell the user to re-run the chain from the stage the
  drift invalidated:
  `/frontend-migration-plugin:fm-analyze {page}` → `fm-style-spec` (if `styleDrift`) → `fm-plan` →
  `fm-gen {page} --force`. Do **not** send them straight to `fm-gen`: the canonical baseline is
  still the pre-drift one — the planner staged its proposal as `migration-plan.next.json` /
  `analysis.next.json` and only Step 5 promotes those — so `fm-gen` would regenerate the page
  against the plan the drift just invalidated. **Delete the two `.next.json` files** on the way out
  so a later run cannot mistake an abandoned proposal for a current one. The skill **stops here**;
  Step 5 (which records an applied incremental delta) does not run.

### Step 5: Record

**Tracker lock.** Every `tracker.json` read-modify-write in this step happens **inside**
`docs/migration/.tracker.lock`, acquired *after* the lock this skill already holds and released
immediately after the write (CLAUDE.md → Lock file). The page lock does not protect
`tracker.json` — twelve writers share that one file, and `fm-extract` holds a different lock
entirely. Take it before the write, not after: a sentence read in order is the instruction.
 (incremental path only)
- **Promote the staged baseline.** `migration-planner` (incremental mode) wrote its proposal to
  `migration-plan.next.json` and `analysis.next.json`; verify both parse and reflect the applied ops
  rather than re-deriving them here (the `styleSurface` is already current from Step 4), then move
  them over the canonical `migration-plan.json` / `analysis.json` and delete the staged copies. This
  is the only step that advances the baseline, and it runs **after** the delta actually applied — so
  a user who chose full regeneration, or a run that failed in Step 4, leaves the reference untouched.
  If either staged file is missing, the delta is incomplete — re-run the planner
  before recording. Archive the delta as `delta-plan.{timestamp}.json`.
- Update `tracker.json` (Read-Modify-Write): set status back to `generated` (the page must re-pass
  the gates), record `deltaAppliedAt`, refresh the tracker `styleSpec` summary when Step 4 re-extracted the answer
  key (otherwise it keeps describing the pre-drift capture), refresh `sourcePaths` for any file the delta created or
  removed, and **clear `gateEvidence` together with the legacy `verifiedAt` / `e2ePassedAt` /
  `parityPassedAt`** — the page's code changed, so every prior gate PASS now rests on superseded code
  and must not read as fresh. Clearing `gateEvidence` alone leaves exactly the fields `fm-route`
  Step 1 hard-gates on (`verifiedAt` + both reports reading `pass`), which would re-authorize the
  flip. **Clear `routePrepared` and `flagKey` on the same pass**, or Step 1-pre still reads the page
  as code-PR-prepared and `--flag-on` skips the fresh `--flag-off` (CLAUDE.md → "Gate Result
  Accounting").
- Release the lock.

### Step 6: Report (incremental path)
In `workingLanguage`: ops applied, tests pass/fail with evidence, confirmation that prior fixes
were preserved, and the re-entry point — `/frontend-migration-plugin:fm-verify {page}` → fm-e2e →
fm-parity. (On the **Full** path the skill already ended in Step 4 after releasing the lock and
printing the `fm-analyze` → `fm-style-spec` → `fm-plan` → `fm-gen --force` next-steps — that
instruction is its report.)
