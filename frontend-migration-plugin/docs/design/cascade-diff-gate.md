# Cascade Diff Gate — why `fm-cascade` exists

**Origin:** OMH-848, mobile `/privacy`, 2026-08-12. Every number below is measured; the command that
produces them is `scripts/cascade-diff.mjs`.

## The blind spot

The pipeline has three stages that could plausibly catch a styling divergence, and each misses the
same class of defect for a different structural reason:

| Stage | Sees | Cannot see |
| --- | --- | --- |
| `fm-style-spec` | computed styles for the elements `analysis.json.styleSurface` names | any node that is not in that index |
| generated unit tests | DOM structure — elements, attributes, text, links | **anything CSS**: they run in jsdom, which applies no stylesheet |
| `fm-parity` | the rendered page, visually | nothing structural — but it needs **both hosts live**, and it is the stage most often blocked |

The gap is the intersection: **markup the page does not author.** CMS rich text, i18n values
containing HTML, editor output — anything reaching the DOM through `innerHTML` /
`dangerouslySetInnerHTML`. Those subtrees are unknown at analysis time and routinely 500–1000 nodes,
so no element index can enumerate them. `fm-parity` is the only gate that covers them, and when it is
blocked the page ships with **zero** style evidence for the majority of its DOM.

## The defect that proved it

Mobile `/privacy` reached `verified` with every table border missing in the English document.

The first hypothesis — the page owner's too — was that migration had dropped a tag or an attribute.
Measured against legacy, it had not:

```
tags   legacy {div 1, p 170, span 163, strong 82, table 5, thead 5, tr 21, td 88, tbody 5, br 6, a 3}
tags   v2     {div 1, p 170, span 163, strong 82, table 5, thead 5, tr 21, td 88, tbody 5, br 6, a 3}
attrs  only difference: _ngcontent-serverapp-c144   (Angular's own view-encapsulation attribute)
```

Byte-identical DOM. The divergence was in the cascade:

```
td  border-top   legacy "3px solid rgb(31,31,31)"    v2 "0px solid rgb(31,31,31)"
```

The CMS authors its cells as `border-style: solid; border-color: …` and **never** declares
`border-width`, taking the CSS initial value `medium` (= 3px, which applies whenever `border-style`
is not `none`). Legacy honours it. Tailwind Preflight ships
`*, ::after, ::before { border: 0 solid }`, which overrides the initial value to `0`.

Same markup, different stylesheet, invisible to every gate that had run.

## The design

Render the same markup twice in one engine at one viewport, changing **only** the global stylesheet,
and diff `getComputedStyle` across every node.

What that buys:

- **No legacy host.** It needs legacy's compiled CSS, not a running legacy server — precisely the
  situation where `fm-parity` is unavailable.
- **Deterministic.** One engine, one viewport, one markup string. No screenshot thresholds, no flake,
  no baseline images to store or refresh.
- **Node-complete.** It never needs to know which elements exist. On `/privacy`: 4,143 nodes × 33
  properties × 5 languages in about 6 seconds.
- **Actionable.** Output names the tag, the property, both values and the node count — a fix
  instruction, not a pixel-diff heat map.

It complements `fm-parity` rather than replacing it: cascade diff catches *rule* divergence; visual
parity still catches assets, fonts, layout and everything outside the property list.

## Result on the origin page

Before:

```
td border-*-width   legacy 3px → v2 0px        EN 88/88 cells · KO/JA/ZH 6 each · VI 3
th border-*-width   legacy 3px → v2 0px        VI 3   (VI is the only language using <th>)
overflow-wrap       legacy break-word → normal  4141 of 4143 nodes, all five languages
```

After — a CMS-scoped `border: revert`, plus porting two legacy globals the target's reset does not
supply (`table { width: 100% }`, `:root { overflow-wrap: break-word }`):

```
EN 0   JA 0   KO 0   VI 0   ZH 0*
```

