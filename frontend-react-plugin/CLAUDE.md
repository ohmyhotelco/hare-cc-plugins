# Frontend React Plugin

A Claude Code plugin that applies tech stack and coding conventions for frontend React development.

## Tech Stack

### Runtime & Build
- Node.js 22.x LTS (>= 22.12)
- Package Manager: pnpm
- Build: Vite
- Language: TypeScript (strict)

### Core Framework
- React 19.x
- Routing: React Router v7 — mode is determined by the `routerMode` setting in `.claude/frontend-react-plugin.json` (default: declarative)
  - declarative: uses `<BrowserRouter>`, `<Routes>`, `<Route>`
  - data: uses `createBrowserRouter`, `RouterProvider`, loader/action
  - import: `react-router` (not `react-router-dom`)
  - Detailed routing patterns: see `.claude/skills/react-router-{routerMode}-mode` (installed by `/frontend-react-plugin:fe-init`)

### UI Layer
- Tailwind CSS
- shadcn/ui (Radix-based, code owned by the project)
- Icons: Lucide (`lucide-react`), consider adding Simple Icons when brand logos are needed

### State & Data
- Client State: Zustand (keep thin — auth token, user, permissions, etc.)
- HTTP: Axios
  - request interceptor: inject JWT Authorization header
  - response interceptor: 401 → logout/re-authenticate, 403 → sync permissions
- Mock: MSW v2 (dev & test) — network-level intercept, no production code changes
- (Future consideration) Auto-generate types/client when REST OpenAPI is available

### Internationalization (i18n)
- i18next + react-i18next
- Languages: ko / en / ja / vi
  > Note: planning-plugin supports 3 spec languages (en/ko/vi). The additional `ja` in the frontend i18n is for application UI only — Japanese specs are not supported by planning-plugin.
- Namespace separation (common, menu, per-feature)
- Lazy-load via Vite import.meta.glob
- Language selection: stored in localStorage
- Date/time: Intl.DateTimeFormat / Intl.RelativeTimeFormat (targeting latest Chrome)

### Auth / RBAC
- Server makes the final RBAC decision
- Frontend role: menu filtering, route guard (/forbidden), syncing with 401/403 server responses
- Do not implement permission logic on the frontend (UX guard level only)

### Testing
- Unit/Component: Vitest — detailed test patterns: see `.claude/skills/vitest` (installed by `/frontend-react-plugin:fe-init`)
- API mock with MSW server (Vitest integration) — reuse feature handlers in tests
- E2E: Playwright

## Conventions
- Use only shadcn/ui components (do not install alternative component libraries)
- 2-space indentation
- functional component + hooks
- Define TypeScript interface for all props/data
- icon-only button: aria-label required, decorative icon: aria-hidden="true"
- form control: must associate with <label> (htmlFor or wrapping)
- variable-length text: apply truncate / line-clamp-*
- full-page layout: set full height chain from html → body → #root → layout

### Mock-First Development
- `mockFirst: true` (default) — develop with MSW v2 without a backend
- Feature-level mock: `src/features/{feature}/mocks/` (factories + fixtures + handlers)
- Factory + Fixture separation: factory generates data for tests, fixture provides fixed data for MSW handlers
- Hardcoded mock data — do not use external libraries like faker
- Environment variable toggle: activate only in dev mode with `VITE_ENABLE_MOCKS=true`
- Global MSW: `src/mocks/` (browser.ts, server.ts, handlers.ts aggregator)

### Performance & Composition
- React performance patterns: see `.claude/skills/vercel-react-best-practices` (waterfall elimination, bundle optimization, re-render minimization)
  - Note: server-side (RSC/SSR) rules do not apply to Vite SPA — agent auto-skips
- Component composition patterns: see `.claude/skills/vercel-composition-patterns` (no boolean props, compound component, React 19 API)
- Web UI accessibility/design audit: see `.claude/skills/web-design-guidelines` (WebFetch latest guidelines during review)

### Routing Conventions
- Routes requiring authentication: wrap with `<ProtectedRoute>` → redirect to /login when unauthenticated (pass return destination via location.state.from)
- Routes requiring permissions: `<RoleRoute permissions={[...]}>` → redirect to /forbidden when unauthorized
- NavLink active state: use shadcn/ui `cn()` + `isActive` callback
- Axios 401 interceptor → /login redirect: use navigate ref pattern (do not directly import useNavigate)
- URL searchParams ↔ Zustand: bidirectional sync via useEffect + store subscription
- Internal navigation: use react-router `<Link>`, `<NavLink>`, `useNavigate` (do not use `<a>`, `window.location`)

