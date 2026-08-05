# Gate cost & preconditions (v0.14.1)

Source: OMH-749 fm-parity confirm round, measured 2026-07-31. Sibling of the four fidelity axes
and the self-confirmation/provenance hardening — but a **different axis**. Those all address
"green gate, defect shipped" (accuracy). This one addresses "accurate gate, but it starts work it
cannot finish" (cost). Accuracy should lean toward safety; cost has no such reason — running a
capture with nothing to freeze makes nothing safer.

## Problem

A gate can consume the critical path without being able to produce a verdict, because the
instructions tell it to start capturing before checking that its own premise holds.

Measured timeline (booking-history, one ticket):

| Time | What happened | Required gate? |
|---|---|---|
| 14:50 | `.lock` acquired | — |
| 14:54 | `parity.baseline.ts` (legacy visual recapture) | yes (visual) |
| 15:21 | `contract.baseline.ts` started | **no** |
| ~15:36 | a human noticed and stopped it | — |
| 15:39 | `telemetry.baseline.ts` written → ran → pass | yes (telemetry) |
| 15:51 | `parity-report.json` rewritten; visual fail, 5 new divergences | — |

This page's `requiredGates` is `[e2e, visual, telemetry]`; contract is not in it, yet the contract
capture ran ~15 min (and the prior round, 07-30, overran its self-chosen 900s budget and was cut).
~45 min went into work that could not affect the verdict — and it was the instructions, not an
agent misjudgement: `agents/parity-verifier.md`'s contract section goes from its heading straight
into the diff, with no "is there anything to compare?" step in between.

The two axes the contract gate conflates:

| Axis | Asks | booking-history |
|---|---|---|
| **necessary** | must this page freeze a contract? | yes (it writes) |
| **possible** | is there a typed contract to freeze? | **no** (`unknown` by the member-hook pattern) |

The plan deferred response-DTO typing (D2-BH) on purpose, so the *possible* axis is No, while the
*necessary* axis is Yes. The gate keyed off neither and just ran.

## Defenses

