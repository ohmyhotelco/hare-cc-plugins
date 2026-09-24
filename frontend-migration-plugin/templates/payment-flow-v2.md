# Payment Funnel — the v2 Flow

Read for every page whose `analysis.json.gateTriggers[]` carries a `payment` entry:
`/hotel/booking-info`, `/hotel/payment`, `/payment-complete`, `/booking-complete`, and the balance-payment
modal on booking-detail. `migration-planner` builds to it, the generators implement it, `e2e-test-runner`
tests it, and `fm-route` Step 1d checks its URLs at flip time.

**The v2 payment funnel is a redesign, not a legacy-parity port.** Legacy signs the gateway request in the
browser and returns through the Angular app's Express server. v2 moved signing, amount authority, approval
and booking creation to oh-api (OMH-1089 for NicePay and OnePay, OMH-1130 for Alipay). A faithful port of
the legacy mechanism is the wrong result here. "Legacy is the reference" applies only to the half this
document lists as preserved.

Source: `ohmyhotel-monorepo` and `oh-api` on `develop`, read 2026-09-24. None of it had reached `master`.
The flow was still changing in September 2026, so re-read the anchors before relying on a detail, and cite
a `develop`-only decision as such (`migration-planner` → `expectedValueSource`).

## What changed

| Concern | Legacy (both apps) | v2 |
| --- | --- | --- |
| Signing | the component signs with `environment.nicePay.*.merchantKey` (`createNicePayData`, `createNpAlipayData`) | oh-api `POST /payment/nicepay/prepare` returns `{mid, moid, amt, ediDate, signData}` for `payType: "nicePay"` or `"alipay"`. The storefront holds no key and signs nothing. |
| Amount | the page's own total | oh-api recomputes the payable amount. The page's figure is a cross-check, refused on mismatch with `E40003`. |
| Return leg | the gateway posts to the Angular host's Express (`/api/nicepay-auth-req`, `/api/alipay/{mb,wb}-auth`, `/api/eximbay-return`), which redirects to `/payment-complete` | the gateway returns to oh-api: `POST /payment/nicepay/callback`, `POST /payment/alipay/callback`, `GET /payment/onepay/return`. oh-api approves, books, and 302s the browser to `/payment-complete?…&result=success\|fail&stage=auth\|verify`. |
| OnePay | `POST /payment/onepay/getPaymentUrl`, then a same-tab `location.href` | the same call, with `returnUrl` = oh-api's `/payment/onepay/return` and the storefront page as `frontReturnUrl` |
| Balance payment | booking-detail modal, signed in the browser | the same prepare with `balancePayment: true` (OMH-1129 mobile, OMH-459 P4-X2 PC) |
| Eximbay | `eximbayStart()` alerts and returns: dead since OMH-1178 (2024-08) | not ported: no route, no form, no alert |

Anchors: oh-api `web-api/src/main/java/com/ohmy/api/router/payment/PaymentRouter.java` (the four routes,
commented OMH-1089), `service/payment/PaymentNicePaySignService.java` (`E40003`); monorepo
`packages/shared-funnel/src/payment/{nicepay-prepare,alipay-prepare,onepay}.ts`,
`docs/migration/pc/payment-funnel/analysis.md` §1 and §3,
`docs/migration/mobile/m4-analysis/pg-server-side-design.md` C4.

The Express handlers are untouched and keep serving the legacy apps. web-mobile still carries
`/api/payment/build-payload`, `/api/nicepay-auth-req` and `/api/alipay/mb-auth`, but its funnel no longer
posts through them. web-pc deleted its copies (analysis.md, P4-F3).

## Gateway selection

`packages/shared-domain/src/payment/gateway-selector.ts` (legacy `hotel-payment.component.ts:764-776`):
KRW → NicePay, VND → OnePay, any other currency → Alipay+ through NicePay. There is no Eximbay arm and no
KakaoPay arm. No code on `develop` selects KakaoPay; the name appears only in notice copy, analytics
configuration and docs.

## Rules for the plan and the code

**Do not port.** Record each item as an `openApprovals[]` entry with `status: "approved"`, the ticket as the
decision and its owner, so the legacy inventory reconciliation passes on a traceable decision rather than a
silent drop (`templates/migration-plan-schema.md` → Legacy inventory reconciliation):

- client-side signing and every `environment.*.merchantKey` read (the `secret` trigger);
- the Express return legs, and the PC `/hotel/payment?errorMessage=` arm they fed. oh-api's
  `result=fail&stage=auth` redirect replaces it, and `/payment-complete` handles that;
- the storefront's own USD→KRW read for Alipay, which oh-api now answers;
- Eximbay, in every form.

**Preserve per app, and gate it against legacy:**

