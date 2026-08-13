# Design — containment fidelity in generation (v1.2.0)

**Origin:** OMH-912, mobile `/event/:seq`, 2026-08-12. Reported by the page owner after the page had
already reached `parity-passed`. Every number below is measured.

## The defect

The migrated event-detail page laid its city-tab pills out past the right edge of the screen and gave
the **whole page** a horizontal scroll. Legacy does not: it is 100% wide with a 16px inset on both
sides and never scrolls sideways.

Measured on Pixel 7 (412px), the same board, the same markup, changing only the strip's CSS:

```
                          before        after
document.scrollWidth      748px         412px
page horizontal overflow  337px           0px
.promotion-tab-header     overflow-x: visible   overflow-x: auto
  its own overflow        352px         352px      ← unchanged; it moved INTO the strip
```

The strip's content was always 352px too wide. The only question was whether that overflow lived
**inside the strip** (legacy) or **escaped into the page** (v2).

Legacy's rule, `_contents.scss:1590-1596`:

```scss
.promotion-tab-header {
  display: flex;
  align-items: center;
  margin-bottom: 15px;
  overflow-x: auto;                          // ← lost
  &::-webkit-scrollbar { display: none; }    // ← structurally uncapturable
  .btn-promotion-tab { flex: none; /* … */ }
}
```

The generated component had `display:flex`, `align-items:center`, `margin-bottom:15px`, `height:40px`
and `flex-none` pills — every value the spec carried, faithfully. It was missing the two that make the
box a box.

## Three independent root causes

This is not one dropped property. Three separate mechanisms each lose containment on their own, and
all three fired on this page.

### 1. Curation by visual significance drops content-dependent properties

The raw probe **did** read the value. `style-baselines/detail-probe-raw.json`:

```json
".promotion-tab-header": { "first": { "style": { "overflow": "auto", "overflowX": "auto", … } } }
```

`style-spec.json` records:

```json
{ "key": ".promotion-tab-header", "source": "live-measured",
  "measured": { "display": "flex", "alignItems": "center", "height": "40px", "marginBottom": "15px" } }
```

The loss happened between the probe and the spec, at the step where the extractor decides which of
~50 captured properties are worth writing down. `overflow-x: auto` was dropped because on the probed
instance it did nothing: **seq 100226 has exactly one city group**, so the strip never overflowed and
the property had no observable effect at capture time.

That is the general shape: **a property whose effect depends on content volume is invisible in a
single capture.** `overflow`, `flex-wrap`, `min-width`, `text-overflow`, `white-space`,
`-webkit-line-clamp` are all in this class. A "keep what visibly matters" filter is exactly wrong for
them — they matter precisely in the case the capture did not contain.

The page had already recorded the same blind spot once, for the same element, and treated it as a
one-off: the spec notes that the INACTIVE tab styling had to come from a second seq because
"seq 100226 has a single, always-active tab". The single-instance problem was seen. That it also
erases *layout* properties, not just *state* variants, was not.

### 2. Pseudo-element rules have no computed-style surface

`::-webkit-scrollbar { display: none }` cannot be read by `getComputedStyle(el)` — the element has no
computed style for a scrollbar part. No probe over any property list will ever return it. It is not a
curation mistake; it is outside what the capture method can express.

It is also not incidental. Legacy pairs the two in **every** occurrence — three in the mobile sheets
(`_contents.scss:1037`, `_contents.scss:1593`, `_components.scss:1216`) — because a visible scrollbar
under a row of pills is not the intended design. Fixing cause 1 alone ships a scrollbar legacy does
not have.

The same hole covers `::before` / `::after` content, `::placeholder`, `::selection`, and rules inside
`@media` / `@supports` blocks the capture viewport did not match.

### 3. CSS does not cross an iframe boundary

The page renders operator-authored CMS HTML in `<iframe srcdoc>` with `scrolling="no"`. A document
authored at a fixed width — the house CMS style is a `width:750px` wrapper — is **silently clipped**
at the device width, with no gesture that can reveal the rest.

Legacy has the same defect and its authors evidently tried to fix it from the parent, at
`_contents.scss:1572-1577`:

```scss
.promotion-detail {
  iframe { * { margin: 0; padding: 0; } }   // dead code — never applies
}
```

That rule has never had any effect: a parent stylesheet cannot style inside a nested browsing
context. **Any page that injects a document into a frame has a styling surface no page-level spec,
cascade diff, or parent stylesheet can reach.** The only place it can be fixed is inside the document
being assembled.

## Insight

Containment is a **page invariant**, not an element value.

The element-indexed spec can only say "this element's `overflow-x` is `auto`". What actually matters
is "**the document's `scrollWidth` never exceeds its `clientWidth`**". These behave differently under
the thing that caused this bug — content the capture never saw:

