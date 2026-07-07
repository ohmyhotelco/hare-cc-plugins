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
baseline rather than capturing a second, possibly divergent one.

## Why this exists — the cross-framework pixel trap

The legacy apps are Angular; the v2 apps are React. Their DOM, font stacks, and sub-pixel rendering
differ enough that a symmetric `toHaveScreenshot(legacy) === toHaveScreenshot(v2)` pixel diff **cannot
pass** at any sane tolerance — the two engines never rasterize identically. So the gate legitimately
falls back to **per-side baselines plus computed-style probes**: legacy is captured to `legacy-*.png`,
v2 to its own `*.png`, and legacy-derived CSS tokens are pinned by `getComputedStyle` probes.

That fallback has TWO failure modes this checklist exists to prevent:

1. **The self-referential baseline.** Once v2 is captured to its own baseline, every later run compares
   v2 against **itself**, not against legacy. If that first capture already encodes a divergence from
   legacy (wrong spacing, wrong icon, wrong alignment), the gate is green forever and the regression
   ships. A v2 baseline is **not the reference — legacy is.** Never treat a first v2 capture as truth;
   it is only truth once it has been checked axis-by-axis against the legacy render.
2. **The incomplete probe set.** Computed-style probes only catch what they explicitly assert. A probe
   set that pins card color, radius, padding, and fonts but omits inter-element spacing or icon
   rendering will pass a page whose pager sits flush against the list or whose accordion toggle is the
   wrong glyph. **Pinning some axes is not pinning parity.** Every axis below must be covered.

## Protocol when a pixel diff is impossible (the normal PC case)

1. Capture legacy and v2 to per-side baselines (symmetric viewport / scope / masking).
2. **Side-by-side compare** the legacy screenshot and the v2 screenshot, axis by axis, against the
   checklist below. This is a human-or-probe comparison of the two *renders*, not each render against
   its own baseline. A difference on any axis is a diff to itemize (fix, or explicitly-accepted delta).
3. For every axis that is content-independent, add a **computed-style probe** (host-runnable) pinning
   the legacy-derived value on v2, so the axis is guarded deterministically in CI — not just by a human
   glance. The probe set must cover **every** axis below, not a subset.
4. Only after the side-by-side + probes agree the v2 render matches legacy (or the diffs are recorded
   as accepted deltas) is the v2 baseline allowed to stand.

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

## Lift-out interaction (public pages shed the my-page shell)

When a page is lifted out of an authenticated shell, the shed chrome (sidebar, two-column layout) is an
**accepted delta** recorded in `acceptedDeltas[]` — but the lift-out often changes the content-area
**width**, which in turn moves the absolute position of centered controls (e.g. a pager). Do not
conflate the two: the shed shell is accepted, but any axis diff *inside* the compared content-area
(spacing, icon, alignment) is still a parity item to fix or explicitly accept — never folded silently
into "it's just the lift-out."
