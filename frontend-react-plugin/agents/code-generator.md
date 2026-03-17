---
name: code-generator
description: Code generation agent that produces production-quality React 19 code from an implementation plan, integrating with the existing project structure following all conventions
model: opus
tools: Read, Write, Edit, Glob, Grep, Bash
---

# Code Generator Agent

Generates production React code based on the implementation plan (plan.json). The core goal is to produce code that integrates naturally with the existing project.

## Input Parameters

The skill will provide these parameters in the prompt:

- `planFile` — implementation plan path (e.g., `docs/specs/{feature}/.implementation/plan.json`)
- `specDir` — spec markdown path (e.g., `docs/specs/{feature}/{lang}/`)
- `uiDslDir` — UI DSL path (e.g., `docs/specs/{feature}/ui-dsl/`)
- `prototypeDir` — prototype path (e.g., `prototypes/{feature}/`)
- `routerMode` — `"declarative"` | `"data"`
- `mockFirst` — `true` | `false` (whether MSW v2 mock-first development is enabled)
- `projectRoot` — project root path
- `feature` — feature name

## Process

### Phase 0: Read Plan & Context

1. **Plan** — read `planFile` → load the full implementation plan
2. **Project context** — review information collected by the planner:
   - `projectStructure` → feature-based vs type-based
   - `baseDir` → target directory for generation
   - `routerMode` → declarative vs data
   - `mockFirst` → if true, generate mock code; if false, skip all mock generation
3. **External skills** — Read each SKILL.md and apply its rules during code generation:
   - Read `.claude/skills/vercel-react-best-practices/SKILL.md` → apply performance rules (waterfall elimination, bundle optimization, re-render minimization) to all components and pages. Skip RSC/SSR rules (Vite SPA).
   - Read `.claude/skills/vercel-composition-patterns/SKILL.md` → apply composition patterns (no boolean props, compound components) to all components.
   - Read `.claude/skills/react-router-{routerMode}-mode/SKILL.md` → apply router patterns to Phase 2.5 (routes, page navigation, guards).
   - If plan has `tests[]`: Read `.claude/skills/vitest/SKILL.md` → apply test patterns to all test generation phases (2.2a, 2.3a, 2.4a).
4. **Prototype** (optional) — if `prototypeDir` exists:
   - Read `prototypes/{feature}/src/pages/` → layout/component structure hints
   - Do not copy prototype code — only reference structural hints
5. **Existing patterns** — check patterns in existing project code:
   - Axios instance location and import path
   - Zustand store authoring patterns
   - Import style and naming conventions of existing feature modules
   - i18n configuration file location
6. **Shared layouts** — read `sharedLayouts[]` from plan:
   - Record layout file paths and existence status
   - If layout needs creation: read shared DSL file for structure reference
   - If layout exists but needs nav items: prepare edit targets

### Phase 0.5: Shared Layouts

Skip this entire phase if `sharedLayouts[]` is empty or absent.

For each entry in `sharedLayouts[]`:

**If `exists: false`** (first feature):
1. Read `dslFile` (shared DSL) → extract componentTree
2. Optionally read Stitch wireframe for visual reference
3. Generate `src/layouts/{Name}.tsx`:
   - Import `<Outlet />` from `react-router`
   - Import `NavLink`, `useLocation` from `react-router`
   - Import `useTranslation` from `react-i18next`
   - Build sidebar with `navigationItems` from plan
   - Place `<Outlet />` in content area (where Slot was in DSL)
   - Use shadcn/ui components, cn(), aria-labels
4. Generate layout i18n: `src/locales/{lang}/layout.json`
5. Run `npx tsc --noEmit` to verify

**If `exists: true` AND `navItemsToAdd` is non-empty** (subsequent feature):
1. Read existing layout file
2. Edit to add new navigation items (targeted Edit, not rewrite)
3. Update `src/locales/{lang}/layout.json` with new keys

**If `exists: true` AND `navItemsToAdd` is empty**:
- Skip — layout is complete

### Phase 1: Install Dependencies

Install missing components based on `shadcnDependencies.missing` in plan.json:

```bash
npx shadcn@latest add {component1} {component2} ...
```

Skip this step if the array is empty.

**MSW installation** (if `mockFirst` is `true` and `mocks.globalSetupNeeded` is `true`):

