# Feature Module Structure Reference

Canonical structure for a feature module. Both the `implementation-planner` and `code-generator` agents reference this structure.

## Directory Layout

```
src/features/{feature}/
├── __tests__/
│   ├── entityApi.test.ts          ← API service tests
│   ├── entityStore.test.ts        ← Store tests
│   ├── EntityForm.test.tsx        ← Component tests
│   └── EntityListPage.test.tsx    ← Page tests (4-state)
├── types/
│   └── {entity}.ts              ← Entity, CreateDto, UpdateDto, enums
├── api/
│   └── {entity}Api.ts           ← Axios CRUD methods, typed req/res
├── mocks/
│   ├── factories.ts             ← Entity/DTO factory functions (createEntity, createEntityList, createEntityDto)
│   ├── fixtures.ts              ← Pre-built mock datasets (using factories) + mutable DB helpers
│   └── handlers.ts              ← MSW v2 request handlers (http.get/post/put/delete)
├── stores/
│   └── {entity}Store.ts         ← Zustand store, thin state
├── components/
│   ├── {Entity}Form.tsx         ← Shared form (create + edit), validation, i18n
│   └── {Entity}Table.tsx        ← Table columns, actions, badges
├── pages/
│   ├── {Entity}ListPage.tsx     ← Table + search + pagination + delete dialog
│   ├── {Entity}CreatePage.tsx   ← Form + submit + toast
│   ├── {Entity}EditPage.tsx     ← Data load + form + submit
│   └── {Entity}DetailPage.tsx   ← Read-only detail view
└── index.ts                     ← Barrel export
```

## Canonical Patterns

### Types (`types/{entity}.ts`)

```typescript
export interface Entity {
  id: string;
  name: string;
  status: EntityStatus;
  createdAt: string;
  updatedAt: string;
}

export enum EntityStatus {
  Active = 'Active',
  Inactive = 'Inactive',
  Pending = 'Pending',
}

export interface CreateEntityDto {
  name: string;
  status?: EntityStatus;
}

export type UpdateEntityDto = Partial<CreateEntityDto>;

export interface ListParams {
  page?: number;
  pageSize?: number;
  search?: string;
  status?: EntityStatus;
  sortBy?: string;
  sortOrder?: 'asc' | 'desc';
}

export interface ListResponse<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
}
```

### API Service (`api/{entity}Api.ts`)

```typescript
import { api } from '@/lib/api'; // project's shared Axios instance
import type {
  Entity,
  CreateEntityDto,
  UpdateEntityDto,
  ListParams,
  ListResponse,
} from '../types/{entity}';

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

### Zustand Store (`stores/{entity}Store.ts`)

```typescript
import { create } from 'zustand';
import type { Entity, ListParams } from '../types/{entity}';

interface EntityState {
  // state
  list: Entity[];
  selected: Entity | null;
  filters: ListParams;
  total: number;
  loading: boolean;
  error: string | null;

  // actions
  setList: (list: Entity[], total: number) => void;
  setSelected: (entity: Entity | null) => void;
  setFilters: (filters: Partial<ListParams>) => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  reset: () => void;
}

const initialState = {
  list: [],
  selected: null,
  filters: { page: 1, pageSize: 20 },
  total: 0,
  loading: false,
  error: null,
};

export const useEntityStore = create<EntityState>((set) => ({
  ...initialState,
  setList: (list, total) => set({ list, total }),
  setSelected: (selected) => set({ selected }),
  setFilters: (filters) =>
    set((state) => ({
      filters: { ...state.filters, ...filters, page: 1 },
    })),
  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error }),
  reset: () => set(initialState),
}));
```

### Form Component (`components/{Entity}Form.tsx`)

```tsx
import { useForm } from 'react-hook-form'; // or native form handling
import { useTranslation } from 'react-i18next';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import type { CreateEntityDto } from '../types/{entity}';

interface EntityFormProps {
  defaultValues?: Partial<CreateEntityDto>;
  onSubmit: (data: CreateEntityDto) => void;
  loading?: boolean;
}

