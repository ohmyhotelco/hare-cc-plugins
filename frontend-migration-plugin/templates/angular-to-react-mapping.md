# Angular → React Mapping Catalog

The canonical idiom-by-idiom mapping for migrating the OhMyHotel Angular 15 apps to
React Router v7. Grounded in the actual PC (`ohmyhotel-pc-analysis`) and Mobile/Hana
(`ohmyhotel-mobile`) source. The `angular-analyzer` references each section by its `id`
(the `## {id}` heading) in `analysis.json.mappingNotes[].catalogRef`.

Target stack: React Router v7 (framework mode) · TanStack Query · Zustand · axios ·
react-hook-form + zod · shadcn/ui · i18next · dayjs. Anchors like `file:line` point at
representative legacy source; verify against current source before relying on a line number.

---

## components

`@Component` class with constructor DI → function component with hooks/props/context.

| Angular | React |
| --- | --- |
| `@Component({ selector, templateUrl, styleUrls })` | function component + Tailwind/CSS module |
| constructor DI (services) | custom hooks / context / direct imports |
| `@Input() x` | prop `x` |
| `@Input() set x()` (setter side effects) | prop + `useEffect`/derived state |
| `@Output() e = new EventEmitter()` | callback prop `onE` |
| `@ViewChild('el')` | `useRef` |
| `ngOnInit()` | `useEffect(() => {...}, [])` |
| `ngOnDestroy()` | `useEffect` cleanup return |

**God components.** `hotel-booking-info.component.ts` (~1939 lines, ~21 injected deps; owns
booking + payment + traveler form + coupons + requests) and `hotel-payment.component.ts`,
`hotel-search-result.component.ts` must be **split** into composed React components — do not
port 1:1. The analyzer proposes `splitSeams`; `fm-plan` finalizes the component tree.

## templates

| Angular template | React JSX |
| --- | --- |
| `*ngIf="c"` | `{c && (…)}` / early return |
| `*ngIf="c; else t"` | ternary `{c ? … : …}` |
| `*ngFor="let x of xs; index as i"` | `{xs.map((x, i) => …)}` (stable `key`) |
| `*ngSwitch` | switch / map lookup |
| `ng-container` | fragment `<>…</>` |
| `ng-template` + `*ngTemplateOutlet` | render-prop / component |
| `ng-content` / `[mainContents]` named slots | `children` / named slot props (`<Layout main={…} bottom={…}/>`) |
| `[prop]="v"` | `prop={v}` |
| `(event)="h($e)"` | `onEvent={h}` |
| `[ngClass]="{…}"` | `className={cn(…)}` (`tailwind-merge`/`clsx`) |
| `[style.x]="v"` | `style={{ x: v }}` |
| `[innerHTML]="v | safeHtml"` | sanitized `dangerouslySetInnerHTML` — **port the DOMPurify options verbatim** (see **pipes-directives** note; `RETURN_DOM`+`.outerHTML` ≠ default string return) |

Example: `pages/hotel/hotel.component.html` (named slots `mainContents`/`bottomContents`) →
a layout component with slot props.

## modals

ng-bootstrap is used at **~260+ call sites** in Mobile. Replace wholesale.

| Angular | React |
| --- | --- |
| `NgbModal.open(Cmp, opts)` | shadcn `Dialog` (controlled `open` state) |
| `NgbActiveModal.close(result)` | `onOpenChange(false)` + resolve callback |
| `modalRef.componentInstance.x = …` | pass props to the dialog content |
| `modalRef.result.then(…)` | promise/callback from the dialog host |
| `AlertService.addMessage(…)` (single-queue) | shadcn Sonner `toast` / alert dialog |

Anchor: `hotel-payment.component.ts:1105` `goToLogin()` opens `LoginModalComponent` and chains
on `.result`. Note the LoginModal-on-guard UX (see **guards-init**).

## state

The app uses a **Facade layer** in front of NgRx — components never touch the store directly.

