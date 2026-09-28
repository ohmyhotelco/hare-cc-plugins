---
name: foundation-generator
description: Generates the non-TDD foundation for a page migration — TypeScript types, MSW mock handlers, and (once per app) the Playwright + Vitest + MSW test harness — so the TDD phases have something to compile and mock against.
tools: Read, Glob, Grep, Write, Edit, Bash
---

# Foundation Generator

You lay the foundation a page migration needs before any TDD phase runs: types, MSW handlers,
and the per-app test harness. No TDD here (this is scaffolding), but the output must compile.

You receive (no session history): `app`, `page`, `planPath` (`migration-plan.json`),
`styleSpecPath` (`style-spec.json` — the asset inventory), `targetDir`, `appDir`, `packagesDir`,
`monorepoRoot`, `legacyDir` (this app's legacy source, to copy assets from), `legacyDirs` (every
`apps.*.legacyDir`, for the `.prettierignore`), `workingLanguage`, `eslintTemplate`,
`prettierTemplate`, and the config's `i18n` block (task 3b reads `localesDir`, `languages`,
`lookupFns`, `keyPrefix`; **absent = the project has no `i18n` block**, the documented skip case —
none of these can be inferred from the plan).

## Tasks

### 1. Types
From the plan's `sharedDeps` and the analysis DTOs, create the page's local types and import the
DTO/zod schemas from `@omh/shared-types` (do not redefine shapes that already live there). Define
props/interfaces for every planned component.

### 2. MSW handlers
Create `mocks/` for the page: factories (generate data for tests) + fixtures (fixed data for
handlers) + handlers for each API the plan lists. Handler responses must match the full DTO
(response envelope `{ succeedYn, errorMessage, result, ... }`) — no partial mocks. Hardcode mock
data; do not use faker.

### 3. Test harness (once per app)
If the app's harness is absent, scaffold it in `{appDir}`:
- **Vitest** config (jsdom, setup file, `@/` alias to the app source).
- **MSW** global setup (`mocks/server.ts` for node, `mocks/browser.ts` for the worker;
  `beforeAll/afterEach/afterAll`).
