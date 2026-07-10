# Shared Package Spec

The six `packages/` that the three React apps (`web-pc`, `web-mobile`, `web-hana`) import.
From the revised migration plan §5, refined with the purity classification observed in the
legacy source. `fm-extract` (AA-42) lifts logic into these; the `angular-analyzer` classifies
each candidate against this spec.

```
packages/
├── shared-i18n      (translation keys; angular-i18next → i18next, same Google Sheets source)
├── shared-types     (zod DTO schemas, response envelope, DataLayerEvent enum, tracker events)
├── shared-config    (env / public ids — NO secrets)
├── shared-data      (axios client + services + DTO models + TanStack Query hooks)
├── shared-domain    (pure business logic — zero React, zero Angular)
└── shared-ui        (shadcn primitives + headless domain hooks + BrandProvider)
```

## Schema source authority — `shared-types` / `shared-data` only

When the project has confirmed backend verification contracts (`contractsDir`, default
`docs/migration/api-contracts/`, OMH-604/606/607), those contracts are the **authoritative**
schema source for **`shared-types` and `shared-data` only** — the legacy `any` DTOs under
`apis/models` are **retired** for everything the contracts cover (migration plan §5). The
contracts are **zod-in-markdown** (zod inside Markdown `ts` code fences, not `.ts` files):
- `{contractsDir}/responses/` (OMH-606) — per-endpoint response zod, each `.extend()`ing the
  shared `ResponseEnvelopeSchema`.
- `{contractsDir}/requests/` (OMH-607) — per-endpoint `{Entity}RqSchema`, each `.extend()`ing
  the shared `CommonRequestParamsRqSchema`.
- Both base schemas (`ResponseEnvelopeSchema`, `CommonRequestParamsRqSchema`) are defined **once**
  in `shared-types`; every per-endpoint schema extends its base.

`package-extractor` **transcribes** this zod verbatim. Legacy source remains the anchor only for
what the contracts do **not** cover (see the per-package notes below). When `contractsDir` is not
configured, both packages fall back to legacy reverse-extraction as before (no regression). The
other four packages (`config`/`i18n`/`domain`/`ui`) are unaffected — they always extract from
legacy.

> **Authoritative ≠ infallible — the live backend is the final arbiter.** A contract doc can be
> wrong (OMH-748: `requests/user-auth.md` described the login envelope as "sent-but-ignored" when the
> real backend strict-rejects an extra root field). Transcribe the contract as the schema source, but
> a behavioral claim in prose ("field X is ignored / optional / tolerated") is **not** verified until
> a real or staging backend confirms it — `fm-parity`'s contract gate checks the request/response
> shape against the live backend, not the doc's prose (see `parity-verifier`). When live and doc
> disagree, the live response wins and the doc is flagged for correction by the OMH-607 contract
> owner.

## Placement rules

A candidate goes to a package by **what it is**, gated by **purity**:

- `pure` — no Angular, no DI, no framework imports → extract as-is.
- `partial` — pure core wrapped in Angular (e.g. a `ValidatorFn` factory) → extract the core,
  re-wrap for React.
- `coupled` — depends on `HttpClient` / `Store` / DOM / `@Injectable` state → re-implement.

### shared-domain — pure business logic
Validators, date math, coupon math, BookingStatus enum + `isCancellable`, client-safe payment
utilities, session timers, price-change detection. **No secrets, no hash builders.**

Observed candidates:
- `UtilDateService` — **pure** (moment → dayjs): age, diff, period validation.
  (`common/services/util-date.service.ts`)
- `CommonUtilService` — **pure**: `numberPad`, language-aware keyword checks, query filtering.
- `CommonValidatorService` — **partial**: `ageCompare()` is pure; `customPattern()` returns an
  Angular `ValidatorFn` → re-express as a zod refinement.
- `CouponService` discount math — **partial** (math pure; HTTP wrapper is not).

> **Security boundary (hard).** `shared-domain/payment/` holds only `gateway-selector`,
> `payment-form-validators`, `display-formatting`. The PG hash builders (`createFgkey`,
> `createNicePayData`, `createNpAlipayData`, `createEximbayData`) and any `environment.*.merchantKey` /
> `kakaoLoginSecretKey` read are **forbidden** here — they move server-side (plan §5/§11.9,
> OMH-477). Lint must block these imports.

