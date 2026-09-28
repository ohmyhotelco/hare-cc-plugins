---
name: fm-route
description: "Use to manage the Strangler Fig route flip for a migrated page at the app's configured edge layer (nginx, CloudFront, or a project flip script spanning several artifacts) — --flag-off prepares the routing artifact + flag (default OFF) for the code PR, --flag-on flips the path to the new app once verify/e2e/parity all pass."
argument-hint: "<page> --flag-off | --flag-on [--confirm-live] | --revert | --cutover [--confirm-live] [--base <branch>] [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Route Flip (Strangler Fig)

Manages the per-path 2-PR feature-flag flip at the app's configured edge layer. The flag stays OFF
until `fm-verify`, `fm-e2e`, and `fm-parity` all pass. The flip *semantics* are identical across
mechanisms — only the **edited artifact** differs (nginx config, CloudFront behavior manifest, or
the set of artifacts a project flip script edits together).
All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config & plan
Read config (absent → run `fm-init`; stop). Resolve `app` (`--app`/`currentApp`), its `domain`,
`port`, `legacyPort`, `appDir`, `legacyDir` (Step 4b hands both to the Codex auditor),
`monorepoRoot`, `packagesDir` (Step 1a maps `sharedDeps[]` through it), **`pluginRoot`** (absolute, per-machine — read from `.claude/frontend-migration-plugin.local.json`, never the shared config; where `scripts/gate-tree-hash.sh` lives). **Absent → the freshness
check cannot run at all**, so decide by what is recorded: if any gate has a `gateEvidence.{gate}.tree`,
**block** — there is evidence that cannot be checked, which is not the same as no evidence; if no
gate has one, treat it as `unverifiable` and acknowledge. Never improvise an inline pipeline. `workingLanguage`, and its **`flipMechanism`** (`apps.{app}.flipMechanism`;
**absent → `nginx`** for backward compatibility). Then resolve the mechanism-specific artifact:
- `nginx` → `infraDir` (default `infra/nginx`).
- `cloudfront` → `cloudfrontDir` (default `infra/cloudfront`) + `manifest` (default `v2-routes.json`).
- `script` → `flipArtifacts` (non-empty list of repo-relative files) + `flipCommands` (`flag-on` and
  `revert` required; `flag-off` and `status` optional). Either missing, or a listed artifact that does
  not exist → stop here and name the key: this app's flip spans several files, and guessing one of
  them is the failure this mechanism exists to prevent (`templates/strangler-fig.md` →
  "Project-script pattern").
- Any other value → stop and name it. Never fall back to `nginx` or `cloudfront` for a value you do
  not recognise — a mechanism that resolves to the wrong artifact looks like a working flip.

**Confirm `apps[app]` before using it** (CLAUDE.md → Configuration): the app entry must exist and carry the keys this stage reads. Config-file presence is not app presence — `mobile`/`hana` are scaffolded, and a `--app` naming an unconfigured one must stop here with a clear message rather than fail deep inside an agent on an unresolved path.

Read the page's `migration-plan.json` → `flagPlan` (`key`, `guardsPath` — the same path is the
nginx `location` *and* the CloudFront path-pattern). Determine `action` from the flags — the per-page
actions `--flag-off` | `--flag-on` | `--flag-on --confirm-live` | `--revert`, **plus the batch action
`--cutover` | `--cutover --confirm-live`** (the big-bang cutover of all ready pages together — no
`<page>` argument; see "Batch cutover" below). A `--cutover` run resolves its own batch set and does
not read a single page's `flagPlan` here.
`--confirm-live` is a **distinct action**, not a modifier on `flag-on`: it edits no artifact, runs no
agent, and only records the human's observation that the merged flip is live (Step 3 is skipped for
it). Treating it as `flag-on` would re-activate the routing rule and re-run the Step 1a/1b
acknowledgements the operator already gave. **Step 1a deliberately does not run here.** It is a
hard gate with no acknowledgement path, and at `parity-passed` + `flipPrOpenedAt` no gate can
re-run to clear it (`fm-verify` refuses while the timestamp stands; `fm-e2e`/`fm-parity`
require earlier statuses) — so applying it here would make `flipped` unreachable and leave
`--revert` of an already-deployed flip as the only move. Another page rewriting a shared file
during the merge window can leave this page's evidence stale; `fm-progress` reports that, and
it is not blocked here because the flip is already live and nothing this command does changes
the edge.

