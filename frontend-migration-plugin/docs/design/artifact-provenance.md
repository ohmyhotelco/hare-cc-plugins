# Design — artifact provenance and answer-key sourcing (v0.14.0)

The sibling docs each closed an axis where generation diverged from the legacy answer key
(`style-spec` v0.9.0, `transform-fidelity` v0.10.0, `request-schema-fidelity` v0.11.0,
`i18n-copy-fidelity` v0.12.0), and `self-confirmation-hardening` (v0.13.0) closed the mechanism where
one reading produced both the test and the code. This one closes a different layer: not what the gate
compares, but **what the gate accepts as the thing it compared against**.

## Problem

The plugin already carries two rules that should have covered this. "Evidence before claims" (the
5-step gate, `CLAUDE.md`) and "Gate criteria are codified, not reinterpretable". OMH-758 (account
deletion) did not slip past them by violating them — it slipped past by **satisfying** them. Both rules
are written for **command execution**, and the failures were about **captured artifacts** and **the
criteria's expected values**.

The 5-step gate's premise is that the thing being verified is a command: run it, and its exit code and
counts prove their own origin. `vitest` printing 1936 passed came from that run. A captured artifact is
a different kind of object. `legacy-ko-1440.png` exists and opens, so "READ the full output" is formally
satisfied — but nothing in the file says it is a legacy render, and nothing in the protocol asked. The
only remaining clue is the file name, and the file name is chosen freely by whoever saved it.

Six items came out of that ticket; two of them were **gate passes that had to be retracted**:

| # | What happened | Why the gate missed it |
| --- | --- | --- |
| 1 | An API capture was of v2 but recorded as legacy; the contract gate used it as pass evidence | No procedure cross-checks an artifact's origin. Filename and directory get promoted to statements of fact |
| 2 | Three "legacy screenshots" were not legacy captures; the visual gate passed | Same. A file that exists and opens satisfies "READ the output" |
| 3 | The v2-side evidence scope was deduced from deployment topology, then retracted — the refuting artifacts were already committed | Statements about coverage/evidence state are not treated as claims needing verification |
| 4 | The contract criterion's answer key was wrong (`currency`/`country` asserted as URL-locale-derived) → a false FAIL | Authoring binds coverage but not the **source of the expected value** |

Measured exposure at the time, over one page set (`docs/migration/` on the OMH-758 branch):

| Item | Count |
| --- | --- |
| Captured `png` artifacts | 561 |
| Whose filename starts with `legacy` | 139 |
| Whose origin is recorded anywhere (`style-spec.json` → `legacySource.screenshot`) | 5 |

134 artifacts were legacy by naming convention alone. How many were actually wrong is not knowable —
that is the point. There was no means of telling.

The second half of the diagnosis is about free text. The one provenance-ish field that existed,
`legacySource.capturedFrom`, defined **two** values (`live | source-fallback`) and was found carrying
**five** hand-written ones across nine pages, one of them a full sentence
(`"authed-read-only-recapture (test-newwww staging, member session)"`) on an object whose `url` and
`screenshot` were both `null` and whose `reason` said the live URL was never reached. Whether that
capture happened cannot be determined from the record — and a record that cannot be adjudicated is the
defect, independent of what actually occurred.

## Design — three defenses

No new stage and no new artifact. One new shared template plus rules folded into existing surfaces.

### A. Provenance decides side (`templates/capture-provenance.md`)

Every capture artifact carries a `provenance` block — `origin` (URL incl. host:port), `side`,
`authState`, `renderSource`, `responseSource`, `captureMode`, `capturedAt`, `viewport`, `partial` —
written by **the code performing the capture**, not by the agent that later reports on it. The field
names are promoted from what the OMH-758 probes already recorded by hand (`host`, `capturedAt`,
`renderSource`, `responseSource`, `stubServed`), so this standardizes practice rather than inventing a
scheme.

