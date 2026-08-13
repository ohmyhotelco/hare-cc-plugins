# style-spec.json — the generation-time style answer key

The per-page style target that `fm-style-spec` produces, `fm-gen` consumes, and `fm-parity`
reuses. One artifact, used **front** (the values generation must hit) and **back** (the values the
parity gate probes) — so there is a single legacy-truth source for style, not two that can drift.

`agents/style-spec-extractor.md` writes it; `agents/tdd-cycle-runner.md` (component phase) and
`agents/foundation-generator.md` (assets) read it; `agents/parity-verifier.md` reuses its captured
baseline instead of re-capturing legacy. It is organized along the **same axes** as
`templates/visual-parity-checklist.md`, deliberately: the checklist is the gate's axis list; this
is those axes filled with legacy values up front.

## Why this exists — style is generated blind today

`angular-analyzer` used to record only "`.scss` presence/scale; style port is manual", and
`tdd-cycle-runner` receives no style input — so a component faithfully clones the legacy markup
(tags + class names) while its styles are eyeballed into Tailwind. Same class name, different
render: the migration *looks* faithful but is not. Two traps make this worse:

- **The real styles are global, not co-located.** A component's own `.scss` is often empty; the
  actual rules live in global sheets (`base.css`, `_contents.scss`). Reading the component file
  misses where the styles are.
- **Committed CSS ≠ live deploy.** A button was `52px/15px` in the committed source but
  `48px/10px` live. The source lies; only the **live render** is ground truth.

## Live-first rule (trap F)

The authoritative value of every axis is the **live legacy render's `getComputedStyle`**, captured
by `style-spec-extractor` with a standalone Playwright probe against the resolved legacy URL — not
the committed CSS. Each value carries a `confidence`:

- `live-confirmed` — read from the live render. This is the target.
- `source-derived` — the live URL was unreachable, so the value came from resolving the source
  cascade (global sheets included). Usable as a target but flagged `unconfirmed`; the `fm-parity`
  visual gate remains the backstop that catches any residual divergence.

Never downgrade a `live-confirmed` value to a source value; live always wins.

When captured live, the extractor also saves a **full-page legacy screenshot**
(`legacySource.screenshot`) at the recorded viewport — the reusable legacy baseline `fm-parity`
compares the v2 render against, so the visual gate does not re-capture a second, possibly divergent
legacy baseline. On source-fallback there is no screenshot (`null`), and `fm-parity` captures legacy
itself.

## Provenance — what makes this the legacy side (`templates/capture-provenance.md`)

`legacySource` carries the `provenance` block defined in `templates/capture-provenance.md`, written
by the probe as it captures: `origin` (the URL it actually loaded, host:port included), `side`,
`authState`, `renderSource`, `responseSource`, `captureMode`, `capturedAt`, `viewport`, and `partial`.
This is what makes the values and the screenshot count as **legacy** evidence — the file's location
and the `legacy-` prefix on its name do not. `fm-parity` re-resolves `side` before it reuses this
baseline, and an unresolved side means the baseline is treated as absent (the gate captures legacy
itself, or reports the axis as uncovered).

The enums are closed. The old `capturedFrom` field is **deprecated**: it packed reach and auth state
into one string, so pages invented values for it (five distinct hand-written values against two
defined ones, including a full sentence, which is how a `null`-URL entry came to read as an
authenticated capture). Read `capturedFrom` when an older spec has it; never write it. What it
carried now lives in three places — reach in `renderSource`, session in `authState`, and "partial"
in the `partial` object, which records **what was not reached and why** instead of hiding it in a
value name.

## Classname ≠ style evidence

A legacy class name on a v2 element is **not** evidence its style was reproduced. The generation
target is this spec's computed values; keeping legacy class names is fine for traceability, but the
generator must reproduce the values and self-verify — never approximate ("close enough") and never
treat "the class name matches" as done.

## The axes (shared with `visual-parity-checklist.md`)

Every element records the axes relevant to it. Keys mirror the checklist so the generation target
and the gate probe speak one language:

- `frame` — width, max-width, centering (`margin:auto`), outer padding.
- `spacing` — inter-element margins/gaps (the most-missed axis): item↔item, title↔body,
  section↔section, list↔pager. Negative margins/bleeds (e.g. an iframe `-8px` left/right) live here
  and are captured by computed style even when invisible in markup (trap C).
