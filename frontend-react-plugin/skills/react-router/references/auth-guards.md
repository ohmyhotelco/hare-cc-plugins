# Auth & RBAC Route Guards

팀 전용 인증/권한 라우트 가드 패턴. Zustand auth store 기반.

## Core Principle

- **서버가 RBAC 최종 판정** — 프론트는 UX 가드 수준만
- 프론트 라우트 가드 = 비인증/비인가 사용자에게 적절한 UI를 보여주는 역할
- API 요청은 항상 서버에서 권한 검증

## ProtectedRoute

인증된 사용자만 접근 가능한 라우트를 감싼다. 미인증 시 `/login`으로 리다이렉트하며, 원래 목적지를 `location.state`로 보존한다.

```tsx
import { Navigate, Outlet, useLocation } from "react-router";
import { useAuthStore } from "@/stores/auth-store";

function ProtectedRoute() {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated);
  const location = useLocation();

  if (!isAuthenticated) {
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  return <Outlet />;
}
```

### Login 후 원래 목적지로 복귀

```tsx
import { useLocation, useNavigate } from "react-router";

function LoginPage() {
  const location = useLocation();
  const navigate = useNavigate();
  const from = (location.state as { from?: Location })?.from?.pathname ?? "/";

  async function handleLogin(credentials: LoginCredentials) {
    await login(credentials);
    navigate(from, { replace: true });
  }

  return <form>...</form>;
}
```

## RoleRoute

특정 권한이 있는 사용자만 접근 가능한 라우트를 감싼다. 권한 부족 시 `/forbidden`으로 리다이렉트한다.

```tsx
import { Navigate, Outlet } from "react-router";
import { useAuthStore } from "@/stores/auth-store";

interface RoleRouteProps {
  permissions: string[];
}

function RoleRoute({ permissions }: RoleRouteProps) {
  const userPermissions = useAuthStore((s) => s.permissions);
  const hasPermission = permissions.every((p) => userPermissions.includes(p));

  if (!hasPermission) {
    return <Navigate to="/forbidden" replace />;
  }

  return <Outlet />;
}
```

## Route Structure with Guards

ProtectedRoute와 RoleRoute를 Layout Route로 감싸는 전체 구조.

```tsx
import { BrowserRouter, Routes, Route } from "react-router";

function App() {
  return (
    <BrowserRouter>
      <Routes>
        {/* Public routes */}
        <Route path="login" element={<Login />} />
        <Route path="forbidden" element={<Forbidden />} />

        {/* Authenticated routes */}
        <Route element={<ProtectedRoute />}>
          <Route element={<AppLayout />}>
            <Route path="/" element={<Home />} />
            <Route path="dashboard" element={<Dashboard />} />
            <Route path="profile" element={<Profile />} />

            {/* Admin routes — additional permission required */}
            <Route element={<RoleRoute permissions={["admin:read"]} />}>
              <Route path="admin" element={<AdminLayout />}>
                <Route index element={<AdminDashboard />} />
                <Route path="users" element={<UserManagement />} />
              </Route>
            </Route>

            {/* Manager routes */}
            <Route element={<RoleRoute permissions={["manager:read"]} />}>
              <Route path="reports" element={<Reports />} />
            </Route>
          </Route>
        </Route>

        {/* 404 */}
        <Route path="*" element={<NotFound />} />
      </Routes>
    </BrowserRouter>
  );
}
```

## 401/403 Interceptor Integration

Axios response interceptor와 라우트 가드를 동기화한다.

### 401 — 인증 만료

```tsx
axiosInstance.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      // 인증 상태 초기화
      useAuthStore.getState().logout();
      // → ProtectedRoute가 isAuthenticated=false 감지 → /login 리다이렉트
    }
    return Promise.reject(error);
  }
);
```

### 403 — 권한 변경

```tsx
axiosInstance.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 403) {
      // 서버에서 최신 권한 다시 조회
      useAuthStore.getState().refreshPermissions();
      // → RoleRoute가 permissions 변경 감지 → /forbidden 리다이렉트
    }
    return Promise.reject(error);
  }
);
```

> 네비게이션 리다이렉트 방식은 [navigation.md](navigation.md)의 Axios 401 Interceptor Navigation 패턴 참조.

## Anti-Patterns

### Frontend Permission Logic

```tsx
// BAD: 프론트에서 권한 로직 구현
function canAccessAdmin(user: User) {
  return user.role === "admin" || user.department === "IT";
}

// GOOD: 서버가 판정한 permissions 배열만 확인
function RoleRoute({ permissions }: { permissions: string[] }) {
  const userPermissions = useAuthStore((s) => s.permissions);
  return permissions.every((p) => userPermissions.includes(p))
    ? <Outlet />
    : <Navigate to="/forbidden" replace />;
}
```

### Client-Side Permission Cache

```tsx
// BAD: 권한을 클라이언트에서 장시간 캐시
localStorage.setItem("permissions", JSON.stringify(permissions));

// GOOD: Zustand store에만 보관, 401/403 시 서버에서 재조회
useAuthStore.getState().refreshPermissions();
```

### Route Loader for Auth Check

```tsx
// BAD: Data Router의 loader로 인증 체크 (Declarative 모드 금지)
const router = createBrowserRouter([
  {
    path: "dashboard",
    loader: async () => {
      const user = await getUser();
      if (!user) throw redirect("/login");
      return user;
    },
  },
]);

// GOOD: ProtectedRoute 컴포넌트로 인증 체크
<Route element={<ProtectedRoute />}>
  <Route path="dashboard" element={<Dashboard />} />
</Route>
```

### Conditional Route Rendering

```tsx
// BAD: 조건부로 라우트 자체를 렌더링/제거
<Routes>
  {isAdmin && <Route path="admin" element={<Admin />} />}
</Routes>

// GOOD: RoleRoute 가드로 접근 제어
<Route element={<RoleRoute permissions={["admin:read"]} />}>
  <Route path="admin" element={<Admin />} />
</Route>
```