### shared-data — API client & DTOs
- axios instance: baseUrl, `usertoken` header (request interceptor), timeout, error handling.
- session-expiry interceptor (`'Invalid Session Token'` / `'Session Expired'`) taking a **UX
  callback** (PC opens a modal, Mobile navigates) — mirrors `HttpHelperService`.
- `getCommonRequestParams()` builder (locale from store) — shapes the request body that extends
  `CommonRequestParamsRqSchema`. **A per-endpoint builder must return its body parsed through that
  endpoint's `RqSchema`** (`RqSchema.parse({ ...getCommonRequestParams(), … })`), so a schema that
  `.omit()`s a root field (e.g. login omits `stationTypeCode`) actually drops it at runtime. Reason:
  TS excess-property check does not see fields re-added by a `...spread`, so the type says "omitted"
  while the body still carries it — only the real backend rejects it (400). Keep request schemas
  **non-strict** so `.parse()` strips the extra key instead of throwing. (OMH-748; see
  `angular-to-react-mapping.md` → **http**.)
- DTO schemas — **transcribed from the contracts** (`{contractsDir}/responses` + `requests`,
  authoritative), **not** reverse-engineered from the legacy `apis/models` `any` (~70 paths,
  retired). Falls back to `apis/models` only when `contractsDir` is unconfigured.
- service methods (`POST_*` / `GET_*`) — `coupled` in Angular, re-implemented here over the
  transcribed schemas (legacy is the anchor for the **wiring & call sites**, not the DTO shapes).
- TanStack Query hooks (`useHotelList`, `useBookingDetail`, …) replacing NgRx effects.

Anchors: schemas ← `{contractsDir}/responses` + `requests` (authoritative; legacy `apis/models/*`
only as fallback). Wiring/call sites ← `core/services/api.service.ts`, `apis/services/*.service.ts`.

### shared-types — schemas & enums
- zod schemas for DTO request/response — **transcribed from the contracts** (authoritative;
  `{contractsDir}/responses` + `requests`), not reverse-engineered from legacy `any`.
- the two shared base schemas, defined **once** here and `.extend()`ed by every per-endpoint
  schema: `ResponseEnvelopeSchema` (the universal envelope `{ succeedYn, errorMessage, result,
  transactionSetId, errorCode }`) and `CommonRequestParamsRqSchema` (the common request params).
- **Contract-excluded (legacy anchor):** `DataLayerEvent` (40 events) + `DataLayerItem`/
  `DataLayerEcommerce` + the tracker event schema — these are **not** part of the request/response
  contracts, so transcribe them from `common/models/data-layer.model.ts` as before.

### shared-i18n — translation
- the i18next resources (same Google Sheets remote source as `translate/provider.ts`),
  namespaces `translation` / `validation` / `error`, `tl.*` keys, `keySeparator: false`.

### shared-config — public config only
- public ids (`gtmContainerId`, `ga4MeasurementId`, OAuth client ids, pixel ids), URLs.
- **No secrets.** Secret env fields move to a runtime secret source (plan §8/§11.9).

### shared-ui — primitives & headless domain hooks
- shadcn primitives (Button, Input, Dialog, Select, Tabs, Pagination, Sonner toast, InputOTP,
  date-range picker, counter).
- headless domain hooks + per-form-factor views (`user-count`, `major-city-list`,
  `city-autocomplete`, hotel/room cards).
- `useAnalytics()` wrapping `dataLayer.push`.
- `BrandProvider` (`omh` | `hana`) + brand tokens — replaces Hana's forced component forks.

## Three-app reconciliation
PC/Mobile DTOs and services are ~97–98% identical; Hana adds `POST_HANA_*` and reads
`environment.nicePay.hana.*`. Hana-specific endpoints live alongside common ones, guarded by
which app imports them (no build-time split). Record each reconciliation decision (e.g. the
coupon v2.1 78-line PC-ahead gap) in the package. The `hana-travel/` fork (~134 files)
collapses into shared components + `BrandProvider`, not a parallel tree.