- `icons` — every sprite/icon/marker: existence, faithful render (a legacy PNG sprite ported as an
  SVG, not a lookalike glyph), position, size, and state variants. Backed by an `assets` entry.
- `alignment` — text/control alignment, and whether a control centers within its own container vs
  the page.
- `controlGeometry` — size/shape of interactive controls (pills, pager buttons, tabs): dimensions,
  border-radius, hit area.
- `colorBorder` — background/text/border color + active/hover/disabled variants; radius; border.
- `typography` — font-family, size, weight, line-height, letter-spacing, tabular-nums.
- `containment` — what happens when the content does **not** fit: `overflowX`, `overflowY`,
  `maxWidth`, `minWidth`, `flexWrap`, `whiteSpace`, `textOverflow`, `webkitLineClamp`,
  `overscrollBehavior`. Distinct from `frame` ("how big is this box") and captured under a different
  rule — see below.

### `containment` is captured VERBATIM (trap G)

Every other axis is curated: the extractor records what visibly matters. For `containment` that
filter is a defect generator, because these properties **do nothing until the content overflows**, and
a probe of one instance routinely has no overflow to observe.

The failure this rule exists to stop, measured on OMH-912 mobile `/event/:seq`: the raw probe read
`overflowX: "auto"` on `.promotion-tab-header`; the spec recorded only
`display/alignItems/height/marginBottom`, because the probed board had **one** city group and the
strip therefore could not overflow. The generated strip shipped without it, and a real board's tabs
gave the whole page **337px** of horizontal scroll with the pills hanging past the right edge
(`document.scrollWidth` 748 vs a 412 viewport). Legacy's rule was three lines away in
`_contents.scss:1590-1596` the whole time.

So: transcribe every non-initial containment value from the probe **even when the probed instance had
nothing to contain**. `overflowX` ≠ `visible`, `flexWrap` ≠ `nowrap`, `maxWidth` ≠ `none`,
`whiteSpace` ≠ `normal` are all recorded on sight, with no "does this matter here" judgement.

When the probed instance **could not exercise** the axis — one tab in a tab strip, one row in a list,
an empty description — say so:

```json
"containment": { "overflowX": "auto", "contentDependent": true,
                 "why": "probed seq 100226 has 1 city group; the strip cannot overflow at n=1" }
```

`contentDependent: true` binds both downstream stages: `tdd-cycle-runner` MUST implement the value
(it is not dismissible as "measured 0"), and the gate MUST drive the element with a **synthetic
overload** instead of the fixture's natural content. It is also the honest record of what the capture
did and did not establish.

## Non-computable rules (trap H)

`getComputedStyle(el)` has no surface for a scrollbar part, so `::-webkit-scrollbar { display: none }`
is invisible to **any** probe over **any** property list. This is not a curation mistake — it is
outside what the capture method can express. The same hole covers `::before`/`::after` content,
`::placeholder`, `::selection`, and rules inside `@media`/`@supports` blocks the capture viewport did
not match.

These are resolved from the **source cascade even on a live capture** (a live capture is not a reason
to skip the grep — it is structurally incapable of returning them) and recorded in a top-level
`nonComputable[]`:

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

**The overflow twin rule.** Whenever a captured `overflowX`/`overflowY` is not `visible`, grep the
source for a `::-webkit-scrollbar` rule on the same selector and record it. In the legacy mobile
sheets that pairing is 3 for 3 (`_contents.scss:1037`, `_contents.scss:1593`, `_components.scss:1216`)
— a scrolling strip with **no** scrollbar rule is a finding to confirm, not a default. Fixing the
overflow without its twin ships a visible scrollbar legacy does not have.

## Injected documents are unreachable from here (trap I)

A page that renders operator HTML into a nested browsing context (`iframe srcdoc`, `[srcdoc]`) has a
styling surface **no** page-level artifact can reach: not this spec, not `fm-cascade`, not the parent
stylesheet. Legacy's own attempt at it is dead code — `_contents.scss:1572-1577` declares
`.promotion-detail iframe * { margin:0; padding:0 }`, which has never applied to anything, because a
parent sheet cannot cross the boundary.