### Step 0a: Action preconditions (per-page actions)
**For `--cutover`, skip this step** — its preconditions are batch-level and live in "Batch cutover"
below. Steps 0a–4c describe the four per-page actions; a `--cutover` run jumps to that section after
Step 0's config.

**Refuse a cluster first.** If the target's `kind` in `tracker.json` is `cluster`, stop before any
per-page action: a cluster owns no route, so there is nothing to flip — it reaches `cluster-ready`, not
`flipped` (CLAUDE.md → Component Clusters). Point the user at the cluster's own gate chain (`fm-verify`
/ `fm-parity` → `cluster-ready`); its readiness becomes a flip-precondition on the *consuming* page's
`--flag-off`, below, not a flip of its own.

Every per-page action writes or clears route state, so every one needs an entry condition. Read
`tracker.json` first and refuse before touching anything:

| action | requires | on refusal |
| --- | --- | --- |
| `--flag-off` | `status = parity-passed`, **no** `flipPrOpenedAt`, and Step 1's gate guard | gates not all passed (name the stage), or a flip is already in flight — `--revert` it first |
| `--flag-on` | Steps 1, 1-pre, 1a, 1b, 1c, 1d below, and **no** `flipPrOpenedAt` | as each step states; a present `flipPrOpenedAt` means a flip is already in flight — use `--confirm-live` or `--revert`, never a second `--flag-on` |
| `--flag-on --confirm-live` | `status = parity-passed` **and** `flipPrOpenedAt` present | no flip is in flight — run `--flag-on` first |
| `--revert` | `status = flipped`, **or** `flipPrOpenedAt` set at any status **except `done`**, **or** `status = parity-passed` with `routePrepared` set | there is nothing in rotation or in flight to roll back — and on `done` there is nothing to roll back *to*: name manual intervention, never a command |

**`flipPrOpenedAt` admits `--revert` at any status but `done`** because every other rule in this plugin
points at `--revert` as the way out of an in-flight flip, and a page can hold the timestamp at a
status below `parity-passed`: `fm-extract` demotes a dependent to `generated` and a `--flag-on`
running concurrently then records the timestamp. Requiring `parity-passed` there left the only
prescribed exit refusing the state it was prescribed for.

