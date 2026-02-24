# Feature Module Structure Reference

feature 모듈의 정규 구조. `implementation-planner`와 `code-generator` 에이전트 모두 이 구조를 참조한다.

## Directory Layout

```
src/features/{feature}/
├── types/
│   └── {entity}.ts              ← Entity, CreateDto, UpdateDto, enums
├── api/
│   └── {entity}Api.ts           ← Axios CRUD methods, typed req/res
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

### i18n JSON (`locales/{lang}/{feature}.json`)

```json
{
  "entityList": {
    "title": "엔티티 목록",
    "searchPlaceholder": "검색어를 입력하세요",
    "empty": "등록된 엔티티가 없습니다"
  },
  "entityForm": {
    "name": {
      "label": "이름",
      "placeholder": "이름을 입력하세요"
    },
    "status": {
      "label": "상태",
      "placeholder": "상태를 선택하세요",
      "active": "활성",
      "inactive": "비활성"
    }
  },
  "entityTable": {
    "name": "이름",
    "status": "상태",
    "createdAt": "등록일",
    "actions": "관리"
  },
  "actions": {
    "create": "등록",
    "edit": "수정",
    "delete": "삭제",
    "deleteConfirm": "정말 삭제하시겠습니까?",
    "submit": "저장",
    "submitting": "저장 중...",
    "retry": "재시도",
    "cancel": "취소"
  },
  "errors": {
    "loadFailed": "데이터를 불러오지 못했습니다",
    "saveFailed": "저장에 실패했습니다",
    "deleteFailed": "삭제에 실패했습니다"
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
