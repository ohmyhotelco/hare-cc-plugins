# URL Values

React Router v7 URL 값 읽기 패턴 — useParams, useSearchParams, useLocation.

## useParams

Dynamic segment (`:param`)로 캡처한 URL 파라미터를 읽는다.

### Basic Usage

```tsx
import { useParams } from "react-router";

// Route: <Route path="users/:userId" element={<User />} />
function User() {
  const { userId } = useParams();
  return <h1>User {userId}</h1>;
}
```

### Multiple Params

```tsx
// Route: <Route path="teams/:teamId/members/:memberId" element={<Member />} />
function Member() {
  const { teamId, memberId } = useParams();
  return <p>Team {teamId}, Member {memberId}</p>;
}
```

### Type Safety

```tsx
import { useParams } from "react-router";

function User() {
  const { userId } = useParams<{ userId: string }>();
  // userId는 string | undefined
  if (!userId) return <NotFound />;
  return <UserDetail id={userId} />;
}
```

### i18n Language Detection (Team Convention)

Optional segment로 언어를 감지하고 i18next에 반영한다:

```tsx
import { useParams } from "react-router";
import { useTranslation } from "react-i18next";
import { useEffect } from "react";

// Route: <Route path=":lang?" element={<AppLayout />}>
function AppLayout() {
  const { lang } = useParams<{ lang?: string }>();
  const { i18n } = useTranslation();

  useEffect(() => {
    const supportedLangs = ["ko", "en", "ja", "vi"];
    if (lang && supportedLangs.includes(lang)) {
      i18n.changeLanguage(lang);
    }
  }, [lang, i18n]);

  return <Outlet />;
}
```

## useSearchParams

URL query string (`?key=value`)을 읽고 쓴다.

### Basic Usage

```tsx
import { useSearchParams } from "react-router";

function ProductList() {
  const [searchParams, setSearchParams] = useSearchParams();
  const category = searchParams.get("category"); // ?category=shoes → "shoes"
  const page = searchParams.get("page") ?? "1";

  function handleCategoryChange(category: string) {
    setSearchParams({ category, page: "1" });
  }

  return <div>...</div>;
}
```

### Multiple Values

```tsx
const [searchParams] = useSearchParams();

// ?tags=react&tags=typescript
const tags = searchParams.getAll("tags"); // ["react", "typescript"]
```

### Preserving Existing Params

```tsx
function updateParam(key: string, value: string) {
  setSearchParams((prev) => {
    prev.set(key, value);
    return prev;
  });
}
```

### Zustand Store Sync (Team Convention)

필터 상태를 URL searchParams와 Zustand store에 동기화한다:

```tsx
import { useSearchParams } from "react-router";
import { useFilterStore } from "@/stores/filter-store";
import { useEffect } from "react";

function ProductList() {
  const [searchParams, setSearchParams] = useSearchParams();
  const { filters, setFilters } = useFilterStore();

  // URL → Store: 초기 로드 시 URL에서 필터 복원
  useEffect(() => {
    const urlFilters = {
      category: searchParams.get("category") ?? "",
      sort: searchParams.get("sort") ?? "newest",
      page: Number(searchParams.get("page") ?? "1"),
    };
    setFilters(urlFilters);
  }, []); // 초기 로드 시 한 번만

  // Store → URL: 필터 변경 시 URL 업데이트
  useEffect(() => {
    const params = new URLSearchParams();
    if (filters.category) params.set("category", filters.category);
    if (filters.sort !== "newest") params.set("sort", filters.sort);
    if (filters.page > 1) params.set("page", String(filters.page));
    setSearchParams(params, { replace: true });
  }, [filters, setSearchParams]);

  return <div>...</div>;
}
```

> 양방향 동기화 시 무한 루프 주의. URL → Store는 초기 로드 시에만, Store → URL은 필터 변경 시에만 실행한다.

## useLocation

현재 location 객체 전체를 읽는다.

### Basic Usage

```tsx
import { useLocation } from "react-router";

function Breadcrumb() {
  const location = useLocation();

  return (
    <nav>
      <span>Current: {location.pathname}</span>
    </nav>
  );
}
```

### Location Object

```tsx
const location = useLocation();

location.pathname;  // "/products/123"
location.search;    // "?color=red"
location.hash;      // "#reviews"
location.state;     // { from: "/cart" } (Link/navigate로 전달한 state)
location.key;       // 고유 키 (히스토리 항목 식별)
```

### Analytics Tracking

```tsx
import { useLocation } from "react-router";
import { useEffect } from "react";

function usePageTracking() {
  const location = useLocation();

  useEffect(() => {
    trackPageView(location.pathname + location.search);
  }, [location]);
}
```

## Anti-Patterns

### URL Parsing with window.location

```tsx
// BAD: React Router 상태와 동기화 안 됨
const params = new URLSearchParams(window.location.search);

// GOOD
const [searchParams] = useSearchParams();
```

### Manual Path Parsing

```tsx
// BAD: 수동 파싱
const userId = window.location.pathname.split("/")[2];

// GOOD: useParams 사용
const { userId } = useParams();
```

### Ignoring Undefined Params

```tsx
// BAD: undefined 가능성 무시
const { userId } = useParams();
fetchUser(userId); // userId가 undefined일 수 있음

// GOOD: 방어 처리
const { userId } = useParams<{ userId: string }>();
if (!userId) return <NotFound />;
fetchUser(userId);
```

---

> Based on [remix-run/agent-skills](https://github.com/remix-run/agent-skills) `react-router-declarative-mode` (MIT License).
