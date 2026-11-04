# fm-route: Flag-on gates

Part of the `fm-route` skill. `{pluginRoot}` is the plugin root the skill states.

### Step 1a: Gate-evidence freshness (flag-on and --confirm-live) — see {pluginRoot}/CLAUDE.md → "Gate Result Accounting"
A gate PASS proves nothing about code that changed after it. For each gate with a
`gateEvidence.{gate}.tree` in `tracker.json`, **re-compute that hash now** and compare. Resolve the
page's **watch paths** from three recorded sources — never by guessing which files belong to the page:

1. **The page's own source** — `tracker.json` `apps[app].pages[page].sourcePaths[]`, the repo-relative
   files `fm-gen` recorded as generated (see `fm-gen` Step 5), minus any untracked entry
   `git check-ignore -q` accepts ({pluginRoot}/CLAUDE.md F — the script refuses an ignored watch path, and every
   producer drops the same entries).
2. **Its shared-package dependencies** — `migration-plan.json` `sharedDeps[]`. Entries are
   `@omh/<package>:<symbol>` (e.g. `@omh/shared-data:useBookingDetail`), so map each to the package
   **directory** `{packagesDir}/<package>` and drop the symbol — the symbol is not a path. A
   `packages/shared-*` change outdates the evidence of every page that imports it, and the gate is
   per-page so nothing else catches it.
3. **The page's `migration-plan.json` itself** — `docs/migration/{app}/{page}/migration-plan.json`.
   It decides `flagPlan.guardsPath` (the production path this flip activates), `gateAcceptance` (the
   criteria the executors enforced verbatim), `requiredGates` and `e2eScenarios`. Edited after the
   gates passed, it changes what ships without touching a single file in axes 1 or 2 — so a plan
   swapped from `/tested` to `/untested` would flip a path no report ever evaluated. **The three gate
   skills hash all three axes; hashing fewer here can never match, and Step 1a is a hard gate with no
   acknowledgement path — the flip would be unreachable for every page, permanently.** One per-gate
   carve-out, {pluginRoot}/CLAUDE.md F: for `verify`, drop every axis-1 entry under `{appDir}/e2e/` — `fm-verify`
   did — and hash all of it for `e2e` and `parity`.

**Where this runs.** HEAD is what this step treats as shipping, so run `--flag-on` on the checkout
of the **merged base branch** — PR1 landed and pulled. On an unmerged PR1 branch every check below
passes for code the base branch does not have, and PR2 would flip traffic to it. And, **from the
project root** (the shell's cwd persists across calls and the gate skills leave it at `{appDir}`, where
a `{monorepoRoot}` of `.` means the wrong directory), `git -C {monorepoRoot} rev-parse --show-cdup` must
exit 0 **and** print nothing (outside a repository it prints nothing and exits 128): a config from
before v1.3.0 nested below the git toplevel addresses evidence at paths the checks below cannot see
— refuse and send the user to `fm-init`.

**Evidence must be committed.** This page's record in `tracker.json` and its `docs/migration/{app}/{page}/`
must match HEAD — the stamps, manifests and reports the flip stands on are PR1's record, and a
working-tree copy proves nothing to a reviewer or to the next checkout:

```sh
REPO=$(git rev-parse --show-toplevel)
command -v jq >/dev/null || { echo "jq missing — compare the whole tracker.json instead"; exit 1; }
REC='.apps[$a].pages[$p]'
WT=$(jq -Sc --arg a "{app}" --arg p "{page}" "$REC" "$REPO/docs/migration/tracker.json") || exit 1
IX=$(git show :docs/migration/tracker.json    | jq -Sc --arg a "{app}" --arg p "{page}" "$REC"); [ -n "$IX" ] || exit 1
HD=$(git show HEAD:docs/migration/tracker.json | jq -Sc --arg a "{app}" --arg p "{page}" "$REC"); [ -n "$HD" ] || exit 1
[ "$WT" = "$IX" ] && [ "$IX" = "$HD" ] || echo "page record differs across working tree / index / HEAD"
git status --porcelain -uall --ignored -- ':(top)docs/migration/{app}/{page}' \
    ':(top,exclude)docs/migration/{app}/{page}/.lock' ':(top,exclude,glob)docs/migration/{app}/{page}/**/*.tmp' \
    ':(top,exclude,glob)docs/migration/{app}/{page}/*.next.json'
git -C "$REPO" --literal-pathspecs diff --cached --quiet -- <watch path>...   # all three axes, all of axis 1
```

