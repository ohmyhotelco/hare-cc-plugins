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
  - Detailed routing patterns: see `.claude/skills/react-router-{routerMode}-mode` (installed by `/frontend-react-plugin:init`)

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
- Unit/Component: Vitest — detailed test patterns: see `.claude/skills/vitest` (installed by `/frontend-react-plugin:init`)
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
- **Agents**: `implementation-planner` (spec analysis → implementation plan), `code-generator` (production code generation based on plan), `spec-reviewer` (spec compliance review), `quality-reviewer` (code quality review), `debugger` (systematic debugging)
- **Skills**: `/frontend-react-plugin:init`, `/frontend-react-plugin:plan`, `/frontend-react-plugin:gen`, `/frontend-react-plugin:verify`, `/frontend-react-plugin:review-code` (reviews generated source code — not to be confused with `/planning-plugin:review` which reviews the specification document), `/frontend-react-plugin:debug`
- **External Skills**: `react-router-*-mode` (from `remix-run/agent-skills`), `vitest` (from `supabase/supabase`), `vercel-react-best-practices` + `vercel-composition-patterns` + `web-design-guidelines` (from `vercel-labs/agent-skills`) — installed by init
- **Configuration**: `.claude/frontend-react-plugin.json` (created by `/frontend-react-plugin:init`)
- **Templates**: `feature-module.md` (feature module structure reference)

### Testing (TDD)
- TDD workflow: plan.json `tests[]` → code-generator creates `__tests__/`
- Test file location: `src/features/{feature}/__tests__/`
- Test types: api (MSW server), component (@testing-library/react), page (4-state coverage), store (unit)
- Factory usage: generate test data from `../mocks/factories`
- MSW server: import from `@/mocks/server`, setup with `beforeAll/afterEach/afterAll`
- Source tracking: reference spec test scenario with `// TS-nnn` comment in each test
- Pipeline: `/frontend-react-plugin:gen` → `/frontend-react-plugin:verify` → `/frontend-react-plugin:review-code` → `/frontend-react-plugin:debug`

### Code Generation
- Feature spec source: `docs/specs/{feature}/` (planning-plugin output)
- Implementation plan: `docs/specs/{feature}/.implementation/plan.json`
- UI DSL first: use structured data from `ui-dsl/` if available, otherwise infer from spec markdown
- Feature-based structure: `src/features/{feature}/` (types, api, stores, components, pages, __tests__)
- Prototypes are for reference only: do not copy code from `src/prototypes/{feature}/` into production code

### Shared Layouts
- Shared layout location: `src/layouts/{PascalCaseLayoutId}.tsx`
- Mapping: `@layout: _shared/{layout-id}` in spec → `src/layouts/{PascalCaseLayoutId}.tsx` in production
- Slot component → `<Outlet />` from react-router
- Features do NOT import layout directly — relationship expressed via React Router nested routes
- First feature: generates layout + feature code
- Subsequent features: reuses existing layout, optionally adds nav items

### Debug & Progress
- Debug report: `docs/specs/{feature}/.implementation/debug-report.json`
- Verification/review results: recorded in `implementation.verification`, `implementation.review` fields of `docs/specs/{feature}/.progress/{feature}.json`
- Progress state machine:
  ```
  planned → generated → verified → reviewed → done
               ↓            ↓           ↓
           gen-failed   verify-failed review-failed
                              ↓           ↓
                          resolved | escalated
  ```

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
├── features/{feature}/ ← Feature modules
├── components/ui/     ← shadcn/ui components
├── mocks/             ← Global MSW setup
├── locales/           ← i18n JSON files
└── ...
```

## Project-Level Configuration

`.claude/frontend-react-plugin.json` (created by `/frontend-react-plugin:init`):
```json
{
  "routerMode": "declarative",
  "mockFirst": true
}
```

- `routerMode`: `"declarative"` (default) | `"data"` — determines React Router v7 mode
- `mockFirst`: `true` (default) | `false` — whether to enable MSW v2 mock-first development
