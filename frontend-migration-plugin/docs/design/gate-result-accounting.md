# Gate result accounting (v0.14.4)

Source: OMH-754 (my-coupon) PR-eve verification, measured 2026-08-02. Sibling of the gate cost &
preconditions work (v0.14.1) and named by that doc's own follow-up. A **different axis** again: the
gates hold judgement rules, but the artifacts lack the fields to record the *basis* for those
judgements, so the rule falls to the executing session's improvisation.

One line: an instruction demands a verdict (`unresolved` findings, gate freshness) that the artifact
gives it no place to record — so it is either skipped or answered from an ad-hoc field invented on
the spot.

## Problem

Three things a gate is told to judge, none of which the schema lets it record. All three surfaced in
one PR-eve pass on my-coupon, where the gates were green but the greenness could not be counted:

| What the rule wants counted | Why it could not be counted |
|---|---|
| Codex `unresolved high-severity` findings (fm-route Step 1b) | the finding schema has no field for whether a finding was later closed |
| how many commits a gate PASS is stale by | the pass is timestamped by date only; no commit SHA is recorded anywhere in `tracker.json` |
| which pages a `packages/shared-*` change outdates | the page↔package dependency is nowhere consulted at flip time |

Measured: `docs/migration/pc/my-coupon/codex-audit.json` carried 48 findings, 14 `high`. Only 2 had
any adjudication recorded; the other 46 could not be read as open or closed from the file. The page
was `parity-passed` in that state.

This is not agent laziness. With no field to write, the fact does not get written — and the executing
session then invents one. Grepping the four ad-hoc fields my-coupon's artifacts actually used against
the whole plugin source:

| Field used in the artifact | Defined in plugin source |
|---|---|
| `ownerAdjudication` | 0 |
| `priorFindingAdjudication` | 0 |
| `priorAuditReconciliation` | 0 |
| `notReRun` | 0 |

Same shape as the v0.14.1 lock seam (a "stale after 30 min" rule with no `acquiredAt` to compute it
from): the rule lives in the instructions, the basis is missing from the output.

## Defenses

- **D — a finding carries its own resolution.** `templates/codex-audit.md` gains an optional
  `adjudication { state: open|closed|rejected, when, by, basis }` on each finding. It is **never
  written by the discovering audit** — Codex reports what it finds; whether it was later fixed or
  dismissed is a separate downstream fact, written by `fm-fix` after a repair (or a human). A finding
  with **no** `adjudication` reads as **`open`** — the safe default, so an unrecorded finding is never
  silently counted as handled. `state` keeps `closed` (fixed) apart from `rejected` (not a defect):
  collapsing them makes the next audit round re-raise a rejected item — exactly the circular re-raise
  observed on my-coupon's `parity` stage, where a round-4 report's own claim came back as a HIGH
  finding and a human had to retract it in yet another ad-hoc field. `basis` is required for
  `closed`/`rejected` — a `closed` with no basis is a declaration, not an adjudication.
  `fm-fix` Step 5 writes the adjudication when a fix closes a finding; `fm-route` Step 1b defines
  `unresolved` = `adjudication` absent or `state: open`. Priority 1: without it, `fm-route --flag-on`
  today pushes all findings (fixed and open alike) at the human, who then acknowledges with no basis to
  distinguish them — the exact path by which a soft gate becomes a rubber stamp.

  *Surviving a re-audit.* Placing the field on the finding means a re-run of that stage would
  overwrite it: `codex-auditor` rewrites `{stage}.findings[]` wholesale, so every closed
  finding would reopen on the next `fm-audit-codex` and the field would defeat its own purpose. So
  the auditor carries adjudications across the rewrite — matched on `area` + `evidence`, with any
  unmatched adjudicated finding preserved verbatim under `{stage}.priorAdjudicated[]` — and
  is barred from authoring or clearing one. The matching is intentionally weak: Codex is an LLM and
  its `detail` prose does not reproduce word for word, so `area` + `evidence` is the most identity a
  re-run can honestly assert. Rather than invent a fingerprint that would silently mis-match, a
  non-match is recorded as **"could not be matched"** and surfaced at Step 1b next to the current
  findings — the human is already acknowledging there, so that is the right place to resolve it.

