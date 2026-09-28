---
name: fm-progress
description: "Use any time to see migration progress — a read-only dashboard from tracker.json: per-app/per-page status, gate state (verify/e2e/parity), shared-package extraction, and the suggested next step per in-flight page."
argument-hint: "[--app pc|mobile|hana] [page]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash
---

# Migration Progress Dashboard

Read-only view of `docs/migration/tracker.json` and the per-page reports. Takes no lock and
changes nothing. All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config
Read config (absent → run `fm-init`; stop). Resolve `workingLanguage`, `monorepoRoot`, and
`packagesDir` (the stale-evidence check maps `sharedDeps[]` through it and shells out to
`scripts/gate-tree-hash.sh`; without them that check cannot run). **`pluginRoot`** (absolute, per-machine — read from `.claude/frontend-migration-plugin.local.json`, never the shared config; where `scripts/gate-tree-hash.sh` lives — absent → report the freshness
axis as `unverifiable` and skip the check. This skill records nothing; it is read-only). Optional `--app` / `page`
narrow the view — when `--app` is given, **confirm `apps[app]` exists** (CLAUDE.md → Configuration)
rather than silently reporting an empty view for a name that was never configured.

### Step 1: Read state
Read `tracker.json`. For detail, read the per-page reports under `docs/migration/{app}/{page}/`
(`analysis.json`, `migration-plan.json`, `e2e-report.json`, `parity-report.json`, `fix-report.json`).

### Step 2: Render the dashboard
In `workingLanguage`, show:
- **Per app** (pc / mobile / hana): page count by status across the state machine
  (`analyzed → style-specced → planned → generated → verified → e2e-passed → parity-passed → flipped
  → done`, plus `*-failed` / `fixing` / `escalated`; a `kind: "cluster"` target terminates at
  **`cluster-ready`** instead of flipping — CLAUDE.md → Component Clusters).
- **Per page** (for the active app or the named page): current status, `requiredGates`, the gate
  results (verify / e2e / parity: pass / fail / pending / **N/A**), rendering mode, flag key, and
  risk. A gate is **N/A** when the page's `notApplicable` has an entry for it with `approvedBy` and
  `approvedAt` (CLAUDE.md → Gate Result Accounting H) — show the reason and approver beside it, and
  keep it visibly distinct from `pass` even after the gate recorded its exempted pass
  (`gateEvidence.{gate}.notApplicable: true`). An entry missing either field is **N/A requested** —
  still pending, awaiting the owner's approval; say whose. Two more states to name rather than
  hide: **exemption withdrawn** — `gateEvidence.{gate}.notApplicable` is set but no approved entry
  remains. Show it as not passed, and give `fm-verify` as the next step instead of `fm-route`, which
  would refuse. **Approval lapsed** — the entry's `grantedTree` differs from the current tree (compute it for
  that gate as in "Stale evidence" below, whatever the page's status). The
  next gate run executes for real unless the owner re-approves.
- **Shared packages**: `tracker.packages` extraction status, and any pieces deferred to
  `fm-secret-audit`.
- **Cutover readiness** (`docs/migration/cutover-ledger.json`, absent → nothing to show): per app, the
  count of pages with **open** `blocksCutover` entries, and the full list of open `flip-precondition`
  rows with `item · owner · ticket` — the single place the big-bang cutover batch reads what is not
  yet ready. Flag any entry whose `owner` is `TBD` (an unowned blocker is itself the defect). Read-only
  — never writes the ledger. See `templates/cutover-ledger.md`.
- **Blockers**: pages in `*-failed` / `fixing` / `escalated` (a `gen-failed` page goes back to
  `fm-gen`, which resumes the incomplete phase — not to `fm-fix`, which has no generation mode), and any unextracted shared
  candidates blocking `fm-gen`.