- **The window model per gateway.** PC NicePay opens the SDK's auth layer with `goPay(form)`
  (`nicepay-3.0.js`), exposes `nicepaySubmit`/`nicepayClose` on `globalThis`, and captures the cancel code
  from `postMessage`. Mobile NicePay posts the form in the same tab to `v3Payment.jsp`. Alipay posts in the
  same tab, to `pcRequest.jsp` on PC and `smartRequest.jsp` on mobile. OnePay is same-tab on both. v2 PC
  reproduces legacy PC here, not mobile, by owner requirement (analysis.md §3.0).
- The hidden-field order of each gateway form, and which fields each app sends (PC sends no `FailURL`).
- The cancel/close alert and its telemetry, the double-submit latch, and the gateway-unavailable alert
  where legacy shows one.
- Everything the legacy inventories name on these pages (`navigationSurface`, `stateSurface`,
  `storageSurface`). The PC funnel's coverage review found four behaviors neither app had ported: the
  `CanDeactivate` unsaved-changes prompt, the price-change alert on load, the `sessionStorage["nav"]`
  cleanup in `ngOnDestroy`, and removing `balancePayment=Y&result=` from the URL after the landing alert
  (analysis.md, P4-B1).

## URLs other systems hold

Gateway configuration and oh-api's redirect hold `/hotel/payment`, `/payment-complete` and
`/booking-complete`. Each is therefore **one unprefixed route with no locale-redirect twin**: a 302 twin
would answer a mid-payment return with a redirect (web-mobile and web-pc `app/routes.ts`).
`/hotel/booking-info` takes the locale prefix like any other page. `fm-route` Step 1d checks the route
shape and the first two items below; the third lives in oh-api, so the flip PR names it instead:

- **Native app links are path-literal.** The iOS AASA excludes the funnel paths by exact string
  (`apps/web-mobile/app/native-app-links/apple-app-site-association.json`). A URL shape v2 serves that the
  exclusions do not name falls through to `{ "/": "*" }`, and a Universal Link can then take the user into
  the native app mid-funnel. Check every shape v2 serves for the page, prefixed variants included.
- **Edge behaviors are exact paths, and the funnel flips as one unit** (`v2.pc.payment-funnel` in
  `infra/cloudfront/v2-routes.json`). `/payment-complete` and `/booking-complete` flip together and after
  `/hotel/payment`. A flipped terminal that navigates to an unflipped one hands the user a 404 after the
  money is taken (web-mobile `app/routes.ts`, flip-unit note).
- **The return host must be on oh-api's allow-list.** oh-api keeps only the path of the `returnUrl`, and
  only when its host (or `host:port`) is in `api.paymentReturnAllowedHosts` (`application.yml`;
  `PaymentCallbackUtil.normalizeReturnUrl` returns `null` otherwise). A new domain or dev port needs an
  oh-api config change first. The monorepo cannot verify this, so the flip PR names it under Migration
  notes.

## Shared code

The funnel's pure modules live in `@omh/shared-funnel` (`packages/shared-funnel/src/{payment,booking}`).
They were lifted from web-mobile with their tests, and web-mobile keeps one-line re-export shims. The React
hooks (`use-*`) and the `*.server.ts` modules stay per app. `shared-domain/payment` still holds only its
three client-safe modules (`templates/shared-package-conventions.md` → Secret boundary). PC pages reuse
logic and view-models only, never mobile markup.

## Testing

The flow has two legs. Test each one where it can be observed:

1. **The storefront contract.** A non-transactional scenario under MSW, with a stub of the gateway SDK.
   Assert:
   - the prepare request body: booking item code, the displayed payable amount, `payType`, coupons;
   - the form handed to the gateway: fields and their order, with `action` = oh-api's callback;
   - the handling of each landing hop (`result=success|fail`, `stage=auth|verify`).

   Two traps from the PC suite: `page.route` does not see requests a service worker answers, and the SDK's
   callback is a form navigation that no mock intercepts.
2. **The real gateway.** One `transactional: true` scenario per gateway, run against the staging or dev
   test endpoints in `stagingConfig.paymentGateways`. When the sandbox cannot run it, record it `not-run`
   with the reason. Never run against production. Known blockers:
   - OnePay's `mtf.onepay.vn` sandbox answers `INVALID_INVOICE` (OMH-795).
   - Legacy's `aliAuth` and `hana` NicePay accounts have no sandbox merchant in any legacy environment file.
     On v2, Alipay+ reaches the checkout page on dev, but a completed payment needs a NicePay Alipay+ test
     wallet (analysis.md, P4-E1).
   - NicePay can be verified on dev with a signed postback.

The legacy dual-run compares the preserved half: window model, form fields and order, alert copy,
telemetry. The redesigned half is asserted against this document. Its divergence from legacy is the
approved `openApprovals` entry, not a failure.

## Pipeline status

No funnel page appears in `docs/migration/tracker.json` for any app: they were ported by hand under OMH-839
(mobile) and OMH-459 (PC). Bringing them into the pipeline, or recording an owner-approved exception, is an
owner decision.