- **E — a gate PASS records the *content* it rests on.** `fm-verify` / `fm-e2e` / `fm-parity` add
  `gateEvidence.{gate} = { at: <ISO-8601>, commit: <sha>, tree: <hash> }` to their `tracker.json`
  record. This has already been realized once by hand: OMH-754 PR #184 shipped a `visual: PASS`
  standing on a screenshot 21 commits stale — the reviewer caught it by counting commits the tracker
  could not name. `at` is ISO-8601 with time, the same regulation the v0.14.1 lock schema set — a
  date-only value is a rule violation, not a shortcut.

  `commit` = `git rev-parse --short HEAD`; a dirty tree records `<sha>+dirty` (honest imprecision
  over a clean-looking lie). It is an **audit-trail field only** — nothing decides freshness from it.
  `tree` is a content hash over the page's watch paths (F below), and it is the field the flip
  compares. It is computed by **one executable**, `scripts/gate-tree-hash.sh`, which every producer
  and consumer runs — never reimplemented inline. The first cut printed the pipeline in CLAUDE.md for
  five call sites to reproduce, and that could not hold: `git ls-files` prints cwd-relative paths
  while `fm-verify` orders every command run from `{monorepoRoot}/{appDir}`, so repo-relative watch
  paths matched nothing there and the pipeline hashed the empty set — a constant that never moves,
  which a hard gate reads as a pass on any code. The script resolves the repo root itself and returns
  `unverifiable` (exit 2) rather than a hash when nothing resolves.

  **The first attempt compared commits, and had to be soft because it fired on every page.** The
  gates run before the code PR exists, so every record was `+dirty` and `git log <sha>..HEAD` could
  not even be evaluated; and once PR1 merged, its merge commit touched every path in `sourcePaths[]`
  by definition. Both conditions fired unconditionally and a re-run could not clear either, so the
  rule was demoted to acknowledge-and-proceed — which is not verification, and left a real
  false-pass path open at the one irreversible step. Hashing **content** removes both failure modes
  at once: a merge changes the commit graph, not the bytes, so an untouched page hashes identically
  and passes cleanly, while a page whose code or shared package actually changed does not. That
  makes `fm-route --flag-on` Step 1a a **hard** gate again: a `tree` mismatch blocks. Naming *which*
  files moved needs more than the aggregate, so each gate also saves the script's `--manifest` output
  under `$(git rev-parse --show-toplevel)/docs/migration/{app}/{page}/gate-tree/{gate}.tsv` — an
  absolute destination, because the gate skills run from `{appDir}` and `{monorepoRoot}` defaults
  to `"."` — passing that repo-relative path back as `--exclude`. Step 1a diffs against it. A record with no `tree` (written before this field) stays `unverifiable` —
  acknowledged, non-blocking, no retro-adjudication.

  The legacy `verifiedAt` / `e2ePassedAt` / `parityPassedAt` stay for backward compatibility;
  `gateEvidence` wins when present. Because a regeneration invalidates them just as surely as it
  invalidates `gateEvidence`, `fm-gen` and `fm-delta` clear all four together — plus `routePrepared`
  and `flagKey` (F below) — otherwise the *advisory* field is cleared while the fields `fm-route`
  Step 1 and Step 1-pre hard-gate on survive and re-authorize the flip.

