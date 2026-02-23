# Navigation

React Router v7 네비게이션 패턴.

## Link

기본 네비게이션 컴포넌트. 항상 `<a>` 대신 `<Link>`를 사용한다.

```tsx
import { Link } from "react-router";

<Link to="/about">About</Link>
<Link to="/products/123">Product Detail</Link>
```

## NavLink

현재 URL과 매칭 시 active 상태를 제공하는 네비게이션 컴포넌트.

### Basic Usage

```tsx
import { NavLink } from "react-router";

<NavLink
  to="/products"
  className={({ isActive }) => (isActive ? "nav-active" : "nav-link")}
>
  Products
</NavLink>
```

### shadcn/ui + Tailwind (Team Convention)

```tsx
import { NavLink } from "react-router";
import { cn } from "@/lib/utils";

function SidebarNav({ items }: { items: { to: string; label: string }[] }) {
  return (
    <nav className="flex flex-col gap-1">
      {items.map((item) => (
        <NavLink
          key={item.to}
          to={item.to}
          className={({ isActive }) =>
            cn(
              "rounded-md px-3 py-2 text-sm font-medium transition-colors",
              "hover:bg-accent hover:text-accent-foreground",
              isActive
                ? "bg-accent text-accent-foreground"
                : "text-muted-foreground"
            )
          }
        >
          {item.label}
        </NavLink>
      ))}
    </nav>
  );
}
```

### Render Props (Style & ClassName)

```tsx
<NavLink
  to="/dashboard"
  style={({ isActive }) => ({
    fontWeight: isActive ? "bold" : "normal",
  })}
>
  Dashboard
</NavLink>
```

### Children Render Function

```tsx
<NavLink to="/notifications">
  {({ isActive }) => (
    <span className={cn("flex items-center gap-2", isActive && "font-bold")}>
      <Bell className={cn("h-4 w-4", isActive && "text-primary")} />
      Notifications
    </span>
  )}
</NavLink>
```

## useNavigate

프로그래매틱 네비게이션. 이벤트 핸들러나 side-effect에서 사용한다.

```tsx
import { useNavigate } from "react-router";

function LoginForm() {
  const navigate = useNavigate();

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    await login();
    navigate("/dashboard");
  }

  return <form onSubmit={handleSubmit}>...</form>;
}
```

### Replace History Entry

```tsx
// 현재 히스토리 항목을 교체 (뒤로가기 시 이전 페이지 건너뜀)
navigate("/dashboard", { replace: true });
```

### Navigate Back

```tsx
navigate(-1); // 뒤로가기
navigate(-2); // 두 단계 뒤로
```

## Relative Navigation

현재 라우트 기준 상대 경로 네비게이션.

```tsx
// 현재 URL: /products/123

<Link to="reviews">       {/* → /products/123/reviews */}
<Link to="../456">         {/* → /products/456 */}
<Link to="..">             {/* → /products */}
```

> 상대 경로는 현재 **라우트** 기준이다 (URL path 기준이 아님). 중첩 라우트에서 주의.

## Passing State

라우트 간 임시 데이터 전달. URL에 노출되지 않는다.

### Link State

```tsx
<Link to="/checkout" state={{ cartId: "abc123", from: "/cart" }}>
  Checkout
</Link>
```

### Navigate State

```tsx
navigate("/checkout", { state: { cartId: "abc123" } });
```

### Reading State

```tsx
import { useLocation } from "react-router";

function Checkout() {
  const location = useLocation();
  const { cartId, from } = location.state ?? {};
  // ...
}
```

> State는 세션 히스토리에 저장된다. 새 탭이나 URL 직접 입력 시에는 `null`이 될 수 있으므로 항상 fallback을 처리한다.

## Axios 401 Interceptor Navigation (Team Convention)

Axios response interceptor에서 401 응답 시 로그인 페이지로 리다이렉트한다.

```tsx
import { NavigateFunction } from "react-router";

let navigateRef: NavigateFunction | null = null;

export function setNavigateRef(fn: NavigateFunction) {
  navigateRef = fn;
}

// Axios interceptor 설정
axiosInstance.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      useAuthStore.getState().logout();
      navigateRef?.("/login", { replace: true });
    }
    return Promise.reject(error);
  }
);
```

```tsx
// App.tsx에서 navigate ref 설정
import { useNavigate } from "react-router";
import { setNavigateRef } from "@/lib/axios";

function NavigateRefSetter() {
  const navigate = useNavigate();
  React.useEffect(() => {
    setNavigateRef(navigate);
  }, [navigate]);
  return null;
}
```

> 인증 상태 관리는 [auth-guards.md](auth-guards.md) 참조.

## Anti-Patterns

### `<a>` Tag for Internal Navigation

```tsx
// BAD: 전체 페이지 리로드 발생
<a href="/about">About</a>

// GOOD: SPA 네비게이션
<Link to="/about">About</Link>
```

### useNavigate in Render

```tsx
// BAD: 렌더 중 네비게이션 호출
function Component() {
  const navigate = useNavigate();
  if (someCondition) navigate("/other"); // 사이드이펙트!
  return <div>...</div>;
}

// GOOD: useEffect 또는 이벤트 핸들러에서 호출
function Component() {
  const navigate = useNavigate();
  useEffect(() => {
    if (someCondition) navigate("/other");
  }, [someCondition, navigate]);
  return <div>...</div>;
}
```

### Window Location for Navigation

```tsx
// BAD: SPA 상태 손실
window.location.href = "/dashboard";

// GOOD
navigate("/dashboard");
```

---

> Based on [remix-run/agent-skills](https://github.com/remix-run/agent-skills) `react-router-declarative-mode` (MIT License).
