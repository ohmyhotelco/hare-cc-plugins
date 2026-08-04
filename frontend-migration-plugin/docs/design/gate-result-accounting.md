# Gate result accounting (v0.14.3)

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

- **E — a gate PASS records the commit it rests on.** `fm-verify` / `fm-e2e` / `fm-parity` add
  `gateEvidence.{gate} = { at: <ISO-8601>, commit: <sha> }` to their `tracker.json` record. `commit`
  = `git rev-parse --short HEAD`; a dirty tree records `<sha>+dirty` (honest imprecision over a
  clean-looking lie — the code checked was not the code at that SHA). The legacy `verifiedAt` /
  `e2ePassedAt` / `parityPassedAt` stay for backward compatibility; `gateEvidence` wins when present.
  `fm-route --flag-on` Step 1a then checks, per gate, whether any commit between
  `gateEvidence.{gate}.commit` and `HEAD` touched the page's watch paths; if so, that PASS is expired
  and must be re-run. This has already been realized once by hand: OMH-754 PR #184 shipped a
  `visual: PASS` standing on a screenshot 21 commits stale — the reviewer caught it by counting commits
  the tracker could not name. `at` is ISO-8601 with time, the same regulation the v0.14.1 lock schema
  set — a date-only value is a rule violation, not a shortcut.

- **F — freshness follows the shared-package dependency.** The gate is per-page, so a
  `packages/shared-*` change (a `shared-ui` button padding, an `@omh/shared-types` field) outdates the
  visual/contract evidence of *every* page that imports it, and nothing per-page catches it — the
  monorepo CI is typecheck/lint/unit/build only, no visual, no e2e on PR. E's freshness check closes
  half of this (a commit on the page's own source), leaving the case where the outdating commit lives
  outside the page, under `packages/`. So E's watch paths are `{page source} + {the migration-plan's
  shared-package deps}` — `fm-plan` already records those deps, so this reuses an existing field, no
  new one. `fm-progress` gains a **stale-evidence** view: `parity-passed` pages whose evidence a later
  commit on a watch path has outdated. The goal is **not** forced re-verification (re-running every
  gate on every shared change is unaffordable) — it is that "this evidence is stale" is visible to a
  human just before flip, instead of passing silently. Depends on E; done with it.

## What was deliberately not done

- **Make Codex a hard gate.** No — advisory is the design intent (`CLAUDE.md` "reads and evaluates
  only"). Findings carry false positives; binding a noisy layer to blocking power stalls the pipeline.
  D gives a way to *count* findings, not a veto.
- **Make `adjudication` a required field.** No — required means the discovering audit must fill it,
  but the discoverer does not know the resolution. Optional + absent-reads-as-`open` is correct.
- **Auto-re-run a gate when its evidence goes stale.** No — re-running parity on every commit
  explodes cost. One check at flip is enough; F only needs the staleness to be *visible*.
- **Timestamp gate freshness by file mtime.** No — files are touched independently of gates, and a
  plain copy bumps mtime. The commit is the only trustworthy coordinate.
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
3. `fm-verify` / `fm-e2e` / `fm-parity` each record `gateEvidence.{gate}` with ISO-8601 `at` +
   `commit`, `<sha>+dirty` on a dirty tree, legacy `*At` fields kept.
4. `fm-route` Step 1a expires a gate whose watch paths (page source + plan shared-package deps) have a
   commit after `gateEvidence.{gate}.commit`; absent `gateEvidence` = `unverifiable`, non-blocking.
5. `fm-progress` lists `parity-passed` pages with stale evidence on the same watch-path basis.
6. Codex stays advisory (`CLAUDE.md` unchanged on that point); no existing artifact is retro-filled.

## Follow-up (out of scope, separate axis)

- Personal `pre-pr-verify` skill coverage of the same three gaps — a monorepo-side workaround, tracked
  separately; some of it becomes unnecessary once these land.
- `web-pc-e2e.yml` not being a PR gate — a monorepo CI-config matter, cited only as F's backdrop.
- "When has a page's parity converged?" — still the open convergence question the v0.14.1 doc left.
