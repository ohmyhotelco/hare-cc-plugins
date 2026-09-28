# TDD Rules (Generation Phases)

The discipline `tdd-cycle-runner` follows. Adapted for migration: behavior comes from the legacy
Angular source (via `analysis.json` + `migration-plan.json`), not a greenfield spec.

## Iron law
No production code without a failing test first.

## Red → Green → Refactor
1. **Red** — write the test for one unit of planned behavior (ported from the legacy logic +
   its edge cases). Stub the module so it fails on the **assertion**, not on MODULE_NOT_FOUND.
   Run Vitest from `{appDir}`. **Read the output; confirm it fails.**
2. **Green** — minimal implementation to pass, applying `angular-to-react-mapping.md`. Run Vitest.
   **Read the output; confirm it passes.**
3. **Refactor** — clean up; keep green.

## Verify RED and GREEN are mandatory
Actually run Vitest and read the summary line. Never skip, never assume. This is the CLAUDE.md
"evidence before claims" 5-step gate applied to tests:
IDENTIFY → RUN → READ → VERIFY → CLAIM.

## Green must survive a mutation (the test earns its green)
After a unit goes green, break the **one behavior you just made pass** in the production code —
delete the guard, invert the condition, or stop passing the prop — rerun Vitest, confirm the test
goes **red**, then revert. A test that stays green asserts nothing about that behavior; strengthen
the assertion before moving on. Scope is the just-written behavior only (one mutation, seconds), not
the whole file. This is the cheapest defense against the false-green class where a wrong reading of
the legacy source produces a test and an implementation that agree with each other (OMH-749).

## Phase isolation
Each TDD phase (`api → store → component → page`) runs in its own agent session. The
coordinator passes only that phase's parameters — no conversation context leaks between phases
(subagent isolation).

## Stub-first for imports
Create minimal stubs so tests fail on assertions, not on missing modules.

## Anti-patterns (do not)
- Test mock behavior — assert on component output / return values instead.
- Add test-only methods to production code.
- Create incomplete mocks — MSW responses must match the full TypeScript interface.
- Mock anything but the network boundary — use real stores, real components.
- Claim a pass you did not run.

## Async: a rendered node is not an attached listener
`findBy*` resolves shortly after the node is in the DOM: Testing Library's async wrapper yields one
`setTimeout(0)` after its check passes. A `useEffect` is a **passive** effect, run by React's scheduler
as a separate task after the commit, and nothing orders that task before the timer. With an asynchronously resolved route (`createRoutesStub`, a loader, a lazy
route) the commit lands after the `act()` around `render()` has exited, so there is a real window in
which the element is on screen and the effect that attaches its `window`/`document` listener has not
run. A loaded CI runner widens it. Two rules, both machine-checkable (`test-reviewer` flags them):

- **Let the scheduled effects run before dispatching an event a listener must receive.** After a
  `findBy*`, and before `window.dispatchEvent` / `document.dispatchEvent` / a `fireEvent` on
  `window`/`document` whose handler an effect attaches, run `await act(async () => {})`. This is a
  macrotask yield, not a direct flush: the commit happened outside `act`, so `act` has no queue of
  its own to drain. In that yield the scheduler's already-queued passive-effect task runs. Where the
  component exposes an observable sign that the listener is attached, waiting on that sign is
  stronger still. Dispatch inside `await act(async () =>
  { … })`.
- **Do not wrap a synchronous outcome in `waitFor`.** If the update under test happens
  synchronously inside the `act()` that dispatched it, assert it synchronously right after. A
  `waitFor` there waits for nothing — and when the listener is missing it turns an immediate, precise
  failure into a timeout whose message names the symptom (the element is still present), not the
  cause.

```ts
expect(await screen.findByTestId("child-body")).toBeInTheDocument();
await act(async () => {});                                  // yield so the passive effect runs
await act(async () => { window.dispatchEvent(new Event("pageshow")); });
expect(screen.queryByTestId("child-body")).not.toBeInTheDocument();   // synchronous: no waitFor
```

Origin: OMH-837 — a `pageshow` spec written as `findBy*` → sync `act(dispatch)` → `waitFor` passed
locally and failed `web-mobile-master-ci` on an unrelated PC PR. With the two rules applied the same
regression fails in ~50 ms at the line that broke.

## Migration-specific
- Import extracted logic from `@omh/shared-*`; never re-implement what `fm-extract` produced.
- Preserve legacy behavior exactly (parity is gated later by `fm-e2e`/`fm-parity`) — including
  the AuthGuard login-modal UX and the API response envelope handling.
