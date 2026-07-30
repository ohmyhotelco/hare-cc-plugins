# Design — self-confirmation hardening (v0.13.0)

The sibling docs (`style-spec` v0.9.0, `transform-fidelity` v0.10.0, `request-schema-fidelity`
v0.11.0, `i18n-copy-fidelity` v0.12.0) each closed one axis where generation diverged from the
legacy answer key. This one addresses the **mechanism underneath all of them**: why a green
pipeline still ships defects.

## Problem

OMH-749 (booking history) passed verify / e2e / parity and deployed to dev; humans then found 5
defects (a warning that never showed, a disabled button with no disabled state, a literal `&apos;`
on screen, a pager re-query the legacy never did, a page-reset on submit).

The root cause is structural, not diligence. The pipeline is:

```
legacy source → (agent reads it) → analysis.json → migration-plan.json → tests → implementation
```

The tests and the implementation are both generated from **one reading** of the legacy source. If
the reading is wrong — `dirty` misread as `touched` — the test encodes the wrong condition and the
code satisfies the wrong test. They agree, so the gate is green. TDD verifies "did I build what I
read"; it cannot verify "was my reading right." The plugin already names this
(`templates/i18n-copy-parity.md`: "a wrong key gets a test asserting that wrong key — self-
confirmation bias") but had no mechanism against it.

The answer key (legacy source) is real and re-openable; the grading procedure just never reopened
it. That is what these defenses change.

## Design — four defenses + one process note

No new stage, no new artifact, no runtime change. Rules reflected into existing surfaces.

### A. Entity render check (defect #3) — machine-enforced

`i18n-copy-parity.md` keyed render mode on markup (`<br/>`, `<a>`) only, and that rule lived as
**prose** — the generated key-coverage spec never checked render mode at all. An HTML entity
(`&apos;`, `&nbsp;`) has no `<`, so a markup-only rule classifies it as plain text; JSX then escapes
it and the user sees the literal `&apos;`.

- `templates/i18n-copy-parity.md` — the render-mode rule (:102) now covers markup **or** entities;
  the K3 table row gains the OMH-749 entity example; and "What it must assert" gains item 4: a value
  carrying markup or an entity rendered on the plain-text path **fails**.
- `agents/foundation-generator.md` (3b) — the scaffolded spec enforces item 4 (it already traverses
  every value for `{{param}}`; this adds the render-path check). `fm-verify`'s existing vitest step
  makes it hard automatically.

Measured exposure (`packages/shared-i18n/src/locales/*`): 17 entity-bearing values across the 5
locales, 0 of which the markup-only rule caught. `tl.bh-change-subscriber.phone-pattern` was the one
that shipped; the rest were waiting.

### B. Legacy anchors (defect #1)

Test anchors pointed at `analysis`/`plan` — derivatives of the one reading, so following an anchor
reaches the preserved misreading, not the source.

- `agents/tdd-cycle-runner.md`, `templates/tdd-rules.md`, `agents/test-reviewer.md` — a test that
  **asserts legacy behavior** carries a `// legacy: <path>:<line>` anchor into the legacy source.
  The anchor makes the reading checkable: a reviewer or Codex opens that line and confirms the
  assumed condition.
- **Scoped on purpose:** only legacy-behavior tests. v2-only-structure tests (routing, loading
  states) have no legacy line; forcing an anchor there produces formalistic noise.

### C. Codex cross-read (defect #1, B's partner)

The Codex `gen`/`verify` audit inputs carried only derivatives, so Codex could check internal
consistency ("built per the plan") but not the reading ("is the plan right"). The independent axis
had no independent reference.

- `templates/codex-audit.md` — the `gen` and `verify` input rows now include the legacy source **at
  the anchors the diff/tests cite** (bounded by B's anchors, so no context explosion). `verify`
  gains a check: open each `// legacy:` line a test cites and state whether its real condition
  matches the test's assumption.
- `agents/codex-auditor.md` already instructs "read the legacy source anchors the artifact cites"
  and defers to the rubric table — left unchanged (no duplication).

B and C interlock: B makes the reading a checkable artifact; C is the second reader that checks it.
B alone is one more rule; C alone has nothing to read.

### D. Minimal mutation check (the false-green class)

No mutation testing existed anywhere in the plugin.

- `agents/tdd-cycle-runner.md` (end of Green) + `templates/tdd-rules.md` — after a unit goes green,
  break the **one behavior just written** (delete the guard / invert the condition / drop the prop),
  confirm the test goes red, revert. Green-under-mutation means the test asserts nothing. Scoped to
  the just-written behavior (one mutation, seconds), not exhaustive mutation testing.

### Process note — confirm scope before generation

- `skills/fm-plan/SKILL.md` — resolve scope (screens, states, branches) before generation; adding a
  surface later re-enters analyze → plan → gen → all gates for it. OMH-749's largest single cost was
  scope changing four times. Deliberate reductions go in `openApprovals[]`, reusing the existing
  coverage-preservation machinery.

## How each OMH-749 defect is now caught

| # | Defect | Caught by |
| --- | --- | --- |
| 1 | warning gated on a misread condition | B (legacy anchor) + C (Codex opens the line) + D (a hollow test dies under mutation) |
| 2 | disabled button had no disabled state | scope/state coverage — the `fm-plan` note + existing 4-state coverage |
| 3 | `&apos;` rendered literally | A (entity render check, machine-enforced) |
| 4 | pager re-query legacy never did | existing `openApprovals` + the `fm-plan` scope note |
| 5 | page reset on submit | same as #4 |

## Decisions

- **Machine over prose (A)** — a render-mode rule an agent has to remember is checked by the same
  agent that could misread it. Moving it into the vitest spec makes it independent of reading
  accuracy. (The prior K3 rule was prose; that is exactly why `&apos;` slipped.)
- **Scoped anchors (B)** — blanket legacy anchors on every test would produce formalistic entries on
  v2-only tests. Restricting to legacy-behavior tests keeps the anchor meaningful.
- **Anchor-bounded legacy input (C)** — feeding whole legacy files to Codex explodes context; the B
  anchors bound it to the lines that matter.
- **One-shot mutation, not a framework (D)** — full mutation testing (Stryker etc.) is heavy and
  slow; mutating only the just-written behavior catches the common false-green at a few seconds per
  cycle. If broader coverage is ever wanted, that is a separate follow-up.

## Rejected (from the proposal; revive only with new justification)

- Auto-detecting render mode at runtime — the i18n lookup never throwing is deliberate legacy
  i18next parity; a runtime change breaks parity. Checks belong in generation/gates.
- Blanket legacy anchors on all tests — see decision above.
- Tightening the parity-gate thresholds — these defects leaked because the compared object was a
  derivative, not because thresholds were loose. Comparing the same derivative harder finds nothing.

## Acceptance

The five OMH-749 defects each map to a defense that would have gone red before release (table
above). Being instruction/template docs with no runtime target in this repo, verification is
document-consistency: the A edit points agree with `fm-verify` Step 4a; B's three anchor sites agree;
C's rubric rows agree with `codex-auditor`; D appears in both the agent and the rules template.

## Not done here (possible follow-ups)

- Full mutation testing across a file/suite (D is deliberately one-shot).
- A key→union type generated from locale resources, moving the entity/key checks to compile time.