Record the frame as one element (its own box is real and worth capturing) and add a `structure[]`
entry naming it an **injected-document surface**, so `tdd-cycle-runner` composes the containment
stylesheet into the document it assembles — the only reachable place. Do not treat the frame's entry
as coverage of its contents. See `docs/design/containment-fidelity-generation.md` §D.

## Structure (trap D)

Markup nesting is part of the spec, not incidental. When legacy wraps several blocks in one box
(e.g. a single `.promotion-detail` wrapping the marketing iframe **and** the recommendations via
`ngTemplateOutlet`), the spec records that wrapper so the generator preserves the box instead of
flattening the children into siblings (which drops the wrapping border). Flattening a recorded
wrapper is a defect, not a style choice.

## Assets (trap B)

Every `background-image` / sprite / icon-font the page's classes reference is inventoried so
`foundation-generator` copies it into the v2 app and wires the reference — a class rendered without
its asset (the star sprite, the tab pill background) is invisible or flat. Each entry records **both**
`liveUrl` (what the live render loaded) and `localPath` (the file under `legacyDir`, or `null` when
the asset is live-only / CDN / cache-busted): `foundation-generator` copies `localPath` when present
and otherwise **fetches `liveUrl`**, so a live-only asset is never silently missed. An
`icons`/`colorBorder` value that depends on an asset must have a matching `assets[]` entry.

## Shape

```jsonc
{
  "app": "pc",
  "page": "event",
  "analysisRef": "docs/migration/pc/event/analysis.json",
  "legacySource": {
    "url": "https://www.ohmyhotel.com/ko/event",   // the live URL probed, or null
    "screenshot": "docs/migration/pc/event/legacy-baseline.png",  // full-page legacy capture; null on source-fallback
    "provenance": {                                // templates/capture-provenance.md — written by the probe
      "origin": "https://www.ohmyhotel.com/ko/event",   // full URL incl. host:port; on fallback, the URL attempted
      "side": "legacy",                            // legacy | v2 | unresolved (resolved from host:port + flip state)
      "authState": "anonymous",                    // anonymous | authenticated
      "renderSource": "live",                      // live | source-fallback
      "responseSource": "backend",                 // backend | stubbed
      "captureMode": "playwright-probe",           // playwright-probe | playwright-screenshot | playwright-route-intercept | source-cascade
      "capturedAt": "ISO-8601",
      "viewport": { "width": 1280, "height": 800 },
      "partial": null                              // else { reached, notReached, why }
    }
  },
  "elements": [
    {
      "selector": ".btn-promotion-tab",              // stable selector / legacy class
      "instanceSelector": ".btn-promotion-tab.active",// the specific instance/state probed, when it matters
      "role": "city tab (pill button)",
      "legacyAnchor": "event.component.html:42",
      "confidence": "live-confirmed",                // live-confirmed | source-derived
      "states": ["active", "inactive"],              // the state variants captured (from styleSurface.states)
      "axes": {
        "frame":           { "padding": "8px 16px" },
        "controlGeometry": { "borderRadius": "16px", "height": "32px" },
        "colorBorder":     { "background": "#ff7a00", "color": "#fff", "border": "none",
                             "states": { "inactive": { "background": "#fff", "color": "#333",
                                                       "border": "1px solid #ddd" } } },
        "typography":      { "fontSize": "14px", "fontWeight": "500", "lineHeight": "20px" },
        "spacing":         { "marginRight": "8px" }
      }
    },
    {
      "selector": ".promotion-tab-header",           // the scroll container the pills sit in
      "role": "city tab strip",
      "legacyAnchor": "_contents.scss:1590",
      "confidence": "live-confirmed",
      "axes": {
        "frame":       { "height": "40px" },
        "spacing":     { "marginBottom": "15px" },
        // VERBATIM — recorded although the probed board had ONE tab and could not overflow.
        "containment": { "overflowX": "auto", "flexWrap": "nowrap",
                         "contentDependent": true,
                         "why": "probed seq 100226 has 1 city group; cannot overflow at n=1" }
      }
    },
    {
      "selector": ".rate-star",
      "role": "hotel rating star",
      "legacyAnchor": "_contents.scss:210",
      "confidence": "live-confirmed",
      "axes": { "icons": { "backgroundImage": "url(/assets/images/sprite-rate.png)",
                           "backgroundPosition": "0 -20px", "width": "16px", "height": "16px" } }
    }
  ],
  "assets": [
    { "kind": "sprite", "liveUrl": "https://www.ohmyhotel.com/assets/images/sprite-rate.png",
      "localPath": "apps/legacy-pc/src/assets/images/sprite-rate.png",   // null if live-only / CDN / cache-busted
      "usedBy": ".rate-star", "cssProp": "background-image",
      "action": "copy localPath (or fetch liveUrl) to apps/web-pc/public/assets/images/ and reference" }
  ],
  "structure": [
    { "wrapper": ".promotion-detail", "wraps": ["iframe.marketing", ".recommend-products"],
      "legacyAnchor": "event.component.html:88 (ngTemplateOutlet)",
      "note": "one bordered box around iframe + recommendations — do not flatten into siblings" },
    { "wrapper": "iframe.marketing", "injectedDocument": true,   // trap I — nested browsing context
      "legacyAnchor": "event-detail.component.html:4 ([srcdoc])",
      "note": "no parent sheet/spec/cascade-diff reaches inside; tdd-cycle-runner composes the containment stylesheet into the document itself" }
  ],
  "nonComputable": [                                 // trap H — rules no getComputedStyle can return
    { "selector": ".promotion-tab-header::-webkit-scrollbar", "kind": "pseudo-element",
      "declarations": { "display": "none" }, "legacyAnchor": "_contents.scss:1594",
      "pairedWith": ".promotion-tab-header", "why": "no computed-style surface — source-resolved" }
  ],
  "acceptedDeltas": [],                              // agreed exceptions (e.g. a shared design-token color)
  "unconfirmed": []                                  // selectors whose values are source-derived, pending live confirmation
}
```

