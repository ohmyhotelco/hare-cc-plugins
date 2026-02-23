---
name: react-router
description: "React Router v7 Declarative mode routing patterns and team conventions. Route configuration, navigation, URL values, and auth/RBAC route guards."
argument-hint: ""
user-invocable: true
allowed-tools: Read, Glob
---

# React Router v7 — Declarative Mode Patterns

React Router v7 라우팅 패턴과 팀 컨벤션 레퍼런스.

## Critical Constraints

### Declarative Mode Only

- **사용**: `<BrowserRouter>`, `<Routes>`, `<Route>`, `<Outlet>`
- **금지**: `createBrowserRouter`, `RouterProvider`, `loader`, `action`, `fetcher`, `useFetcher`, `useLoaderData`, `useActionData`
- **Import path**: `react-router` (NOT `react-router-dom`)

### Auth Guard 필수

- 인증이 필요한 라우트는 반드시 `<ProtectedRoute>`로 감싼다
- 권한이 필요한 라우트는 `<RoleRoute permissions={[...]}>`로 감싼다
- 프론트에서 권한 로직 구현 금지 — UX 가드 수준만, 서버가 RBAC 최종 판정

### Full-Page Layout Chain

- Layout Route에서 `html → body → #root → layout` 전체 height chain 설정
- `h-screen` 또는 `min-h-screen` + `flex flex-col` 패턴 사용

## When to Apply This Skill

| 상황 | 참조 |
|------|------|
| 라우트 설정/수정 | [routing.md](references/routing.md) |
| 네비게이션 추가 | [navigation.md](references/navigation.md) |
| URL 파라미터/쿼리 읽기 | [url-values.md](references/url-values.md) |
| 인증/권한 가드 구현 | [auth-guards.md](references/auth-guards.md) |
| 레이아웃/중첩 라우트 | [routing.md](references/routing.md) |
| 404/에러 바운더리 | [routing.md](references/routing.md) |

## References

| File | Description |
|------|-------------|
| [routing.md](references/routing.md) | Route configuration — nested, layout, dynamic, optional, splat, 404 |
| [navigation.md](references/navigation.md) | Link, NavLink, useNavigate, relative navigation, state passing |
| [url-values.md](references/url-values.md) | useParams, useSearchParams, useLocation |
| [auth-guards.md](references/auth-guards.md) | ProtectedRoute, RoleRoute, 401/403 interceptor integration |

## Critical Patterns (Quick Reference)

### Basic Route Setup

```tsx
import { BrowserRouter, Routes, Route } from "react-router";

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="about" element={<About />} />
        <Route path="*" element={<NotFound />} />
      </Routes>
    </BrowserRouter>
  );
}
```

### NavLink with shadcn/ui

```tsx
import { NavLink } from "react-router";
import { cn } from "@/lib/utils";

<NavLink
  to="/dashboard"
  className={({ isActive }) =>
    cn("text-sm font-medium transition-colors hover:text-primary",
       isActive ? "text-primary" : "text-muted-foreground")
  }
>
  Dashboard
</NavLink>
```

### Auth Guard (Summary)

```tsx
// 인증 필수 영역
<Route element={<ProtectedRoute />}>
  <Route path="dashboard" element={<DashboardLayout />}>
    <Route index element={<Dashboard />} />
    {/* 추가 권한 필요 */}
    <Route element={<RoleRoute permissions={["admin:read"]} />}>
      <Route path="admin" element={<Admin />} />
    </Route>
  </Route>
</Route>

// 비인증 영역
<Route path="login" element={<Login />} />
<Route path="forbidden" element={<Forbidden />} />
```

---

> Based on [remix-run/agent-skills](https://github.com/remix-run/agent-skills) `react-router-declarative-mode` (MIT License), extended with team conventions.
