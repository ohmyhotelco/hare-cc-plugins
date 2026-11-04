# fm-route: Action preconditions and branch freshness

Part of the `fm-route` skill. `{pluginRoot}` is the plugin root the skill states.

### Step 0a: Action preconditions (per-page actions)
**For `--cutover`, skip this step** — its preconditions are batch-level and live in "Batch cutover"
below. Steps 0a–4c describe the four per-page actions; a `--cutover` run jumps to that section after
Step 0's config.

**Refuse a cluster first.** If the target's `kind` in `tracker.json` is `cluster`, stop before any
per-page action: a cluster owns no route, so there is nothing to flip — it reaches `cluster-ready`, not
`flipped` ({pluginRoot}/CLAUDE.md → Component Clusters). Point the user at the cluster's own gate chain (`fm-verify`
/ `fm-parity` → `cluster-ready`); its readiness becomes a flip-precondition on the *consuming* page's
`--flag-off`, below, not a flip of its own.

Every per-page action writes or clears route state, so every one needs an entry condition. Read
`tracker.json` first and refuse before touching anything:

| action | requires | on refusal |
| --- | --- | --- |
| `--flag-off` | `status = parity-passed`, **no** `flipPrOpenedAt`, and Step 1's gate guard | gates not all passed (name the stage), or a flip is already in flight — `--revert` it first |
| `--flag-on` | Steps 1, 1-pre, 1a, 1b, 1c, 1d below, and **no** `flipPrOpenedAt` | as each step states; a present `flipPrOpenedAt` means a flip is already in flight — use `--confirm-live` or `--revert`, never a second `--flag-on` |
| `--flag-on --confirm-live` | `status = parity-passed` **and** `flipPrOpenedAt` present, Step 1a fresh, and no `regateFailed` entry | no flip is in flight — run `--flag-on` first; stale or failed evidence — `fm-verify {page} --regate` first |
| `--revert` | `status = flipped`, **or** `flipPrOpenedAt` set at any status **except `done`**, **or** `status = parity-passed` with `routePrepared` set | there is nothing in rotation or in flight to roll back — and on `done` there is nothing to roll back *to*: name manual intervention, never a command |

**`flipPrOpenedAt` admits `--revert` at any status but `done`** because every other rule in this plugin
points at `--revert` as the way out of an in-flight flip, and a page can hold the timestamp at a
status below `parity-passed`: `fm-extract` demotes a dependent to `generated` and a `--flag-on`
running concurrently then records the timestamp. Requiring `parity-passed` there left the only
prescribed exit refusing the state it was prescribed for.

**`--revert` never promotes a page.** From `flipped` it returns the page to `parity-passed` — the
state it was in before the flip, and one it genuinely earned. From `parity-passed` it **keeps the
current status** and only clears the route fields, undoing a `--flag-off` or a prepared-but-not-live
flip (whether or not PR2 was actually opened — see the field's definition in {pluginRoot}/CLAUDE.md).

**Tell the operator the rollback is not finished.** `--revert` edits the in-repo artifact; the
edge returns to legacy when the rollback PR is merged and propagated — the soft rollback this
plugin targets at 5–10 minutes (`{pluginRoot}/templates/strangler-fig.md`). Step 4's clearing of `flippedAt`
records that rollback, and `{pluginRoot}/templates/capture-provenance.md` reads it that way, so the report must
say plainly that the operator has to complete it, and must not start a fresh
`--flag-off`/`--flag-on` cycle before it propagates or the two PRs race at the edge.
It must never write `parity-passed` over any other status: `parity-passed` is a gate-passed state,
and "only the gate issues its own passed state" ({pluginRoot}/CLAUDE.md → Per-page State Machine) binds this
skill exactly as it binds `fm-fix`. Without this guard, `--revert` on a `generated` page (say, one
`fm-delta` had just reset) would promote it, and since `--flag-off` merely re-arms `routePrepared`,
the next `--flag-on` would find every precondition satisfied and flip code no gate has seen.

### Step 0b: Branch freshness (PR-preparing actions: `--flag-off`, `--flag-on`)
Both PRs are graded against **flag-ON at merge** (the big-bang cutover model —
`{pluginRoot}/templates/pr-body.md` → Grading standard), so a branch behind its base ships and is graded on a tree
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
  (`{pluginRoot}/templates/pr-body.md` → Branch: synced by rebase, never by merging the base in), then
  **re-measure every gate stamp at the new HEAD** (Step 1a's freshness recompute, and the answer-key
  freshness of P0-A) before re-running this action — a stamp carried across a sync is the
  stale-on-merge defect (`{pluginRoot}/templates/pr-body.md` → Rules). Refuse; do not prepare the PR.
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
