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
| `[innerHTML]="v | safeHtml"` | sanitized `dangerouslySetInnerHTML` |

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
| NgRx Effect `ofType→switchMap→service.POST_*→map→Set` | TanStack Query `queryFn`/`mutationFn` |
| reducer `on(setX, …)` | Query cache / Zustand setter |
| `catchError(() => EMPTY)` (silent) | **do not preserve silently** — surface error or decide deliberately; the analyzer flags every site |

Server state (API-backed lists/details) → TanStack Query. Client/UI state (search form, locale,
toggles) → Zustand (thin). Anchors: `store/hotel/hotel.facade.ts`, `store/hotel/hotel.effects.ts`,
`store/booking/*`.

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
| `timeout(environment.timeOut)` + `handleError` | axios timeout + error interceptor |
| `HttpHelperService` session-expiry (`'Invalid Session Token'`/`'Session Expired'` → remove token + LoginModal) | axios response interceptor with a UX callback (modal on PC / route on mobile) |
| `getCommonRequestParams()` (localStorage `locale`) spread into body | `shared-data` request builder reading the locale store |
| response envelope `{ succeedYn, errorMessage, result, transactionSetId, errorCode }` | typed in `shared-types` (zod); unwrap in the query layer |

Anchors: `core/services/api.service.ts:65,100`, `apis/services/http-helper.service.ts:28`,
`core/models/condition.model.ts:5` (`getCommonRequestParams`).

## routing

| Angular | React Router v7 |
| --- | --- |
| `createRoute({ path, component })` / `Routes` | route config / file route |
| `loadChildren: () => import(...)` | lazy route (`lazy`) |
| feature `*-routing.module.ts` | nested route module |
| module ctor `commonFacade.setCurrentRootUrl('/hotel')` | layout route loader / context |
| `Resolve<T>` resolver | route `loader` |
| `ActivatedRoute.params`/`queryParams.subscribe` | `useParams` / `useSearchParams` / `loaderData` |
| `routerLink` | `<Link>` / `<NavLink>` |
| `Router.navigate([...])` | `useNavigate()` |

Anchors: `app-routing.module.ts:1`, `pages/hotel/hotel-routing.module.ts:9`,
`pages/hotel/resolvers/ads-search-result.resolver.ts`.

## guards-init

| Angular | React Router v7 |
| --- | --- |
| `CanActivate` guard | route `loader` redirect / `<ProtectedRoute>` |
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
| `safeHtml` (DomSanitizer) | sanitized `dangerouslySetInnerHTML` |
| `minuteToHourMinute` / `numberToLocaleString` / `numberPad` | `shared-domain` util functions |
| custom directive `inputPattern` | input mask hook / controlled handler |
| `download` / `iframeResizer` directives | custom hook |

Anchors: `common/pipes/safe-html-pipe/safe-html.pipe.ts`,
`common/pipes/minute-to-hour-minute-pipe/…`, `common/directive/input-pattern.directive.ts`.

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
| **secret** | `environment.nicePay.{simple,aliAuth,hana}.merchantKey`, `environment.eximbay.key`, `environment.kakaoLoginSecretKey`; `createFgkey()` / `createNicePayData()` / `createNpAlipayData()` | server-side relocation; `fm-secret-audit`. Anchors: `hotel-payment.component.ts:504,541,623`; `social-connect.component.ts:257,303` |
| **sso** | `initApp()` `?ts`, `AuthHanaService`/`AuthHanaTSService`, `passAuth`, `POST_HANA_VERIFY_TIME`, fail-open `error.status === 0` | `parity` SSO check + `templates/hana-sso.md`. Anchors: `app.module.ts:50`, `auth-hana.service.ts:28-84` |
| **webview** | `navigator.userAgent.includes('wv'|'ww')`, `universal-link.service`, `sessionStorage 'cnoUser'`, URL-scheme intents | `parity` WebView round-trip + `templates/webview-bridge.md`. Anchors: `app.component.ts:409`, `universal-link.service.ts:87` |
| **telemetry** | `DataLayerService` / `dataLayer.push`, pixel services | `parity` telemetry dual-fire (plan §11.8) |

> Note: the migration plan §11.7 describes an explicit `window.ohmyhotelAndroid.*` /
> `window.webkit.messageHandlers.*` bridge. The current Mobile web source primarily uses
> UA detection + `universal-link.service` + `sessionStorage` instead. AA-46 reconciles the
> exact bridge surface; the analyzer should flag **either** form as a `webview` trigger.
