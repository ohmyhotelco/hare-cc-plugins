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
    "capturedFrom": "live",                          // live | source-fallback
    "viewport": { "width": 1280, "height": 800 },
    "capturedAt": "ISO-8601"
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
      "note": "one bordered box around iframe + recommendations — do not flatten into siblings" }
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

## Acceptance (definition of done)

For any migrated page, open the **live legacy** and the new render side by side and compare key
elements' `getComputedStyle` per element per axis: the structural properties must match, with only
`acceptedDeltas` (agreed exceptions, e.g. a shared design-token color) recorded. This is verified up
front (the spec is the target the generator built to) and again at `fm-parity` (which reuses this
spec's baseline) — the two never disagree because they share this one source.