- **F — freshness follows the shared-package dependency.** The gate is per-page, so a
  `packages/shared-*` change (a `shared-ui` button padding, an `@omh/shared-types` field) outdates the
  visual/contract evidence of *every* page that imports it, and nothing per-page catches it — the
  monorepo CI is typecheck/lint/unit/build only, no visual, no e2e on PR. E's freshness check closes
  half of this (a commit on the page's own source), leaving the case where the outdating commit lives
  outside the page, under `packages/`. A third case sits outside both: the page's
  `migration-plan.json` decides the route that gets flipped (`flagPlan.guardsPath`), the criteria
  the executors enforced (`gateAcceptance`), which gates ran (`requiredGates`) and what e2e tested
  (`e2eScenarios`) — edit it after the gates pass and the reports describe work that no longer
  matches what ships. So E's watch paths are `{page source} + {shared-package deps} + {the plan}`,
  and both halves must resolve from a **recorded** field — a check that asks the session to work out
  which files belong to the page reintroduces the improvisation this whole axis exists to remove.

  *Own source.* Nothing recorded it. `componentTree` carries component **names**, not paths, and
  `generation-state.json` tracks phase status only. So `fm-gen` Step 5 records `sourcePaths[]` (the
  files its phases wrote under `appDir`) and `fm-delta` refreshes it. Both also **clear `gateEvidence`
  together with the legacy `verifiedAt` / `e2ePassedAt` / `parityPassedAt`** on the way through: a
  regenerated page's prior PASSes stand on code that no longer exists. Clearing `gateEvidence` alone
  would be the worse half of the job — that is the field `fm-route` Step 1a treats as *evidence*,
  while Step 1's hard precondition reads `verifiedAt` and the two report files, so the authoritative
  traces would survive the regeneration untouched and re-authorize the flip.
  A page with no `sourcePaths` (generated before the field) is `unverifiable` on
  this axis — the same honest-state treatment absent `gateEvidence` gets — and the consumer must say
  which axis it checked rather than reporting a bare "fresh".

  *Shared deps.* `migration-plan.json` `sharedDeps[]` already records them, so this half genuinely
  reuses an existing field — but the entries are `@omh/<package>:<symbol>`, not paths, so each maps
  to the directory `{packagesDir}/<package>` and the symbol is dropped. Naming the field and its
  shape matters: an instruction saying "the plan's shared-package deps" leaves the executor to guess
  both which field and what its values mean.

  `fm-progress` gains a **stale-evidence** view: `parity-passed` pages whose recorded `tree` no
  longer matches a re-hash of their watch paths, resolved identically to Step 1a. There it is a
  *warning* — an early signal that a `packages/shared-*` change has outdated many queued pages at
  once, so the re-runs can be scheduled rather than discovered at the flip. At `fm-route --flag-on`
  the same mismatch is a **hard block**: that is the irreversible step, and an acknowledgement is
  not a test. Depends on E; done with it.

## What was deliberately not done

- **Make Codex a hard gate.** No — advisory is the design intent (`CLAUDE.md` "reads and evaluates
  only"). Findings carry false positives; binding a noisy layer to blocking power stalls the pipeline.
  D gives a way to *count* findings, not a veto.
- **Make `adjudication` a required field.** No — required means the discovering audit must fill it,
  but the discoverer does not know the resolution. Optional + absent-reads-as-`open` is correct.
- **Auto-re-run a gate when its evidence goes stale.** No — re-running parity on every commit
  explodes cost. The plugin never re-runs a gate for you: `fm-progress` makes staleness *visible*
  early, and `fm-route --flag-on` *blocks* on it and tells the operator which gates to re-run. What
  is refused is the third option — accepting stale evidence at the flip on an acknowledgement.
- **Timestamp gate freshness by file mtime.** No — files are touched independently of gates, and a
  plain copy bumps mtime. **Content is the only trustworthy coordinate** (the commit was tried and
  failed for its own reasons — see E); `scripts/gate-tree-hash.sh` is what computes it.
- **Retro-fill existing `codex-audit.json` / `tracker.json`.** No — the capturing session is gone, so
  a filled-in value would be a guess, and re-adjudicating would drop already-passed pages to
  `unresolved`/`unverifiable` en masse. New records only; the same decision
  `templates/capture-provenance.md` made for provenance, reused not restated.

## Acceptance

No runnable suite; deliverables are English instruction docs, verified by document consistency:

1. `templates/codex-audit.md` schema shows `adjudication` as optional and post-discovery, absent =
   `open`, `basis` required for `closed`/`rejected`, no retro-fill.
2. `fm-route` Step 1b defines `unresolved` as adjudication-absent-or-`open`; `fm-fix` Step 5 records
   the adjudication when a fix closes a finding.
2a. `codex-auditor` carries adjudications across a stage rewrite (matched on `area` + `evidence`),
   preserves unmatched ones under `priorAdjudicated[]`, and is barred from authoring or clearing one;
   `fm-route` Step 1b surfaces `priorAdjudicated` `high` entries as `unmatched`.
3. `fm-verify` / `fm-e2e` / `fm-parity` each record `apps[app].pages[page].gateEvidence.{gate}` with
   ISO-8601 `at` + `commit` (`<sha>+dirty` on a dirty tree; audit trail only) + `tree` (the
   watch-path content hash, the comparable field), legacy `*At` fields kept.
4. `fm-route` Step 1a re-computes `tree` with `scripts/gate-tree-hash.sh` over the same watch paths
   — `tracker.json` `sourcePaths[]` plus each `sharedDeps[]` entry mapped
   `@omh/<package>:<symbol>` → `{packagesDir}/<package>` — and **blocks** on a mismatch, naming the
   files that differ from the gate's saved `--manifest`. Absent `tree` or absent `gateEvidence` =
   `unverifiable`, acknowledged and non-blocking; absent `sourcePaths` = `unverifiable` on that axis
   only, and the report names which axis it checked.
5. `fm-progress` lists `parity-passed` pages whose `tree` no longer matches on the same watch-path
   basis, and declares `allowed-tools` that include `Bash` (the check shells out to `git`).
6. `fm-gen` Step 5 records `sourcePaths[]` and clears `gateEvidence`, the legacy
   `verifiedAt`/`e2ePassedAt`/`parityPassedAt`, **and `routePrepared`/`flagKey`**; `fm-delta` Step 5
   refreshes and clears the same, so a regenerated page never carries a PASS for code that no longer
   exists — on any of the three field sets `fm-route` reads.
7. Codex stays advisory (`CLAUDE.md` unchanged on that point); no existing artifact is retro-filled.

## Follow-up (out of scope, separate axis)

- Personal `pre-pr-verify` skill coverage of the same three gaps — a monorepo-side workaround, tracked
  separately; some of it becomes unnecessary once these land.
- `web-pc-e2e.yml` not being a PR gate — a monorepo CI-config matter, cited only as F's backdrop.
- "When has a page's parity converged?" — still the open convergence question the v0.14.1 doc left.