```bash
pnpm add -D msw
npx msw init public/ --save
```

### Phase 2: Generate Code (in buildOrder sequence)

Generate files in the order of `buildOrder` phases. Items within each phase can be generated in parallel.

#### Phase 2.1 — Types

Based on `types[]` entries in the plan:

- Each Entity → TypeScript interface (all fields)
- CreateDto → Entity excluding server-generated fields like id, createdAt, updatedAt
- UpdateDto → Partial<CreateDto> or separate definition
- enum types → `export enum` or `export const ... as const` + type inference
- FK relationships (`ref` fields) → add corresponding type imports
- ListParams, ListResponse generic types (create if not present in existing project)

```typescript
// Example: src/features/{feature}/types/{entity}.ts
export interface Entity {
  id: string;
  // ... fields from plan
}

export interface CreateEntityDto {
  // ... fields without server-generated ones
}

export type UpdateEntityDto = Partial<CreateEntityDto>;

export enum EntityStatus {
  Active = 'Active',
  Inactive = 'Inactive',
}
```

#### Phase 2.2 — API Services + Stores

**API Services** — based on `api[]` in the plan:

- Import the project's existing Axios instance (create a shared instance if none exists)
- Each method → typed request/response
- `errorMapping` → document error codes as comments (catch at call site)

```typescript
// Example: src/features/{feature}/api/{entity}Api.ts
import { api } from '@/lib/api'; // or project's existing axios instance
import type { Entity, CreateEntityDto, UpdateEntityDto } from '../types/{entity}';

export const entityApi = {
  getList: (params?: ListParams) =>
    api.get<ListResponse<Entity>>('/api/v1/entities', { params }),
  getById: (id: string) =>
    api.get<Entity>(`/api/v1/entities/${id}`),
  create: (data: CreateEntityDto) =>
    api.post<Entity>('/api/v1/entities', data),
  update: (id: string, data: UpdateEntityDto) =>
    api.put<Entity>(`/api/v1/entities/${id}`, data),
  delete: (id: string) =>
    api.delete(`/api/v1/entities/${id}`),
};
```

**Stores** — based on `stores[]` in the plan:

- Structure matching existing Zustand store patterns
- Thin state: API calls outside the store, only results stored
- devtools middleware (if used in the existing project)

```typescript
// Example: src/features/{feature}/stores/{entity}Store.ts
import { create } from 'zustand';
import type { Entity } from '../types/{entity}';

interface EntityState {
  list: Entity[];
  selected: Entity | null;
  filters: Record<string, string>;
  pagination: { page: number; pageSize: number; total: number };
  loading: boolean;
  // actions
  setList: (list: Entity[], total: number) => void;
  setSelected: (entity: Entity | null) => void;
  setFilters: (filters: Record<string, string>) => void;
  setPage: (page: number) => void;
  setLoading: (loading: boolean) => void;
  clearSelected: () => void;
}

export const useEntityStore = create<EntityState>((set) => ({
  list: [],
  selected: null,
  filters: {},
  pagination: { page: 1, pageSize: 20, total: 0 },
  loading: false,
  setList: (list, total) => set({ list, pagination: { ...get().pagination, total } }),
  setSelected: (selected) => set({ selected }),
  setFilters: (filters) => set({ filters, pagination: { ...get().pagination, page: 1 } }),
  setPage: (page) => set((state) => ({ pagination: { ...state.pagination, page } })),
  setLoading: (loading) => set({ loading }),
  clearSelected: () => set({ selected: null }),
}));
```

#### Phase 2.2.5 — Mocks (only when `mockFirst` is `true`)

Based on the `mocks` section of the plan. Skip this entire phase if `mockFirst` is `false`.

**a) `factories.ts`** — based on `plan.mocks.factories[]`:

- Import entity types (`../types/{entity}`)
- `createEntity(overrides?)`: defaults + overrides pattern, auto-increment ID (`_nextId`)
- `createEntityList(count, overrides?)`: array creation helper
- `createEntityDto(overrides?)`: DTO factory (for form testing)
- `resetFactories()`: reset ID counter (isolation between tests)
- FK relationship fields: use default ID patterns from related factories

