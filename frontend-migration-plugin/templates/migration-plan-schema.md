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
    // coversVariant links to a behavioralVariants.feature; use coversCopySource for a
    // copySources[] surface, so a copy-side reduction is traceable to what it reduced
  ],
  "copyBindings": [                         // from analysis.copySources — where each screen's text comes from
    { "surface": "login failure message", "mechanism": "localized-key",
      "key": "tl.login.fail-message", "renderMode": "text",   // text | html (the value carries markup)
      "boundIn": "LoginForm", "analysisAnchor": "login-password.component.ts:114" },
    { "surface": "password reset error", "mechanism": "errorCode-map",
      "mapModule": "app/lib/auth/password-error.ts", "codes": ["…6 codes…"],
      "renderMode": "text", "boundIn": "NewPasswordForm",
      "analysisAnchor": "new-password.component.ts:141" }
  ],
  "requiredGates": ["e2e", "visual", "contract", "telemetry"],
  "gateAcceptance": { "visual": { "compares": "...", "scope": "...", "artifacts": "...", "excludes": [] } },
                                            // REQUIRED — one entry per gate in requiredGates; see below
  "flagPlan": { "key": "v2_pc_booking_info", "guardsPath": "/hotel/booking-info",
                "twoPr": ["code PR with flag OFF", "one-line flag-ON PR after parity passes"] },
  "e2eScenarios": [
    { "name": "fill traveler form and proceed to payment", "transactional": false,
      "steps": ["..."], "legacyAnchor": "file:line" },
    { "name": "login with wrong password shows the failure message", "transactional": false,
      "assertsCopy": true,                  // dual-run compares the DISPLAYED TEXT, not just the flow
      "coversCopyBinding": "login failure message",
      "steps": ["..."], "legacyAnchor": "login-password.component.ts:114" },
    { "name": "complete card payment", "transactional": true, "gateway": "nicePay",
      // MUST match a key in config stagingConfig.paymentGateways verbatim (nicePay | eximbay | kakaoPay);
      // no case normalization is performed, so "nicepay" reads as an unconfigured gateway
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
(`e2e` / `visual` / `contract` / `webview` / `telemetry` — the complete set; `parity-verifier`
implements no other check and `parity-report.json` has no other slot, so a plan naming anything else
is rejected by `fm-plan` Step 4.1. `secret` and `sso` are **not** gates: they are `gateTriggers[]`
entries routed to `fm-secret-audit` and to `e2eScenarios` + `templates/hana-sso.md` respectively). A plan without `gateAcceptance` is
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
- `states` (visual gate only) — the rendered states each axis is compared in, derived from
  `copyBindings` + the analysis: `default` plus every state whose content only appears when driven
  there (error shown per failure surface, session expired, empty/zero-result). A default-only capture
  can never see error or session-expired copy, so omitting a planned state is an incomplete gate,
  not a smaller one.
- `languages` — the languages the gate runs in. Defaults to the full `i18n.languages` set from
  config; that config block is what "every supported language" **resolves to**. Any narrowing is an
  `openApprovals` item. The `i18n` block is **optional**: when config has none there is no set to
  default to, so omit `languages` rather than inventing one — the verifier records the language axis
  as `not-run` with a reason and runs the gate at the app's single served locale. Omitting it is only
  legitimate for that reason; with an `i18n` block present, a missing `languages` is an incomplete
  criterion.
- `expectedValueSource` — **required whenever the criterion asserts a v2-side expected value** (the
  answer key: "the body sends `currency` derived from the URL locale", "the response envelope carries
  `succeedYn`", "this label reads X"). Cite where that expectation comes from: a prior page's
  `style-spec.json` `acceptedDeltas` or its `migration-plan.json` `openApprovals` (different
  artifacts — the visual exceptions live in the style spec), an ADR, a shared-module commit, a BE
  confirmation, or the legacy
  source line — with the anchor, and with **where the decision lives** (a commit on `develop` but not
  yet on `master` must say so; "on develop, not yet on master" is the accurate citation). Record
  `"searched: <what>; no prior v2 decision found"` when that is the answer — an unrecorded search is
  indistinguishable from no search. A criterion asserting a v2 expected value with no
  `expectedValueSource` is **incomplete**, returned to the planner exactly like a missing
  `gateAcceptance` entry (`fm-plan` Step 4).
- `criterionAmendment` — present only when the criterion was corrected after authoring; see
  "Criterion amendment" below.
- `budgetSeconds` (optional) — a wall-clock cap for this gate's capture. On overrun the verifier
  records `result: "not-run"` + `reason: "budget exceeded"` and proceeds — it never fails the gate and
  never hard-kills a running capture (`parity-verifier` → Rules). Per-gate, not per-round: `visual`
  runs long across the language set by design; a `contract` overrun usually signals nothing to freeze.
  **Omitted → no cap.** There is no plugin-wide default: an unset `budgetSeconds` means the gate runs
  to completion, and only an explicit value creates a budget. (An unspecified "default cap" would be
  a number the executor has to invent, which is the improvisation the codified criteria exist to
  remove.) Set generous first values and tighten from measured runs.

**Executors enforce these criteria verbatim.** No level — skill delegation prompt, verifier
agent, orchestrator summary — may reinterpret, narrow, or substitute them. A criterion that
cannot be met is a failure or an explicit approval request, never a silent scope reduction.

The one carve-out is `budgetSeconds`, and it is not an exception to this rule but an application of
it: an overrun records `not-run` + `reason`, which is precisely *not* a silent pass — the criterion
is reported as unmeasured, with the budget named, and the gate's `result` cannot be `pass` on the
strength of it. What the rule forbids is quietly declaring an unmet criterion satisfied; recording
honestly that it was never measured is the behavior it asks for.

**Authoring is bound by the same rule.** `scope` coverage defaults to the FULL supported
matrix — every language, device class, and viewport the product serves. Sampling or any
coverage reduction (e.g. "representative languages only") is itself a decision: the planner
records it as an open approval item with its rationale and the decision owner's sign-off —
it never enters the criteria as a silent default. An author's cost/representativeness
trade-off is not a decision. The same discipline governs *functional* scope (which providers,
locales, and branches the code implements) — see "Behavioral-coverage reconciliation" — and the
gate `scope` is bound to the `behavioralVariants` dimensions the analysis discovered, so the two
can never disagree.

**The answer key is bound too — cite where the expected value comes from.** Coverage is only half of a
criterion; the other half is what the gate expects to *see*, and that half has been unbound. A
criterion asserting a v2-side expected value records its `expectedValueSource` (above). In particular,
when the expectation is "same as legacy", confirm and cite that the v2 platform has not **already
decided to diverge** on that axis: search the prior pages' `style-spec.json` `acceptedDeltas` and
`migration-plan.json` `openApprovals`, the
ADRs, and the git log of the shared module that owns the value — and record the search either way,
including "found nothing".

Why this is not bureaucracy: a wrong answer key does not fail safe. It **fails the gate on correct
code**, and a gate failing on correct code puts pressure on the executor to read the criterion more
narrowly — the exact behavior "Executors enforce these criteria verbatim" exists to forbid. The
authoring error manufactures the reinterpretation pressure. That happened on the first page whose
contract gate compared an actual request body field-by-field: the criterion said three locale-derived
fields, written from the legacy source alone, while the v2 platform had already decided (on `develop`)
that only one of them follows the URL locale and the other two preserve the user's locale-modal choice.
Coverage was right; the answer key was wrong; the gate produced a false FAIL. Expect this on every page
that asserts a v2-side value, not just request bodies.

Example — a `visual` gate:

```jsonc
"gateAcceptance": {
  "visual": {
    "compares": "legacy render vs new render — style parity (layout, spacing, typography, color), not just content structure/text. Legacy(Angular)↔v2(React) cannot pixel-diff: per-side baselines + computed-style probes, legacy is the reference (never the self-referential v2 baseline)",
    "scope": "full page including app shell for pilot pages; content-area style parity always; every supported language",
    "artifacts": "same-pattern Playwright screenshots of BOTH apps (same viewport, fullPage, masking) compared side-by-side per axis + a computed-style probe per content-independent axis",
    "axes": ["frame", "inter-element spacing/gaps", "icons/glyphs", "alignment", "control geometry", "color/border", "typography"],
    "states": ["default", "login failure shown", "session expired", "empty result"],
    "languages": ["KO", "EN", "JA", "ZH", "VI"],   // = config i18n.languages; narrowing → openApprovals
    "expectedValueSource": "style-spec.json legacySource.provenance (side: legacy, live-confirmed computed values); searched prior pages' acceptedDeltas + packages/shared-ui git log for an approved v2 divergence on these axes — none found (2026-07-30)",
    "excludes": []          // e.g. ["animated carousel region (masked both sides)"]
  }
}
```

## Criterion amendment (when the answer key itself was wrong)

A criterion whose expected value turns out to be wrong is fixed by **amending the criterion**, and that
is a decision-owner act — not the executor's. Keep the two apart in writing, or a reviewer reading the
report cannot tell a correction from the silent scope reduction the gate rules prohibit. An executor who
believes a criterion is wrong raises it (a `fail` plus an approval request); the owner amends.

An amendment records, in the criterion, under `criterionAmendment`:

| Field | What goes in it |
| --- | --- |
| `amendedAt` / `amendedBy` | Date, and the decision owner (a person, with their standing for this page's gates) |
| `via` | How the error surfaced — the approval request, report, or review that raised it |
| `clauseBefore` / `clauseAfter` | The criterion text verbatim on both sides of the change |
| `coverageUnchanged` | The explicit statement that nothing was narrowed: what `scope` still requires, and which other clauses are untouched. An amendment that also shrinks coverage is two changes; the reduction goes through `openApprovals` on its own |
| `whyTheOriginalClauseWasWrong` | The authoring error, named (typically: legacy's behavior encoded as v2's requirement without checking whether v2 had already decided otherwise) |
| `priorDecision` | The v2 decision the amended clause now follows, cited — ticket, commit, ADR, with the wording it actually used |
| `priorDecisionLocation` | **Where that decision lives**, verified: which branch carries it, and whether it has reached `master`. A decision on `develop` but not on `master` must say exactly that — this is the field most easily overstated and the one a reviewer checks first |
| `beConfirmation` | The backend/platform confirmation, when the amendment rests on one, with its date, artifact, and the endpoints it covers |
| `fence` | What the amendment does **not** cover — the pages, endpoints, or axes it must not be read as clearing. Without this an amendment drifts into a repo-wide precedent |
| `whatThisDoesNotClose` | Which findings and tickets remain open regardless. An amendment dispositions a divergence; it does not remove it |
| `evidenceBase` | The artifacts the amendment rests on, enumerated (both sides, all locales, file paths) — the same standard as any gate claim |

A gate that passes under an amended criterion records `amendedCriterion: true` in its report entry and
preserves the pre-amendment reason as `priorWhy`, so the pass is never mistaken for one under the
original clause and the history survives in the artifact rather than in a PR thread.

Field names are the ones the first real amendment used (`docs/migration/pc/delete-account` on the
OMH-758 branch) — promoted, not re-invented, so existing reports keep parsing.

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

## Copy-source reconciliation (required)

The same rule, applied to the copy axis. Every `analysis.json.copySources[]` entry marked
`mustPreserve` must survive into `copyBindings[]` — **or** be recorded in `openApprovals[]` with a
rationale and decision owner. A `mustPreserve` copy source silently absent from both makes the plan
**incomplete** (`fm-plan` Step 4 rejects it back to the planner, exactly like a missing
`gateAcceptance` entry).

Why it needs pinning: where a screen's text comes from is a **legacy rule**, not a generator choice.
The response envelope carries an `errorMessage` field, so a generator with no recorded rule will
naturally render it — and the backend resolves that field against a hardcoded EN locale (OMH-784),
putting English on every non-English screen. Legacy instead uses a fixed localized key or maps
`errorCode` through a lookup table. Unrecorded, the same mistake is re-derived independently on every
screen (it was, on three). `renderMode` is part of the binding: a value carrying markup (`<br/>`,
`<a href>`) must render as HTML rather than JSX text, and a path inside such a value still follows
the migration's route scheme. See `templates/i18n-copy-parity.md`.

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

**Failure branches are required, not optional.** Derive one scenario per `copyBindings` failure
surface (every place legacy sets a form-error flag, opens an alert, or shows an inline message) and
mark it `assertsCopy: true` with `coversCopyBinding` naming the binding it covers — the dual-run
then compares the **displayed text** on both apps, not just navigation. A happy-path-only suite
cannot see a wrong error string, a raw `tl.*` key, or a literal `<br/>`, because none of them appear
in a successful flow. Where those surfaces exist, cover at minimum: wrong password, OTP/
verification-code failure, and blocked/duplicate email. See `templates/i18n-copy-parity.md`.
