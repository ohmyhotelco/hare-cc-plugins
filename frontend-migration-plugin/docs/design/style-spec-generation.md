# Design — style-spec generation (v0.9.0)

## Problem

`fm-parity`'s `visual-parity-checklist.md` (shipped in the prior release, v0.8.3) hardened the
**gate** that catches wrong styles just before a route flip. But the gate runs at flip time, after the fact — if generation keeps
producing wrong styles, every page burns a gate cycle on post-hoc fixes. The OMH-708 event page
passed its gates yet diverged from legacy in ~a dozen places (tab pills flat, card radius 15 vs 25,
rating stars invisible, iframe side padding, a flattened wrapper box).

Root cause is structural, not a one-off mistake:

- `angular-analyzer` recorded only "`.scss` presence/scale; **style port is manual**".
- `tdd-cycle-runner` received **no style input** — it cloned legacy markup (tags + class names) and
  styles were eyeballed into Tailwind.
- Two traps amplify it: the real styles live in **global** sheets (`base.css`, `_contents.scss`),
  not the component `.scss` (often empty); and committed CSS can be **stale** vs the live deploy
  (a button was 52/15 in source, 48/10 live). Same class name, different render — faithful-looking,
  actually wrong.

## Insight

The capability to read live-legacy computed styles **already exists** in the plugin — the
`parity-verifier` visual gate captures legacy with Playwright and pins values via computed-style
probes. The only gap is **timing**: that truth is produced at the back of the pipeline, not fed to
generation at the front. So the fix is to **hoist that capture to the front** as a reusable artifact.

## Design

A per-page **`style-spec.json`** — the legacy style answer key — produced by a new
`fm-style-spec` stage between `fm-analyze` and `fm-plan`, consumed by `fm-gen`, and reused by
`fm-parity`. One legacy-truth source, used **front** (generation target) and **back** (gate probe),
so the two cannot drift.

```
fm-analyze → fm-style-spec → fm-plan → fm-gen → fm-verify → fm-e2e → fm-parity → fm-route
(styleSurface)  (style-spec)            (build to it)                (reuse baseline)

state: analyzed → style-specced → planned → generated → …
```

### Components

- **`agents/angular-analyzer.md`** — retires "style port is manual"; emits a `styleSurface` **map**:
  per element, its classes, the **global** sheets where the rules live, asset refs, and nesting
  structure. This is *where the styles are*, not their values.
- **`skills/fm-style-spec/SKILL.md`** + **`agents/style-spec-extractor.md`** (new) — resolve the
  **values**. Live-first: a **standalone Playwright probe** (no app harness needed — `npx playwright`
  is verified by `fm-init`) navigates the live legacy URL and reads `getComputedStyle` per element
  per axis, plus an asset inventory. Fallback: source-cascade resolution flagged `source-derived` /
  `unconfirmed` when the URL is unreachable — never blocks. Writes `style-spec.json`; sets
  `style-specced`.
- **`templates/style-spec.md`** (new) — the schema + live-first rule + confidence flags, organized
  along the **same axes** as `visual-parity-checklist.md`.
- **`agents/migration-planner.md`** / **`migration-plan-schema.md`** — each `componentTree` node gets
  `styleTargets` (its spec elements + assets + structure); `gateAcceptance.visual` binds its probe
  set to the spec's `live-confirmed` values.
- **`agents/foundation-generator.md`** — copies the inventoried assets into the app's public dir
  (fills the prior asset gap — the wholesale-omission trap).
- **`agents/tdd-cycle-runner.md`** (component/page) — builds to the spec values; "a class name is not
  evidence of style", no eyeballing, preserve structure, self-verify.
- **`agents/parity-verifier.md`** / **`visual-parity-checklist.md`** — reuse the spec's captured
  baseline instead of a second, possibly divergent capture.
- **`fm-delta`** / **`delta-modifier`** — on visual/style drift, refresh `style-spec.json` first,
  then build the delta to it.

### Live-first (confidence)

Each value is `live-confirmed` (from the live render — the target) or `source-derived` (cascade
fallback, `unconfirmed`, re-checked by `fm-parity`). Live always wins over committed CSS (trap F).

## Error types closed

| Type | Was | Closed by |
| --- | --- | --- |
| A eyeball approximation | radius/weight/margin/grid off | exact `axes` values are the target; no approximation |
| B global class / asset omission | class name rendered, CSS/asset absent | global-sheet cascade + asset inventory + `foundation-generator` copies them |
| C invisible CSS trick | iframe bleed, section padding | computed style captures it regardless of markup |
| D markup flattening | one box split into siblings | `structure[]` records the wrapper; generator preserves it |
| F stale source | 52/15 source vs 48/10 live | `live-confirmed` computed supersedes committed CSS |

## Decisions

- **New stage vs fold-in** → new `fm-style-spec` stage + `style-spec.json` artifact + `style-specced`
  state. Explicit, resumable, cleanly separated (the live capture is environment-dependent; keeping
  it its own stage keeps `fm-analyze` static and fast).
- **Live capture** → live-first with static fallback. The strongest fix (handles stale source) while
  degrading gracefully when the legacy page is unreachable at generation time; `fm-parity` stays the
  backstop.

## Acceptance

For any migrated page, live legacy vs new side-by-side, per-element `getComputedStyle` per axis:
structural properties match, only `acceptedDeltas` recorded. Verified up front (the generation
target) and again at `fm-parity` (same baseline) — they agree because they share one source.

## Not done here (possible follow-ups)

- A `style-spec` stage in `codexAuditStages` (independent second check of the spec).
- Automating the legacy-URL resolution per page (currently config domain / staging + route, else
  prompt / static fallback).