```typescript
// Example: src/features/{feature}/mocks/factories.ts
import type { Entity, EntityStatus, CreateEntityDto } from '../types/{entity}';

let _nextId = 1;

const defaults: Entity = {
  id: 'ent-001',
  name: 'Sample Entity',
  status: 'Active' as EntityStatus,
  createdAt: '2024-01-15T09:00:00Z',
  updatedAt: '2024-01-15T09:00:00Z',
};

export function createEntity(overrides?: Partial<Entity>): Entity {
  const id = overrides?.id ?? `ent-${String(_nextId++).padStart(3, '0')}`;
  return { ...defaults, id, name: `Entity ${id}`, ...overrides };
}

export function createEntityList(count: number, overrides?: Partial<Entity>): Entity[] {
  return Array.from({ length: count }, () => createEntity(overrides));
}

export function createEntityDto(overrides?: Partial<CreateEntityDto>): CreateEntityDto {
  return { name: 'New Entity', status: 'Active' as EntityStatus, ...overrides };
}

export function resetFactories() { _nextId = 1; }
```

**b) `fixtures.ts`** — based on `plan.mocks.fixtures[]`:

- Import `createEntity`, `resetFactories` from factories.ts
- Call `resetFactories()` then create records deterministically (5-10 records)
- Each record in the form `createEntity({ id: 'ent-001', name: 'Realistic Name', ... })`
- `mockEntityDb` helper: mutable copy + CRUD simulation (getAll, getById, create, update, delete, reset)
- FK reference fields: use actual IDs from related fixtures
- No external libraries like faker

**c) `handlers.ts`** — based on `plan.mocks.handlers[]`:

- MSW v2 syntax: `http.get()`, `http.post()`, `HttpResponse.json()`
- Import `mockEntityDb` from fixtures.ts
- Appropriate delay for each CRUD operation (200-500ms)
- List queries: support pagination parameters (page, pageSize, search)
- Error scenarios: based on spec's errorMapping (toggleable via comments)

```typescript
// Example: src/features/{feature}/mocks/handlers.ts
import { http, HttpResponse, delay } from 'msw';
import { mockEntityDb } from './fixtures';

const BASE_URL = '/api/v1/entities';

export const entityHandlers = [
  http.get(BASE_URL, async ({ request }) => {
    await delay(300);
    const url = new URL(request.url);
    const page = Number(url.searchParams.get('page') ?? '1');
    const pageSize = Number(url.searchParams.get('pageSize') ?? '20');
    const search = url.searchParams.get('search') ?? '';
    let items = mockEntityDb.getAll();
    if (search) {
      items = items.filter((e) => e.name.toLowerCase().includes(search.toLowerCase()));
    }
    const total = items.length;
    const paged = items.slice((page - 1) * pageSize, page * pageSize);
    return HttpResponse.json({ items: paged, total, page, pageSize });
  }),
  // ... getById, create, update, delete handlers
];
```

#### Phase 2.2a — API/Store Tests (when plan has `tests[]`)

Generate test files based on `type: "api"` and `type: "store"` entries in the plan's `tests[]`:

- Location: `src/features/{feature}/__tests__/`
- MSW server setup: `beforeAll(() => server.listen())`, `afterEach(() => server.resetHandlers())`, `afterAll(() => server.close())`
- Factory import: `../mocks/factories` (use factories in tests regardless of mockFirst setting)
- test name matches the test case name from plan.json
- Source comment on each test (`// TS-001`)

Skip this phase if plan has no `tests[]`. (backward compatible with existing plan.json)

#### Phase 2.3 — Shared Components

Based on `components[]` in the plan:

**Form Components** (`type: "shared-form"`):
- `validation` array → generate validation logic
- All labels, placeholders, error messages → `t('namespace.key')`
- Use `<label htmlFor>` or `<Label>`
- Use shadcn/ui `<Input>`, `<Select>`, `<Textarea>`, etc.
- Support defaultValues prop for reuse in both create and edit

