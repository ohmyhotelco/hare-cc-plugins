# Cascade Diff — stylesheet-level parity for a migrated page

The technique behind `fm-cascade` and the `cascade-differ` agent. Read this before running either.

## The question it answers

`fm-style-spec` answers *"what values does legacy compute for the elements this page renders?"* — it
is **element-indexed**, driven by `analysis.json.styleSurface`.

That index cannot exist for markup the page does not author: CMS rich text, i18n values containing
HTML, editor output, anything reaching the DOM through `innerHTML` / `dangerouslySetInnerHTML`. Those
subtrees are unknown at analysis time, arbitrary in shape, and routinely thousands of nodes.

Cascade diff answers the complementary question, without an index:

> Holding the markup and the engine constant, do legacy's global stylesheet and the target app's
> global stylesheet compute the **same** values, for **every** node?

## The invariant

Exactly one variable changes between the two renders: **the global stylesheet**. Everything else is
held identical.

| Held identical | Why it matters |
| --- | --- |
| markup | the same document string on both sides — never one scraped from legacy and one from the target |
| engine + version | one browser launch, two pages in the same context |
| viewport + DPR | column widths and any `@media` branch depend on it |
| **font stack** | see *The font trap* below — this one bites |
| `lang` attribute **and** `lang-…` class | drives per-language font sheets, line breaking and `text-transform`; apps disagree which convention their per-language rules hang off (`html.lang-zh` vs `html[lang="zh"]`), so the differ sets **both, on both sides** |

Any divergence in the report is then attributable to the stylesheets. If a second variable is loose,
the report is noise and will send its reader after the wrong rule.

## The font trap

**This is the failure mode that costs the most time, so it is a mandatory step, not advice.**

A page's fonts usually come from stylesheets *other* than the main one — per-language `@font-face`
sheets, a vendored web-font CSS, a `<link>` in the host document. Load only the two main sheets and
the two sides silently resolve different fonts. Different font ⇒ different intrinsic width ⇒
different table column distribution, different wrap points, different heights. The report then fills
with `width` divergences that look exactly like a missing layout rule and are not.

Two defences, use both:

1. **Neutralise.** Inject the *same* `font-family` override into both sides, at a specificity that
   beats both stylesheets. The differ does this by default; `--keep-fonts` opts out when fonts are
   themselves the subject.
2. **Keep `fontFamily` in the property list.** If a mismatch survives anyway it then announces itself
   directly — as a `fontFamily` divergence on every node, an unmistakable signature — instead of
   hiding inside `width`.

Recorded instance: on OMH-848 the un-neutralised run left 14 residual `width` divergences on VI.
They were read as a missing `overflow-wrap: break-word` (a rule genuinely absent from the target).
Porting it changed nothing. Neutralising the font took VI to 0. The rule was innocent; the harness
was not.

## Inputs

| Input | Where it comes from |
| --- | --- |
| legacy CSS | the legacy app's compiled stylesheet — fetched from a running legacy dev server (`/styles.css`) or read from its build output. **Compiled, not source**: `@import`, nesting and the build's own resets must already be resolved |
| target CSS | the target app's compiled stylesheet, fetched from its dev server. Under Vite this arrives wrapped in a JS module (`const __vite__css = "…"`); unwrap it before use |
| markup | the page's captured documents when it has them (golden fixtures, MSW response fixtures), else the rendered container scraped once from the running target app |

Note what is **not** required: a running legacy server. Only its CSS. That is what makes this stage
available when `fm-parity` is blocked on a dead or unreachable legacy host.

The measurement itself is `scripts/cascade-diff.mjs`, copied to `{appDir}/.cascade-diff.tmp.mjs`
and run from there with absolute arguments — ESM resolves `import "playwright"` from the script's
location, not the cwd, so the copy is what lets it use the app's own Playwright install. See
`agents/cascade-differ.md` Step 3.

## Property list

Not "all properties" — `getComputedStyle` enumerates hundreds, most of them derived or irrelevant,
and the noise buries the signal. The list is the properties a document's appearance actually rests
on:

```
border      borderTopWidth borderRightWidth borderBottomWidth borderLeftWidth
            borderTopStyle borderTopColor borderCollapse
box         marginTop marginRight marginBottom marginLeft
            paddingTop paddingRight paddingBottom paddingLeft
            display width boxSizing
type        fontSize fontWeight fontFamily lineHeight letterSpacing
            textAlign verticalAlign textDecorationLine textTransform
paint       color backgroundColor
flow        whiteSpace wordBreak overflowWrap listStyleType
```

Extend per page when the content warrants it (`gridTemplateColumns` for a layout-heavy document,
`objectFit` for image-heavy). Record any extension in the report so the next run is comparable.

## Reading the report

Aggregate by `(tag, property, legacyValue, targetValue)` with a node count. Three kinds of row:

**Real divergence** — a rule present on one side and not the other. Usually a small number of
distinct rows with large node counts. Fix, or record as intended.

**Consequence** — a row caused by another row. Border-width divergence shifts `width` on every cell
in the same table; do not chase these separately. Re-run after fixing the cause and they disappear.

**Harness artifact** — the whole document diverging on one property, especially `fontFamily`. Not a
finding. Fix the harness and re-run.

A property whose target value is *more* correct than legacy's is still reported. Deciding that a
divergence is intended is the owner's call, recorded in `owner-decisions.md` as an **approved**
entry (`status: approved`, `by`, `when`) — never the differ's, never silent, and never a `pending`
item presented as a decision.

## Fixing what it finds

Two shapes, and the choice between them is the substance of the fix:

**Port the legacy rule** — when legacy declares something global that the target's reset does not
supply. Port it verbatim, at the same scope legacy used, citing the legacy file and line.
*Example:* legacy `_common.scss:123` `table { width: 100% }`; Tailwind Preflight supplies
`border-collapse` but not the width.

**Scope a revert** — when the target's reset declares something legacy never had, and the content was
authored against the plain UA cascade. Do **not** delete the reset: the target's own components were
authored under it and depend on it. Scope a `revert` to the container holding the foreign markup.
*Example:* Preflight's `* { border: 0 solid }` vs CMS cells that declare `border-style` and no
`border-width`, taking the initial `medium`.

`revert` rolls a property back to the **UA origin** — not to the previous cascade layer — which is
precisely the cascade unstyled legacy content ran under. That is why it is the right keyword here and
`initial`/`unset` generally are not.

## What it does not cover

Not a replacement for `fm-parity`. Blind to: assets and images, anything painted by pseudo-elements
whose content differs, animation and transition end-states, scroll-dependent and sticky behaviour,
`@media` branches other than the one probed, and any property outside the list. Visual parity remains
the backstop.

## Turning a finding into a gate

A cascade diff run is evidence at a point in time; a regression test is what keeps the fix. The
differ's finding converts directly into an assertion on the running target app, and the assertion
should be written from **the invariant, not the number**:

> "every cell whose inline style declares a border style and no width must paint the initial
> `medium`" — derived from the markup, needs no legacy server, and survives a CMS content change

rather than *"this cell is 3px"*, which is a value copied off one render.

Prove the new test is not vacuous before trusting it: disable the fix, confirm the test fails, restore
the fix, confirm it passes. A cascade test that passes both ways protects nothing.
