# Visual Parity Checklist

The complete set of visual axes the `parity-verifier` `visual` gate must compare — and the protocol
to follow when a true legacy↔v2 pixel diff is impossible. This is the single source of truth that
`agents/parity-verifier.md` (the gate) and `skills/fm-parity/SKILL.md` (the inspection step) both
point at. `migration-planner` folds these axes into every page's `gateAcceptance.visual` so the plan
codifies them up front.

**Same axes, front and back.** These axes are also the shape of `templates/style-spec.md` — the
legacy values `fm-style-spec` captures **before** generation as the target (`tdd-cycle-runner` builds
to them). This checklist is the **back** (the gate re-probes the same values); the style-spec is the
**front** (generation aims at them). One legacy-truth source, so a green gate means generation hit
the target, not that a divergent v2 baseline was blessed. The gate reuses the spec's captured
baseline — the computed-style values (always) and, on a live capture, the legacy screenshot at
`legacySource.screenshot` — rather than capturing a second, possibly divergent one; it re-captures
legacy only when the spec was a `source-fallback` (no screenshot), when the spec's
`legacySource.provenance.side` does not resolve to `legacy` (step 0), or to refresh a `source-derived`
value.

## Why this exists — the cross-framework pixel trap

The legacy apps are Angular; the v2 apps are React. Their DOM, font stacks, and sub-pixel rendering
differ enough that a symmetric `toHaveScreenshot(legacy) === toHaveScreenshot(v2)` pixel diff **cannot
pass** at any sane tolerance — the two engines never rasterize identically. So the gate legitimately
falls back to **per-side baselines plus computed-style probes**: legacy is captured to `legacy-*.png`,
v2 to its own `*.png`, and legacy-derived CSS tokens are pinned by `getComputedStyle` probes.

That fallback has THREE failure modes this checklist exists to prevent:

1. **The self-referential baseline.** Once v2 is captured to its own baseline, every later run compares
   v2 against **itself**, not against legacy. If that first capture already encodes a divergence from
   legacy (wrong spacing, wrong icon, wrong alignment), the gate is green forever and the regression
   ships. A v2 baseline is **not the reference — legacy is.** Never treat a first v2 capture as truth;
   it is only truth once it has been checked axis-by-axis against the legacy render.
2. **The incomplete probe set.** Computed-style probes only catch what they explicitly assert. A probe
   set that pins card color, radius, padding, and fonts but omits inter-element spacing or icon
   rendering will pass a page whose pager sits flush against the list or whose accordion toggle is the
   wrong glyph. **Pinning some axes is not pinning parity.** Every axis below must be covered.
3. **The unverified side.** Per-side baselines make the *file* the carrier of "this is the legacy
   render" — and a file only claims that through its name. A v2 render saved as `legacy-ko-1440.png`
   satisfies every later step: step 1 has its two files, the side-by-side compares them, the probes
   pin values, the gate goes green. Nothing in the axis list ever asks whether the legacy-side
   artifact came from legacy. It has already passed that way twice (a contract gate reading a v2
   capture as legacy; a visual gate passing on three non-legacy "legacy screenshots"). **A file name
   is a claim, not provenance** — hence step 0 below.

## When this gate is BLOCKED — what still can be measured

This gate needs both hosts live, which makes it the stage most often blocked (a dead legacy host, an
unbuilt dependency, a scenario waiting on another milestone). A blocked visual gate is `not-run`, and
`not-run` is never a pass — but it is also not a reason to record no style evidence at all.

`fm-cascade` measures the stylesheet half of this comparison from legacy's **compiled CSS alone**, no
legacy host required: same markup, same engine, same viewport, stylesheet as the only variable,
diffed over every node. It cannot replace this gate — it is blind to assets, fonts, real layout, and
anything outside its property list — but it converts "we know nothing" into "we know the rules
agree", which is most of what a blocked page is missing. Run it and say in the report which half was
covered and which was not. See `templates/cascade-diff.md`.