- **A — contract confirms its premise before the response-DTO capture.** `parity-verifier.md`'s
  contract section now opens with a premise check. The response-DTO diff freezes the page's v2
  response shape against the legacy DTOs from `analysis`, so its one real premise is that the response
  hooks carry a concrete DTO shape — **not `unknown`, and not a vacuous `any`** (`any` passes a naive
  typed-check but the diff against it matches everything, a false pass; treat it like `unknown`). When
  concrete → run. When `unknown`/`any`, split on **why**: an **approved sign-off** — an
  `openApprovals[]` entry with `status: "approved"` and a named `owner` (not `TBD`) → `result:
  "not-run"` + `reason: "typing deferred: <openApprovals ref>"` and proceed; no such entry →
  `result: "fail"` (or an explicit approval request), never a silent `not-run`. A **`pending` entry
  and a bare free-text typing note are equally insufficient**: skipping a contract sub-check is a
  coverage reduction, and this plugin routes every coverage reduction through an approved
  `openApprovals` entry, never a self-authored default — otherwise the pipeline could excuse its own
  skip. A precondition, not a plan flag: when the deferral resolves and the DTOs become typed, the
  capture runs again with no one editing a plan. `parity-report.json`'s contract entry gains
  `not-run` + `reason`.

  **Two corrections over the raw proposal (recorded decisions).**

  1. *Scope of the premise — request vs response.* The contract gate has two independent sub-checks:
     (1) the response-DTO diff, whose baseline capture is the expensive part, and (2) the
     request-body-against-the-live-backend check (OMH-748, the gate-side half of request-schema
     fidelity v0.11.0), which needs only the request builder + a reachable backend and does **not**
     depend on typed response DTOs. The premise gates **only (1)**. Gating the whole section on typed
     response DTOs — as the proposal read — would skip (2) on exactly the write-with-`unknown`-typing
     pages where it matters most, re-opening the v0.11.0 hole. So (2) still runs on every page that
     builds a request body.

  2. *What the premise actually tests.* The proposal's premise was "typed DTOs **and** a contract doc
     under `contractsDir`". Dropped the `contractsDir` conjunct: it is optional infra (absent whenever
     `docs/migration/api-contracts/` does not exist), and the response diff's reference is the legacy
     analysis DTOs, not a `contractsDir` doc — so requiring it would `not-run` the response diff on
     *every* page of any project without that dir, i.e. the required check silently going missing. The
     real premise is a concrete v2 DTO shape alone. And an `unknown` hook is only a legitimate skip when
     the plan **recorded** the deferral; an unrecorded `unknown` on a write page is a defect the gate
     must surface (`fail`), not absorb as "nothing to freeze" — otherwise a lazily-untyped page masks
     itself with a reason that reads as legitimate, the self-confirmation the plugin exists to stop.

  **Follow-up tightening (post-merge review, same axis).** Two seams in the shipped A were closed after
  a review round flagged that the contract skip was softer than the rest of the plugin:

  - *Sign-off, not a self-authored note.* The legitimate `not-run` originally accepted "an
    `openApprovals[]` item **or** the plan's typing note". The second channel was softer than this
    plugin's universal rule — every coverage reduction goes through `openApprovals` with a decision
    owner's sign-off (`migration-plan-schema.md`), never a self-authored default. A free-text typing
    note the pipeline can write itself let it excuse its own skip. Now only an approved
    `openApprovals` deferral permits `not-run`; a bare note is treated as "not recorded" → `fail`.

    *Which entries count* — the sign-off is `status: "approved"` **and** an `owner` that names a real
    decision owner (not `TBD`). Naming the entry alone is not enough: `status` is
    `pending | approved | rejected` and **`fm-plan` writes `pending` entries itself** (the schema's own
    example is `"owner": "TBD", "status": "pending"`), so "an `openApprovals` item exists" would have
    left the self-approval seam open one indirection further along — the pipeline writing its own
    pending entry instead of its own note. `pending` and `rejected` read as "not recorded", same as a
    note.

    *Transition* — a deferral carried only as a free-text typing note (booking-history's `D2-BH`, the
    known case) must be promoted to an approved `openApprovals` entry before that page's next parity
    run; until then the premise records `fail`. Consistent with the precondition framing: it reads
    present reality rather than re-judging pages that already passed.
  - *Exclude vacuous `any`.* The premise "typed (not `unknown`)" let an `any`-typed hook through, and
    the diff against `any` matches every legacy shape — a **false pass** (worse than an honest skip: it
    claims verification that never happened). The premise now requires a concrete DTO shape and treats
    `any` like `unknown`. Lower probability in v2 (zod/`unknown` dominate), but the failure mode is a
    silent green, so it is worth excluding explicitly.

    *How it is read* — from the `api` phase output (the TanStack Query hooks over `@omh/shared-data`
    services): `unknown`, `any`, or an alias/generic resolving to either is not concrete. A concrete
    DTO with an `any`-typed **field** stays concrete — the diff runs, that field is excluded and named
    in `evidence`. Stating this matters because "not vacuous `any`" alone leaves the nested case to the
    executing session, which is the improvisation the premise exists to remove.

- **B — the lock carries a parseable timestamp.** The "stale after 30 minutes" rule lived in ~11
  places but no file defined the lock's fields; `acquiredAt` appeared nowhere in the plugin, and the
  lock actually written in OMH-749 carried a date-only `acquiredAt` from which 30-minute staleness
  cannot be computed. `CLAUDE.md` now specifies a minimal schema — `holder` / `pid` / ISO-8601
  `acquiredAt` (with time) — and a rule: a date-only or unparseable timestamp is **immediately
  stale**, so a malformed lock never becomes a permanent deadlock. The five lock-taking skills and
  `codex-auditor` point at the schema on their Acquire line. Harmless today (serial sessions), a
  deadlock the moment sessions run in parallel.