| | element value | page invariant |
| --- | --- | --- |
| survives an unrepresentative capture | no — a 1-group strip has nothing to contain | yes — drive it with a synthetic overload |
| covers markup outside the element index | no | yes — measures the whole document |
| covers a nested browsing context | no | yes, once declared per frame |
| tells the generator *what to write* | yes | no |

So keep the element value as the generation target, and add the invariant as the thing the gate
actually asserts. Neither replaces the other.

## Design

### A. `containment` — a new style-spec axis, captured verbatim

A ninth axis alongside `frame` / `spacing` / `icons` / `alignment` / `controlGeometry` /
`colorBorder` / `typography`, holding `overflowX`, `overflowY`, `maxWidth`, `minWidth`, `flexWrap`,
`whiteSpace`, `textOverflow`, `webkitLineClamp`, `overscrollBehavior`.

The rule that makes it work is not the axis, it is the **capture discipline**: these properties are
transcribed from the probe **verbatim, including values that had no visible effect on the probed
instance**. They are exempt from the "is this worth recording" filter that every other axis is
subject to, because for this axis that filter is a defect generator.

Every non-initial value in the axis (`overflowX` ≠ `visible`, `flexWrap` ≠ `nowrap`, `maxWidth` ≠
`none`, …) is recorded even when the element fits its box.

### B. `contentDependent` — name the unrepresentative capture

An element whose containment axis was captured from an instance that **could not exercise it** — one
tab in a tab strip, one row in a list, an empty description — is flagged:

```json
"containment": { "overflowX": "auto", "contentDependent": true,
                 "why": "probed seq 100226 has 1 city group; the strip cannot overflow at n=1" }
```

`contentDependent: true` is a contract on the two downstream stages: the generator MUST implement the
value (it cannot be dismissed as "measured 0"), and the gate MUST drive it with a synthetic overload
rather than the fixture's natural content. It is also the honest record of what the capture did and
did not establish.

### C. `nonComputable[]` — the rules a probe cannot see

A new top-level spec array for rules with no `getComputedStyle` surface, resolved from the **source
cascade even on a live capture**. A live capture is not a reason to skip the source grep for these;
it is structurally incapable of returning them.

```json
"nonComputable": [
  { "selector": ".promotion-tab-header::-webkit-scrollbar",
    "kind": "pseudo-element",
    "declarations": { "display": "none" },
    "legacyAnchor": "_contents.scss:1594",
    "pairedWith": ".promotion-tab-header",
    "why": "no computed-style surface — source-resolved" }
]
```

**The overflow twin rule.** Whenever an element's captured `overflowX`/`overflowY` is not `visible`,
grep the source for a `::-webkit-scrollbar` rule on the same selector and record it. In this codebase
that pairing is 3 for 3; treat a scrolling strip with no scrollbar rule as a finding to confirm, not
a default.

### D. Injected-document containment (the frame surface)

A page whose analysis records an injected-document surface (`iframe srcdoc`, `[srcdoc]`,
`dangerouslySetInnerHTML` into a frame) gets a **containment stylesheet composed into the document
being assembled** — the only reachable place — capping it at the frame and moving the overflow into
the wide subtree rather than clipping it:

```css
html,body{max-width:100%}
body{overflow-x:hidden}
body>*{max-width:100%;overflow-x:auto;overscroll-behavior-x:contain;
       -webkit-overflow-scrolling:touch;scrollbar-width:none}
body>*::-webkit-scrollbar{display:none}
body>img,body>picture,body>video,body>svg,body>canvas{height:auto}
```

Four properties of the implementation are load-bearing:

- **Composed after sanitisation.** The trust boundary applies to operator content; our own stylesheet
  must not be run through a config tuned for untrusted markup.
- **First child, no `!important`.** Equal specificity, later wins — the operator keeps the last word
  on their own document.
- **Marked and idempotent.** A client-side re-parse of an already-composed document (in-app link
  rewrites, hydration re-derivation) must not stack a second sheet per render.
- **Declared as a deviation.** Legacy *clips*; this *scrolls*. That is a behaviour change on a sealed
  legacy port, so it is an `acceptedDeltas[]` entry with a decision owner, not a silent improvement.

### E. The containment invariant — a gate axis, on every page

Added to `templates/visual-parity-checklist.md` as an axis in its own right, and to the e2e scenario
set. Asserted on the v2 render at every viewport × language in the gate's matrix:

```
document.documentElement.scrollWidth <= document.documentElement.clientWidth
```

…plus, for each element carrying `contentDependent: true`, drive a synthetic overload first and then
assert **both** halves — that the element really did overflow (the test is not vacuous), and that the
page absorbed none of it:

```js
strip.scrollWidth - strip.clientWidth  >  0   // the row outgrew its box…
docEl.scrollWidth  - docEl.clientWidth <= 0   // …and the page did not grow
```