The converse also holds and is worth stating in any report that passes this gate: a screenshot
comparison is a *sample* of the cascade. It confirms the pixels it photographed, at the viewports it
used, in the states it drove — it does not establish that the two stylesheets agree. When both stages
have run, say so; when only one has, say which.

## Protocol when a pixel diff is impossible (the normal PC case)

0. **Resolve both sides' provenance before comparing anything.** For each artifact you are about to
   treat as the legacy side and the v2 side, read its recorded `provenance`
   (`templates/capture-provenance.md`) and resolve `side` from `origin`'s host:port against config
   (`apps.*.legacyPort` / `apps.*.port` / the declared legacy host, plus whether `tracker.json` records
   the path as flipped — after a flip the production host serves v2, so the host alone no longer
   decides). Do not infer the side from the file name, the directory, or a previous report's prose.
   An artifact whose side does not resolve is **absent**: the axes it was supposed to carry are
   uncovered, which is an incomplete gate (`fail`) — the same verdict as an unprobed axis — and the
   fix is to capture that side yourself, not to accept the file on the strength of its name. Applies
   to captures taken from here on; artifacts predating the rule stay origin-unknown and are not
   retro-filled or re-adjudicated.
1. Capture legacy and v2 to per-side baselines (symmetric viewport / scope / masking), each carrying
   its own `provenance` block written at capture time.
2. **Side-by-side compare** the legacy screenshot and the v2 screenshot, axis by axis, against the
   checklist below. This is a human-or-probe comparison of the two *renders*, not each render against
   its own baseline. A difference on any axis is a diff to itemize (fix, or explicitly-accepted delta).
3. For every axis that is content-independent, add a **computed-style probe** (host-runnable) pinning
   the legacy-derived value on v2, so the axis is guarded deterministically in CI — not just by a human
   glance. The probe set must cover **every** axis below, not a subset.
4. Only after the side-by-side + probes agree the v2 render matches legacy (or the diffs are recorded
   as accepted deltas) is the v2 baseline allowed to stand.

## States — the axes are compared in every planned state, not just the default render

A screenshot captures whatever state the page happened to be in. Error text, a session-expired
title, and an empty-list message never appear in the default render, so a default-only capture is
blind to them **permanently** — no amount of axis coverage helps if the pixels were never taken.
That is how a literal `<br/>` shipped in a session-expired modal title (OMH-748).

So drive the page into each state the plan records (`gateAcceptance.visual.states`, derived from
`copyBindings` + the analysis) and capture there, symmetrically on both apps. Typical states:
default, **error shown** (per failure surface), **session expired**, empty/zero-result, and loading
where it is a distinct rendered state. Every axis below applies within each state.

Coverage is the full matrix — states × the languages in `gateAcceptance.visual.languages`
(= config `i18n.languages`; `scope` is the prose description, `languages` is the field to read).
Capturing every state in every language is expensive, so a reduction is a legitimate thing to ask
for and an **illegitimate thing to assume**: record it in `openApprovals[]` with its rationale and
decision owner, exactly as with any other scope reduction. An author's cost trade-off is not a
decision.

## The axes — every one must be compared AND (where content-independent) probed

- **Frame & container** — width, max-width, centering (`margin:auto`), outer padding. (The 1200px
  content-area class, etc.)
- **Inter-element spacing / gaps** — the margins and gaps *between* blocks, not just padding *inside*
  them: list↔pager gap, section↔section, item↔item, title↔body, search↔list. **This is the most
  commonly-missed axis** — a probe on card padding does NOT cover the gap above the pager.
- **Icons & glyphs** — every sprite / icon / marker: does it exist, and is its **render** faithful
  (a legacy PNG sprite ported as an SVG, not a lookalike unicode character), at the right **position**
  (e.g. absolute `right center` vs an inline flex item), **size**, and state changes (open/active,
  hover, disabled)? Chevrons, toggles, arrows, badges, Q/A markers.