- **C — gates have a per-gate cost cap.** `gateAcceptance.{gate}.budgetSeconds` (optional; a plugin
  default when omitted). On overrun the verifier records `result: "not-run"` +
  `reason: "budget exceeded"` and proceeds — never `fail` (a measurement not taken ≠ a measurement
  that failed), never a hard-kill (a half-written artifact reads as evidence next round). Per-gate,
  not per-round: `visual` runs long by design; a `contract` overrun usually means there was nothing
  to freeze. C generalizes what A fixes for this one case: A removes gates that should not run,
  C bounds gates that run too long.

## What was deliberately not done

- **Derive the gate set from `requiredGates` (drop "always").** Tempting — `parity-verifier.md` and
  `fm-parity/SKILL.md` both carry the self-contradicting "the gates the plan requires (always visual
  + contract)". Not taken: across the 12 monorepo plans, 10 omit contract from `requiredGates`, and
  those 10 include pages that must freeze a contract (coupon POST, info PUT, password POST). The
  omission reads as "no one had to write it because it always ran", not "judged unnecessary". And
  `wish-list` names the gate `contract-freeze`, so a name-match derivation would drop it with no
  warning. Fixing the gate-set derivation needs three prior things (an inclusion rule, gate-name
  normalization, back-filling existing plans) — a plan-quality axis, left separate. So this change
  does not touch the gate set or the contradictory sentence.
- **A `gateExemptions` field on the plan.** No — the exemption reason here is a machine-readable
  precondition, not a planner policy. A field would outlive D2-BH's resolution and keep the gate off
  forever. A precondition tracks reality; a manual flag rots.
- **Auto-kill on budget overrun.** No — a killed capture leaves a half-written artifact that can be
  misread as valid evidence. Record and proceed.
- **Replace the file lock.** Overkill. The file lock is fine; only the schema was missing.

## Preserved (do not regress)

`parity-report.json` already keeps three facts apart without collapsing them, each by a distinct
mechanism in the schema: **excluded by the plan** is `result: "skipped"`; **attempted but
unfinished** is `result: "fail"` with the shortfall named (`uncaptured[]` on visual — a non-empty
list is an incomplete gate, which is a fail); **not started** is the gate having no entry in the
report at all. A's and C's `not-run` is an extension of that split — a fourth honest fact ("premise
absent / budget spent"), not a replacement. This is the `SKILL.md` Step 3-5 rule (a silent scope
reduction is a fail) working as intended.

## Acceptance

This repo has no runnable suite; deliverables are English instruction docs, verified by document
consistency:

1. `parity-verifier.md` contract section states the premise is a concrete v2 DTO shape alone —
   not `unknown`, not vacuous `any` (`contractsDir` not required) — gates the response-DTO diff
   **only**, and the request-body check runs regardless of response typing. An `unknown`/`any` hook is
   `not-run` only under an `openApprovals` entry with `status: "approved"` and a named `owner`;
   `pending`, `rejected`, a `TBD` owner, and a bare plan note are all `fail`.
2. `parity-report.json` contract result enum includes `not-run` with a `reason` (and an `unknown`/`any`
   write page with no **approved** `openApprovals` deferral is a `fail`, not `not-run`).
3. `parity-verifier.md` states where the premise is read from (the `api` phase response hooks) and how
   a nested `any` **field** is handled (diff runs, field excluded and named in `evidence`); the
   free-text-note transition for existing plans is recorded.
4. `budgetSeconds` documented in `migration-plan-schema.md` and its overrun behavior in
   `parity-verifier.md` Rules agree (not-run + reason, per-gate, no kill, no fail).
5. `CLAUDE.md` lock schema (`holder`/`pid`/ISO-8601 `acquiredAt`) present; unparseable = immediately
   stale; the 5 skills + `codex-auditor` reference it.
6. Gate-set derivation, the "always" sentence, and existing plans are untouched.

## Follow-up (out of scope, separate axis)

- Gate-set derivation quality (inclusion rule + `contract-freeze` name normalization + back-fill).
- "When has a page's parity converged?" — new divergences keep surfacing as capture depth grows
  (07-22 waive → 07-31 two → confirm five); the plugin has no convergence criterion.
- The same missing-decision-field pattern as B is reported in two more places (Codex-finding
  resolution, gate-pass commit) in OMH-754 — separate PR.