## Architecture
- **Agents**:
  - `implementation-planner` — spec analysis → implementation plan (plan.json)
  - `foundation-generator` — types + mock infrastructure generation (no TDD)
  - `tdd-cycle-runner` — strict Red-Green TDD cycle per phase (api, store, component, page)
  - `integration-generator` — routes + i18n + MSW global setup + full verification
  - `spec-reviewer` — spec compliance review
  - `quality-reviewer` — code quality review
  - `review-fixer` — TDD-disciplined review issue fixer
  - `debugger` — systematic debugging
- **Skills**: `/frontend-react-plugin:fe-init`, `/frontend-react-plugin:fe-plan`, `/frontend-react-plugin:fe-gen` (TDD coordinator), `/frontend-react-plugin:fe-verify`, `/frontend-react-plugin:fe-review` (reviews generated source code — not to be confused with `/planning-plugin:review` which reviews the specification document), `/frontend-react-plugin:fe-fix`, `/frontend-react-plugin:fe-debug`
- **External Skills**: `react-router-*-mode` (from `remix-run/agent-skills`), `vitest` (from `antfu/skills`), `vercel-react-best-practices` + `vercel-composition-patterns` + `web-design-guidelines` (from `vercel-labs/agent-skills`) — installed by init
- **Configuration**: `.claude/frontend-react-plugin.json` (created by `/frontend-react-plugin:fe-init`)
- **Templates**: `feature-module.md` (feature module structure), `tdd-rules.md` (TDD rules adapted from obra/superpowers)

### Communication Language
- Feature-level skills (fe-plan, fe-gen, fe-verify, fe-review, fe-fix, fe-debug) read `workingLanguage` from `docs/specs/{feature}/.progress/{feature}.json`
- All user-facing output (summaries, questions, feedback, next-step guidance) must be in the working language
- Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

### Testing (Strict TDD)