- **Alignment** — text and control alignment (left / center / right), and whether a control is
  centered within its *own* container vs the *page* (a lift-out width change moves a centered control's
  absolute x — itemize it, don't silently accept it).
- **Control geometry** — size and position of interactive controls: pager buttons, search box/button,
  tabs, filters. Shape (circle/pill/box), dimensions, hit area.
- **Color / fill / border** — background, text, border color and the active/hover/disabled variants;
  border radius; border width/style.
- **Typography** — font family, size, weight, line-height, letter-spacing, tabular-nums — the wrapper
  frame's typography context (CMS-inline internals are exempt only where the plan says so).
- **Containment & overflow** — what happens when the content does *not* fit. Unlike every other axis
  this one is **not** settled by comparing the default render, because in the default render there is
  usually nothing to contain. See the protocol below.

### Containment: the axis a screenshot cannot decide

A screenshot compares the content the fixture happened to have. `overflow`, `flex-wrap`, `min-width`,
`white-space` and `-webkit-line-clamp` only do anything when there is *more* of it, so a default-only
comparison is permanently blind to them — the same structural blindness the **States** section
describes, along a different dimension.

That is how OMH-912 mobile `/event/:seq` passed this gate and shipped with **337px** of horizontal
page scroll (`document.scrollWidth` 748 on a 412 viewport), the city-tab pills hanging past the right
edge: the fixture had two short tabs, they fit, the screenshots matched. Legacy's
`overflow-x: auto` + `::-webkit-scrollbar{display:none}` (`_contents.scss:1590-1596`) was never
reproduced, and nothing in this checklist asked.

**Protocol — assert the invariant, not just the values.** At every viewport × language in the matrix:

1. **The page invariant, on the default render.**
   `document.documentElement.scrollWidth <= document.documentElement.clientWidth`. This is the item
   that catches the failure **without knowing which element caused it** — including elements the
   style-spec index does not contain.
2. **Synthetic overload for every `contentDependent` element** the spec flags. Drive real overflow
   into it (pad the labels, add rows), then assert **both** halves: engagement **on the axis the
   property controls** — horizontal (`overflowX`, `whiteSpace: nowrap`, `textOverflow`):
   `el.scrollWidth - el.clientWidth > 0`; vertical (`overflowY`, `webkitLineClamp`):
   `el.scrollHeight - el.clientHeight > 0`; `flexWrap: wrap`: the children wrapped and
   `el.scrollWidth <= el.clientWidth`, because horizontal overflow IS the wrap failing — **and** the
   page invariant above still holds. Asserting only the second half passes a test that never
   overflowed anything; asserting the horizontal pair on a wrap/clamp element fails a correct
   implementation.
3. **Injected-document frames** (`structure[].injectedDocument`): the frame element's width ≤ the
   viewport, and the frame's own `document.body` computes `overflow-x: hidden`. Nothing outside the
   frame can establish this — a parent-side probe reads the parent's box, not the document's.
4. **`nonComputable[]` counterparts.** Each entry (`::-webkit-scrollbar`, `::placeholder`, …) has a
   matching rule in the v2 stylesheet. These have no `getComputedStyle` surface, so this is a
   stylesheet check, not a probe.

Design: `docs/design/containment-fidelity-generation.md`.

## Lift-out interaction (public pages shed the my-page shell)

When a page is lifted out of an authenticated shell, the shed chrome (sidebar, two-column layout) is an
**accepted delta** recorded in `acceptedDeltas[]` — but the lift-out often changes the content-area
**width**, which in turn moves the absolute position of centered controls (e.g. a pager). Do not
conflate the two: the shed shell is accepted, but any axis diff *inside* the compared content-area
(spacing, icon, alignment) is still a parity item to fix or explicitly accept — never folded silently
into "it's just the lift-out."
