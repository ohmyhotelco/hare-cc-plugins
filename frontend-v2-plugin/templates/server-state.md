# Template: Server-State Layering (TanStack Query ↔ loader)

The contract when `serverState == tanstack-query` (D9/D13). Read by `implementation-planner` (plans the
`queries` block), `tdd-cycle-runner` (api-tdd), `foundation-generator`, `integration-generator`, and
`quality-reviewer`. When `serverState == zustand-only` this template does not apply — server data flows
through Axios services + Zustand as before.

## Where each data need lives

| Need | Home |
| --- | --- |
| SSR / SSG route initial data | route `loader` fetches via the base client, returns data; component may hand it to `useQuery` as `initialData` |
| SPA route data | pure `useQuery` (or `clientLoader` + query) |
| Lists with paging / infinite scroll | `useInfiniteQuery` |
| Create / update / delete | `useMutation` + invalidation map |
| UI / client state (search-form input, filters-as-UI, locale, toggles) | Zustand — **never** server data |

## Rule (a): one query-key factory, one fetcher — fetch-client-agnostic

Loader and hook share **one** `queryOptions` factory. The factory takes the fetch client as an argument,
so it composes with the D13 base/browser split rather than conflicting with it: the loader injects the
**base client**, the hook injects the **browser wrapper**.

```ts
// features/hotel-search/api/queries.ts
import { queryOptions, infiniteQueryOptions } from '@tanstack/react-query'
import type { ApiClient } from '~/lib/api.types' // shared interface both clients implement

export const hotelKeys = {
  all: ['hotels'] as const,
  list: (params: HotelSearchParams) => [...hotelKeys.all, 'list', params] as const,
  detail: (id: string) => [...hotelKeys.all, 'detail', id] as const,
}

export function hotelListQuery(client: ApiClient, params: HotelSearchParams) {
  return queryOptions({
    queryKey: hotelKeys.list(params),
    queryFn: () => client.get<HotelListResponse>('/hotels', { params }),
    staleTime: 60_000, // rule (b)
  })
}
```

## Rule (b): explicit `staleTime` > 0 on loader-fed queries

The TanStack default `staleTime: 0` makes `initialData` immediately stale, so the hook refetches on
mount — reintroducing the double-fetch this contract exists to prevent. Loader-fed queries set an
explicit `staleTime` (default 60s; tune per data volatility). The root `QueryClient` also sets a 60s
default (see `framework-app-shell.md`).

## Rule (c): pass `initialDataUpdatedAt` from the loader

The loader returns its fetch timestamp; the component passes it so a previously-populated cache entry is
not overwritten by staler loader data.

```tsx
// features/hotel-search/pages/HotelSearchPage.tsx (page-body component; receives loaderData as props)
export function HotelSearchPage({ data, fetchedAt, params }: HotelSearchLoaderData) {
  const client = useBrowserApiClient() // D13 browser wrapper on the client
  const { data: hotels } = useQuery({
    ...hotelListQuery(client, params),
    initialData: data,
    initialDataUpdatedAt: fetchedAt, // rule (c)
  })
  // ...render
}
```

> If a route only needs the data once with no live refetch, skip `useQuery` entirely and render
> `loaderData` directly. Reach for `initialData` only when the client also refetches.

## Mutations + invalidation

```ts
const qc = useQueryClient()
const create = useMutation({
  mutationFn: (body: CreateHotelDto) => client.post('/hotels', body),
  onSuccess: () => qc.invalidateQueries({ queryKey: hotelKeys.all }), // invalidation map
})
```

Plan each mutation's `invalidates[]` (query keys) in `plan.json` `api[].queries.hooks[]`.

## Anti-patterns (quality-reviewer enforces)

- **No `useEffect` fetching** — a data need has a query hook or a loader; never a `useEffect` + `setState`.
- **No server data in Zustand** — stores hold UI/client state only.
- **No hand-written fetch twice** — loader and hook go through the same factory (rule a).
- Loaders import only the **base** client (D13); the browser wrapper (JWT/localStorage interceptors) is
  client-only.

## Escalation to full hydration (O2 — deferred)

The `initialData` handoff is the v1 pattern. Escalate to `dehydrate` / `HydrationBoundary` only when
nested routes must share one cache entry (a single query consumed by multiple route levels). Not in
Phase 1 scope.