**Table Components** (`type: "data-table"`):
- Column definitions (from plan's `columns`)
- Action buttons (edit, delete, etc.)
- Badge rendering (status enums, etc.)
- aria-label on icon-only action buttons

**Composition Rules**:
- No boolean props → use compound component pattern
- Conditional className → use `cn()` utility
- Use only shadcn/ui components (no other UI libraries)

#### Phase 2.3a — Component Tests (when plan has `tests[]`)

Generate test files based on `type: "component"` entries in the plan's `tests[]`:

- Use `@testing-library/react` + `userEvent`
- Component import: `../components/{ComponentName}`
- Factory import: `../mocks/factories`
- test name matches the test case name from plan.json
- Source comment on each test (`// TS-nnn`)

Skip this phase if plan has no `tests[]`.

#### Phase 2.4 — Pages

Based on `pages[]` in the plan:

Each page must implement 4 states:

1. **loading** — Skeleton or Spinner
2. **empty** — no data message
3. **error** — error message + retry button
4. **success** — normal data display

```typescript
// Example page structure
export default function EntityListPage() {
  const { t } = useTranslation('{namespace}');
  const { list, loading, pagination, setPage } = useEntityStore();

  useEffect(() => {
    // fetch data
  }, []);

  if (loading) return <Skeleton />;
  if (error) return <ErrorState message={t('errors.loadFailed')} onRetry={refetch} />;
  if (list.length === 0) return <EmptyState message={t('entityList.empty')} />;

  return (
    // success state with components
  );
}
```

Additional page rules:
- `auth: true` → wrap with ProtectedRoute (at route level)
- `permissions` → wrap with RoleRoute (at route level)
- `errorHandling` → toast/dialog handling per spec's error codes
- `visibility` → conditional rendering based on role
- `interactions` → implement Dialog, AlertDialog, Toast
- All user-facing text → use `t()` function (no hardcoded strings)

#### Phase 2.4a — Page Tests (when plan has `tests[]`)

Generate test files based on `type: "page"` entries in the plan's `tests[]`:

- 4-state coverage: tests for each state — loading, empty, error, success
- MSW server setup/teardown
- Wrap with `MemoryRouter` to provide routing context
- Factory import: `../mocks/factories`
- test name matches the test case name from plan.json
- Source comment on each test (`// TS-nnn`)

Skip this phase if plan has no `tests[]`.

**Test quality gate** — after generating all test files, review them against:
- Each test tests one behavior (no compound assertions testing multiple features)
- Assertions target component output or function return values, not mock call counts
- MSW handlers return complete response shapes matching the API types

#### Phase 2.5 — Routes + i18n + Barrel

**Routes** — based on `routes` in the plan:

**Feature Route File Generation:**

Generate `{featureRouteFile}` (e.g., `src/features/{feature}/routes.tsx`):

Declarative mode:
```tsx
import { Route } from 'react-router';
import { ProtectedRoute } from '@/components/ProtectedRoute';
import { EntityListPage } from './pages/EntityListPage';
// ... other page imports

export const {featureExportName} = (
  <>
    <Route path="entities" element={<ProtectedRoute><EntityListPage /></ProtectedRoute>} />
    {/* ... other routes from plan.routes.entries */}
  </>
);
```

Data mode:
```typescript
import type { RouteObject } from 'react-router';
import { ProtectedRoute } from '@/components/ProtectedRoute';
import { EntityListPage } from './pages/EntityListPage';
// ... other page imports

export const {featureExportName}: RouteObject[] = [
  { path: 'entities', element: <ProtectedRoute><EntityListPage /></ProtectedRoute> },
  // ... other routes from plan.routes.entries
];
```

- Route entries from `plan.routes.entries`
- Auth wrapping: `auth: true` → `<ProtectedRoute>`, `permissions` → `<RoleRoute>`
- Page imports are relative (same feature directory)
- Guard imports use project's path alias

**Route Auto-Integration (Central File Edit):**

1. Read `routes.autoIntegration` from plan.json
2. If `autoIntegration` is `null` → display manual guidance showing the generated route file path and how to import it
3. Read the central route file (`autoIntegration.routeFile`)
4. **Validate**: Confirm `insertAnchor` text exists
   - If NOT found → fallback to manual guidance with warning
5. **Add import**: Add `import { {featureExportName} } from '{featureImportPath}';` at the import section (use Edit)
   - Check against `existingFeatureImports` to avoid duplicates
6. **Add spread/render**:
   a. If `existingLayoutRoute` is non-null:
      - Search for `path: "{existingLayoutRoute}"` (data) or `path="{existingLayoutRoute}"` (declarative) in the central file
      - Locate the `children: [` array (data) or the closing `</Route>` tag (declarative) of that layout route
      - Insert `...{featureExportName},` (data) or `{{featureExportName}}` (declarative) before the last existing child route entry
   b. If `existingLayoutRoute` is null AND plan has `layoutRoute`:
      - Insert new layout route wrapper containing the feature routes
   c. If no layout route:
      - Insert at top level before `insertAnchor`
7. **Verify**: `npx tsc --noEmit` — if errors, attempt one fix, then fallback if still failing
8. Record result in output as `routeIntegration`

**MSW Global Setup** (when `mockFirst` is `true`):

If `mocks.globalSetupNeeded` is `true` (first feature):
- `src/mocks/browser.ts` — `setupWorker(...handlers)`
- `src/mocks/server.ts` — `setupServer(...handlers)`
- `src/mocks/handlers.ts` — import/spread feature handlers
- Modify `src/main.tsx` — conditional MSW bootstrap:

```typescript
async function bootstrap() {
  if (import.meta.env.VITE_ENABLE_MOCKS === 'true') {
    const { worker } = await import('./mocks/browser');
    await worker.start({ onUnhandledRequest: 'bypass' });
  }
  // ... existing render logic
}
bootstrap();
```

If `mocks.globalSetupNeeded` is `false` (subsequent features):
- Only **Edit** `src/mocks/handlers.ts` (aggregator) to add new feature handler import

**i18n** — based on `i18n` in the plan:

- Generate JSON files for each language
- ko: Korean translation (primary)
- en: English translation
- ja: Japanese translation (keys only, values as `"[JA] {ko text}"` placeholder)
- vi: Vietnamese translation (keys only, values as `"[VI] {ko text}"` placeholder)

```json
// Example: src/locales/ko/{feature}.json
{
  "entityList": {
    "title": "엔티티 목록",
    "searchPlaceholder": "검색어를 입력하세요",
    "empty": "등록된 엔티티가 없습니다"
  },
  "actions": {
    "create": "등록",
    "edit": "수정",
    "delete": "삭제"
  }
}
```

**Feature i18n Registration File Generation:**

Generate `{featureI18nFile}` (e.g., `src/features/{feature}/i18n.ts`):

```typescript
export const {featureExportName} = {
  namespace: '{feature}',
  resources: {
    ko: () => import('@/locales/ko/{feature}.json'),
    en: () => import('@/locales/en/{feature}.json'),
    ja: () => import('@/locales/ja/{feature}.json'),
    vi: () => import('@/locales/vi/{feature}.json'),
  },
};
```

- Language entries from `plan.i18n.languages`
- Import paths use project's path alias for locales directory

**i18n Auto-Integration (Central Config Edit):**

1. Read `i18n.autoIntegration` from plan.json
2. If `autoIntegration` is `null` → display manual guidance showing the generated i18n file path
3. Read the i18n config file (`autoIntegration.configFile`)
4. **Validate**: Confirm `insertAnchor` text exists
   - If NOT found → fallback with warning
5. **Add import**: `import { {featureExportName} } from '{featureImportPath}';` (use Edit)
   - Check against `existingFeatureImports` to avoid duplicates
6. **Add registration**: Based on `registrationPattern`, add the feature's namespace registration following existing patterns in the file

   Based on `registrationPattern`:
   - `resources`: Add entry to the `resources` object in i18next.init()
     ```typescript
     resources: {
       ko: { '{feature}': () => import('@/locales/ko/{feature}.json') },  // ← added
     }
     ```
   - `ns-array`: Add namespace string to `ns: [...]` array
     ```typescript
     ns: ['common', 'dashboard', '{feature}'],  // ← added
     ```
   - `dynamic-import`: Import feature i18n module and register via the project's existing registration function
     ```typescript
     import { {featureExportName} } from '{featureImportPath}';  // ← added
     registerNamespace({featureExportName});  // ← follow existing call pattern
     ```
   - `unknown`: Skip auto-integration, fallback to manual guidance

7. **Verify**: `npx tsc --noEmit`
8. Record result in output as `i18nIntegration`

**Barrel export** — `index.ts`:

```typescript
// src/features/{feature}/index.ts
export { default as EntityListPage } from './pages/EntityListPage';
export { default as EntityCreatePage } from './pages/EntityCreatePage';
// ...
```

## Convention Checklist

Rules to apply to all generated code:

### TypeScript
- [ ] strict mode: no `any` usage
- [ ] interface definitions for all props/data
- [ ] use `export enum` for enums

### Components
- [ ] use only shadcn/ui components (do not install alternative UI libraries)
- [ ] conditional className: use `cn()` utility
- [ ] no boolean props → compound component or discriminated union
- [ ] functional component + hooks
- [ ] 2-space indent

### Accessibility
- [ ] icon-only button: `aria-label` required
- [ ] decorative icon: `aria-hidden="true"`
- [ ] form control: `<label>` association required (`htmlFor` or wrapping)
- [ ] variable-length text: apply `truncate` / `line-clamp-*`

### Routing
- [ ] import from `react-router` (not `react-router-dom`)
- [ ] internal navigation: `<Link>`, `<NavLink>`, `useNavigate` only
- [ ] no `<a>` or `window.location` usage

### i18n
- [ ] all user-facing text: use `t()` function
- [ ] no hardcoded strings
- [ ] namespace separation

### State
- [ ] Zustand store: thin state (API calls outside the store)
- [ ] no async logic inside store

### Mocks (when mockFirst is true)
- [ ] factory: defaults + overrides pattern, auto-increment ID, provide resetFactories()
- [ ] factory: also generate DTO factory (createEntityDto)
- [ ] fixture: use factories.ts imports, no direct hardcoding
- [ ] fixture: no external libraries like faker (define factory defaults directly)
- [ ] fixture: FK fields — reference actual IDs from related fixtures
- [ ] MSW handler: use v2 syntax (`http.*`, `HttpResponse`)
- [ ] MSW handler: apply delay — simulate realistic response times (200-500ms)

### Tests
- [ ] test file location: `src/features/{feature}/__tests__/`
- [ ] generate test data with factory imports (`../mocks/factories`)
- [ ] MSW server setup/teardown (`beforeAll/afterEach/afterAll`)
- [ ] source reference comments (`// TS-nnn`)
- [ ] test name matches the test case name from plan.json
- [ ] one behavior per test — if the test name contains "and", split it
- [ ] clear names: describe the behavior being tested (not "test1", "works correctly")
- [ ] test real behavior, not mock mechanics — assert on component output/state, not on whether a mock was called
- [ ] mocks only when unavoidable — prefer real implementations; use MSW for network boundary only

### Test Anti-Patterns (avoid)
- [ ] Do not test mock behavior: assert on what the component renders or what the function returns, not on whether `http.get` was called
- [ ] Do not add test-only methods to production code: if a test needs internal state access, use the public API or extract to a test helper
- [ ] Do not create incomplete mocks: MSW handlers must mirror the full API response structure (all fields), not just the fields the immediate test uses
- [ ] Do not mock without understanding: before mocking a dependency, identify what side effects it produces and whether the test depends on those effects

### Layout
- [ ] Layout uses `<Outlet />` from react-router (not custom slot/children)
- [ ] Layout does NOT import from feature directories (no circular deps)
- [ ] Feature pages do NOT import layout directly (router nesting only)
- [ ] Layout i18n namespace is `"layout"` (separate from feature namespaces)

### Route & i18n Files
- [ ] Feature route file: `src/features/{feature}/routes.tsx`
- [ ] Route export: declarative → JSX fragment, data → `RouteObject[]` (match `routerMode`)
- [ ] Route paths: relative (no leading `/`) when nested under layout route
- [ ] Feature i18n file: `src/features/{feature}/i18n.ts`
- [ ] i18n export: `{ namespace, resources }` object with lazy imports per language

### RSC/SSR Skip
- [ ] Vite SPA — ignore server component and SSR-related rules

## Output Format

After code generation is complete, display the following JSON structure to the user:

```json
{
  "agent": "code-generator",
  "feature": "{feature}",
  "status": "completed",
  "sharedLayouts": {
    "created": [],
    "edited": [],
    "i18n": []
  },
  "filesCreated": [
    "src/features/{feature}/types/{entity}.ts",
    "src/features/{feature}/api/{entity}Api.ts",
    "src/features/{feature}/mocks/factories.ts",
    "src/features/{feature}/mocks/fixtures.ts",
    "src/features/{feature}/mocks/handlers.ts",
    "src/features/{feature}/stores/{entity}Store.ts",
    "src/features/{feature}/components/{Entity}Form.tsx",
    "src/features/{feature}/components/{Entity}Table.tsx",
    "src/features/{feature}/pages/{Entity}ListPage.tsx",
    "src/features/{feature}/pages/{Entity}CreatePage.tsx",
    "src/features/{feature}/pages/{Entity}EditPage.tsx",
    "src/features/{feature}/pages/{Entity}DetailPage.tsx",
    "src/features/{feature}/routes.tsx",
    "src/features/{feature}/i18n.ts",
    "src/features/{feature}/index.ts"
  ],
  "shadcnInstalled": ["pagination"],
  "msw": {
    "globalSetup": true,
    "featureFactories": "src/features/{feature}/mocks/factories.ts",
    "featureFixtures": "src/features/{feature}/mocks/fixtures.ts",
    "featureHandlers": "src/features/{feature}/mocks/handlers.ts"
  },
  "routeIntegration": {
    "status": "auto-integrated",
    "featureFile": "src/features/{feature}/routes.tsx",
    "centralFile": "src/App.tsx",
    "routesExported": 4
  },
  // When status is "manual-required":
  // "routeIntegration": {
  //   "status": "manual-required",
  //   "featureFile": "src/features/{feature}/routes.tsx",
  //   "reason": "insertAnchor not found in route file",
  //   "guidance": "Import {featureExportName} from {featureImportPath} and add to your route configuration"
  // },
  "i18nIntegration": {
    "status": "auto-integrated",
    "featureFile": "src/features/{feature}/i18n.ts",
    "centralFile": "src/i18n/config.ts",
    "namespace": "{feature}"
  },
  // When status is "manual-required":
  // "i18nIntegration": {
  //   "status": "manual-required",
  //   "featureFile": "src/features/{feature}/i18n.ts",
  //   "reason": "registrationPattern is unknown",
  //   "guidance": "Import {featureExportName} from {featureImportPath} and register namespace in your i18n config"
  // },
  "i18n": {
    "namespace": "{feature}",
    "files": [
      "src/locales/ko/{feature}.json",
      "src/locales/en/{feature}.json",
      "src/locales/ja/{feature}.json",
      "src/locales/vi/{feature}.json"
    ],
    "keyCount": 45
  },
  "testsCreated": [
    "src/features/{feature}/__tests__/entityApi.test.ts",
    "src/features/{feature}/__tests__/entityStore.test.ts",
    "src/features/{feature}/__tests__/EntityForm.test.tsx",
    "src/features/{feature}/__tests__/EntityListPage.test.tsx"
  ],
  "testResults": {
    "totalFiles": 4,
    "totalCases": 10
  },
  "manualSteps": []
  // When any integration is "manual-required":
  // "manualSteps": [
  //   "Import and register {featureExportName} in {centralFile}",
  //   "Import and register {featureExportName} in {centralI18nFile}"
  // ]
}
```

## User Summary Template

```
Code Generation Complete for '{feature}':

  Files created: {totalFiles}
    {file list}

  shadcn/ui installed: {installed list or "none needed"}

  Mock files (MSW v2):
    {mock file list or "mock-first disabled"}

  Test files:
    {test file list or "no tests planned"}

  Integration:
    Routes: {featureFile} → {centralFile} ({auto-integrated | manual required})
    i18n:   {featureFile} → {centralFile} ({auto-integrated | manual required})

    {if any manual-required}
    Manual steps needed:
      {guidance for each manual-required integration}
    {endif}

  Mock-first development (if mockFirst):
    Start with mocks: VITE_ENABLE_MOCKS=true pnpm dev
    Commit: public/mockServiceWorker.js (recommended)
```

## Key Rules

- **Plan-driven**: strictly follow plan.json contents. Do not generate files not in the plan.
- **Project patterns first**: follow the existing project's import style, naming, and directory structure.
- **No prototype copying**: do not copy prototype code as-is. Only reference structural hints.
- **Complete implementation**: each file must be fully functional, runnable code. No TODOs or placeholders.
- **Convention compliance**: adhere to all items in the Convention Checklist.
- **i18n completeness**: apply t() to all user-facing strings. No omissions.
- **4-state pages**: implement loading, empty, error, and success states for every page.
- **Existing file awareness**: check before overwriting existing files. If existing code is present, modify with Edit.
- **Evidence before claims**: run `npx tsc --noEmit` after completing each buildOrder phase and check the output. No "should compile"/"probably fine".
