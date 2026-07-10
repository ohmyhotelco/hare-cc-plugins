# migration-plan.json Schema

The plan `migration-planner` writes and `fm-gen` executes. One per page, at
`docs/migration/{app}/{page}/migration-plan.json`.

## Rendering decision table (OMH-454 §5)

| Page kind | Mode | Why |
| --- | --- | --- |
| notice / faq / event / terms / privacy / app-download | **SSG** | static/CMS; SEO with zero server cost |
| `/my-page/*` (auth-gated) | **SPA** (`ssr: false`) | no SEO value |
| hotel detail (`/hotel/search-room-type`) | **SSR + ISR** | highest-value SEO surface |
| hotel search-results list / map | **SPA** | query-dependent, no canonical URL |
| booking-info / payment / payment-complete / booking-complete | **SPA** | transactional, no SEO |
| home | **SSG** | marketing landing |
| login / join / edge | **SPA** | transactional / low traffic |
| **all Hana routes** | **SPA** | external SSO entry, no SEO |

## Shape

```jsonc
{
  "app": "pc",
  "page": "hotel-booking-info",
  "analysisRef": "docs/migration/pc/hotel-booking-info/analysis.json",
  "styleSpecRef": "docs/migration/pc/hotel-booking-info/style-spec.json",   // the legacy style answer key
  "rendering": "spa",                       // ssr | ssg | spa
  "targetDir": "apps/web-pc/app/features/booking-info",
  "componentTree": [
    { "name": "BookingInfoPage", "kind": "page", "fromGodSeam": "...", "children": ["TravelerForm", "CouponSelector"],
      "styleTargets": { "elements": [".promotion-detail"], "assets": [], "structure": [".promotion-detail wraps iframe+recommend"] } },
    { "name": "TravelerForm", "kind": "component", "form": true,
      "styleTargets": { "elements": [".btn-promotion-tab"], "assets": ["/assets/images/sprite-rate.png"], "structure": [] } }
  ],
  "mapping": [
    { "angular": "hotelFacade.getBookingTraveler$", "react": "useBookingTraveler() (TanStack Query)",
      "catalogRef": "state", "analysisAnchor": "file:line" }
  ],
  "sharedDeps": ["@omh/shared-data:useBookingDetail", "@omh/shared-domain:validators/birthday",
                 "@omh/shared-types:RsBookingTraveler"],
  "blockers": [{ "candidate": "CouponService.calcMaxDiscount", "reason": "not extracted",
                 "action": "fm-extract" }],
  "openApprovals": [                        // coverage reductions awaiting a decision owner (never silent)
    { "topic": "social-login provider set", "coversVariant": "social-login-buttons",
      "decision": "reduce 6→4 (drop Line, Facebook)",
      "rationale": "Line not confirmed live for PC-KO; Facebook initFacebookSDK commented out",
      "owner": "TBD", "status": "pending" }
  ],
  "requiredGates": ["e2e", "visual", "contract", "telemetry"],
  "gateAcceptance": { "visual": { "compares": "...", "scope": "...", "artifacts": "...", "excludes": [] } },
                                            // REQUIRED — one entry per gate in requiredGates; see below
  "flagPlan": { "key": "v2_pc_booking_info", "guardsPath": "/hotel/booking-info",
                "twoPr": ["code PR with flag OFF", "one-line flag-ON PR after parity passes"] },
  "e2eScenarios": [
    { "name": "fill traveler form and proceed to payment", "transactional": false,
      "steps": ["..."], "legacyAnchor": "file:line" },
    { "name": "complete card payment", "transactional": true, "gateway": "nicepay",
      "steps": ["..."] }
  ],
  "buildOrder": [
    { "phase": "foundation", "creates": ["types.ts", "mocks/handlers.ts"], "tests": 0 },
    { "phase": "api",        "creates": ["api/booking.ts"], "tests": 6 },
    { "phase": "store",      "creates": ["stores/bookingForm.ts"], "tests": 4 },
    { "phase": "component",  "creates": ["components/TravelerForm.tsx"], "tests": 8 },
    { "phase": "page",       "creates": ["pages/BookingInfoPage.tsx"], "tests": 5 },
    { "phase": "integration","creates": ["routes.tsx", "i18n.ts"], "tests": 0 }
  ]
}
```

## Style targets (style-spec binding)

`styleSpecRef` points at the page's `style-spec.json` (`fm-style-spec`, `templates/style-spec.md`) —
the legacy style answer key. Each `componentTree` node carries `styleTargets`: the `style-spec`
`elements` it renders (whose axis values it must reproduce), the `assets` it needs wired, and any
`structure` wrapper it must preserve. Generation (`tdd-cycle-runner` component phase) builds to these
values; a legacy class name is **not** evidence the style was reproduced. The `visual`
`gateAcceptance` probe set pins the same `style-spec` `live-confirmed` values, so the generation
target and the parity check share one legacy-truth source and cannot drift.

## gateAcceptance (required)