- **Stale evidence**: `parity-passed` (awaiting flip) pages whose gate evidence no longer matches
  the current content of their watch paths. For each such page, resolve its **watch paths** exactly as `fm-route --flag-on`
  Step 1a does — `tracker.json` `sourcePaths[]` (minus untracked entries `git check-ignore -q`
  accepts), each `migration-plan.json` `sharedDeps[]` entry
  mapped from `@omh/<package>:<symbol>` to the directory `{packagesDir}/<package>`, **and the page's
  `migration-plan.json` itself (axis 3)** — omitting axis 3 makes every recomputation differ from
  the producers' and reports every page stale on unchanged code — **for the `verify` stamp, minus
  every axis-1 entry under `{appDir}/e2e/`** (F's carve-out; `e2e`/`parity` hash all of it) — then
  re-compute the watch-path content hash by running
  `{pluginRoot}/scripts/gate-tree-hash.sh --exclude docs/migration/{app}/{page}/gate-tree/{gate}.tsv
  -- <watch path>...` — the same `--exclude` and `--` that gate passed, or the sets differ and
  every page reads stale (never an inline pipeline —
  CLAUDE.md → "Gate Result Accounting") and compare it against each `gateEvidence.{gate}.tree`. A
  gate whose hash moved is **stale**; list the page with those gate(s). A page for which the script
  prints `unverifiable` is shown as such, never as fresh and never as stale. **Never pass `gateEvidence.{gate}.commit` to `git`** —
  it is an audit-trail field and is routinely `<sha>+dirty` (the normal state for a page that has not
  had its code PR yet, i.e. most of this view's population), which `git` rejects as an unknown
  revision. Freshness is decided by `tree` alone. See CLAUDE.md → "Gate Result Accounting". This is the early warning for a
  `packages/shared-*` change silently outdating many queued pages at once. Pages with no
  `gateEvidence`, or whose record predates `tree`, are shown as `unverifiable`, not stale; a page with no `sourcePaths` is
  `unverifiable` on its own-source axis but still checkable on its shared-package axis — say which
  axis was checked rather than reporting a bare "fresh". Read-only — flags, never re-runs.
- **Answer-key freshness** (CLAUDE.md → "Gate Result Accounting" G): where a page records
  `answerKeyEvidence.parity`, re-compute `{pluginRoot}/scripts/gate-tree-hash.sh` over its recorded
  `legacyPaths` (the same set `fm-parity` hashed) and compare against the stored `legacyTree`; report
  `answer-key-stale` when it moved — a master merge changed legacy source under a recorded style/parity
  answer key, which the v2-side stale-evidence check above cannot see (`fm-route --flag-on` blocks on
  this; here it is the early read-only warning). A page with **no** `answerKeyEvidence` (parity-passed
  before the producer landed, or under a parity exemption) is `not-recorded`, never fresh and never stale — do not infer freshness
  from its absence. Read-only.

### Step 3: Next-step guidance
For each in-flight page, print the exact next command, using the same mapping as the SessionStart
hook — including its carve-outs: `gen-failed` → `fm-gen` (not `fm-fix`), `escalated` → manual
intervention then `fm-fix`, `flipped` → no command (mark `done` by hand once the legacy page is
deleted); a `verified`/`e2e-passed`/`parity-passed` page whose `verifiedAt` is **absent** → **no
command**, only the note that the gate authorization was cleared and the last run's own report is
authoritative about where to restart — `fm-delta` Full says `fm-analyze` (the plan is still
pre-drift), a failed `fm-delta` says re-run `fm-delta`, and an `fm-extract` invalidation needs only
the gates from `fm-verify`. Do not name one of them here; the hook does not either; a page with `flipPrOpenedAt` set at any status **other than**
`parity-passed`/`flipped`/`done` → `fm-route --revert` (every other command refuses while a flip is
in flight, so the normal next step would be refused); a `*-failed` page with `regenRequiredAt` set → `fm-gen
--force` (**except `gen-failed`**, whose recovery is a resume — `--force` would discard it) (a full regeneration is owed — a fix that changed no code, or an absent i18n
key-coverage spec); a page under an app other than `currentApp` → append
`--app {app}`;
and `parity-passed`'s **three** sub-states — `flipPrOpenedAt` set → `fm-route --flag-on
--confirm-live` (the flip artifact is prepared and PR2 handed over; re-running plain `--flag-on`
would prepare a second flip over an in-flight one),
else `routePrepared` set → `--flag-on`, else `--flag-off`:
analyzed→`fm-style-spec`, style-specced→`fm-plan`, planned→`fm-gen`, generated→`fm-verify`,
verified→`fm-e2e` (say to run `fm-cascade` first when the page injects markup it does not author,
and surface a `cascade` record with `unresolved > 0` — those rows block `fm-route --flag-on` until
fixed or recorded), e2e-passed→`fm-parity`, parity-passed→`fm-route --flag-off` / `--flag-on` /
`--flag-on --confirm-live` per the three sub-states above, `*-failed`→`fm-fix`, `done`→no command.
A `kind: "cluster"` target never routes: `cluster-ready`→**no command** (terminal — a cluster has no
flip), and a cluster at any pre-terminal status takes the same chain command as a page **except** it
can never reach `fm-route` (CLAUDE.md → Component Clusters). Print its readiness as the flip-precondition
it is for the pages in its `consumedBy`.

The mapping does not change for an exempted gate: `verified` → `fm-e2e` and `e2e-passed` →
`fm-parity` still hold, because the gate skill is what records the exemption. Say "records the
approved exemption; runs nothing" beside the command so the reader does not expect a Playwright run.

This skill is read-only — it never acquires the lock or mutates state.
