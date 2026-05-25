# WebView Bridge (Mobile / Hana)

What the `parity-verifier` `webview` gate preserves. The OMH iOS and Android apps are pure native
WebView wrappers that load the mobile web; the **native shells are out of v2 scope and must not be
modified** — the v2 mobile web is responsible for staying contract-compatible. (PC has no WebView;
this gate is skipped for PC, which is the path validated first.)

## Surface to preserve

### 1. WebView detection (the load-bearing part today)
The mobile web detects the WebView context by user agent and adjusts behavior (e.g. hides
popups):
- `navigator.userAgent.includes('wv') || navigator.userAgent.includes('ww')`
  (anchors: `app.component.ts:409`, `common/services/universal-link.service.ts:87`)
- iOS device parsing (`/iphone|ipad|ipod/`) for app-download/popup logic.

The v2 web must reproduce the same detection and the same conditional behavior. Prefer a single
`useIsNativeWebview()` hook over scattered UA checks.

### 2. Universal-link / URL schemes
`universal-link.service.ts` builds Android intent schemes and relies on iOS Universal Links for
deep linking. The v2 web must construct the same scheme/intent URLs so the OS routes them to the
native handlers unchanged.

### 3. Session tokens via storage
Native ↔ web hand-off uses `sessionStorage` tokens (e.g. `cnoUser`, anchor
`pages/hana-travel/.../hotel-payment.component.ts:381`) and the shared `.ohmyhotel.com` JWT
cookie `{hostname}_userToken`. The v2 web must read/write the **same keys** with the same domain
attribute so native cookie persistence and token round-trips keep working.

### 4. Explicit JS bridge (reconcile)
The migration plan §11.7 documents an explicit bridge:
`window.ohmyhotelAndroid.doNativeAction({action, param})` /
`window.ohmyhotelAndroid.getBase64FromBlobData(...)`,
`window.webkit.messageHandlers.<name>.postMessage(...)`, and URL schemes
`ohmyhotel://openUrlShare|openPrint`, plus PG callback schemes (`iamporttest`, gateway-specific).
The current mobile web source primarily uses UA detection + universal-link + sessionStorage rather
than these globals. **Reconcile per page:** inventory the actual bridge callsites the page uses
(PDF/print/download, payment) and wire the React equivalents with the **exact same identifiers** —
do not rename. If the page uses neither, the webview gate is a no-op for it.

## Gate criteria (parity-verifier `webview`)
For a mobile/hana page, the gate passes only when, inside the iOS WKWebView and Android WebView:
- UA detection yields the same branch as legacy;
- universal-link / URL schemes reach the same native handlers;
- session token + JWT cookie round-trip identically (same keys, same domain);
- any explicit bridge call (`window.ohmyhotelAndroid.*` / `webkit.messageHandlers.*` /
  `ohmyhotel://`) round-trips identically.

A page is **not** considered migrated until it loads, navigates, and exchanges cookies correctly
inside both native shells — not just standalone mobile browsers (plan §11.7).

## Open question
Whether a Hana-branded native shell exists is unconfirmed (working assumption: Hana is
mobile-web-only). If one exists, Hana needs its own WebView verification — flag in the page's
`openQuestions`.