Per-gate acceptance criteria — one entry for **every** gate in `requiredGates`
(`visual` / `e2e` / `contract` / `secret` / `sso` / `webview` / `telemetry`). A plan without `gateAcceptance` is
**incomplete**: `fm-gen` and `fm-parity` Step 0 reject it and point back to `fm-plan`. Each entry:

- `compares` — what is compared, against what reference.
- `scope` — at what scope (full page incl. shell vs content area; viewports; languages).
- `artifacts` — the evidence the gate must produce; comparison artifacts are **symmetric**
  (same capture pattern/scope/harness on both legacy and new app).
- `excludes` — what is explicitly out of scope. An exclusion not listed here does not exist,
  no matter what any downstream prompt or report says; empty means nothing is excluded.
- `axes` (visual gate only) — the enumerated visual axes the gate must compare AND probe, from
  `templates/visual-parity-checklist.md`: frame, inter-element spacing/gaps, icons/glyphs, alignment,
  control geometry, color/border, typography. The verifier's computed-style probe set must cover
  **every** listed axis (not a subset); a partial set is an incomplete gate = fail.

**Executors enforce these criteria verbatim.** No level — skill delegation prompt, verifier
agent, orchestrator summary — may reinterpret, narrow, or substitute them. A criterion that
cannot be met is a failure or an explicit approval request, never a silent scope reduction.

**Authoring is bound by the same rule.** `scope` coverage defaults to the FULL supported
matrix — every language, device class, and viewport the product serves. Sampling or any
coverage reduction (e.g. "representative languages only") is itself a decision: the planner
records it as an open approval item with its rationale and the decision owner's sign-off —
it never enters the criteria as a silent default. An author's cost/representativeness
trade-off is not a decision. The same discipline governs *functional* scope (which providers,
locales, and branches the code implements) — see "Behavioral-coverage reconciliation" — and the
gate `scope` is bound to the `behavioralVariants` dimensions the analysis discovered, so the two
can never disagree.

Example — a `visual` gate:

```jsonc
"gateAcceptance": {
  "visual": {
    "compares": "legacy render vs new render — style parity (layout, spacing, typography, color), not just content structure/text. Legacy(Angular)↔v2(React) cannot pixel-diff: per-side baselines + computed-style probes, legacy is the reference (never the self-referential v2 baseline)",
    "scope": "full page including app shell for pilot pages; content-area style parity always; every supported language",
    "artifacts": "same-pattern Playwright screenshots of BOTH apps (same viewport, fullPage, masking) compared side-by-side per axis + a computed-style probe per content-independent axis",
    "axes": ["frame", "inter-element spacing/gaps", "icons/glyphs", "alignment", "control geometry", "color/border", "typography"],
    "excludes": []          // e.g. ["animated carousel region (masked both sides)"]
  }
}
```

## Behavioral-coverage reconciliation (required)

Every `analysis.json.behavioralVariants` entry marked `mustPreserve` must survive into the plan:
implemented in `componentTree` / `mapping` / `e2eScenarios`, **or** recorded in `openApprovals[]`
with a rationale and decision owner. A `mustPreserve` variant silently absent from both makes the
plan **incomplete** — `fm-plan` Step 4 rejects it back to the planner, exactly like a missing
`gateAcceptance` entry.

This is the functional-scope twin of the `gateAcceptance.scope` full-matrix rule: the gate rule
protects *what the gates test*; this protects *what the code does*. The two must agree —
`gateAcceptance.scope` is bound to the dimensions the analysis discovered (`behavioralVariants`),
not to planner discretion, so a feature that varies across 5 locales can never carry a PC-KO-only
gate scope. A source note ("ticket names 4", "SDK commented out") is input to a reduction decision,
never authority for a silent one; the decision lives in `openApprovals` or it does not happen.

`openApprovals[]` entries: `topic`, `coversVariant` (the `behavioralVariants.feature` it reduces),
`decision`, `rationale`, `owner`, `status` (`pending | approved | rejected`). `fm-plan` surfaces
every `pending` entry in its report; a coverage reduction is a human decision, not a default.

## 2-PR flag plan

Every page migration ships as two PRs (Git Branch Strategy + migration plan §12):
1. **Code PR** — the RR v7 implementation with the feature flag **OFF**. Merges to `main`; the
   path still serves the legacy app.
2. **Flag-ON PR** — a one-line change flipping the flag, opened only after `fm-verify`,
   `fm-e2e`, and `fm-parity` all pass. `fm-route` manages the route flip at the app's configured
   edge layer — nginx routing + flag, or a CloudFront behavior manifest entry (per
   `apps.{app}.flipMechanism`; AA-47). `guardsPath` is the nginx `location` *and* the CloudFront
   path-pattern, so the plan is mechanism-independent.

`flagPlan.key` is the flag; `guardsPath` is the route it gates. Rollback = flip the flag back.

## E2E scenarios

`e2eScenarios[]` enumerates the legacy user flows that must hold on the new page. The planner
maps them from the analysis; `fm-e2e` (AA-45) realizes them as Playwright specs, runs the
legacy dual-run, and (for `transactional: true`) runs against staging gateways.
