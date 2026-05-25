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
  "rendering": "spa",                       // ssr | ssg | spa
  "targetDir": "apps/web-pc/app/features/booking-info",
  "componentTree": [
    { "name": "BookingInfoPage", "kind": "page", "fromGodSeam": "...", "children": ["TravelerForm", "CouponSelector"] },
    { "name": "TravelerForm", "kind": "component", "form": true }
  ],
  "mapping": [
    { "angular": "hotelFacade.getBookingTraveler$", "react": "useBookingTraveler() (TanStack Query)",
      "catalogRef": "state", "analysisAnchor": "file:line" }
  ],
  "sharedDeps": ["@omh/shared-data:useBookingDetail", "@omh/shared-domain:validators/birthday",
                 "@omh/shared-types:RsBookingTraveler"],
  "blockers": [{ "candidate": "CouponService.calcMaxDiscount", "reason": "not extracted",
                 "action": "fm-extract" }],
  "requiredGates": ["e2e", "visual", "telemetry"],
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

## 2-PR flag plan

Every page migration ships as two PRs (Git Branch Strategy + migration plan §12):
1. **Code PR** — the RR v7 implementation with the feature flag **OFF**. Merges to `main`; the
   path still serves the legacy app.
2. **Flag-ON PR** — a one-line change flipping the flag, opened only after `fm-verify`,
   `fm-e2e`, and `fm-parity` all pass. `fm-route` manages the nginx route + flag (AA-47).

`flagPlan.key` is the flag; `guardsPath` is the route it gates. Rollback = flip the flag back.

## E2E scenarios

`e2eScenarios[]` enumerates the legacy user flows that must hold on the new page. The planner
maps them from the analysis; `fm-e2e` (AA-45) realizes them as Playwright specs, runs the
legacy dual-run, and (for `transactional: true`) runs against staging gateways.