All three must be silent (the last: exit 0). The record is read from three trees — working tree,
**index**, HEAD — because a staged record is what the next commit ships and neither the working
tree nor HEAD shows it; an unreadable tree is an `exit 1`, not an empty match. The record is
page-scoped on purpose — `tracker.json`
is shared, and another page's in-flight rows are not this flip's business; the `jq` guard is there
because an empty diff from a tool that did not run is not a pass — without `jq`, compare the whole
file (`git status --porcelain -- ':(top)docs/migration/tracker.json'`: stricter, may block on another
page's work). `-uall` defeats `status.showUntrackedFiles=no`; `--ignored` surfaces a report or manifest
a repository ignore rule keeps out of every commit (an ignored evidence file is `!!`, and a block);
`:(top)` resolves from the repo root whatever the cwd; the page lock, `*.tmp` and `*.next.json` are
transient, excluded here and gitignored by `fm-init`. The staged check exists because both recomputes
below hash the tree and the disk, never the index — a staged edit on a watched file is invisible to
them and is exactly what the next commit ships. Anything printed → **block**. Which way to clear it
only the operator knows: something this pipeline wrote since PR1 — a gate re-run's pair, a Step 1b
adjudication in `codex-audit.json`, an owner approval in `owner-decisions.md` — commit it; a drift
nobody meant (a revert, a stash, a hand merge) — restore this page's record from HEAD's
`tracker.json`, never commit it.

**Two recomputes per gate, one script, same flags.** Hash the union by **running the script** the
gate skills ran — never an inline pipeline — once against the committed tree and once against the
working tree:

```sh
{pluginRoot}/scripts/gate-tree-hash.sh --rev HEAD \
    --exclude docs/migration/{app}/{page}/gate-tree/{gate}.tsv -- <watch path>...   # what ships
{pluginRoot}/scripts/gate-tree-hash.sh \
    --exclude docs/migration/{app}/{page}/gate-tree/{gate}.tsv -- <watch path>...   # what is on disk
```

**Pass the same `--exclude` and `--` that gate passed.** The producer excluded its own manifest so
the evidence would not describe itself; a consumer omitting either flag hashes a different set, and
every comparison then fails as a permanent hard block on correct code.

Judge each gate on both hashes against its recorded `gateEvidence.{gate}.tree`:

- **Both equal** → fresh: what ships is what was gated, and nothing uncommitted rides into PR2.
- **Committed ≠, working tree =** → the working tree holds the gated content and HEAD does not.
  **Block**, and name the files — the `--rev HEAD --manifest` output diffed against the gated
  manifest. The hashes say which tree holds the gated bytes, not which is newer, and no timestamp
  decides that (squash and rebase rewrite dates): the operator does. Either the file was left out
  of PR1's commit (a file untracked when the gate ran included) — commit it, no re-run — or HEAD was
  changed on purpose after the gate and the working tree is a stale copy — discard it, and the gate
  is stale (below). A `dirty:` submodule record has no committed form at all: commit inside the
  submodule and re-run. The gates hash the working tree because they run before the code is
  committed; only this recompute can say the commit carried it (OMH-750 PR #330 shipped a manifest
  38 rows behind its stamp, and a component left out the same way passes every working-tree check).
- **Committed =, working tree ≠** → HEAD carries the gated content; the working tree has an
  uncommitted edit on the named files that would ride into PR2 (an IDE format, a stray save).
  **Block**; stash it — or discard it if it is yours: under `{packagesDir}` it may be another page's
  live `fm-extract`/`fm-fix` work — and re-check. Not a re-run, and never a commit.
- **Both ≠** → the page moved since the gate ran: **stale**, handled below. (A checkout that
  received PR1's evidence without its code lands here as well — the named files' history shows the
  commit this checkout lacks; merge it rather than re-run.)

**The gated manifest**, for naming files, is whichever copy hashes with `git hash-object
--no-filters` to the stamp — `git show HEAD:docs/migration/{app}/{page}/gate-tree/{gate}.tsv` or the
working-tree file (a re-stamp rewrites it; a checkout may hold an older one). If neither does, say
the aggregate moved and stop there rather than inventing a file list.

**This is a hard gate: a stale gate blocks the flip.** Name the stale gates **and the files that
moved** — re-run the script with `--manifest` and diff it against the gated manifest; the stored
`tree` is a single aggregate and a diff against it is not computable. If the manifest diff shows
entries the recompute no longer lists whose replacements exist under new names (a rename or
refactor outside the pipeline), **refresh `sourcePaths` first — under the
page lock** (acquire it for this write even though the flip is refused: a pre-lock tracker
mutation races any live same-page writer; take `.tracker.lock` for the write itself, then release
both): drop the deleted paths, add the replacements. When the saved manifest is **missing**, check
the recorded `sourcePaths` against the filesystem instead — entries that no longer exist mean a
rename nothing on disk can map; refresh the list from the files that actually exist (the fm-gen
phase reports, `git log --follow`) before any re-run. Re-running the chain over a stale list would
record fresh-looking evidence that watches only paths which no longer exist and none of their
replacements. Then send the user back to **`fm-verify`** — the chain head. Naming "those
gates" invites `fm-e2e`/`fm-parity`, which require exactly `verified`/`e2e-passed` and refuse the
`parity-passed` this step runs at; when only `e2e` or `parity` is stale the named set contains
nothing that accepts. `fm-verify` takes a gate-passed page (with its demotion warning) and the
chain re-runs in order. Do not offer an acknowledgement
path: this is the one irreversible step in the pipeline, and an acknowledgement is not a test.

**Why this is comparing content and not commits.** The first version of this rule compared
`gateEvidence.{gate}.commit` against `HEAD` with `git log`, and had to be soft because it fired on
every page by construction — the gates run on generated code *before* it is committed (`fm-gen` →
`fm-verify` → `fm-e2e` → `fm-parity` → `--flag-off` opens PR1, the code PR), so every record was
`+dirty`, and once PR1 merged its merge commit touched every path in `sourcePaths[]` by definition.
Neither condition could be cleared by re-running. Comparing **content** dissolves both: a merge
changes the commit graph, not the bytes, so an untouched page hashes identically and passes with no
prompt at all. The `--rev HEAD` recompute is that same comparison against the committed tree — a
merge that changed no bytes still matches, and it is what proves the commit carries the gated content. The hash moves only when the page's code or a shared package it imports actually
changed — which is the case the rule exists for, and the one that must block. (OMH-754 PR #184
shipped a `visual: PASS` standing on a screenshot 21 commits stale; under this rule it does not
reach the flip.)

Two carve-outs, both honest-state rather than retro-judgment, and both **acknowledge-and-proceed**
because there is nothing to compare against:
- A gate whose `gateEvidence` is absent, or whose record has no `tree` (written before these fields
  existed), is **`unverifiable`** — surfaced for explicit acknowledgement, not blocked. No
  retro-adjudication, the same principle as `{pluginRoot}/templates/capture-provenance.md`.
- A page with no `sourcePaths` (generated before that field existed) is `unverifiable` on axis 1;
  still hash axes 2 and 3, which need only the plan (axis 3 is the plan). Report which axis was covered rather than a bare
  "fresh" — a freshness claim covering some of the three axes is a scope statement, and {pluginRoot}/CLAUDE.md → Design
  Principles makes evidence-scope statements claims in their own right.
- A recompute that prints **`unverifiable`** (exit 2) is not a *mismatch*, but what it means depends
  on whether there was evidence to begin with:
  - **No `tree` recorded** → `unverifiable`, acknowledge and proceed. Nothing was ever claimed.
  - **A `tree` IS recorded and the recompute now resolves nothing** → **block**. The gate hashed a
    non-empty file set; that set has since vanished from the working tree and the index, which is a
    change to the watched surface, not an absence of evidence — **unless the other recompute still
    equals the stamp**: from `--rev HEAD` alone it is the "committed ≠, working tree =" verdict
    (commit or merge); from the working tree alone while `--rev HEAD` matches it is "committed =,
    working tree ≠" (the files were removed locally — restore them from HEAD). Neither is a
    re-run. The usual cause is a refactor that
    renamed every `sourcePaths[]` entry — and since the replacements are not in `sourcePaths[]`,
    they are not watched at all. Send the user to **`fm-verify`** and let the chain re-run in order —
    same reason as above; `fm-e2e`/`fm-parity` refuse `parity-passed` (which re-records `sourcePaths`
    via `fm-gen`/`fm-delta`). Treating this as acknowledge-and-proceed would wave through the one
    case where the evidence is provably stale.
  Never compare the literal token against the stored hash and read the inequality as "stale" — the
  distinction above is the judgement, not string inequality.
- Likewise a recompute that **fails** (exit 1 — an unhashable or unreadable watch-path file) is not
  a mismatch and not a pass: report the script's message and stop. A gate cannot be judged on
  evidence that could not be computed.

**Cascade divergences (`fm-cascade`).** If `cascade-diff.json` exists, every divergence it classified
`real` must be either fixed (absent from the latest run) or **owner-approved** in
`owner-decisions.md`: an entry with `status: approved`, `by`, and `when`. Unresolved rows, and rows
whose entry is `pending` or incomplete, **block** — surfaced individually with `tag · property ·
legacy → target · node count`, the same handling as unresolved Codex `high` findings. An approved
divergence proceeds without further ceremony: deciding it is intended is the owner's call, and the
**approval** — not the item fm-cascade wrote — is that call.

Before judging the file, compare it with the tracker: a `cascade` record with `notRun: true` and a
`runAt` **newer** than the file's own `runAt` means the latest attempt failed and the file is an
older run's history — report the stage `not-run` (the file does not vouch for the current tree),
but still enforce its unapproved `real` rows: blocking evidence does not expire.

Absence of `cascade-diff.json` is **not** a block and not a pass — it is `not-run`, reported as such.
Do not infer it was unnecessary. But if the page injects markup it does not author (CMS rich text,
i18n values containing HTML, editor output) and `fm-parity`'s visual gate is anything other than
`pass`, say plainly in the report that **no stage has checked the cascade for the majority of this
page's DOM** — the combination is the exact hole `fm-cascade` was built for, and it is invisible in a
gate table that shows `fm-verify: pass`.

A `<sha>+dirty` value in `commit` is normal and means nothing here — `commit` is the audit trail and
freshness is decided entirely by `tree`. Never pass a `+dirty` string to `git`.

**Answer-key freshness (hard gate; {pluginRoot}/CLAUDE.md → "Gate Result Accounting" G).** The recompute above
covers the **v2** side. The gate also compared against a **legacy answer key**, and a master merge
that changed legacy source rots it silently — the v2 hash still matches. So if the page records
`answerKeyEvidence.parity.legacyTree`, recompute it now with the **same** `gate-tree-hash.sh` over the
recorded `answerKeyEvidence.parity.legacyPaths` (the producer stored the list so this recompute uses
the identical set — `fm-parity` Step 4), and compare against the stored `legacyTree`:
- **Equal** → the answer key is fresh.
- **Different** → **answer-key-stale: block.** A cited legacy file moved since parity ran, so the
  passing comparison stood on a legacy truth that has since changed. Name the moved files (a
  `--manifest` diff over `legacyPaths`) and send the user to **`fm-delta`** (legacy drifted under the
  page — the skill that re-migrates the changed surface) or, if the drift is only the answer key,
  re-run the gate chain from **`fm-verify`**. Do not offer an acknowledgement path — a stale answer key
  is a provably-changed premise, the same standing as a stale v2 gate.
- **No `answerKeyEvidence` recorded** (a page parity-passed before the producer landed, or under a
  parity exemption) →
  `unverifiable` on this axis: acknowledge and proceed, never block, no retro-fill — the same
  grandfathering as an absent `gateEvidence.tree`.
Re-check this under the lock in Step 2, exactly as the v2-side hashes are — a concurrent merge can move
a cited legacy file between this read and the write.

### Step 1b: Codex audit acknowledgement (flag-on only; soft gate) — see {pluginRoot}/CLAUDE.md → "Codex Independent Audit"
Read `docs/migration/{app}/{page}/codex-audit.json`. Collect **unresolved high-severity** findings
across all stages — **`unresolved` = a finding whose `adjudication` block is absent, or whose
`adjudication.state` is `open`** (`closed`/`rejected` are resolved). See `{pluginRoot}/templates/codex-audit.md`.
Read `e2e-report.json` too: list every scenario at `result: "not-run"` with its `reason`. On a
report written under the current rule there should be none — a `not-run` scenario makes the gate's
top-level `result` `not-run` and `fm-e2e` leaves the page at `verified`, so it never reaches this
skill. Any that appear come from a report predating that rule, and they are a **hard block, not an
acknowledgement**: the staging-gateway case makes the unmeasured scenario the *transactional* flow,
which is exactly the one that must not ship untested. Send the user back to **`fm-verify`** — not
`fm-e2e`, which requires the page at exactly `verified` and refuses the `parity-passed` this step
runs at. `fm-verify` accepts a gate-passed page (with its demotion warning) and the chain then
re-runs `fm-e2e` → `fm-parity` in order.

**Gate exemptions.** List every gate that reached this page, or a cluster it consumes, as
`not-applicable`, with its `reason`,
`compensatingEvidence` if any, `approvedBy` and `approvedAt`. They join the acknowledgement below:
the flip rests on a gate that did not run, and the person flipping has to say they know it.

Also read each stage's `{stage}.priorAdjudicated[]` (stages are top-level keys in
`codex-audit.json`; there is no `stages` wrapper) — adjudicated findings a re-audit could not match to a
current one — and present any `high` entries alongside, labelled **`unmatched`**. They are neither
open nor confirmed resolved: the code moved and identity could not be asserted. Show them rather than
resolving them either way; this gate is already a human acknowledgement, so the judgement belongs
here and not in the auditor.
If any exist — or any gate exemption above — present them and **require the user's explicit acknowledgement**
before continuing — this is a soft gate, not an auto-block: Codex is advisory, so a human may
acknowledge and proceed, or send the page back through the gates — **not `fm-fix`**, which accepts
only `*-failed`/`fixing`/`escalated` and refuses the `parity-passed` this step runs at. To act on a
finding rather than acknowledge it, re-run `fm-verify` (it accepts a gate-passed page and demotes
with a warning), which puts the page back on the chain a fixer can reach. If `codexAudit` is disabled or Codex is
unavailable, skip only the Codex findings; the gate exemptions still need the acknowledgement.