## Error types this closes (from the OMH-708 event page)

| Type | What went wrong | Closed by |
| --- | --- | --- |
| A eyeball approximation | radius 15↔25, weight 500↔600, grid↔flex-wrap, margin 40↔20 | exact `axes` values are the target; no approximation |
| B global class / asset omission | star sprite + tab pill CSS rendered as class name only | global-sheet cascade + `assets[]` + `foundation-generator` copies/wires them |
| C invisible CSS trick | iframe `-8px` bleed, section padding | computed style captures it regardless of markup visibility |
| D markup flattening | one wrapping box split into siblings | `structure[]` records the wrapper; generator preserves it |
| F stale source | button 52/15 (source) vs 48/10 (live) | `live-confirmed` computed value supersedes committed CSS |
| G content-dependent property dropped | `overflow-x:auto` captured at n=1, curated away as a no-op, page scrolls 337px sideways at n=6 | `containment` captured verbatim + `contentDependent` + the synthetic-overload gate |
| H non-computable rule | `::-webkit-scrollbar`, `::placeholder`, `@media`-conditional rules — no computed-style surface at all | `nonComputable[]` resolved from source + the overflow twin rule |
| I unreachable nested context | a document injected into a frame; legacy's own parent-side rule for it is dead code | `structure[].injectedDocument` → containment sheet composed into the document |

## What this spec structurally CANNOT close

A style spec is **element-indexed**: it captures the elements `analysis.json.styleSurface` names. So
it cannot cover markup the page does not author — CMS rich text, i18n values containing HTML, editor
output, anything reaching the DOM through `innerHTML` / `dangerouslySetInnerHTML`. Those subtrees are
unknown at analysis time and routinely 500–1000 nodes; enumerating them in an index is not merely
tedious, it is impossible, because the content changes without a deploy.

Record the injecting container as one element (its own inherited values are real and worth capturing)
and **do not** treat that entry as coverage of its descendants. The descendants belong to
`fm-cascade`, which diffs the two stylesheets over every node instead of over an index — see
`templates/cascade-diff.md`. The failure this prevents is concrete: on OMH-848 `/privacy` the spec
recorded 13/13 elements live-confirmed and the page still shipped with every table border missing,
because all 88 affected cells were inside the one container the spec had marked done.

## Acceptance (definition of done)

For any migrated page, open the **live legacy** and the new render side by side and compare key
elements' `getComputedStyle` per element per axis: the structural properties must match, with only
`acceptedDeltas` (agreed exceptions, e.g. a shared design-token color) recorded. This is verified up
front (the spec is the target the generator built to) and again at `fm-parity` (which reuses this
spec's baseline) — the two never disagree because they share this one source.