Two decisions carry the weight:

- **`side` is resolved, never asserted.** Ordered rules: localhost + `apps.*.legacyPort` / `apps.*.port`
  → `legacy` / `v2`; a declared legacy host → `legacy` only while `tracker.json` shows the path
  un-flipped (post-flip the same production host serves v2); a declared v2 host → `v2`; anything else →
  `unresolved`. The flip-state condition is why host matching alone is insufficient: `apps.*.domain` is
  the same string before and after a flip.
- **`unresolved` means absent.** Not "probably legacy". The axes that artifact was to carry are
  uncovered, which is an incomplete gate = `fail`, the same verdict as an unprobed axis. This inverts
  the previous default, under which an origin-less artifact was honoured at face value — a fabricated
  or mislabeled capture now falls out on its own, which is what should have happened.

Reflected in: `CLAUDE.md` (Evidence before claims + 2 red-flag rows), `templates/style-spec.md`
(`legacySource.provenance`; `capturedFrom` deprecated, split into `renderSource` + `authState` +
`partial`), `templates/visual-parity-checklist.md` (failure mode 3 + protocol **step 0**),
`templates/e2e-testing.md` (per-leg provenance on the dual-run), `agents/style-spec-extractor.md`
(both paths), `agents/parity-verifier.md` (step 0, baseline reuse, evidence citation),
`agents/e2e-test-runner.md` (`dualRun.legacyProvenance` / `newProvenance`),
`skills/fm-parity/SKILL.md` (inspection check 1), `skills/fm-style-spec/SKILL.md` (tracker record).

### B. A statement about the evidence is a claim (B's cost is three sentences)

The red-flag table's five rows all caught "thoughts that skip running something". Nothing covered
**meta-statements about the evidence**: "both sides were measured", "only one side was observable",
"1 of 5 locales was reachable". Item 3 above was exactly that shape — evidence scope deduced from
routing configuration, while `probes/contract_{ko,en,ja,vi,zh}.json` and an E2E scenario asserting all
five locales were already committed. Routing decides what a URL serves; it does not decide what a
capture aimed at a local build can read.