\* ZH retained one row, `strong`/`span` `font-weight` 600 vs 700, which the differ correctly reports
and which turned out to be a **real** finding of a different kind — a **cross-app rule leak**, traced
to source:

- the migrated mobile app's `fonts.css` carries
  `html[lang="zh"] body strong { font-weight: 700 !important }`, commented
  `/* _common.scss:77-87 — the lang-zh strong !important block, verbatim. */`
- that block exists in **legacy-PC**'s `_common.scss` (inside `&.lang-zh`, lines ~76-86) — so the
  rule and its comment are correct **for the PC app**
- **legacy-mobile**'s `&.lang-zh` declares only `font-family`. It has no `strong` block at all, and
  its lines 77-87 are the `lang-vi` block
- the migrated mobile `fonts.css` is a self-declared *"verbatim mirror of web-pc's fonts.css"*

So a PC-only legacy rule was carried into mobile by a whole-file mirror, along with a source citation
that is accurate for the app it was copied from and wrong for the app it landed in. Mobile ZH renders
`<strong>` at 700 where legacy renders 600.

This is worth dwelling on as a design justification: the divergence is **invisible to every
element-indexed check**, because nothing is wrong with any element the page authors — the wrong rule
is in a global stylesheet, correctly implemented, correctly tested (the PC app has a `fonts.css.test.ts`
pinning it), and simply in the wrong app. Only a whole-stylesheet comparison against *that app's own*
legacy surfaces it.

It also belongs to the shell owner, not the page — which is exactly the disposition the skill's
Step 5/6 requires: classify, then record for the owner rather than silently fix across a boundary.

## Two traps this design must defend against, because both produced wrong answers first

**1. The font trap.** The first run left 14 residual `width` divergences on VI. They read as a
missing layout rule, and legacy's `:root { overflow-wrap: break-word }` — genuinely absent from the
target — was the obvious candidate. Porting it changed nothing. The real cause was the harness: it
loaded only the two *main* stylesheets, so the legacy side fell back to Times New Roman while the
target kept its own stack. Different font ⇒ different intrinsic width ⇒ different auto-layout column
distribution (same 410.999px total, redistributed). Neutralising the font identically on both sides
took VI to 0.

*(The overflow-wrap rule was later confirmed as a real divergence on its own evidence — 4141 nodes —
which is the point: it was innocent of the crime it was first charged with.)*

**2. The selector-convention trap.** The next run reported `strong` at 600 vs 700 across 258 ZH
nodes. Legacy hangs its per-language rules off `html.lang-zh` (a class); the target uses
`html[lang="zh"]` (an attribute). A host document that sets only one silently disables half of one
side's stylesheet. The differ now sets both, on both sides.

Both traps are the same failure: **a second variable came loose.** Hence the invariant stated at the
top of `templates/cascade-diff.md`, the mandatory font neutralisation, and `fontFamily` being kept in
the property list on purpose — so a surviving mismatch announces itself directly instead of hiding
inside `width`.

## Pipeline position

```
fm-analyze → fm-style-spec → fm-plan → fm-gen → fm-verify → [fm-cascade] → fm-e2e → fm-parity → fm-route
```

After `fm-verify` because the target's CSS must compile first; before `fm-e2e` so a rule-level
divergence is fixed before behavioural evidence is gathered against it.

## Gate strength — open for the owner to rule on

Proposed as **advisory-with-teeth**, not an automatic FAIL: some divergences are intended, and a
migration may deliberately drop a legacy rule. The stage requires each divergence to be either fixed
or recorded in `owner-decisions.md` with a reason, and `fm-route --flag-on` should refuse while
unresolved, unrecorded divergences exist — mirroring how the plugin already treats Codex `high`
findings.

The alternative (hard FAIL on any non-empty diff) was considered and not proposed: the ZH
`font-weight` row above is a real divergence that belongs to a different ticket's file, and a hard
gate would have blocked the page on someone else's work with no route forward except a bypass — which
is how gates get routinely bypassed.