TDD methodology adapted from [obra/superpowers](https://github.com/obra/superpowers). See `templates/tdd-rules.md` for full rules.

- **Iron Law**: No production code without a failing test first
- **Red-Green-Refactor**: Write test → verify failure → write minimal code → verify pass → refactor
- **Verify RED/GREEN are MANDATORY**: Actually run vitest and check the output. Never skip.
- **Phase-level TDD**: Each layer (api, store, component, page) runs a separate TDD cycle in its own agent session
- **Stub-first for imports**: Create minimal stubs so tests fail on assertions, not on MODULE_NOT_FOUND

Test infrastructure:
- Test file location: `src/features/{feature}/__tests__/`
- Test types: api (MSW server), component (@testing-library/react), page (4-state coverage), store (unit)
- Factory usage: generate test data from `../mocks/factories`
- MSW server: import from `@/mocks/server`, setup with `beforeAll/afterEach/afterAll`
- Source tracking: reference spec test scenario with `// TS-nnn` comment in each test

Anti-patterns (from obra/superpowers testing-anti-patterns):
- Never test mock behavior — assert on component output or return values
- Never add test-only methods to production classes
- Never mock without understanding dependency side effects
- Never create incomplete mocks — MSW responses must match full TypeScript interfaces
- Mock only at network boundary (MSW) — use real stores, real components

Pipeline: `/frontend-react-plugin:fe-gen` → `/frontend-react-plugin:fe-verify` → `/frontend-react-plugin:fe-review` → `/frontend-react-plugin:fe-fix` (if issues) → `/frontend-react-plugin:fe-review` (re-review)
`/frontend-react-plugin:fe-debug` remains for runtime bugs at any point

### Code Generation (TDD Phases)
- Feature spec source: `docs/specs/{feature}/` (planning-plugin output)
- Implementation plan: `docs/specs/{feature}/.implementation/plan.json`
- Generation state: `docs/specs/{feature}/.implementation/generation-state.json` (tracks phase progress, enables resume)
- UI DSL first: use structured data from `ui-dsl/` if available, otherwise infer from spec markdown
- Feature-based structure: `src/features/{feature}/` (types, api, stores, components, pages, __tests__)
- Prototypes are for reference only: do not copy code from `prototypes/{feature}/` into production code
- TDD phase execution order:
  1. `foundation` — types + mocks (foundation-generator agent, no TDD)
  2. `api-tdd` — API tests → API services (tdd-cycle-runner agent)
  3. `store-tdd` — store tests → stores (tdd-cycle-runner agent)
  4. `component-tdd` — component tests → components (tdd-cycle-runner agent)
  5. `page-tdd` — page tests → pages (tdd-cycle-runner agent)
  6. `integration` — routes + i18n + MSW global + barrel (integration-generator agent)
- Each TDD phase runs in a separate agent session for context isolation
- External skills loaded per-phase (not all at once): vitest for TDD phases, composition-patterns for components, react-best-practices for pages, router for integration
- Resume support: if generation is interrupted, re-running fe-gen resumes from the last incomplete phase

### Shared Layouts
- Shared layout location: `src/layouts/{PascalCaseLayoutId}.tsx`
- Mapping: `@layout: _shared/{layout-id}` in spec → `src/layouts/{PascalCaseLayoutId}.tsx` in production
- Slot component → `<Outlet />` from react-router
- Features do NOT import layout directly — relationship expressed via React Router nested routes
- First feature: generates layout + feature code
- Subsequent features: reuses existing layout, optionally adds nav items

### Route & i18n Auto-Integration
- Each feature generates `routes.tsx` (route definitions) and `i18n.ts` (namespace registration) in its feature directory
- Integration-generator auto-integrates by adding import + spread to the central route file and i18n config (same pattern as MSW handler aggregation)
- Supports declarative mode (`<Route>` JSX fragments) and data mode (`RouteObject[]` arrays)
- Layout route nesting: spreads feature routes under existing layout route's children when present
- Graceful fallback: if the central file has unexpected structure, falls back to manual guidance
- The implementation-planner detects aggregation patterns, insertion anchors, and existing imports in plan.json

### Debug & Progress
- Debug report: `docs/specs/{feature}/.implementation/debug-report.json`
- Verification/review results: recorded in `implementation.verification`, `implementation.review` fields of `docs/specs/{feature}/.progress/{feature}.json`
- Review report: `docs/specs/{feature}/.implementation/review-report.json`
- Fix report: `docs/specs/{feature}/.implementation/fix-report.json`
- Progress state machine:
  ```
  planned → generated → verified → reviewed → done
               ↓    ↘       ↓         ↓    ↓
           gen-failed  ↘ verify-failed ↓  review-failed
                        ↘     ↓        ↓      ↓
                         → resolved  fixing → (re-review → reviewed/review-failed)
                           escalated    ↓
                              ↓    escalated
                        (manual intervention)
  ```
  Additional transitions:
  - `generated → reviewed | review-failed` — fe-verify is optional, can go directly to fe-review
  - `fixing → reviewed | review-failed` — after fe-fix, fe-review determines next status
  - `fixing → generated` — when regen-required issues exist, fe-gen re-run resets to generated
  - `resolved → verified | verify-failed` — re-verify after debug resolution
  - `resolved → reviewed | review-failed` — re-review after debug resolution
  - `resolved → fixing | escalated` — fe-fix after debug resolution (when review issues remain)
  - `escalated` — requires manual intervention, then re-enter pipeline via fe-verify or fe-review

### Verification Philosophy

A principle applied across all agents and skills: **"Evidence before claims, always"**

5-Step Gate:
1. IDENTIFY — identify the target to verify
2. RUN — execute verification tools (tsc, build, vitest, etc.)
3. READ — review the full output (exit code, error count)
4. VERIFY — determine whether the output matches the claim
5. CLAIM — report the result citing evidence

Red Flags (all agents):
- "should work" / "probably fine" / "seems correct" — do not use without running tools
- Do not substitute a previous run's result for the current verification
- Do not skip verification because "the change is small"

## File Structure

```
.claude-plugin/  - Plugin manifest
agents/          - Agent definitions
skills/          - Skill entry points
hooks/           - Hook configuration
scripts/         - Hook handler scripts
templates/       - Template files
docs/            - Documentation
```

### Generated Project Structure

```
src/
├── layouts/           ← Shared layouts (cross-feature, uses <Outlet />)
├── features/{feature}/
│   ├── routes.tsx     ← Feature route definitions (auto-integrated)
│   ├── i18n.ts        ← Feature i18n registration (auto-integrated)
│   └── ...            ← types, api, stores, components, pages, __tests__
├── components/ui/     ← shadcn/ui components
├── mocks/             ← Global MSW setup
├── locales/           ← i18n JSON files
└── ...
```

## Project-Level Configuration

`.claude/frontend-react-plugin.json` (created by `/frontend-react-plugin:fe-init`):
```json
{
  "routerMode": "declarative",
  "mockFirst": true
}
```

- `routerMode`: `"declarative"` (default) | `"data"` — determines React Router v7 mode
- `mockFirst`: `true` (default) | `false` — whether to enable MSW v2 mock-first development