### Step 1c: Cutover-ledger preconditions (flag-on only; hard gate) — see `{pluginRoot}/templates/cutover-ledger.md`
Read `docs/migration/cutover-ledger.json` (absent → no ledger entries, not a block). Collect this
page's entries with `blocksCutover: true`. Any at `status: "open"` **block the flip** — surfaced
individually with `item · owner · ticket · evidence`, the same handling as an unresolved Codex `high`
or an unapproved cascade `real` row. An `approved` entry (carrying `by` + `resolvedAt`) proceeds — the
owner's call, not this skill's; a `resolved` entry proceeds. There is no acknowledgement path for an
`open` blocker here: an owner records `approved` in the ledger (with `by`/`when`), or the work lands
and the entry moves to `resolved`. This is what stops a page flipping while a named flip-precondition
("internal-link conversion complete for this path", "style gate must run on the real route") is still
open with no owner — the recurring "deferral set is recorded nowhere the cutover can read it" gap.
Then repeat Step 4a's consumed-cluster test: a consumed cluster that is not ready blocks the flip like
an `open` entry — even when its ledger entry reads `resolved` or is absent, because its status and its
exemptions can change after the code PR — unless an owner has `approved` that entry. The way out is
the cluster's chain from `fm-verify`, or that approval.

### Step 1d: Route resolution and navigation targets (flag-on only; hard gate) — see `{pluginRoot}/templates/angular-to-react-mapping.md` → routing
The edge is about to send this page's paths to v2, so check that v2 can serve every one of them and
that the page navigates correctly from the state the flip creates. Read the app's route config
(`routes.ts`), the routing artifact entries for `flagPlan.guardsPath`, and the page's
`analysis.json` `navigationSurface[]`:
- **Every path the edge entry sends to v2 resolves to a v2 route** — each locale-prefixed variant,
  the locale-less legacy entry (served by a redirect route), and every legacy child path the pattern
  covers (a wildcard hands the whole subtree over). A path with no v2 route is a broken entry point
  after the flip (PR #236 B2: the main mobile `/hotel` entry). Where the project serves loader
  data from sibling paths (`.data`), each loader route's sibling is covered too.
- **Every redirect keeps the query string** (`utm_*`, `gclid`) unless legacy strips it.
- **Every client navigation (`<Link>`, `navigate()`) in the page's code targets a v2-served route** —
  flipped, or in this same flip or cutover batch. A client navigation into a path legacy still serves
  lands on the error boundary; it must be a document navigation to the bare legacy path instead.
- **Inbound producers**: the `navigationSurface[]` inbound entries are updated to the mechanism the
  flip calls for, or recorded as a ledger precondition with an owner.
- **URLs other systems hold** — for a page whose `analysis.json` `gateTriggers[]` carries `payment`,
  check what `{pluginRoot}/templates/payment-flow-v2.md` → URLs other systems hold names:
  - `/hotel/payment`, `/payment-complete` and `/booking-complete` are each one unprefixed route with no
    locale-redirect twin;
  - if the legacy path was excluded in the app's AASA, every URL shape v2 serves for the page is
    excluded too;
  - the funnel's flip unit holds: the terminals flip together, and not before `/hotel/payment`.
  oh-api's return-host allow-list is the one item this repository cannot show. Name it in the PR
  body's Migration notes instead of reporting it verified.

Any unresolved path or wrong mechanism **blocks** the flip and is named with the file and target.
An analysis with no `navigationSurface[]` (written before it existed) is `unverifiable` on the last
two checks — say so; the route-resolution checks still run from the route config and the artifact.