Reflected in: the 5-step gate's scope sentence + 2 red-flag rows (`CLAUDE.md`),
`agents/parity-verifier.md` (rules), `templates/codex-audit.md` (an audit's own coverage claims).

### C. The answer key needs a source, and a wrong one is amended by the owner

v0.8.2 bound `gateAcceptance` **coverage** to the full matrix. The **expected value** — the answer key —
stayed unbound, and item 4 is what that costs: the criterion was written from the legacy source alone
while the v2 platform had already decided (on `develop`) that only `language` follows the URL locale
while `nation`/`currency` preserve the user's locale-modal choice. Coverage was right and deliberate;
the answer key was wrong; the gate produced a false FAIL.

A false FAIL is not a harmless inversion of a false pass. **It fails the gate on correct code**, and
that pressures the executor to read the criterion more narrowly — the precise behavior
"Executors enforce these criteria verbatim" exists to forbid. The authoring error manufactures the
reinterpretation pressure.

- `expectedValueSource` (new `gateAcceptance` field) — required whenever a criterion asserts a v2-side
  expected value: the prior page's `acceptedDeltas`/`openApprovals`, an ADR, a shared-module commit
  **with the branch it lives on**, a BE confirmation, or an explicit `"searched: …; none found"`.
  Recording the empty search matters: otherwise "searched and found nothing" is indistinguishable from
  "did not search". `fm-plan` Step 4 returns a plan without it, exactly like a missing `gateAcceptance`
  entry.
- `criterionAmendment` (new section) — 13 fields, promoted verbatim from the first real amendment
  (`docs/migration/pc/delete-account`), including two the original proposal omitted: `beConfirmation`
  and `fence`. `fence` earns its place by bounding the amendment ("pages carrying a price are not
  covered by this clause"), without which one page's correction drifts into a repo-wide precedent.
  `priorDecisionLocation` is the field a reviewer checks first — the cited decision was on `develop` and
  **not** on `master`, so only a citation saying that was accurate. A pass under an amended criterion
  carries `amendedCriterion: true` + `priorWhy`.

Reflected in: `templates/migration-plan-schema.md` (field list, authoring rule, new section),
`agents/migration-planner.md` (the prior-decision search), `skills/fm-plan/SKILL.md` (Step 4 check 4),
`agents/parity-verifier.md` + `skills/fm-parity/SKILL.md` (amendment is the owner's act; a claimed
amendment the plan does not record is a `fail`).

## Decisions

- **One shared provenance template, not three copies.** style-spec / parity / e2e all capture, and
  three local definitions drift — `capturedFrom`'s two-defined-vs-five-in-use spread is the evidence.
  The block is defined once and referenced.
- **Closed enums, with `partial` as its own field.** Four of nine pages wrote `live-partial`, which
  never says *what* was partial. Splitting the axes (reach / session / response source) and giving
  "partial" a `{ reached, notReached, why }` object gives that information a place to live. A value the
  enums lack is a change request against the template, never a local invention.
- **New captures only; no retroactive fill, no re-adjudication.** The original sessions are gone, so any
  value filled in now is a guess — the act this rule forbids. And re-judging the existing set would drop
  a large share of already-passed pages to absent and stall the pipeline for no new information.
  Existing artifacts stay origin-unknown, which is the honest record.
- **`unresolved` = absent rather than a warning.** A warning preserves the current default (the name is
  believed, with a note). Absence is what makes a fabricated capture fail on its own.

## Rejected (from the proposal; revive only with new justification)

- Retro-filling provenance onto the 139 existing `legacy*` artifacts — the filled value would be a
  guess.
- Re-adjudicating already-passed pages under the new rule — a large share would drop to absent and the
  pipeline would stall, with no new information gained.
- Detecting side automatically from the screenshot (e.g. a legacy-specific DOM signature) — this gate's
  own premise is that Angular↔React cannot be pixel-compared. Recording origin at capture time is the
  only trustworthy method.
- Tightening the gate thresholds — these failures came from an unverified comparison target and a wrong
  answer key, not from loose thresholds. Comparing the same object harder finds nothing.

## Acceptance

Document consistency (this repo has no test suite and these artifacts are instruction docs): the
enums agree across all eleven A edit points, `templates/style-spec.md`'s jsonc example matches what
`agents/style-spec-extractor.md` writes, the non-retroactivity clause appears in both `CLAUDE.md` and
the checklist's step 0, and `fm-plan` Step 4's new check matches the `expectedValueSource` field
definition. The functional check is a role-replay read: reading `CLAUDE.md` →
`visual-parity-checklist.md` → `parity-verifier.md` as the agent running a visual gate, an artifact
with no recorded origin is now refused rather than accepted on its filename.

## Not done here (possible follow-ups)

- **Destructive / irreversible page class** (proposal D): the `route.fulfill` no-egress capture
  technique, an `analysis.json` classification field, and a `live-render-stubbed-data` confidence grade.
  Note when picking this up: the proposal states the grade enum has three values
  (`live-confirmed` / `source-derived` / `source-fallback`) — it has **two**; `source-fallback` was a
  `capturedFrom` value, i.e. the two axes are conflated. The practice-invented grades
  (`live-corroborated`, `live-render-stubbed-data`) should be formalized together and the enum closed,
  consistent with A.
- **Legacy-capture availability as project config** (proposal E): `apps.*.legacyCapture` (per-app —
  legacy app, hosts, and accounts differ per surface), default `unknown`, never guessed by `fm-init`,
  read by `fm-plan` so an unsatisfiable authenticated-legacy criterion becomes an `openApprovals` item at
  planning time instead of an executor's improvised waiver at gate time.
