# Design — transform-fidelity generation (v0.10.0)

Companion to `style-spec-generation.md` (v0.9.0). That edition closed the **style** leak — "the
markup arrived but the stylesheet didn't." This one closes the **logic/transform** leak — "the
function was ported but its output *shape* was changed." Both share one root: a port that looks
faithful (same-named function, gates green) yet produces a different result than legacy.

## Problem

On the OMH-708 event migration, pages built through yesterday rendered fine, but `/event/100221`
lost the grey band (`#f5f5f5`) that should sit above its recommended products. The gates were green
and the code called the "same" sanitizer as legacy.

The grey was not a page background — it lived on the marketing HTML's own `<body>` tag
(`style="background:#f5f5f5;padding:24px 0"`), a grey margin wrapping white content. The v2 port
dropped it:

- Legacy (`event-detail.component.ts:203-217`):
  `DOMPurify.sanitize(doc, { FORCE_BODY: true, ADD_TAGS: ['script'], RETURN_DOM: true })`, then
  `.outerHTML` on the returned `<body>` node → the wrapper **and its background** survive.
- v2 (before the fix): `DOMPurify.sanitize(html, { FORCE_BODY: true, ADD_TAGS: ['script'] })` — a
  **string** return → only `body.innerHTML`, so the `<body>` wrapper and its background/padding are
  gone.

The port treated `RETURN_DOM` + `.outerHTML` as removable. In DOMPurify,
`RETURN_DOM`/`WHOLE_DOCUMENT`/`FORCE_BODY` are **not** security-strength knobs — they change the
**shape of the output**, and that fact never reached the port.

Root cause is structural, not a one-off:

- **The mapping catalog was too coarse.** `angular-to-react-mapping.md` mapped `safeHtml`
  (DomSanitizer) → "sanitized `dangerouslySetInnerHTML`" in a single line, with no notion that the
  options passed to the sanitizer change the output shape, and no distinction for the
  `<iframe srcdoc>` + `<body>`-wrapper case. Given only the common case, the generator improvised and
  lost the option.
- **The generated test only spot-checked security.** It asserted a few behaviors (`onerror`
  removed / `javascript:` stripped / `script` allowed) but never pinned the **whole output shape**
  ("does it keep the `<body>` wrapper?"). So the port passed all of its own tests while diverging
  from legacy.

Why it stayed hidden until day two: earlier events had no style on their marketing `<body>`, so
`innerHTML` and `outerHTML` rendered identically. 100221 was the first event to style `<body>`
itself, so the missing option only then reached the screen. The defect existed from the start; the
data that reveals it arrived that day (a **data-dependent delayed exposure**).

## Insight

The same shape as the style edition: the answer key must be the **legacy function's real output**,
and a **pure transform** should be fixed by comparing that whole output — not by asserting a few
behaviors. `RETURN_DOM`/`WHOLE_DOCUMENT`/`FORCE_BODY` never enter as regressions if generation
targets the legacy output string; the spot-check gap never ships if the transform is pinned by a
golden test from the start, whenever the revealing data arrives.

## Design

No new stage or artifact — this is a **rule reflected into three existing surfaces**, prioritized
generation → mapping → gate (cause first, then the specific hole, then the net).

### Components

- **`templates/tdd-rules.md`** + **`agents/tdd-cycle-runner.md`** (4-1, generation, the cause) — a
  ported **pure transform** (sanitizer, formatter, serializer, URL builder) is pinned by a **golden
  / differential test** to the **full legacy output** over a representative input set. Behavior
  spot-checks supplement, never substitute. "Passes its own tests" ≠ "produces the legacy output."
  This one rule catches types G/H/I regardless of how coarse the catalog is.
- **`templates/angular-to-react-mapping.md`** (4-2, the specific hole) — the `safeHtml`/DomSanitizer
  rows (templates §, pipes-directives §) now carry a note: port the DOMPurify options **verbatim**;
  `RETURN_DOM`/`WHOLE_DOCUMENT`/`FORCE_BODY` change the output shape, not the security strength;
  `RETURN_DOM`+`.outerHTML` preserves the `<body>` wrapper, the default string return gives only
  `innerHTML`; an `<iframe srcdoc>` host differs from a plain fragment. Generalized: never simplify a
  library call to its common case — the options are part of the contract.
- **`agents/parity-verifier.md`** (4-3, the net) — for a page whose appearance depends on a pure
  transform over **unbounded input**, a content-instance screenshot is not parity evidence (content
  is a non-enumerable axis; any sample is unrepresentative). The gate instead confirms a
  **content-independent output-pin test** exists; its absence is a `fail`. Backstop when 4-1/4-2 are
  missed.

## Error types closed

Paired with the style edition's A–F; these are the logic/transform axis.

| Type | Was | Closed by |
| --- | --- | --- |
| G library-option simplification | `RETURN_DOM` dropped → `<body>` wrapper lost | port options verbatim (mapping) + golden test (generation) |
| H return-shape change | `outerHTML`→`innerHTML`, array↔scalar, `null`↔`''` | golden test pins the full legacy output |
| I spot-check-only test | behaviors asserted, whole output unfixed | golden test is the target; spot-checks only supplement |
| J data-dependent delayed exposure | defect visible only on the first `<body>`-styled event | content-independent output pin (generation + parity backstop) |

## Decisions

- **Rule reflection vs new stage** → reflected into the existing generation rule, mapping catalog,
  and parity gate. Unlike the style edition (which needed a new capture stage + `style-spec.json`
  artifact because the truth was environment-dependent), the legacy transform's output is
  deterministic and reproducible in a unit test, so no new stage/artifact is warranted — a golden
  test is the natural home.
- **Golden vs behavior spot-check** → golden (full-output) as the target, spot-checks as a
  supplement. Spot-checks are content-blind to shape; only a full-output pin catches G/H/I.
- **Not in the Codex audit set** → like `fm-style-spec`, this adds no audited stage; the rule rides
  inside existing stages already audited (`gen`, `parity`).

## Acceptance

For any migrated page's pure transform, a representative input set passed through the legacy and v2
functions yields identical output strings (only explicitly-agreed differences — e.g. an
`iframeResizer` script replaced by a React binding — recorded). For data-driven transforms,
`fm-parity` confirms a legacy-output-pin test exists. This checks that the generation artifact
targeted the legacy output from the start; it is separate from the pre-flip visual gate.

## Not done here (possible follow-ups)

- A shared golden-fixture helper (legacy-vs-v2 differential runner) if enough pure transforms accrue.
- Extending the pin idea beyond sanitizers to any `shared-domain` formatter/serializer as they are
  extracted.
