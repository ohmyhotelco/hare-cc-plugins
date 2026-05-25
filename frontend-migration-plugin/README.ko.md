# Frontend Migration Plugin (한국어)

OhMyHotel Angular 15 앱(PC·Mobile·Hana)을 **React Router v7**로 마이그레이션하는 Claude Code
플러그인입니다. 개정된 v2 마이그레이션 계획을 따릅니다. **완전 독립형**(자체 에이전트·파이프라인)
이지만, 생성 결과의 일관성을 위해 `frontend-react-plugin`의 스택 컨벤션을 공유합니다.

> 빌드 상태: 스킬/에이전트/템플릿이 모두 갖춰진 기능 완성 단계. 실제 실행은 마이그레이션
> 프로젝트가 스캐폴딩하는 v2 모노레포(`apps/` + `packages/`)를 대상으로 합니다.

## 무엇을 하나

코드 생성에 마이그레이션이 필요로 하는 네 가지를 감쌉니다:
1. **Angular 소스 분석** — 레거시 page/service/store를 읽어 구조화된 계획 산출
2. **공유 패키지 추출** — 순수 로직을 framework-agnostic `packages/shared-*`로 추출
3. **레거시 패리티 게이트** — 트래픽 플립 전 신규가 레거시와 동등함을 증명
4. **Strangler Fig 오케스트레이션** — 페이지 단위 라우트 플립 + 진척 추적

## 타깃 스택

React Router v7(framework mode) · TypeScript(strict) · Tailwind · shadcn/ui · TanStack Query ·
Zustand · axios · react-hook-form + zod · i18next · dayjs · Vitest + MSW · **Playwright**(E2E +
시각 회귀 — fe-plugin agent-browser와의 의도적 분기).

## 시작하기

```
/frontend-migration-plugin:fm-init
```
레거시 Angular 앱과 모노레포 레이아웃을 감지해 `.claude/frontend-migration-plugin.json`을 작성
(앱별 `legacyDir`/`targetDir`/`appDir`/`domain`/`port`/`ssr`/`webview`/`sso`)하고
`docs/migration/tracker.json`을 초기화합니다. PC 우선, Mobile/Hana는 스캐폴딩 후 추후 검증.

## 워크플로우

```
/fm-init                       설정 + tracker (1회)

[Phase 0]
/fm-secret-audit               레거시 secret 인벤토리(client vs server) — OMH-477
/fm-analyze <target>           Angular → analysis.json
/fm-extract <candidate>        순수 로직 → packages/shared-*

[페이지 루프]
/fm-analyze <page> → /fm-plan → /fm-gen → /fm-verify
                                             │ 실패 → /fm-fix
                                   /fm-e2e   (Playwright 게이트키퍼)
                                   /fm-parity (시각/계약/webview/telemetry)
                                   /fm-route --flag-off (PR1) → --flag-on (PR2, 게이트 가드)

/fm-delta <page>               레거시 변경 시 변경분만 재마이그레이션
/fm-progress                   앱별/페이지별 상태(read-only)
```

생성 후 두 하드 게이트가 직렬로 — `fm-verify`(빌드/tsc/vitest) → `fm-parity`(레거시 동등성),
그 사이에 `fm-e2e`(Playwright) 기능 게이트키퍼. verify+e2e+parity 전부 통과해야 플립 허용.

## 스킬

`fm-init` · `fm-analyze` · `fm-extract` · `fm-plan` · `fm-gen` · `fm-verify` · `fm-fix` ·
`fm-e2e` · `fm-parity` · `fm-route` · `fm-progress` · `fm-delta` · `fm-clean-code` ·
`fm-test-review` · `fm-secret-audit` (상세: `docs/skill-reference.md`)

## 문서

- `docs/workflow.md` — 페이지 상태 머신, 게이트 체인, 토폴로지
- `docs/skill-reference.md` — 전체 스킬·에이전트 레퍼런스
- `CLAUDE.md` — 컨벤션, 상태파일·Lock 규칙, 설계 원칙, 매핑/게이트 인덱스
- `templates/` — 매핑 카탈로그, 공유 패키지 스펙/규약, WebView 브리지, Hana SSO, Strangler Fig,
  TDD 규칙, migration-plan 스키마

영문: `README.md` · Tiếng Việt: `README.vi.md`