| Angular | React |
| --- | --- |
| `*.facade.ts` method (`loadX` / `getX$`) | **custom hook** `useX()` wrapping Query + Zustand |
| `store.dispatch(loadX({ body }))` | `useQuery`/`useMutation` (server) |
| `store.select(getX)` (selector) | hook return value / Zustand selector |
| NgRx Effect `ofType→switchMap→service.POST_*→map→Set` | TanStack Query `queryFn`/`mutationFn` — **with the cache policy legacy actually has** (see note below) |
| reducer `on(setX, …)` | Query cache / Zustand setter |
| `catchError(() => EMPTY)` in an effect | the effect swallows the error, but that does not make the page silent: `ApiService.handleError` runs first and may already have raised the global alert (see the http rows — it differs per app). Port what the user saw, not the effect's silence — and check the endpoint against legacy's silent list (`isSilentErrorEndpoint`, e.g. `/user/agree-terms`). The analyzer flags every site |

Server state (API-backed lists/details) → TanStack Query. Client/UI state (search form, locale,
toggles) → Zustand (thin). Anchors: `store/hotel/hotel.facade.ts`, `store/hotel/hotel.effects.ts`,
`store/booking/*`.

> **TanStack Query caches by default; legacy does not.** A legacy effect sends its POST on every
> dispatch and the reducer overwrites the slice, so every user action reaches the backend. TanStack
> Query does the opposite unless told otherwise: a result stays fresh for the app's default
> `staleTime` (`app/lib/query-client.ts`, 60 s at review time), an identical key is answered from cache
> with no request, and a window refocus refetches. Ported as-is, an A→B→A filter toggle sends no third
> request and the wish heart reverts (OMH-935 #362 H1); a re-search refetches the pre-reset key
> (booking-history L1); a refocus re-runs a read whose failure raises an alert (OMH-936 #339). So for
> each `apiCalls[]` entry read the analysis `firesPerAction` and set the policy to match it:
> `staleTime: 0` — and no dedupe of an identical body — where legacy sends the request on every
> action; `refetchOnWindowFocus: false` unless legacy re-reads on focus; invalidate exactly what legacy
> re-reads after a mutation, no wider (`couponKeys.all` was too wide, OMH-937 #329); per-open loading
> reads `isPending`, not `isFetching`. **Per-user queries are identity-scoped**: key them by the member
> id or clear them on every session change, or a login mid-page keeps the guest rows and submits as a
> guest (OMH-935 #362 item 13, OMH-839 #396 H4). Record the policy per query in the plan's mapping row
> and pin it with a request-count e2e scenario (`migration-plan-schema.md` → Legacy inventory
> reconciliation).

## reactivity

| Angular RxJS | React |
| --- | --- |
| `BehaviorSubject` (e.g. `userToken$`) | Zustand store / `useState` + context |
| `Subject` for input (`emailTextChanged`) + `debounceTime` | `useState` + debounced effect / `useDeferredValue` |
| `obs.pipe(takeUntil(this.subscribes)).subscribe()` | `useEffect` with cleanup (no manual takeUntil) |
| `take(1)` one-shot | `useQuery`/await in loader |
| `combineLatest([a$, b$])` | derive from multiple hook values |
| async pipe `x$ | async` | direct value from hook |

Anchor: `app.component.ts:50,94-147` (`subscribes = new Subject()` + `takeUntil` + `ngOnDestroy`).

## forms

Hybrid reactive + `ngModel`, with a custom `Control[]` config and CVA inputs.

| Angular | React (react-hook-form + zod) |
| --- | --- |
| `Control[]` + `formControlService.toFormGroup()` | `useForm({ resolver: zodResolver(schema) })` |
| `Validators.required/pattern/maxLength` | zod schema rules |
| `FormArray` (rooms/travelers) | `useFieldArray` |
| `[(ngModel)]` standalone | controlled input / `register` |
| `ControlValueAccessor` custom input (`NG_VALUE_ACCESSOR`, `InputTextComponent`) | component wrapped in RHF `Controller` |
| `[disabled]="form.invalid"` | `formState.isValid` |

Anchors: `pages/find-password/find-password.component.ts:46` (`Control[]`),
`common/components/input-text/input-text.component.ts:35` (CVA),
`hotel-booking-info` travelers/rooms `FormArray`.

## di-services

| Angular | React |
| --- | --- |
| `@Injectable({ providedIn: 'root' })` stateful service | Zustand store or React context |
| pure utility service (`UtilDateService`, `CommonUtilService`) | plain module functions in `shared-domain` |
| `HttpClient` wrapper (`ApiService`) | axios instance (`shared-data`) |
| service holding observable state | hook + store |

See **http** and `templates/shared-package-spec.md` for where each lands.

## http

| Angular | React |
| --- | --- |
| `apis/services` `POST_*`/`GET_*` (`ApiService.post`) | axios call in `shared-data/services` |
| `usertoken` header injection | axios request interceptor |
| `timeout(environment.timeOut)` + `handleError` | axios timeout + error interceptor. **`handleError` is a user-visible failure path, not logging — and it differs per app, so read it in each app's `core/services/api.service.ts`.** On legacy-pc every failed call shows an alert ("Updating service. Please try again later." for a transport failure, `status 0`; a generic message otherwise) whose confirm runs `window.location.reload()`; it stays quiet only when the browser is offline (the network service alerts instead) and for endpoints on `isSilentErrorEndpoint`. Legacy-mobile's shows the alert with no reload, and as written it returns early — with no alert — whenever `error.url?.indexOf("/hana/session-user")` is truthy, which includes `-1`. A v2 page that turns a legacy-alerted failure into an empty list or a silent no-op has dropped this path (OMH-749 #191, OMH-936 #339) |
| `HttpHelperService` session-expiry (`'Invalid Session Token'`/`'Session Expired'` → remove token + LoginModal) | axios response interceptor with a UX callback (modal on PC / route on mobile) |
| `getCommonRequestParams()` (localStorage `locale`) spread into body | `shared-data` request builder reading the locale store — **parse the assembled body through its endpoint `RqSchema` at runtime** (see note below) |
| response envelope `{ succeedYn, errorMessage, result, transactionSetId, errorCode }` | typed in `shared-types` (zod); unwrap in the query layer — **`errorMessage` is not display copy** (see note) |

Anchors: `core/services/api.service.ts:65,100`, `apis/services/http-helper.service.ts:28`,
`core/models/condition.model.ts:5` (`getCommonRequestParams`).

> **The response `errorMessage` is not display copy — do not render it.** The backend resolves that
> field against a **hardcoded EN locale** (OMH-784), so drawing it puts English on a Korean (or JA/
> ZH/VI) screen. It sits right there in the unwrapped envelope, which is exactly why a generator
> reaches for it — but legacy never displays it: its login call does not even carry the server
> message back on failure (`auth.service.ts:144` returns `of(false)`). Legacy resolves failure copy
> one of two ways, and the plan records which per surface (`copyBindings[]`):
> - a fixed localized key via a form-error flag — `login-password.component.ts:114` →
>   `.html:21` renders `tl.login.fail-message`;
> - an `errorCode` → i18n-key lookup table — `new-password.component.ts:141` +
>   `common/utils/password-error.util.ts` (6 codes).
>
> Use `errorMessage` only where the plan carries an explicit `server-message` binding. See
> `templates/i18n-copy-parity.md` (K2) and `migration-plan-schema.md` → Copy-source reconciliation.

> **A request body must obey its own schema at runtime — not just at the type level.** The common
> builder (`getCommonRequestParams()`) returns the shared envelope (e.g.
> `{ stationTypeCode, currency, country, language }`), but some endpoints **omit** a root field from
> that envelope — a login body is `CommonRequestParamsRqSchema.omit({ stationTypeCode: true })`
> (`stationTypeCode` lives inside `condition`, not at root). The trap: TypeScript's excess-property
> check fires **only on object literals**, so a field re-introduced by a **spread**
> (`...getCommonRequestParams()`) is *not* caught — the type says "omitted" while the runtime body
> carries it. The real backend strict-rejects the extra root field (`400
> error.common.schema.invalid.request`) even though every static/mock gate passed.
> **Fix at generation:** build the body, then return it **parsed through the endpoint's zod schema** —
> `return RqUserLoginParamsSchema.parse({ ...getCommonRequestParams(), condition: {…} })`. Default
> (non-`.strict()`) zod **strips** keys not in the schema, so an omitted root field is removed
> automatically; keep the request schemas non-strict so `.parse()` filters rather than throws. Pin it
> with a body-shape test (`tdd-rules.md` → "request bodies"). Origin: OMH-748 — a login body spread
> the root `stationTypeCode` back in and the backend rejected it 400.

> **Values the app does not control are untrusted — never `.parse()` them where a throw reaches
> render or a loader.** URL params, cookies, `localStorage`/`sessionStorage` records and anything a
> legacy page wrote arrive in shapes the zod types reject: `?userNo=1.5`, `?o-cur=usd`, a
> legacy-written nation `HANS`, a lowercase language code. A builder that feeds them into `.parse()`
> inside `useMemo`, a component or a loader turns one malformed value into a blank page, an SSR 500 or
> a reload loop (OMH-934 #317, OMH-840 #337, OMH-1126 #408) — the body-shape rule above is the trigger
> when its inputs are untrusted. Validate each untrusted input **at the boundary** with `safeParse`,
> fall back to what legacy does with the same value (usually the default it would have used), and build
> the body from the checked value; the body-shape `.parse()` then filters values that are already
> valid. Apply a fix to every sibling builder that reads the same input. **Every route that loads data
> exports an `ErrorBoundary`** that renders legacy's error copy — without one, any throw becomes the
> framework's 500 and the localized alert is lost (OMH-935 #362, OMH-937 #345). A malformed-input test
> per untrusted source is required (`tdd-rules.md`).

## routing

| Angular | React Router v7 |
| --- | --- |
| `createRoute({ path, component })` / `Routes` | route config / file route |
| `loadChildren: () => import(...)` | lazy route (`lazy`) |
| feature `*-routing.module.ts` | nested route module |
| module ctor `commonFacade.setCurrentRootUrl('/hotel')` | layout route loader / context |
| `Resolve<T>` resolver | route `loader` |
| `ActivatedRoute.params`/`queryParams.subscribe` | `useParams` / `useSearchParams` / `loaderData` |
| `routerLink` / `Router.navigate[ByUrl]` to a target **v2 serves** when this page flips (already flipped, or in the same cutover batch) | `<Link>` / `<NavLink>` / `useNavigate()`, with the locale-prefixed path from the page's language |
| `routerLink` / `Router.navigate[ByUrl]` to a target **legacy still serves** (not migrated, or dark at the edge) | a **document navigation** — `<a href>` / `window.location.assign` — to the **bare legacy path** (legacy's `APP_INITIALIZER` adds the prefix itself) |
| `window.location.href = …` (legacy full reload) | keep it a document navigation; find out why legacy reloads before changing it |
| `CanDeactivate` guard on the source route | runs on every navigation away — reproduce it (`useBlocker`, or the same check before a document navigation); never drop it silently |
| `shouldReuseRoute = () => false` / `onSameUrlNavigation: 'reload'` | a same-URL navigation re-creates the page: key the route element or revalidate so state resets as legacy's new instance did |

Anchors: `app-routing.module.ts:1`, `pages/hotel/hotel-routing.module.ts:9`,
`pages/hotel/resolvers/ads-search-result.resolver.ts`.

> **Navigation crosses the migration boundary; the mechanism follows where the target is served.**
> During the strangler period a v2 page links to pages legacy still serves, and legacy pages link to
> pages v2 now serves. A client navigation into a route the v2 app does not serve lands on the error
> boundary or the wrong route (OMH-934 #317 soft-navigated to a dark `/event`; OMH-839 #396 L7). A
> document navigation into legacy with a prefixed path makes legacy's `APP_INITIALIZER` redirect a
> second time and reset the currency (my-page-layout H1). Links **into** a migrated page are a
> migration surface too — grep the whole app, including other clusters, for its bare path (the
> sign-up consent rows linked to bare `/privacy` and `/common-agreement`, so the terms opened in the
> cookie's language). The reverse direction has its own traps: turning a legacy router navigation into
> `location.href` skips the source route's `CanDeactivate` guard (OMH-749 #335: the marketing-consent
> nudge never showed) and races any fire-and-forget request still in flight — send it with
> `keepalive`/`sendBeacon`, or await it. Changing SPA vs full-load can also re-open an incident legacy
> fixed on purpose: read the legacy file's git history before changing the mechanism (OMH-837 #261
> re-introduced OMH-941, an iOS universal-link loop). Every redirect keeps the query string (`utm_*`,
> `gclid`) unless legacy strips it (OMH-840 #337). The analysis lists each navigation in
> `navigationSurface[]`, the plan records the mechanism per target, and `fm-route` Step 1d re-checks
> the targets at flip time.

## guards-init

| Angular | React Router v7 |
| --- | --- |
| `CanActivate` guard | route `loader` redirect / `<ProtectedRoute>` |
| a guard or `canActivate` that runs on **every** navigation (route-level, or a `createRoute` wrapper applied app-wide) | a step that also runs on client navigation — a root/layout `loader` whose `shouldRevalidate` keeps it running — not a one-time `clientLoader`: a flag it clears or a `returnUrl` it stamps goes stale on child-to-child navigation (my-page-layout M1, M3) |
| `AuthGuardService` opens **LoginModal** (not redirect) on fail | preserve the modal UX — loader sets a flag / triggers the login dialog rather than a hard redirect |
| non-member token query (`?token=`) access | loader param check |
| `APP_INITIALIZER` language-prefix redirect (PC) | root loader / middleware |
| `APP_INITIALIZER` `initApp()` Hana `?ts` SSO (mobile) | `clientLoader` on the `hana` layout route (see `templates/hana-sso.md`, AA-46) |

Anchors: `common/services/auth-guard.service.ts:36,102`, PC `app.module.ts` `handleLanguagePrefixUrl`,
Mobile `app.module.ts:50` `initApp`.

## i18n

The apps use **angular-i18next** (not @ngx-translate); React reuses the same i18next +
Google Sheets pipeline.

| Angular | React (i18next + react-i18next) |
| --- | --- |
| `{{ 'tl.x' | i18next }}` | `{t('tl.x')}` via `useTranslation()` |
| `I18NEXT_SERVICE.instant('tl.x')` / `.get(...)` | `t('tl.x')` / `i18n.t` |
| key namespaces `translation` / `validation` / `error` | i18next namespaces |
| remote Google Sheets source (`translate/provider.ts`) | same source, loaded into i18next |
| key style `tl.*`, `keySeparator: false`, `nsSeparator: false` | preserve these init options |

## pipes-directives

| Angular | React |
| --- | --- |
| `| i18next` | see **i18n** |
| `| date` / `| currency` / `| number` | dayjs / `Intl.NumberFormat` util |
| `safeHtml` (DomSanitizer) | sanitized `dangerouslySetInnerHTML` — **options are load-bearing, port verbatim** (see note below) |
| `minuteToHourMinute` / `numberToLocaleString` / `numberPad` | `shared-domain` util functions |
| custom directive `inputPattern` | input mask hook / controlled handler |
| `download` / `iframeResizer` directives | custom hook |

Anchors: `common/pipes/safe-html-pipe/safe-html.pipe.ts`,
`common/pipes/minute-to-hour-minute-pipe/…`, `common/directive/input-pattern.directive.ts`.

> **Sanitizer options change the output shape — port them verbatim, don't simplify to the common
> case.** `safeHtml`/DomSanitizer usually wraps a `DOMPurify.sanitize(...)` call, and its options are
> not security-strength knobs — they decide **what the function returns**:
> - `RETURN_DOM: true` (legacy reads `.outerHTML` off the returned node) preserves the **`<body>`
>   wrapper and its attributes** — e.g. `style="background:#f5f5f5;padding:24px 0"`. The default
>   string return gives only `body.innerHTML`, silently **dropping that wrapper** and any
>   background/padding on it.
> - `WHOLE_DOCUMENT` / `FORCE_BODY` likewise decide how much of the document survives serialization.
> - An `<iframe srcdoc>` host that injects a whole marketing document is **not** a plain
>   `dangerouslySetInnerHTML` of a fragment — it needs the wrapper-preserving form.
>
> Carry **every** option the legacy call passes; a missing `RETURN_DOM`/`WHOLE_DOCUMENT`/`FORCE_BODY`
> is a behavioral regression, not a harmless cleanup. General rule for any library call (sanitizer,
> formatter, serializer, URL builder): **never simplify it to its common case — the options are part
> of the contract.** Pin the result with a golden test against the legacy output (`tdd-rules.md` →
> "pure transforms"). Origin: OMH-708 — a dropped `RETURN_DOM` erased a `<body>`-level grey band
> (`#f5f5f5`) on `/event/100221` while every gate stayed green.

## analytics

| Angular | React |
| --- | --- |
| `DataLayerService` (40-event `DataLayerEvent` enum, typed `pushEvent`) | `useAnalytics()` hook wrapping `window.dataLayer.push`; enum in `shared-types` |
| `GtmService.initialize()` (script inject, `isPlatformBrowser` SSR-safe) | GTM init in root (browser-only) |
| `MetaPixelService` / `NaverLogService` / `KakaoLogService` (wrap `fbq`/`wcs`/`kakaoPixel`, skip non-prod) | thin wrappers; long-term migrate into GTM tags (plan §11.8) |
| empty `gtmContainerId` (Hana) → no-op | per-app sink filter (drop for Hana) |

Anchors: `common/services/data-layer.service.ts:36`,
`common/models/data-layer.model.ts:17`, `common/services/gtm.service.ts:25`.

## gate-triggers

These idioms set `analysis.json.requiredGates` / `gateTriggers` (drive `fm-e2e`/`fm-parity`/
`fm-secret-audit`):

| Trigger | Detect | Gate / action |
| --- | --- | --- |
| **secret** | `environment.nicePay.{simple,aliAuth,nonAuth}.merchantKey`, `environment.eximbay.key`, `environment.kakaoLoginSecretKey`; `createFgkey()` / `createNicePayData()` / `createNpAlipayData()` / `createEximbayData()` | `fm-secret-audit`. The PG signers are **not ported**: oh-api signs (`POST /payment/nicepay/prepare`, `templates/payment-flow-v2.md`), and the Eximbay builders are dead code. Anchors: `hotel-payment.component.ts:504,541,623`; `social-connect.component.ts:257,303` |
| **payment** | `goPay(`, `nicepaySubmit`/`nicepayClose`, forms posting to `v3Payment.jsp`/`pcRequest.jsp`/`smartRequest.jsp`, `/payment/onepay/getPaymentUrl`, the `pgName` return query, `/payment/np-alipay/verify`, `/payment/np-verify`, the balance-payment modal | **not a gate** — built to `templates/payment-flow-v2.md` (the v2 flow is a redesign, not a port); verified through its two-leg `e2eScenarios`; URLs checked by `fm-route` Step 1d |
| **sso** | `initApp()` `?ts`, `AuthHanaService`/`AuthHanaTSService`, `passAuth`, `POST_HANA_VERIFY_TIME`, fail-open `error.status === 0` | **not a gate** — no verifier and no report slot; becomes an `e2eScenarios` entry and is built to `templates/hana-sso.md`. Anchors: `app.module.ts:50`, `auth-hana.service.ts:28-84` |
| **webview** | `navigator.userAgent.includes('wv'|'ww')`, `universal-link.service`, `sessionStorage 'cnoUser'`, URL-scheme intents | `parity` WebView round-trip + `templates/webview-bridge.md`. Anchors: `app.component.ts:409`, `universal-link.service.ts:87` |
| **telemetry** | `DataLayerService` / `dataLayer.push`, pixel services | `parity` telemetry dual-fire (plan §11.8) |

> Note: the migration plan §11.7 describes an explicit `window.ohmyhotelAndroid.*` /
> `window.webkit.messageHandlers.*` bridge. The current Mobile web source primarily uses
> UA detection + `universal-link.service` + `sessionStorage` instead. AA-46 reconciles the
> exact bridge surface; the analyzer should flag **either** form as a `webview` trigger.