The first half is **per-axis**: the strip above is a horizontal scroller, so it proves engagement
on `scrollWidth`; a vertical scroller or a `-webkit-line-clamp` proves it on
`scrollHeight - clientHeight > 0`; a `flex-wrap: wrap` proves it by wrapping — growing taller with
**no** horizontal overflow, because horizontal overflow is the wrap failing; a size cap
(`max-width`/`min-width`) proves it by holding the box at the cap under the overload; and
`overscroll-behavior` has no overload metric at all — it is asserted as a computed value. The
horizontal pair asserted blindly on a wrap/clamp element fails a correct implementation. The second
half is universal.

…plus, for each injected-document frame: the frame element's width ≤ the viewport, and the frame
document's own `body` computes `overflow-x: hidden`.

This is the only one of the five parts that catches the failure **without knowing which element
caused it** — which is why it is the gate item and the rest are generation inputs.

## Why the existing stages all missed it

| Stage | Why it passed |
| --- | --- |
| `fm-style-spec` | captured the value, then curated it away as visually insignificant at n=1 |
| generated unit tests | jsdom applies no stylesheet — no CSS assertion is possible there |
| `fm-verify` | build / types / lint / unit: none of them can observe layout |
| `fm-e2e` | asserted behaviour (which products show for which tab), never geometry |
| `fm-parity` | compared a screenshot of the **default** render, where the fixture's 1–2 short tabs fit |
| `fm-cascade` | diffs stylesheets over the page's own DOM; blind inside the iframe, and the missing rule was in neither sheet |

The common thread: every stage looked at the content it was handed. None asked what happens when
there is more of it.

## Error types closed (extends the table in `templates/style-spec.md`)

| Type | What goes wrong | Closed by |
| --- | --- | --- |
| G content-dependent property dropped | `overflow-x`/`flex-wrap`/`min-width` captured at n=1, curated away as no-op, page scrolls sideways at n=6 | verbatim `containment` capture + `contentDependent` flag + synthetic-overload gate (A, B, E) |
| H non-computable rule | `::-webkit-scrollbar`, `::placeholder`, `@media`-conditional rules — no `getComputedStyle` surface, invisible to any probe | `nonComputable[]` resolved from source + the overflow twin rule (C) |
| I unreachable nested context | a document injected into a frame; no parent sheet, spec, or cascade diff can reach it — legacy's own attempt at it is dead code | containment sheet composed into the document, declared as an accepted delta (D) |

## Files

| File | Change |
| --- | --- |
| `templates/style-spec.md` | `containment` axis; `contentDependent`; `nonComputable[]`; the verbatim-capture rule |
| `agents/style-spec-extractor.md` | capture containment verbatim; the overflow twin grep; flag unrepresentative instances |
| `agents/tdd-cycle-runner.md` | build the containment axis; the no-horizontal-page-scroll invariant; the injected-document sheet |
| `templates/visual-parity-checklist.md` | **Containment & overflow** as an axis, with the synthetic-overload protocol |
| `agents/parity-verifier.md` | probe the invariant; drive `contentDependent` elements |
| `agents/e2e-test-runner.md` | a standing overload scenario per `contentDependent` element |

## Decisions

- **New axis vs widening `frame`** → new axis. `frame` is "how big is this box"; containment is "what
  happens when the content does not fit". They have different capture rules (verbatim vs curated) and
  different gate protocols (static probe vs synthetic overload), and folding them would put the
  verbatim rule on properties that do not need it.
- **Gate invariant vs more probes** → both, and the invariant is primary. A probe set only catches
  what it enumerates; the page-scroll invariant catches the failure regardless of which element
  caused it, including elements no index contains.
- **Frame containment: scroll vs clip** → scroll, as an explicit accepted delta. Clipping is legacy's
  behaviour and reproducing it is defensible, but it makes content unreachable with no affordance;
  the deviation is small, contained, and owner-approved. The rule is that it is *recorded* as a
  deviation — a page that silently improves on legacy is the same class of problem as one that
  silently regresses.

## Acceptance

For any migrated page, at every viewport × language in the gate matrix: the document has no
horizontal overflow in the default render **and** after driving a synthetic overload into every
element the spec flags `contentDependent`; every injected-document frame is ≤ the viewport with its
own document capped; and every `nonComputable[]` entry has a counterpart rule in the v2 stylesheet.

## Not done here (possible follow-ups)

- A `containment` stage in `codexAuditStages` (independent second read of the axis).
- Extending `fm-cascade` to diff **inside** injected documents — it currently stops at the frame
  boundary, which is where cause 3 lives.
- Deriving the overload size from the legacy data (max observed city groups per board) instead of a
  fixed synthetic pad.
