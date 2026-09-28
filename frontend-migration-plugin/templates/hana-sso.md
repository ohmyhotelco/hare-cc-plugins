# Hana SSO → React Router v7

How the Hana `?ts` external SSO (~140 LOC of Angular) ports to a single RR v7 `clientLoader` on a
`hana` layout route. Used when the analysis records an `sso` entry in `gateTriggers[]` (hana only) —
as the **generation** contract for that port. `sso` is deliberately not a parity gate (no executor,
no report slot); the flow is verified as behavior through the page's `e2eScenarios`. Migration plan §7.

## Legacy surface (anchors)
- `initApp()` in `app.module.ts:50-59` — captures `?ts`, decodes it, calls
  `AuthHanaService.setToken` + `checkAuth()` (runs as `APP_INITIALIZER`).
- `AuthHanaService.checkAuth()` in `common/services/auth-hana.service.ts:28-84`:
  - `sessionStorage 'passAuth' === 'true'` short-circuit;
  - whitelist bypass for `/payment-complete` and `/hana/my-page/booking-history/K*`;
  - calls `POST_HANA_VERIFY_TIME` with the decoded token;
  - **fail-open**: on `error.status === 0` (CORS/offline/backend down) it treats auth as
    verified (`result = true`);
  - sets `sessionStorage 'passAuth'`.
- `AuthHanaTSService` guard (`auth-hana-ts.service.ts`) — `CanActivate` awaiting the auth promise.

## Target — clientLoader on the hana layout route

```tsx
// apps/web-hana/app/routes/hana.tsx
import { redirect, Outlet, type LoaderFunctionArgs } from "react-router";
import { POST_HANA_VERIFY_TIME, getCommonRequestParams } from "@omh/shared-data";

const PG_BYPASS_PREFIXES = ["/payment-complete", "/hana/my-page/booking-history/K"];

export async function clientLoader({ request }: LoaderFunctionArgs) {
  const url = new URL(request.url);
  const ts = url.searchParams.get("ts");
  const { pathname } = url;

  if (sessionStorage.getItem("passAuth") === "true") return null;
  if (PG_BYPASS_PREFIXES.some((p) => pathname.includes(p))) {
    sessionStorage.setItem("passAuth", "true");      // see decision 2
    return null;
  }
  if (!ts) throw redirect("/not-found");
  if (import.meta.env.DEV && ts === "test") {         // see decision 4
    sessionStorage.setItem("passAuth", "true");
    return null;
  }

  let res;
  try {
    res = await POST_HANA_VERIFY_TIME({
      ...getCommonRequestParams(),
      condition: { code: decodeURIComponent(ts) },
    });
  } catch (err) {
    // OMH-631 (decision 1): reproduce legacy `error.status === 0` — a transport failure (no HTTP
    // response) lets the visitor through. Do NOT fail closed here.
    if (!err?.response) {
      sessionStorage.setItem("passAuth", "true");
      return null;
    }
    throw redirect("/not-found");                      // a real HTTP error response denies
  }
  if (!res.succeedYn || !res.result) throw redirect("/not-found");   // an "invalid token" answer denies

  sessionStorage.setItem("passAuth", "true");
  url.searchParams.delete("ts");                       // see decision 3
  window.history.replaceState({}, "", url.toString());
  return null;
}

export default function HanaLayout() { return <Outlet />; }
```

All Hana routes nest under this layout. Hana ships **SPA** (no SEO surface; external SSO entry).

## Four security decisions (1 is resolved; resolve 2–4 with the Hana/HanaCard contact in the migration PR)
1. **Fail-open on network error — RESOLVED 2026-06-22 (OMH-631): keep it.** Legacy treats
   `error.status === 0` as verified, and the Hana/BE stakeholder confirmed this is a deliberate
   graceful-degradation buffer: no HTTP response includes requests dropped during our own rolling
   deploys, and a real visitor should not be blocked by those. The backend's genuine "invalid token"
   answer (HTTP 200, `result: false`) still denies. The v2 loader **must** reproduce the pass-through
   on a transport failure (the `catch` branch above) and must not default to fail-closed. The record
   is the monorepo's `docs/migration/v2-migration-plan.md` → Hana, and the legacy rationale landed via
   PR #46. This is a decision, not an open question: do not list it in `openQuestions`.
2. **PG-callback bypass scope.** Legacy sets `passAuth = true` for the whole session when hitting
   `/payment-complete` or `/hana/my-page/booking-history/K*`. Consider a **one-shot** pass (allow
   the specific render, do not persist `passAuth`).
3. **`?ts` persistence.** Legacy leaves the token in the URL (Referer/analytics leakage). The v2
   loader strips it via `history.replaceState`. Confirm no flow relies on it remaining.
4. **Dev `test` backdoor.** `import.meta.env.DEV && ts === "test"` mirrors the legacy dev
   shortcut. Decide whether to keep or drop it for v2.

## Behavior criteria (e2e scenarios)
The SSO loader verifies against staging external SSO; decisions 2–4 above are recorded as the
page's `openQuestions` until signed off. Decision 1 is settled, so its scenario asserts the
pass-through: a transport failure on `POST_HANA_VERIFY_TIME` renders the page, while an HTTP error
response and a `result: false` answer both redirect to `/not-found`. Do **not** port the dead Mobile-OMH `?ts` capture —
no OMH flow sets `?ts` (plan §7).
