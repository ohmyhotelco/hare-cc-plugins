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
> `createNicePayData`, `createNpAlipayData`) and any `environment.*.merchantKey` /
> `kakaoLoginSecretKey` read are **forbidden** here — they move server-side (plan §5/§11.9,
> OMH-477). Lint must block these imports.

### shared-data — API client & DTOs
- axios instance: baseUrl, `usertoken` header (request interceptor), timeout, error handling.
- session-expiry interceptor (`'Invalid Session Token'` / `'Session Expired'`) taking a **UX
  callback** (PC opens a modal, Mobile navigates) — mirrors `HttpHelperService`.
- `getCommonRequestParams()` builder (locale from store).
- DTO models from `apis/models` (~70 paths).
- service methods (`POST_*` / `GET_*`) — `coupled` in Angular, re-implemented here.
- TanStack Query hooks (`useHotelList`, `useBookingDetail`, …) replacing NgRx effects.

Anchors: `core/services/api.service.ts`, `apis/services/*.service.ts`, `apis/models/*`.

### shared-types — schemas & enums
- zod schemas for DTO request/response.
- the universal response envelope `{ succeedYn, errorMessage, result, transactionSetId,
  errorCode }`.
- `DataLayerEvent` (40 events) + `DataLayerItem`/`DataLayerEcommerce` (`common/models/data-layer.model.ts`).
- tracker event schema.

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
