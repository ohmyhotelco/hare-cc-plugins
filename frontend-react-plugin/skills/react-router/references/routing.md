# Route Configuration

React Router v7 Declarative 모드 라우트 설정 패턴.

## Team Constraints

- **Import**: `react-router` (NOT `react-router-dom`)
- **금지 API**: `createBrowserRouter`, `RouterProvider`, `loader`, `action`, `fetcher`, `useFetcher`, `useLoaderData`, `useActionData`
- **Layout Route**: full-page height chain 필수 (`h-screen` 또는 `min-h-screen`)
- **인증 라우트**: `<ProtectedRoute>` / `<RoleRoute>` 감싸기 필수 → [auth-guards.md](auth-guards.md) 참조

## Basic Setup

```tsx
import { BrowserRouter, Routes, Route } from "react-router";

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="about" element={<About />} />
        <Route path="contact" element={<Contact />} />
      </Routes>
    </BrowserRouter>
  );
}
```

## Route Props

| Prop | Type | Description |
|------|------|-------------|
| `path` | `string` | URL 패턴 매칭 |
| `element` | `ReactElement` | 렌더링할 컴포넌트 |
| `index` | `boolean` | 부모 URL에서 렌더링되는 기본 자식 |

## Nested Routes with Outlet

부모 라우트 컴포넌트에서 `<Outlet />`으로 자식 라우트를 렌더링한다.

```tsx
import { Routes, Route, Outlet } from "react-router";

function Dashboard() {
  return (
    <div>
      <h1>Dashboard</h1>
      <nav>
        <Link to="settings">Settings</Link>
        <Link to="profile">Profile</Link>
      </nav>
      <Outlet />
    </div>
  );
}

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="dashboard" element={<Dashboard />}>
          <Route index element={<DashboardHome />} />
          <Route path="settings" element={<Settings />} />
          <Route path="profile" element={<Profile />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}
```

## Layout Routes (Pathless)

`path` 없이 `element`만 지정하면 자식들에게 공통 레이아웃을 적용한다.

```tsx
<Routes>
  <Route element={<MarketingLayout />}>
    <Route path="/" element={<Home />} />
    <Route path="about" element={<About />} />
  </Route>
  <Route element={<AppLayout />}>
    <Route path="dashboard" element={<Dashboard />} />
    <Route path="settings" element={<Settings />} />
  </Route>
</Routes>
```

### Full-Page Layout Height Chain (Team Convention)

Layout Route 컴포넌트에서 전체 높이 체인을 설정한다:

```tsx
function AppLayout() {
  return (
    <div className="flex min-h-screen flex-col">
      <Header />
      <main className="flex-1">
        <Outlet />
      </main>
      <Footer />
    </div>
  );
}
```

> `index.html`의 `<html>`, `<body>`, `#root`에도 `h-full` 또는 `min-h-screen`이 적용되어야 전체 height chain이 완성된다.

## Index Routes

부모 경로에 정확히 매칭될 때 렌더링되는 기본 자식 라우트.

```tsx
<Route path="dashboard" element={<DashboardLayout />}>
  <Route index element={<DashboardHome />} />
  <Route path="settings" element={<Settings />} />
</Route>
```

- `/dashboard` → `<DashboardHome />` 렌더링
- `/dashboard/settings` → `<Settings />` 렌더링

## Route Prefixes

공통 경로 접두사를 그룹핑할 때 사용. `element` 없이 `path`만 지정.

```tsx
<Route path="settings">
  <Route index element={<SettingsHome />} />
  <Route path="profile" element={<Profile />} />
  <Route path="notifications" element={<Notifications />} />
</Route>
```

## Dynamic Segments

`:param` 문법으로 URL 세그먼트를 파라미터로 캡처한다.

```tsx
<Route path="users/:userId" element={<User />} />
```

```tsx
import { useParams } from "react-router";

function User() {
  const { userId } = useParams();
  return <h1>User {userId}</h1>;
}
```

## Optional Segments

`?` 접미사로 세그먼트를 선택적으로 만든다.

```tsx
<Route path=":lang?/products" element={<Products />} />
<Route path="users/:userId/edit?" element={<User />} />
```

### i18n Locale Prefix (Team Convention)

다국어 라우팅에 optional segment를 활용한다:

```tsx
<Route path=":lang?" element={<AppLayout />}>
  <Route index element={<Home />} />
  <Route path="dashboard" element={<Dashboard />} />
  <Route path="settings" element={<Settings />} />
</Route>
```

- `/dashboard` → 기본 언어 (localStorage 기반)
- `/ko/dashboard` → 한국어
- `/en/dashboard` → 영어

> 언어 감지 로직은 [url-values.md](url-values.md)의 useParams i18n 패턴 참조.

## Splats / Catch-All

`*` 패턴으로 이후 모든 경로를 매칭한다.

```tsx
<Route path="docs/*" element={<Docs />} />
```

```tsx
import { useParams } from "react-router";

function Docs() {
  const { "*": splatPath } = useParams();
  // /docs/guides/routing → splatPath = "guides/routing"
  return <DocViewer path={splatPath} />;
}
```

## 404 Catch-All

최상위에 `*` 라우트를 추가하여 매칭되지 않는 URL을 처리한다.

```tsx
<Routes>
  <Route path="/" element={<Home />} />
  <Route path="about" element={<About />} />
  {/* ... other routes ... */}
  <Route path="*" element={<NotFound />} />
</Routes>
```

## Anti-Patterns

### Flat Routes (Bad)

```tsx
// BAD: 공통 레이아웃 없이 평탄하게 나열
<Route path="dashboard" element={<Dashboard />} />
<Route path="dashboard/settings" element={<DashboardSettings />} />
<Route path="dashboard/profile" element={<DashboardProfile />} />
```

### Nested Routes (Good)

```tsx
// GOOD: 중첩 라우트로 레이아웃 공유
<Route path="dashboard" element={<DashboardLayout />}>
  <Route index element={<Dashboard />} />
  <Route path="settings" element={<DashboardSettings />} />
  <Route path="profile" element={<DashboardProfile />} />
</Route>
```

### Banned API Usage (Bad)

```tsx
// BAD: Data Router API 사용 금지
import { createBrowserRouter, RouterProvider } from "react-router";

const router = createBrowserRouter([
  { path: "/", element: <Home />, loader: homeLoader },
]);

function App() {
  return <RouterProvider router={router} />;
}
```

---

> Based on [remix-run/agent-skills](https://github.com/remix-run/agent-skills) `react-router-declarative-mode` (MIT License).