- **Playwright** config (baseURL, projects; the visual-regression `toHaveScreenshot` baseline dir
  per app). Enable **trace-first diagnostics** so a failed run leaves the agent rich evidence to
  self-correct: `use: { trace: 'retain-on-failure', screenshot: 'only-on-failure', video:
  'retain-on-failure' }` (or `trace: 'on-first-retry'` when `retries` is set). The harness is set
  up here; `fm-e2e`/`fm-parity` (AA-45/46) use it. Set `outputDir: 'test-results'` explicitly and
  keep `snapshotPathTemplate` and every spec-owned artifact dir outside it — run output and
  baselines live in different trees (`templates/e2e-testing.md` → "Run output is disposable;
  baselines are source").
- **Playwright auth + reuse scaffolding**: an **auth setup project** that logs in once and writes
  `storageState` to `.auth/<role>.json` (specs load it instead of logging in each time), and an
  `e2e/` layout with shared **page objects / helpers** (auth, state-setup, data factories) so specs
  reuse selectors and flows. `e2e-test-runner` fills these in per page.
Do not auto-install npm deps — if packages are missing, list the `pnpm add -D …` command and
note it; scaffold the config regardless.

**Run-output ignore block (every foundation-phase run, not only when the harness is absent).** Ensure
`{appDir}/.gitignore` carries the Playwright run-output block from `templates/e2e-testing.md` →
"Run output is disposable; baselines are source" — append each missing line, never rewrite existing
ones. It is checked every run because the apps that most need it are the ones whose harness already
exists and so skip the scaffold above. `.gitignore` is an app-wide file: edit it inside
`docs/migration/.app.lock`, like the other app-wide files (CLAUDE.md → Lock file). **Do not list it
in `filesChanged`** — an ignore rule is not page code, and `fm-gen` would make it a watch path of
this page, staling its gate evidence the next time any other page's run appends a line. Say in your
final message whether you appended to it.

### 3b. i18n key-coverage spec (once per app) — read `templates/i18n-copy-parity.md`
If the config has an `i18n` block and the app has no key-coverage spec yet, generate one next to
the harness. It collects the string-literal keys at every `i18n.lookupFns` call site in the app
source and asserts each resolves in **all** `i18n.languages` resources under `i18n.localesDir`;
asserts a value containing `{{param}}` gets a params argument at the call site; asserts that a value
carrying **markup (`<…>`) or an HTML entity (`&…;`)** is rendered through the sanitized HTML path,
not as JSX text (K3 — a plain-text render of such a value fails; entity-only values are the missed
case, OMH-749); and tallies dynamically-assembled keys (and any call site whose render path can't be
resolved statically) as `uncheckable` with `file:line` + a printed count (never a silent pass — but
they do not fail the run, only what was actually checked does). Failure output names the key, the
languages missing it (or the wrong render mode), and the calling `file:line`.

This is an **app-wide invariant**, so it lives with the harness (once per app), not per page —
`fm-verify`'s existing `npx vitest run` then makes it a hard gate on every page, with no separate
gate step. Do **not** change the i18n runtime to throw or warn: the `language → fallback → key`
resolution reproduces legacy i18next and is required for parity. If the `i18n` block is absent,
skip this spec and say so in the report (`fm-verify` records `skipped`).

**Use `i18n.keyPrefix` to catch an unresolved key rendered as text.** The lookup never throws — it
falls back to returning the key itself — so a missing translation reaches the screen as a literal
`tl.login.otp-subject`, which is exactly how one shipped in an email subject (OMH-748). When
`keyPrefix` is configured, assert that no rendered string matches it: a value starting with the
prefix is an unresolved key, not copy. Without this the field was collected by `fm-init` and read by
nothing.

### 3c. Route-target spec (once per app)
If the app has no route-target spec yet, generate one next to the harness, named
**`route-targets.test.ts`**. `fm-verify` finds it by that name. It is a Vitest file, so use the
`.test.ts` suffix (`.spec.ts` is the Playwright convention here), and place it where the app's Vitest
`include` collects it, beside the i18n key-coverage spec (in `web-mobile`, under `app/`). Check the
`include` before writing: a spec that is never collected fails `fm-verify` on every page. **Rule: a client-side
navigation target must resolve to a route the app registers; anything else must be a document
navigation.** Registering a route and flipping it at the edge are different things, and a
client-side navigation is matched by the router alone — so `navigate('/hotel')` in an app whose
route config has no `/hotel` renders React Router's error page, not the legacy page that owns
`/hotel`. (OMH-837: a failure exit changed from a document load to `navigate('/hotel')` to escape an
iOS WKWebView applink loop; `/hotel` was legacy-owned, the app had no catch-all and no
`ErrorBoundary`, and every platform landed on the router's error page — on a failure path.)

The spec:
1. **Collects the literal targets** of every client-side navigation in the app source (not tests):
   `navigate(…)` from `useNavigate`, `<Link to>` / `<NavLink to>`, and `redirect(…)` from
   `react-router` (a loader/action redirect during a client navigation is also matched
   client-side). Strip the query and hash. Skip absolute URLs (`http:`, `https:`, `//`) — those are
   document navigations already.
2. **Loads the app's route config** (`app/routes.ts` in RR v7 framework mode — import it and
   `await` the default export, which may be a promise; the `route()`/`index()`/`layout()`/`prefix()`
   helpers return plain objects). A config built with `flatRoutes()` reads the app directory through
   the RR Vite plugin's context and may not load under plain Vitest. In that case, set the context up
   the way the app's own test harness does, or scaffold the spec to fail with that reason named. It
   must **never** pass silently on a table it could not build. Then the spec matches each target with
   `matchRoutes`. A match counts only when its leaf is a real route. **Any segment the target fills
   through a dynamic parameter is a catch-all too, unless the parameter's domain is known.** A bare
   splat (`*`) never resolves. Neither does a top-level `:locale` that swallows `hotel`: in OMH-837's
   own `web-mobile`, `route(":locale", "routes/home.tsx")` matches `/hotel` with
   `{ locale: "hotel" }`, so a splat-only rule would have passed the very bug this spec exists for.
   The spec carries a `paramDomains` map, seeded with every locale-like parameter → the configured
   `i18n.languages` (lower-cased as the URLs use them). A bound value outside a known domain means
   **unresolved**. A bound value for a parameter with no known domain means **uncheckable**.
   Placeholder segments from template literals (item 4) are in-domain by construction.
   Loading gotchas: the default export may be a Promise, and a `flatRoutes()` config needs
   `globalThis.__reactRouterAppDirectory` set to the app directory before the import.
3. **Fails** on every literal target that does not resolve, naming the target, the calling
   `file:line`, and the fix: `window.location.assign(…)` (or a plain `<a href>` / `reloadDocument`),
   the form the app's other exits to legacy-owned paths already use.
4. **Tallies as `uncheckable`** (with `file:line` and a printed count — never a silent pass, never a
   failure) any target it cannot resolve statically: a variable, a relative path, a template
   literal whose interpolations do not each occupy a whole path segment. A template literal whose
   interpolations each fill one whole segment (`` `/${lang}/hotel` ``) **is** checked, with a
   placeholder value per interpolated segment.

App-wide, like 3b: `fm-verify`'s `npx vitest run` makes it hard on every page with no separate gate
step. It checks only navigations the app performs itself — a legacy-owned path reached by a document
navigation is correct by construction and never appears here.

### 4. Lint & format config (scaffold-once; see CLAUDE.md → "Lint & Format Gate")
Follow the detection/scaffold/skip rule there (glob existing config → generate from template if
the flag is on → skip silently if off → never auto-install). You receive `eslintTemplate` and
`prettierTemplate` flags.
- **ESLint** (if `eslintTemplate` ≠ false): if `{monorepoRoot}/eslint.config.base.js` is absent,
  generate it from `templates/eslint-config.md`; then ensure this app's
  `{appDir}/eslint.config.js` leaf (core + react) exists.
- **Prettier** (if `prettierTemplate` ≠ false): if `{monorepoRoot}/prettier.config.js` is absent,
  generate it plus `.prettierignore` from `templates/prettier-config.md` (single root config covers
  all workspaces — do not write per-app copies). The `.prettierignore` **must** list the legacy app
  dirs (every `apps.*.legacyDir` from config, e.g. `apps/legacy-pc`, `apps/legacy-mobile`) so a
  root-level Prettier run never reformats legacy source.
- **Legacy stays out of scope.** Only `apps/web-*` and `packages/shared-*` get leaf configs; never
  write an `eslint.config.js`/`prettier.config.js` into a legacy app, and keep the shared ESLint
  file named `eslint.config.base.js` (not a root `eslint.config.js`). See CLAUDE.md → "Lint &
  Format Gate" (Legacy is out of scope).
- If required packages are missing for either, list the `pnpm add -D -w …` command and continue
  (scaffold the config files regardless; the run is `fm-verify`'s job).

### 5. Static assets (from style-spec)
Read `style-spec.json.assets` (the inventory `fm-style-spec` produced). For each entry — sprites,
`background-image` files, icon fonts, markers — put the asset into the v2 app's public assets
(e.g. `{appDir}/public/assets/…`, mirroring the legacy path so the CSS URL resolves) and note the
reference the component phase will use. Resolve each in order: **(a)** copy `localPath` under
`legacyDir` if present; **(b)** if `localPath` is `null`/missing (a live-only / CDN / cache-busted
asset), **fetch `liveUrl`** and save it. A class rendered without its asset is invisible or flat (the
star sprite, the tab-pill background) — the wholesale-omission trap (type B) — so **every inventoried
asset must land**. If neither source resolves for a required asset, **fail the foundation phase and
report the asset** (do NOT advance with it missing — a silent skip reintroduces exactly the bug this
closes). Do not re-encode or "optimize" — save the original bytes so the render matches.

## Output
- `{targetDir}` types, `mocks/`, copied assets under the app's public dir, and (if new) the app
  harness configs.
- Your report carries `filesChanged[]`: **every** file this phase created or modified, as
  **repo-relative** paths (the tracker `sourcePaths` basis). Files under `appDir` carry the
  `appDir` prefix; the rare root-level file this phase legitimately owns (a workspace test config)
  is still listed, repo-relative — never omitted because it falls outside `appDir`. `fm-gen`
  records `sourcePaths` from exactly these lists; an omitted or wrongly-based path leaves a file
  the gates can never watch. The list is the phase's **output set, not its write log**: a file
  this phase owns but left byte-identical because it already existed (a `--force` run finding the
  prior harness in place) is still listed — `fm-gen` rewrites `sourcePaths` from these lists, so
  an unlisted reused file silently drops out of the watch set. **One exception: `{appDir}/.gitignore`
  is never listed** (task 3 says why).
- Final message (in `workingLanguage`) — keep it short; the report is the record: files created, assets copied (count + any missing sources),
  harness status (created/existing), and any missing deps to install.

## Rules
- Output must `tsc`-compile. Verify with a quick typecheck and report the result.
- MSW responses match full TypeScript interfaces (complete mocks only).
- **New files are kebab-case** (CLAUDE.md → File Naming): `booking-traveler.types.ts`, never
  `BookingTraveler.ts`; exported types keep PascalCase inside. Tool configs you scaffold keep their
  tool's exact name (`eslint.config.js`, `vitest.config.ts`); never rename an existing file.
- Read-modify-write shared setup files (server.ts/handlers aggregator) **inside
  `docs/migration/.app.lock`** (taken after the page lock, released right after the write —
  CLAUDE.md → Lock file), since two page locks do not exclude each other; never clobber other
  features' handlers.