**`--revert` never promotes a page.** From `flipped` it returns the page to `parity-passed` — the
state it was in before the flip, and one it genuinely earned. From `parity-passed` it **keeps the
current status** and only clears the route fields, undoing a `--flag-off` or a prepared-but-not-live
flip (whether or not PR2 was actually opened — see the field's definition in CLAUDE.md).

**Tell the operator the rollback is not finished.** `--revert` edits the in-repo artifact; the
edge returns to legacy when the rollback PR is merged and propagated — the soft rollback this
plugin targets at 5–10 minutes (`templates/strangler-fig.md`). Step 4's clearing of `flippedAt`
records that rollback, and `templates/capture-provenance.md` reads it that way, so the report must
say plainly that the operator has to complete it, and must not start a fresh
`--flag-off`/`--flag-on` cycle before it propagates or the two PRs race at the edge.
It must never write `parity-passed` over any other status: `parity-passed` is a gate-passed state,
and "only the gate issues its own passed state" (CLAUDE.md → Per-page State Machine) binds this
skill exactly as it binds `fm-fix`. Without this guard, `--revert` on a `generated` page (say, one
`fm-delta` had just reset) would promote it, and since `--flag-off` merely re-arms `routePrepared`,
the next `--flag-on` would find every precondition satisfied and flip code no gate has seen.

### Step 0b: Branch freshness (PR-preparing actions: `--flag-off`, `--flag-on`)
Both PRs are graded against **flag-ON at merge** (the big-bang cutover model —
`templates/pr-body.md` → Grading standard), so a branch behind its base ships and is graded on a tree
it was never validated against. This is the recurring merge-sync finding (OMH-936 PR #294 "BEHIND by
43", OMH-938 PR #302) — catch it before the PR is prepared, not in review.

Resolve the base branch — **the branch this PR will target**, not the repo's default. First match wins:
1. `--base <branch>`;
2. config `defaultBaseBranch`;
3. `git -C {monorepoRoot} symbolic-ref --quiet --short refs/remotes/origin/HEAD` (strip the `origin/`);
4. `main`, else `master`.

The repo default is only a fallback because a repo that ships through several long-lived branches
targets them from different PRs. In the consuming monorepo `origin/HEAD` is `master`, while 127 of its
v2 PRs target `develop` and 27 target `staging` (the `-develop` / `-staging` branch copies). Checking
freshness against `master` passes a branch that is behind `develop`, and blocks one that is only
missing master-only commits. **When the branch will target anything but the repo default, pass
`--base`.** Say which base was used, and how it was resolved, in the PR body's Rebase-confirmation
field.

Then, from the repo root, count what the base has that HEAD lacks:

```sh
BASE=<resolved base ref, e.g. origin/main>
git -C {monorepoRoot} rev-list --count HEAD.."$BASE" 2>/dev/null   # commits on base not on HEAD
```

- **> 0 → block.** The branch is behind its base. Tell the operator to **rebase** onto the base
  (`templates/pr-body.md` → Branch: synced by rebase, never by merging the base in), then
  **re-measure every gate stamp at the new HEAD** (Step 1a's freshness recompute, and the answer-key
  freshness of P0-A) before re-running this action — a stamp carried across a sync is the
  stale-on-merge defect (`templates/pr-body.md` → Rules). Refuse; do not prepare the PR.
  **Sync, re-stamp, then ask for review — in one push.** On a repo that dismisses stale approvals on
  push, any sync after approval costs a re-approval. So rebase and re-stamp before requesting review,
  never as a separate last commit after approval (OMH-936 #354: re-stamping as the last commit before
  merge dismissed the approval it was meant to satisfy). A rebase rewrites SHAs: re-point every SHA the
  records cite to its rebased twin (`git range-diff`) in that same push.
  Also count merge commits (`git rev-list --merges --count "$BASE"..HEAD`): a branch synced by merging
  the base in is reported, not blocked, so the operator can rebase before review.
- **0 → proceed**, and record in the PR body's Rebase-confirmation field that the branch is current at
  this HEAD.
- **Base unresolvable, or the count command errors** (no `origin/HEAD`, offline mirror, detached
  HEAD) → do **not** block on a check that could not run: skip the mechanical test, and emit the
  Rebase-confirmation field as `TODO(owner): confirm rebased onto base + re-measure stamps` so the gap
  is visible in the PR rather than silently passed. This is a local, no-network check; the forge's own
  BEHIND status is authoritative, and the PR-body attestation is where the human confirms it.

### Step 1: Gate guard (flag-on only)
For `--flag-on`, read `tracker.json` and `docs/migration/{app}/{page}/e2e-report.json` +
`parity-report.json`. Require the page `status` to be `parity-passed` (the monotonic chain
guarantees `verified` and `e2e-passed` were reached first — the single `status` field has since been
overwritten to `parity-passed`), `verifiedAt` present (verify's durable trace — verify has no report
file), and both reports show `result: pass` — or `result: "not-applicable"` for a gate whose
`notApplicable` entry in the page's tracker record is **still present with `approvedBy` and
`approvedAt`, and whose `grantedTree` equals `gateEvidence.{gate}.tree`** (CLAUDE.md → Gate Result
Accounting H). An exempted pass with no recorded `tree` cannot be bound to code: say so, and block
it like a missing entry. A `not-applicable` report with no such entry
blocks: the exemption was withdrawn or never granted, and the gate must run — send the user to
`fm-verify`, the chain head. If any is not satisfied, stop and report the blocking gate — do not
flip.

These three are the *durable* traces, and `fm-gen`/`fm-delta` clear `verifiedAt`/`e2ePassedAt`/
`parityPassedAt` alongside `gateEvidence` for exactly that reason: without it a regenerated page
would keep the fields this step reads while losing only the advisory one.

### Step 1-pre: Require the code PR first (flag-on only)
`--flag-on` is the second PR of a mandatory two-PR flow (`templates/strangler-fig.md`), so refuse it
unless `tracker.json` records `routePrepared: true` from a prior `--flag-off`. Without this the flip
can be raised on a page whose code PR was never prepared, skipping the route-stage Codex audit that
runs in `--flag-off` Step 4b. Point the user at `--flag-off` first.

### Step 1a: Gate-evidence freshness (flag-on only) — see CLAUDE.md → "Gate Result Accounting"
A gate PASS proves nothing about code that changed after it. For each gate with a
`gateEvidence.{gate}.tree` in `tracker.json`, **re-compute that hash now** and compare. Resolve the
page's **watch paths** from three recorded sources — never by guessing which files belong to the page:

1. **The page's own source** — `tracker.json` `apps[app].pages[page].sourcePaths[]`, the repo-relative
   files `fm-gen` recorded as generated (see `fm-gen` Step 5), minus any untracked entry
   `git check-ignore -q` accepts (CLAUDE.md F — the script refuses an ignored watch path, and every
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
   carve-out, CLAUDE.md F: for `verify`, drop every axis-1 entry under `{appDir}/e2e/` — `fm-verify`
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
  retro-adjudication, the same principle as `templates/capture-provenance.md`.
- A page with no `sourcePaths` (generated before that field existed) is `unverifiable` on axis 1;
  still hash axes 2 and 3, which need only the plan (axis 3 is the plan). Report which axis was covered rather than a bare
  "fresh" — a freshness claim covering some of the three axes is a scope statement, and CLAUDE.md → Design
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

**Answer-key freshness (hard gate; CLAUDE.md → "Gate Result Accounting" G).** The recompute above
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

### Step 1b: Codex audit acknowledgement (flag-on only; soft gate) — see CLAUDE.md → "Codex Independent Audit"
Read `docs/migration/{app}/{page}/codex-audit.json`. Collect **unresolved high-severity** findings
across all stages — **`unresolved` = a finding whose `adjudication` block is absent, or whose
`adjudication.state` is `open`** (`closed`/`rejected` are resolved). See `templates/codex-audit.md`.
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

### Step 1c: Cutover-ledger preconditions (flag-on only; hard gate) — see `templates/cutover-ledger.md`
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

### Step 1d: Route resolution and navigation targets (flag-on only; hard gate) — see `templates/angular-to-react-mapping.md` → routing
The edge is about to send this page's paths to v2, so check that v2 can serve every one of them and
that the page navigates correctly from the state the flip creates. Read the app's route config
(`routes.ts`), the routing artifact entries for `flagPlan.guardsPath`, and the page's
`analysis.json` `navigationSurface[]`:
- **Every path the edge entry sends to v2 resolves to a v2 route** — each locale-prefixed variant,
  the locale-less legacy entry (served by a redirect route), and every legacy child path the pattern
  covers (a wildcard hands the whole subtree over). A path with no v2 route is a broken entry point
  after the flip (PR #236 B2: the main mobile `/hotel` entry). Where the project serves loader
  data from sibling paths (`.data`), each loader route's sibling is covered too (OMH-934 #317).
- **Every redirect keeps the query string** (`utm_*`, `gclid`) unless legacy strips it (OMH-840 #337).
- **Every client navigation (`<Link>`, `navigate()`) in the page's code targets a v2-served route** —
  flipped, or in this same flip or cutover batch. A client navigation into a path legacy still serves
  lands on the error boundary; it must be a document navigation to the bare legacy path instead.
- **Inbound producers**: the `navigationSurface[]` inbound entries are updated to the mechanism the
  flip calls for, or recorded as a ledger precondition with an owner.
- **URLs other systems hold** — for a page whose `analysis.json` `gateTriggers[]` carries `payment`,
  check what `templates/payment-flow-v2.md` → URLs other systems hold names:
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

### Step 2: Lock
**The checks above read `tracker.json` without holding it.** That is deliberate — Steps 1a/1b
prompt a human — but it means the state can move
between the check and the write. **Re-verify, once the lock is held, exactly the checks this action ran**: Step 0a's precondition
for every action, and — for plain `--flag-on` only — Step 1's gate guard (including that each
exemption it accepted is still approved), Step 1-pre's
`routePrepared`, Step 1a's hashes (v2-side **and** answer-key freshness), Step 1b's Codex-finding adjudication state (a concurrent audit
can publish a new `high` between the unlocked check and this lock), Step 1c's cutover-ledger
preconditions (a concurrent `fm-route --flag-off` or an owner edit can add or reopen a
`blocksCutover` entry between the unlocked read and this lock), Step 1d's route resolution (another
page's integration can rewrite `routes.ts` under `.app.lock` meanwhile), and the cascade-divergence
check (every `real` row in `cascade-diff.json` must be fixed or `status: approved` **with
`by`/`when`** in `owner-decisions.md` — `pending` or incomplete blocks, the same criteria as the
unlocked check — because a concurrent `fm-cascade` can publish new rows between the unlocked read
and this lock). A concurrent `fm-fix` or `fm-delta` can demote the page
while the operator is reading the Step 1b findings, and the whole point of those guards is that a
flip never proceeds from a status the page no longer has. **Do not re-run Step 1a for
`--confirm-live`** — it never ran it (Step 0, Step 1a's heading), and re-running it here reinstates
the dead end that revert removed: a hard gate with no acknowledgement path, in a state where no
gate can re-run to clear it.

**Any refusal here releases the lock first.** Step 4's release is on the success path and is not
reached here (Step 3's orchestrator-refusal release is the other one) — stopping without releasing strands the page under a holder that has ended
and refuses every recovery the refusal itself prescribes.
Acquire `docs/migration/{app}/{page}/.lock` (stale only when its holder is gone — CLAUDE.md → Lock file).

### Step 3: Orchestrate — skipped for `--flag-on --confirm-live`
`--confirm-live` mutates no artifact: the routing rule was already activated by the `--flag-on` run
whose PR the operator has just watched merge and deploy. Re-running the orchestrator would re-apply
an edit that is already live and, on `cloudfront`, rewrite a manifest entry the deployment owner has
applied. Go straight to Step 4 and record only the tracker transition.

For the other three actions, launch `strangler-orchestrator` (Agent) with only its params: `app`, `page`, `action`,
`flagPlan`, `domain`, `port`, `legacyPort`, **`flipMechanism`** and its artifact target
(`infraDir` for `nginx`; `cloudfrontDir` + `manifest` for `cloudfront`; `flipArtifacts` +
`flipCommands` for `script`), **the page's current
`status`** (not a literal `parity-passed` — `--revert` is admitted at any status carrying
`flipPrOpenedAt`, Step 0a) **plus `routePrepared` and `flipPrOpenedAt`**, `verifiedAt`, the
`e2e-report.json` / `parity-report.json` paths, `notApplicable` (the page's approved gate
exemptions — Step 1 has already refused on any other; `[]` when none), `workingLanguage`. The agent's `--revert`
precondition tests the two route fields; naming only the flip-path gate state would hand it a
status the page does not have and none of the fields it must check.

**If the agent refuses, release the page lock before returning** (CLAUDE.md → Lock file): Step 4's
release is on the success path. The agent picks the
strategy from `flipMechanism`; the gate precondition is identical for all three.

### Step 4: Record

**Tracker lock.** Take `docs/migration/.tracker.lock` around every `tracker.json` write below —
after the lock this step already holds, released right after the write (CLAUDE.md → Lock file). Write it per CLAUDE.md → Serialization.

Update `tracker.json` (Read-Modify-Write):
- `--flag-off` → keep current status; record `routePrepared: true`, `flagKey` (= `flagPlan.key`).
  On `script` with no `flag-off` command nothing was edited: `routePrepared` then records that the
  code PR was prepared, and the hand-authored inactive entries are that PR's content. The project's
  `flag-on` command must refuse a page they are missing from (`templates/strangler-fig.md`).
  Step 4c stages the evidence, after the route audit has written its part.
- `--flag-on` (succeeded) → record `flipPrOpenedAt`; **do not set `flipped` yet.** This skill edits
  the in-repo routing artifact for PR2; **opening the PR is the user's step**, exactly as it is for
  the code PR on `--flag-off`. Say so in the report, and read the field accordingly: `flipPrOpenedAt`
  records *when the flip artifact was prepared and handed over*, which is the last moment this
  plugin can observe. It is not proof that a PR exists on the forge, and nothing may treat it as
  such — `--flag-on --confirm-live` still requires a human who watched the merge and the deploy.
  `strangler-orchestrator` never deploys, reloads nginx, or applies a
  CloudFront distribution. Between opening PR2 and the change actually propagating there is a review,
  a merge, a deploy, and cache propagation, and through all of it the edge is still serving legacy.
  Writing `flipped` there would break the invariant that the tracker and the edge agree, and
  provenance resolves a capture's `side` from exactly that status — so a capture from the production
  host would be labelled `v2` while the host still serves legacy: the wrong-side baseline inverted.
- `--flag-on --confirm-live` (run by the operator **after** PR2 is merged and the change is deployed
  and propagated) → `apps[app].pages[page].status = "flipped"`, `flippedAt`, clear `flipPrOpenedAt`.
  This is the only transition that claims the edge is serving v2, and only a human can observe that.
- `--revert` → **clear `flippedAt`, `routePrepared`, `flagKey`, and `flipPrOpenedAt`**, record `revertedAt`, and
  set the status per Step 0a: from `flipped` → back to `parity-passed`; from any other admitted
  status → leave it unchanged. This skill never issues a gate-passed state.
  Clearing `routePrepared` matters as much as `flippedAt`: the SessionStart hook
  splits `parity-passed` on it and would otherwise tell the operator to run `--flag-on` — re-flipping
  the page they just rolled back. On `cloudfront` the entries stay in the manifest at `active: false`
  after a revert of a flipped or in-flight page (`strangler-orchestrator`), but they describe a flip
  that was rolled back: another flip goes through a fresh `--flag-off`, which re-arms `routePrepared`
  over the kept entries. Clearing `flippedAt` matters too: `templates/capture-provenance.md` resolves `apps[app].domain` to `unresolved` whenever
  `flippedAt` is present without a `flipped` status, because that combination normally means the
  tracker and the edge have drifted. A completed revert is the one case where it does *not* — the
  edge really is serving legacy again — so leaving `flippedAt` behind would make the production host
  permanently unusable as legacy evidence for this page.
Release the lock.

### Step 4a: Project cutover-ledger entries (--flag-off only) — see `templates/cutover-ledger.md`
The code PR is where a page's deferrals become knowable to the cutover batch, so project them into
`docs/migration/cutover-ledger.json` now. Read the page's `migration-plan.json` `openApprovals[]`;
for every entry carrying `blocksFlip: true` (a coverage reduction that must close before the path
flips), plus any deferred gate item the plan or the gate reports record as a flip precondition, write
or update a ledger entry keyed on `app` + `page` + `item`: `kind: "flip-precondition"`,
`blocksCutover: true`, `owner`/`ticket`/`evidence`/`status` carried from the approval,
`sourceApproval` pointing back at the `openApprovals` topic. **Never invent an `owner`** — an approval
with `owner: "TBD"` projects an entry whose owner is `TBD`, which is itself the blocker to surface, not
a value to fill in. A plan with no `blocksFlip` approvals writes nothing.

**Also project not-yet-ready consumed clusters (CLAUDE.md → Component Clusters).** Scan `tracker.json`
for entries with `kind: "cluster"` whose `consumedBy` contains this page and that are **not ready**. A
cluster is ready when its status is `cluster-ready` **and** every gate its `gateEvidence` marks
`notApplicable` still has an approved entry whose `grantedTree` equals that gate's `tree` (Step 1's
exemption test). For each cluster that is not ready, write a ledger entry `kind: "flip-precondition"`, `blocksCutover: true`,
`item: "cluster <name> not yet cluster-ready"`, `owner`/`ticket` from the cluster's tracker record (or
`TODO(owner):` when it has none — an unowned unready cluster is the blocker to surface). A page must
not flip on a cluster that has not passed its own gates. A ready cluster writes
nothing (and a prior entry for it moves to `resolved`).

This is an app-wide file:
take `docs/migration/.app.lock` then `.tracker.lock` (in that order, under the page lock already held —
CLAUDE.md → State Files & Lock Convention), Read-Modify-Write merging on the key, release both.
Step 4c stages it with the rest of PR1's evidence.

### Step 4b: Codex audit (advisory; --flag-off only) — see CLAUDE.md → "Codex Independent Audit"
After preparing the code PR (`--flag-off`), if `codexAudit` is enabled and `route` is in
`codexAuditStages` (**absent → all seven**; the key narrows coverage, it never means "none" — and
this is the sign-off before the irreversible flip, so a silent skip here is the costliest of the
seven),
spawn `codex-auditor` (Agent) for the `route` stage (params: `app`, `page`, `stage="route"`,
`appDir`, `legacyDir`, the full PR diff + all gate reports + `codex-audit.json`,
`outPath = docs/migration/{app}/{page}/codex-audit.json`, `workingLanguage`) — Codex's final
independent sign-off of the whole page. Advisory; its high-severity findings are what the
`--flag-on` acknowledgement (Step 1b) will surface.

### Step 4c: Stage the evidence (every action)
Every action wrote `tracker.json` in Step 4, and the PR that action prepares carries it — PR1, the
PR2 (the flip unit), the rollback PR — or `flipPrOpenedAt` / `flipped` / `revertedAt` exist in one working
tree only and every other checkout re-arms the flip. Stage it. `--flag-off` additionally stages the
page's evidence, after Step 4b — the route audit is part of the record PR1 must carry:

```sh
REPO=$(git rev-parse --show-toplevel)
git add -- "$REPO/docs/migration/tracker.json"
# --flag-off only:
for l in .lock '.*.lock' '*.tmp' '*.next.json'; do   # the ignore file fm-init writes; older projects lack it
  grep -qxF -- "$l" "$REPO/docs/migration/.gitignore" 2>/dev/null || printf '\n%s\n' "$l" >> "$REPO/docs/migration/.gitignore"
done
git add -- "$REPO/docs/migration/.gitignore" "$REPO/docs/migration/{app}/{page}"
[ -f "$REPO/docs/migration/cutover-ledger.json" ] && git add -- "$REPO/docs/migration/cutover-ledger.json"   # Step 4a's projection (a bare `git add` on a missing path errors)
```

The ignore file (appended with a leading newline — a file that ends without one would glue the
rule onto its last line) is what keeps a live lock, a pre-run manifest or `fm-delta`'s proposed baseline out
of the directory add (an `:(exclude)` pathspec naming an ignored file makes `git add` exit 1 with
the ignored-path advice, so the ignore rule is the mechanism, not a pathspec), and it ships with PR1
so every later checkout has it. The gate skills staged the tracker as of their pass; this write
supersedes that index entry. Staging here leaves nothing for Step 1a's evidence check to find but a
later change.

### Step 5: Report
In `workingLanguage`: action, the `flipMechanism` and **every** artifact edited (the nginx routing
block in `infraDir`, the CloudFront behavior manifest `cloudfrontDir/<manifest>`, **or** each
`flipArtifacts` file the project's command changed, with the command and its `status` output), the
path/flag/app:port mapping, gate-guard result, and next step.

**Emit the PR title and body (`--flag-off`, `--flag-on`, `--cutover`).** A PR-preparing action ends by
printing a title and a complete body from `templates/pr-body.md` for the operator to paste — the code
PR on `--flag-off`, the flip PR on `--flag-on` / `--cutover`. The title is `<type>(<scope>): <subject>`
within 50 characters. Fill every required body field, in the template's order, from the artifacts
already read: Summary and Changed files from `migration-plan.json` + `sourcePaths[]` (every changed
file outside the page listed separately, with the pages whose watch set it touches); Test evidence
measured at this HEAD; Risk level by the team definitions and **equal to `tracker.json` `risk`** (or
say why not); Jira as `KEY: link`; the **Rebase confirmation** checkbox with today's date from Step
0b's verdict (or `TODO(owner): rebase + re-measure` when it could not be confirmed); **Rollback plan**
when Risk is High; **Migration notes on every flip PR** — it edits the edge artifact, so name the
entries changed, who applies them, propagation time, zero-downtime or not, and the `--revert` steps;
Gate evidence with each gate's freshness **recomputed at this HEAD**, never a stamp copied forward; and
Deferred items pointing at this page's `cutover-ledger.json` rows. A field the skill cannot fill is
emitted as `TODO(owner): …`, never as a plausible blank. The text is English (a committed artifact);
only the surrounding skill summary is in `workingLanguage`.

Next step:
- after `--flag-off`: open the **code PR** with the flip prepared but OFF — for `nginx` the routing
  block + flag entry (default OFF), for `cloudfront` the manifest entry mapping `guardsPath` to the
  v2 origin but **not yet active**, for `script` whatever the project's `flag-off` command prepared
  or, with none declared, the inactive entries authored by hand in every `flipArtifacts` file. When
  review passes, run `fm-route {page} --flag-on` for the flip PR (the page's whole flip unit).
- after `--flag-on`: the flip artifact is **prepared, not live** — and **opening PR2 is your step**,
  the same as the code PR on `--flag-off`. The path keeps serving legacy until that PR
  is merged and the change is deployed and propagated — this skill edits an in-repo artifact and
  never deploys. Once the operator has confirmed it is live, `fm-route {page} --flag-on
  --confirm-live` records `flipped`. Rollback = `fm-route {page} --revert`.
- for `cloudfront`, remind the user `fm-route` only edits the in-repo manifest for a PR they open — it
  **does not push to AWS**; applying the behavior change is the apply owner's step (`apps.{app}.applyOwner`, else `TODO(owner): name the apply owner`).
- for `script`, name every `flipArtifacts` file the PR must carry together — a PR that lands one
  tier without the other is a half-flip — and, after a `--flag-off` with no `flag-off` command, list
  the entries the code PR must author by hand. Applying them at the edge is the deployment owner's
  step, as for the other two.
- mark the page `done` by hand once the legacy page is deleted (CLAUDE.md → Per-page State Machine).

## Batch cutover (`--cutover`) — the big-bang flip of all ready pages

The confirmed cutover model flips **all ready pages together at merge**, not one page at a time
(CLAUDE.md → "Cutover Ledger & PR Body" → Cutover model). `--cutover` is that batch action. It reuses
the per-page code-PR preparation unchanged — every page still reaches `parity-passed` with
`routePrepared` via its own `--flag-off` — and replaces the per-page `--flag-on` with one gated batch
flip. It takes **no `<page>`**; it resolves its own set. Run it from the merged base checkout, the
same as `--flag-on` (Step 1a treats HEAD as what ships).

### C1: Resolve the batch set
The batch = every entry in `tracker.json` for the app (`--app`/`currentApp`) with `kind: "page"` (or
absent — **never `kind: "cluster"`**, which has no route), `status: "parity-passed"`, `routePrepared:
true`, and **no** `flipPrOpenedAt` (not already in flight). A cluster is never in the set; a page not
yet `parity-passed` is not ready and is listed as *excluded, not ready* — the operator decides whether
to wait or cut over without it, but the batch never silently drops a page it should have flipped.
Report the set and the excluded pages before doing anything.

### C2: Batch gate — all-or-nothing (hard)
Big-bang means the batch flips as a unit, so **one unready page blocks the whole batch** rather than
flipping the rest. Refuse the cutover unless **both** hold:
1. **Every page in the set passes its own flag-on preconditions** — run Steps 1, 1a (v2-side **and**
   answer-key freshness), 1b (Codex acknowledgement), 1c (that page's ledger entries) and 1d (route
   resolution and navigation targets — a navigation into another page of the same batch counts as
   v2-served) for each, exactly as a per-page `--flag-on` would. Any page that is stale,
   answer-key-stale, has an unacknowledged Codex `high`, an uncommitted evidence pair or an unresolved
   path blocks the batch; name it.
2. **The cutover ledger is clean for the whole batch** — `docs/migration/cutover-ledger.json` has
   **zero** `blocksCutover: true` entries at `status: "open"` for any page in the set (this is the
   ledger's whole purpose: the batch-level readiness view). An `approved` entry proceeds; an `open`
   one blocks and is surfaced with `item · owner · ticket`.

The batch gate is the aggregate of the per-page gates plus the ledger; it never weakens a per-page
check, and there is no acknowledgement path that clears an `open` blocker — an owner records `approved`
in the ledger or the work lands.

### C3: Activate and record
Only when C2 is fully green, activate every page's prepared artifact as **one batch flip PR**: for each
page run `strangler-orchestrator` with its `action: "flag-on"` and its `flagPlan` (nginx flag ON /
CloudFront behavior `active: true` / the project's `flag-on` command), editing the shared routing artifact **under `.app.lock`** (one
lock across the whole batch — the artifact is app-wide), and record `flipPrOpenedAt` on each page's
tracker row (each write under `.tracker.lock`, per-page `.lock` held while its row is written — lock
order page → `.app.lock` → `.tracker.lock`, CLAUDE.md → State Files & Lock Convention). No page moves
to `flipped` yet — opening the batch PR is the operator's step, exactly as PR2 is per page. Emit **one**
PR body from `templates/pr-body.md` covering the batch: the set, each page's gate evidence recomputed
at HEAD, and an empty Deferred-items section (an open item would have blocked C2).

### C4: `--cutover --confirm-live`
Run by the operator **after** the batch PR is merged, deployed, and propagated. It edits no artifact
and launches no agent — it records the human's observation. Set every page carrying a `flipPrOpenedAt`
from this cutover to `status: "flipped"`, `flippedAt`, and clear `flipPrOpenedAt`. This is the only
transition that claims the edge is serving v2, and only a human can observe it.

### C5: Rollback
There is no batch `--revert`: roll back per page with `fm-route <page> --revert` (nginx flag OFF /
the CloudFront entries back to `active: false` / the project's `revert` command), which returns a `flipped` page to `parity-passed`. Reverting the whole
batch is repeating that per page — deliberately explicit, so a rollback names each path it touches.