- Tag each test with a `// scenario` comment, and — for any test that **asserts legacy behavior** —
  a `// legacy: <path>:<line> (<symbol>)` anchor pointing at the **legacy source itself**, not `analysis`/`plan`
  (those are derivatives of one reading; an anchor into them can't catch a misreading). A legacy
  anchor makes the reading checkable: a reviewer or Codex can open that exact line and confirm the
  condition the test assumes (e.g. `dirty` vs `touched`). Scope it to legacy-behavior tests only —
  tests of v2-only structure (routing, loading states) have no legacy line, so do not force an anchor
  there (a formalistic anchor is worse than none). Origin: OMH-749 (a misread `control.dirty` → a
  test asserting the wrong condition, green). **The symbol is the authoritative half.** A bare line
  number goes stale with every edit above it, and reviewers asked for member names instead after
  anchors drifted in seven PRs (OMH-936 #374 R3, OMH-935 #376 R2). `scripts/check-records.sh` checks
  that the symbol is still at the cited line and reports where it moved.
- **Pure transforms are pinned to the legacy output (golden test), not spot-checked.** When a phase
  ports a **pure transform** — a sanitizer, formatter, serializer, URL builder, any
  input→string/DOM function — the test target is the **full legacy output** over a **representative
  input set** (a golden / differential test), not a handful of behavior assertions. Behavior
  spot-checks (dangerous tag removed, `javascript:` stripped, script allowed) are a **supplement,
  never a substitute**: a port can pass all of its own spot-checks and still reshape the output —
  `<body>` wrapper dropped, `outerHTML`→`innerHTML`, array↔scalar, `null`↔`''`. "Passes its own
  tests" and "produces the legacy output" are **different claims**; only the golden test proves the
  second. Port the legacy call's options verbatim (`angular-to-react-mapping.md` → **pipes-directives**),
  and record any deliberately-agreed difference (e.g. an `iframeResizer` script replaced by a React
  binding) explicitly rather than letting it drift. Origin: OMH-708.
- **Request bodies must obey their own schema — pin the shape, don't trust the type** (`api` phase).
  A body assembled from `...getCommonRequestParams()` (or any spread) can carry a field the endpoint
  schema `.omit()`s from the root — TypeScript's excess-property check **only fires on object
  literals**, so a spread-reintroduced field slips past the compiler while the type claims it is
  gone. The runtime body then contradicts its own type, and **only the real backend rejects it**
  (400 `error.common.schema.invalid.request`) — every static/mock gate passes. Two things prevent
  it: (1) the builder **returns its body parsed through the endpoint `RqSchema`** so non-strict zod
  strips the stray key; (2) a **body-shape test** asserts the omitted field is **absent at the top
  level** and present where it belongs (e.g. inside `condition`). Keep the request schema non-strict
  so `.parse()` filters rather than throws. Origin: OMH-748 — a login body spread the root
  `stationTypeCode` back in and the backend rejected it 400.
- **Untrusted input never reaches `.parse()` in render or a loader.** URL params, cookies,
  web-storage records and legacy-written values are checked **at the boundary** with `safeParse`, with
  the legacy fallback, before any body is built from them; write one malformed-value test per source
  (`?userNo=1.5`, `?o-cur=usd`, a legacy nation `HANS`). When you fix one builder, fix every sibling that
  reads the same input. Every data route exports an `ErrorBoundary`, and a route-level test proves a
  loader or parse failure renders legacy's error copy rather than the framework's 500
  (`angular-to-react-mapping.md` → http).
- **A request is tested for where its values come from and how often it fires.** The body test asserts
  each field's source from `apiCalls[].fieldSources` — a correct shape with the wrong source passes a
  shape test. Where `firesPerAction` is `every`, add a request-count assertion (A→B→A toggle-back,
  same-body re-emit); the TanStack Query defaults hide exactly this (`angular-to-react-mapping.md` →
  state).
- **Wiring is tested through the route's default export.** A seam test that injects a prop proves the
  component, not that the route passes the prop. Anything that depends on route-level wiring — an
  identity gate, a handler, a safety flag — gets at least one test that renders the route's default
  export and drives it, and a safety prop defaults to its fail-safe value (OMH-756 #309, OMH-749 #335,
  OMH-839 #396 M17). A legacy-behavior helper with no route-reachable caller is not done, however green
  its own tests are (OMH-839 #396 H3: a load-time price alert implemented and never called).
- **New files are kebab-case** (CLAUDE.md → File Naming). Name every file you create in kebab-case —
  `traveler-form.tsx` and its test `traveler-form.test.tsx`, never `TravelerForm.tsx` — while the
  exported identifier keeps its own convention (component/type PascalCase, function/hook camelCase:
  `use-faq-answer.ts` exports `useFaqAnswer`). A dotted role suffix follows the one the directory
  already uses (`.test`, `.queries`, `.service`). Framework-reserved names (`root.tsx`, `routes.ts`,
  `entry.client.tsx`) and tool configs keep their exact names. Never rename an existing file to
  conform — create new files kebab-case, leave existing names alone.
