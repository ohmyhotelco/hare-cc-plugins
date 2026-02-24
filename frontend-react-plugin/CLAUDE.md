# Frontend React Plugin

프론트엔드 React 개발 시 기술 스택과 코딩 컨벤션을 적용하는 Claude Code 플러그인.

## Tech Stack

### Runtime & Build
- Node.js 22.x LTS (>= 22.12)
- Package Manager: pnpm
- Build: Vite
- Language: TypeScript (strict)

### Core Framework
- React 19.x
- Routing: React Router v7 — 모드는 `.claude/frontend-react-plugin.json`의 `routerMode` 설정에 따름 (default: declarative)
  - declarative: `<BrowserRouter>`, `<Routes>`, `<Route>` 사용
  - data: `createBrowserRouter`, `RouterProvider`, loader/action 사용
  - import: `react-router` (not `react-router-dom`)
  - 자세한 라우팅 패턴: `.claude/skills/react-router-{routerMode}-mode` 참조 (installed by `/frontend-react-plugin:init`)

### UI Layer
- Tailwind CSS
- shadcn/ui (Radix 기반, 프로젝트에 코드 소유)
- Icons: Lucide (`lucide-react`), 브랜드 로고 필요 시 Simple Icons 추가 고려

### State & Data
- Client State: Zustand (auth token, user, permissions 등 얇게 유지)
- HTTP: Axios
  - request interceptor: JWT Authorization 헤더 주입
  - response interceptor: 401 → logout/재인증, 403 → 권한 동기화
- (향후 고려) REST OpenAPI 제공 시 타입/클라이언트 자동생성

### Internationalization (i18n)
- i18next + react-i18next
- 언어: ko / en / ja / vi
- 네임스페이스 분리 (common, menu, feature별)
- Vite import.meta.glob 기반 lazy-load
- 언어 선택: localStorage 저장
- 날짜/시간: Intl.DateTimeFormat / Intl.RelativeTimeFormat (최신 Chrome 고정)

### Auth / RBAC
- 서버가 RBAC 최종 판정
- 프론트 역할: 메뉴 필터링, 라우트 가드 (/forbidden), 401/403 서버 응답 동기화
- 프론트에서 권한 로직 구현 금지 (UX 가드 수준만)

### Testing
- Unit/Component: Vitest — 자세한 테스트 패턴: `.claude/skills/vitest` 참조 (installed by `/frontend-react-plugin:init`)
- E2E: Playwright

## Conventions
- shadcn/ui 컴포넌트만 사용 (대체 컴포넌트 라이브러리 설치 금지)
- 2-space 들여쓰기
- functional component + hooks
- 모든 props/data에 TypeScript interface 정의
- icon-only button: aria-label 필수, decorative icon: aria-hidden="true"
- form control: <label> 연결 필수 (htmlFor 또는 wrapping)
- variable-length text: truncate / line-clamp-* 적용
- full-page layout: html → body → #root → layout 전체 height chain 설정

### Routing Conventions
- 인증 필요 라우트: `<ProtectedRoute>`로 감싸기 → 미인증 시 /login 리다이렉트 (return destination을 location.state.from으로 전달)
- 권한 필요 라우트: `<RoleRoute permissions={[...]}>` → 미권한 시 /forbidden 리다이렉트
- NavLink active state: shadcn/ui `cn()` + `isActive` callback 사용
- Axios 401 interceptor → /login 리다이렉트: navigate ref 패턴 사용 (useNavigate 직접 import 금지)
- URL searchParams ↔ Zustand: useEffect + store subscription으로 양방향 동기화
- 내부 네비게이션: react-router `<Link>`, `<NavLink>`, `useNavigate` 사용 (`<a>`, `window.location` 금지)

## Architecture
- **Agents**: (없음 — 추후 추가)
- **Skills**: `/frontend-react-plugin:init`
- **External Skills**: `react-router-declarative-mode` | `react-router-data-mode` (from `remix-run/agent-skills`), `vitest` (from `supabase/supabase`) — installed by init
- **Configuration**: `.claude/frontend-react-plugin.json` (created by `/frontend-react-plugin:init`)
- **Templates**: (없음 — 추후 추가)

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

## Project-Level Configuration

`.claude/frontend-react-plugin.json` (created by `/frontend-react-plugin:init`):
```json
{
  "routerMode": "declarative"
}
```

- `routerMode`: `"declarative"` (default) | `"data"` — React Router v7 모드 결정