export function EntityForm({ defaultValues, onSubmit, loading }: EntityFormProps) {
  const { t } = useTranslation('{feature}');

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="space-y-2">
        <Label htmlFor="name">{t('entityForm.name.label')}</Label>
        <Input
          id="name"
          placeholder={t('entityForm.name.placeholder')}
          defaultValue={defaultValues?.name}
        />
      </div>

      <div className="space-y-2">
        <Label htmlFor="status">{t('entityForm.status.label')}</Label>
        <Select defaultValue={defaultValues?.status}>
          <SelectTrigger id="status">
            <SelectValue placeholder={t('entityForm.status.placeholder')} />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="Active">{t('entityForm.status.active')}</SelectItem>
            <SelectItem value="Inactive">{t('entityForm.status.inactive')}</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <Button type="submit" disabled={loading}>
        {loading ? t('actions.submitting') : t('actions.submit')}
      </Button>
    </form>
  );
}
```

### Table Component (`components/{Entity}Table.tsx`)

```tsx
import { useTranslation } from 'react-i18next';
import { Pencil, Trash2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import type { Entity } from '../types/{entity}';

interface EntityTableProps {
  data: Entity[];
  onEdit: (id: string) => void;
  onDelete: (entity: Entity) => void;
}

export function EntityTable({ data, onEdit, onDelete }: EntityTableProps) {
  const { t } = useTranslation('{feature}');

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>{t('entityTable.name')}</TableHead>
          <TableHead>{t('entityTable.status')}</TableHead>
          <TableHead>{t('entityTable.createdAt')}</TableHead>
          <TableHead className="w-24">{t('entityTable.actions')}</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {data.map((entity) => (
          <TableRow key={entity.id}>
            <TableCell className="truncate max-w-xs">{entity.name}</TableCell>
            <TableCell>
              <Badge variant={entity.status === 'Active' ? 'default' : 'secondary'}>
                {t(`entityTable.status.${entity.status.toLowerCase()}`)}
              </Badge>
            </TableCell>
            <TableCell>{new Intl.DateTimeFormat().format(new Date(entity.createdAt))}</TableCell>
            <TableCell>
              <div className="flex gap-1">
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => onEdit(entity.id)}
                  aria-label={t('actions.edit')}
                >
                  <Pencil className="h-4 w-4" aria-hidden="true" />
                </Button>
                <Button
                  variant="ghost"
                  size="icon"
                  onClick={() => onDelete(entity)}
                  aria-label={t('actions.delete')}
                >
                  <Trash2 className="h-4 w-4" aria-hidden="true" />
                </Button>
              </div>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
```

### List Page (`pages/{Entity}ListPage.tsx`)

```tsx
import { useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router';
import { useTranslation } from 'react-i18next';
import { Plus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { EntityTable } from '../components/{Entity}Table';
import { useEntityStore } from '../stores/{entity}Store';
import { entityApi } from '../api/{entity}Api';

export default function EntityListPage() {
  const { t } = useTranslation('{feature}');
  const navigate = useNavigate();
  const { list, total, filters, loading, error, setList, setFilters, setLoading, setError } =
    useEntityStore();

  const fetchList = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data } = await entityApi.getList(filters);
      setList(data.items, data.total);
    } catch (err) {
      setError(t('errors.loadFailed'));
    } finally {
      setLoading(false);
    }
  }, [filters]);

  useEffect(() => {
    fetchList();
  }, [fetchList]);

  // Loading state
  if (loading && list.length === 0) {
    return <div>{/* Skeleton */}</div>;
  }

  // Error state
  if (error) {
    return (
      <div className="flex flex-col items-center gap-4 py-12">
        <p className="text-destructive">{error}</p>
        <Button onClick={fetchList}>{t('actions.retry')}</Button>
      </div>
    );
  }

  // Empty state
  if (!loading && list.length === 0) {
    return (
      <div className="flex flex-col items-center gap-4 py-12">
        <p className="text-muted-foreground">{t('entityList.empty')}</p>
        <Button onClick={() => navigate('new')}>
          <Plus className="mr-2 h-4 w-4" aria-hidden="true" />
          {t('actions.create')}
        </Button>
      </div>
    );
  }

  // Success state
  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">{t('entityList.title')}</h1>
        <Button onClick={() => navigate('new')}>
          <Plus className="mr-2 h-4 w-4" aria-hidden="true" />
          {t('actions.create')}
        </Button>
      </div>
      <Input
        placeholder={t('entityList.searchPlaceholder')}
        onChange={(e) => setFilters({ search: e.target.value })}
      />
      <EntityTable
        data={list}
        onEdit={(id) => navigate(`${id}/edit`)}
        onDelete={handleDelete}
      />
    </div>
  );
}
```

### Route Patterns

#### Declarative Mode

```tsx
import { Route } from 'react-router';

// Inside <Routes>
<Route path="/admin/entities" element={<ProtectedRoute><EntityListPage /></ProtectedRoute>} />
<Route path="/admin/entities/new" element={<ProtectedRoute><EntityCreatePage /></ProtectedRoute>} />
<Route path="/admin/entities/:id" element={<ProtectedRoute><EntityDetailPage /></ProtectedRoute>} />
<Route path="/admin/entities/:id/edit" element={<ProtectedRoute><EntityEditPage /></ProtectedRoute>} />
```

#### Data Mode

```typescript
import { createBrowserRouter } from 'react-router';

// Inside route config array
{
  path: '/admin/entities',
  element: <ProtectedRoute><EntityListPage /></ProtectedRoute>,
  loader: entityListLoader,
},
{
  path: '/admin/entities/new',
  element: <ProtectedRoute><EntityCreatePage /></ProtectedRoute>,
  action: entityCreateAction,
},
{
  path: '/admin/entities/:id',
  element: <ProtectedRoute><EntityDetailPage /></ProtectedRoute>,
  loader: entityDetailLoader,
},
{
  path: '/admin/entities/:id/edit',
  element: <ProtectedRoute><EntityEditPage /></ProtectedRoute>,
  loader: entityEditLoader,
  action: entityEditAction,
},
```

### Shared Layout Integration

When a feature uses a shared layout (via `@layout:` directive):

**Layout lives at app level (not inside feature):**
```
src/layouts/
└── MainLayout.tsx          ← Uses <Outlet />, shared by all features
```

**Nested routes:**

Declarative mode:
```tsx
<Route path="/app" element={<MainLayout />}>
  <Route path="dashboard" element={<ProtectedRoute><DashboardPage /></ProtectedRoute>} />
  <Route path="leave-request" element={<ProtectedRoute><LeaveListPage /></ProtectedRoute>} />
</Route>
```

Data mode:
```typescript
{
  path: "/app",
  element: <MainLayout />,
  children: [
    { path: "dashboard", element: <ProtectedRoute><DashboardPage /></ProtectedRoute> },
    { path: "leave-request", element: <ProtectedRoute><LeaveListPage /></ProtectedRoute> },
  ]
}
```

**Feature pages render content only (no shell):**
```tsx
// CORRECT
export default function DashboardPage() {
  return <main>...</main>;
}

// WRONG — do not import layout in feature page
import MainLayout from '@/layouts/MainLayout';
```

### i18n JSON (`locales/{lang}/{feature}.json`)

```json
{
  "entityList": {
    "title": "Entity List",
    "searchPlaceholder": "Enter search term",
    "empty": "No entities registered"
  },
  "entityForm": {
    "name": {
      "label": "Name",
      "placeholder": "Enter name"
    },
    "status": {
      "label": "Status",
      "placeholder": "Select status",
      "active": "Active",
      "inactive": "Inactive"
    }
  },
  "entityTable": {
    "name": "Name",
    "status": "Status",
    "createdAt": "Created Date",
    "actions": "Actions"
  },
  "actions": {
    "create": "Create",
    "edit": "Edit",
    "delete": "Delete",
    "deleteConfirm": "Are you sure you want to delete?",
    "submit": "Save",
    "submitting": "Saving...",
    "retry": "Retry",
    "cancel": "Cancel"
  },
  "errors": {
    "loadFailed": "Failed to load data",
    "saveFailed": "Failed to save",
    "deleteFailed": "Failed to delete"
  }
}
```

### Barrel Export (`index.ts`)

```typescript
export { default as EntityListPage } from './pages/EntityListPage';
export { default as EntityCreatePage } from './pages/EntityCreatePage';
export { default as EntityEditPage } from './pages/EntityEditPage';
export { default as EntityDetailPage } from './pages/EntityDetailPage';
```

### Factory (`mocks/factories.ts`)

Functions for generating per-test custom data. Uses the defaults + overrides pattern to reduce boilerplate and keep tests self-contained.

```typescript
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

### Fixture (`mocks/fixtures.ts`)

Fixed datasets for MSW handlers. Generated deterministically using factories, with mutable DB helpers providing CRUD simulation.

```typescript
import { createEntity, resetFactories } from './factories';
import type { Entity, CreateEntityDto } from '../types/{entity}';

resetFactories();
export const entities: Entity[] = [
  createEntity({ id: 'ent-001', name: 'Hotel Paradise', status: 'Active' }),
  createEntity({ id: 'ent-002', name: 'Grand Resort', status: 'Inactive' }),
  createEntity({ id: 'ent-003', name: 'Ocean View Hotel', status: 'Active' }),
  createEntity({ id: 'ent-004', name: 'Mountain Lodge', status: 'Pending' }),
  createEntity({ id: 'ent-005', name: 'City Center Inn', status: 'Active' }),
];

let entityDb = [...entities];

export const mockEntityDb = {
  getAll: () => entityDb,
  getById: (id: string) => entityDb.find((e) => e.id === id),
  create: (data: CreateEntityDto) => {
    const newEntity = createEntity({ ...data, id: `ent-${String(entityDb.length + 1).padStart(3, '0')}` });
    entityDb.push(newEntity);
    return newEntity;
  },
  update: (id: string, data: Partial<Entity>) => {
    const index = entityDb.findIndex((e) => e.id === id);
    if (index === -1) return undefined;
    entityDb[index] = { ...entityDb[index], ...data, updatedAt: new Date().toISOString() };
    return entityDb[index];
  },
  delete: (id: string) => {
    entityDb = entityDb.filter((e) => e.id !== id);
  },
  reset: () => {
    entityDb = [...entities];
  },
};
```

### MSW Handler (`mocks/handlers.ts`)

MSW v2 request handlers. Uses the `http.*()` + `HttpResponse.json()` pattern. Intercepts at the network level without modifying any production code (API services).

```typescript
import { http, HttpResponse, delay } from 'msw';
import { mockEntityDb } from './fixtures';

const BASE_URL = '/api/v1/entities';

export const entityHandlers = [
  // GET /api/v1/entities — List query
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

  // GET /api/v1/entities/:id — Detail query
  http.get(`${BASE_URL}/:id`, async ({ params }) => {
    await delay(200);
    const entity = mockEntityDb.getById(params.id as string);
    if (!entity) {
      return new HttpResponse(null, { status: 404 });
    }
    return HttpResponse.json(entity);
  }),

  // POST /api/v1/entities — Create
  http.post(BASE_URL, async ({ request }) => {
    await delay(400);
    const data = await request.json();
    const created = mockEntityDb.create(data);
    return HttpResponse.json(created, { status: 201 });
  }),

  // PUT /api/v1/entities/:id — Update
  http.put(`${BASE_URL}/:id`, async ({ params, request }) => {
    await delay(300);
    const data = await request.json();
    const updated = mockEntityDb.update(params.id as string, data);
    if (!updated) {
      return new HttpResponse(null, { status: 404 });
    }
    return HttpResponse.json(updated);
  }),

  // DELETE /api/v1/entities/:id — Delete
  http.delete(`${BASE_URL}/:id`, async ({ params }) => {
    await delay(200);
    mockEntityDb.delete(params.id as string);
    return new HttpResponse(null, { status: 204 });
  }),
];
```

### Global MSW Setup

Global MSW files created once when the first feature is generated.

**`src/mocks/browser.ts`** — For browser development mode:

```typescript
import { setupWorker } from 'msw/browser';
import { handlers } from './handlers';

export const worker = setupWorker(...handlers);
```

**`src/mocks/server.ts`** — For Vitest:

```typescript
import { setupServer } from 'msw/node';
import { handlers } from './handlers';

export const server = setupServer(...handlers);
```

**`src/mocks/handlers.ts`** — Imports and re-exports all feature handlers:

```typescript
import { entityHandlers } from '@/features/{feature}/mocks/handlers';

export const handlers = [
  ...entityHandlers,
];
```

### Conditional MSW bootstrap in `src/main.tsx`

```typescript
async function bootstrap() {
  if (import.meta.env.VITE_ENABLE_MOCKS === 'true') {
    const { worker } = await import('./mocks/browser');
    await worker.start({ onUnhandledRequest: 'bypass' });
  }

  // ... existing render logic (ReactDOM.createRoot, etc.)
}

bootstrap();
```

### Canonical Test Patterns

Test files are located in `src/features/{feature}/__tests__/`. They use factories to generate test data and mock APIs with the MSW server.

#### Store Test (`__tests__/entityStore.test.ts`)

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { useEntityStore } from '../stores/entityStore';
import { createEntity, createEntityList } from '../mocks/factories';

describe('entityStore', () => {
  beforeEach(() => {
    useEntityStore.getState().reset();
  });

  it('sets list and total', () => { // TS-001
    const entities = createEntityList(3);
    useEntityStore.getState().setList(entities, 10);

    const state = useEntityStore.getState();
    expect(state.list).toHaveLength(3);
    expect(state.total).toBe(10);
  });

  it('resets filters page on setFilters', () => { // TS-002
    useEntityStore.getState().setFilters({ search: 'test' });
    expect(useEntityStore.getState().filters.page).toBe(1);
  });
});
```

#### Component Test (`__tests__/EntityForm.test.tsx`)

```tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { EntityForm } from '../components/EntityForm';
import { createEntityDto } from '../mocks/factories';

// i18n mock or wrapper needed

describe('EntityForm', () => {
  it('renders form fields', () => { // TS-010
    render(<EntityForm onSubmit={() => {}} />);
    expect(screen.getByLabelText(/name/i)).toBeInTheDocument();
  });

  it('calls onSubmit with form data', async () => { // TS-011
    const onSubmit = vi.fn();
    render(<EntityForm onSubmit={onSubmit} />);

    await userEvent.type(screen.getByLabelText(/name/i), 'Test Entity');
    await userEvent.click(screen.getByRole('button', { name: /submit|save/i }));

    expect(onSubmit).toHaveBeenCalled();
  });
});
```

#### Page Test (`__tests__/EntityListPage.test.tsx`) — 4-state coverage

```tsx
import { describe, it, expect, beforeAll, afterAll, afterEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { server } from '@/mocks/server';
import { http, HttpResponse } from 'msw';
import EntityListPage from '../pages/EntityListPage';
import { createEntityList } from '../mocks/factories';

beforeAll(() => server.listen());
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

describe('EntityListPage', () => {
  it('shows loading state', () => { // TS-020
    render(<MemoryRouter><EntityListPage /></MemoryRouter>);
    // assert skeleton or spinner
  });

  it('shows empty state when no data', async () => { // TS-021
    server.use(
      http.get('/api/v1/entities', () =>
        HttpResponse.json({ items: [], total: 0, page: 1, pageSize: 20 })
      ),
    );
    render(<MemoryRouter><EntityListPage /></MemoryRouter>);
    await waitFor(() => expect(screen.getByText(/empty/i)).toBeInTheDocument());
  });

  it('shows error state on failure', async () => { // TS-022
    server.use(
      http.get('/api/v1/entities', () => new HttpResponse(null, { status: 500 })),
    );
    render(<MemoryRouter><EntityListPage /></MemoryRouter>);
    await waitFor(() => expect(screen.getByText(/error|failed/i)).toBeInTheDocument());
  });

  it('shows entity list on success', async () => { // TS-023
    const entities = createEntityList(3);
    server.use(
      http.get('/api/v1/entities', () =>
        HttpResponse.json({ items: entities, total: 3, page: 1, pageSize: 20 })
      ),
    );
    render(<MemoryRouter><EntityListPage /></MemoryRouter>);
    await waitFor(() => expect(screen.getAllByRole('row')).toHaveLength(4)); // header + 3 rows
  });
});
```

### Factory Usage Example in Vitest

```typescript
import { createEntity } from '../mocks/factories';

it('shows inactive badge', () => {
  const entity = createEntity({ status: 'Inactive' });
  render(<EntityTable data={[entity]} />);
  expect(screen.getByText('Inactive')).toBeInTheDocument();
});
```
