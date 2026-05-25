# Frontend Migration Plugin (한국어)

OhMyHotel Angular 15 앱(PC·Mobile·Hana)을 **React Router v7**로 마이그레이션하는 Claude Code
플러그인입니다. 개정된 v2 마이그레이션 계획을 따릅니다. **완전 독립형**(자체 에이전트·파이프라인)
이지만, 생성 결과의 일관성을 위해 `frontend-react-plugin`의 스택 컨벤션을 공유합니다.

> 상태: 기능 완성 툴링(v0.2.0). 이 플러그인은 제품 앱을 포함하지 않으며, 마이그레이션
> 프로젝트가 스캐폴딩하는 v2 모노레포(`apps/` + `packages/`)를 대상으로 동작합니다.

## 무엇을 하나

코드 생성에 마이그레이션이 필요로 하는 네 가지를 감쌉니다:
1. **Angular 소스 분석** — 레거시 page/service/store를 읽어 구조화된 계획 산출
2. **공유 패키지 추출** — 순수 로직을 framework-agnostic `packages/shared-*`로 추출
3. **레거시 패리티 게이트** — 트래픽 플립 전 신규가 레거시와 동등함을 증명
4. **Strangler Fig 오케스트레이션** — 페이지 단위 라우트 플립 + 진척 추적

## 개념 (먼저 읽기)

마이그레이션이 처음이라면 다음 용어가 반복됩니다:

- **Strangler Fig** — 페이지 단위로 마이그레이션. nginx가 각 경로를 레거시 Angular 앱 또는
  신규 React 앱으로 라우팅하여, 한 번에 하나씩 구 앱을 "교살(strangle)"합니다. 빅뱅 재작성 아님.
- **페이지 루프** — 모든 페이지가 동일 순서를 거칩니다: `analyze → plan → gen → verify → e2e →
  parity → route`. 한 번에 한 페이지.
- **3중 패리티 게이트** — 생성 후 순서대로 통과해야 함: `fm-verify`(기술: 빌드/타입/단위테스트),
  `fm-e2e`(레거시처럼 동작하는가?), `fm-parity`(레거시처럼 보이고/계약/추적되는가?). 셋 다
  통과 전까지 라우트 플립 **차단**.
- **레거시 dual-run** — `fm-e2e`가 동일 시나리오를 레거시와 신규 양쪽에 실행해 비교. 레거시
  동작이 정답.
- **공유 패키지** — 순수 로직(validators·date·DTO·i18n)을 `packages/shared-*`로 한 번 추출해
  3개 앱이 import. 가능한 한 React-free.
- **2-PR 피처 플래그** — 페이지는 2개 PR로: 플래그 **OFF** 코드 PR(사용자는 아직 레거시) →
  게이트 통과 후 한 줄짜리 플래그 **ON** PR. 롤백 = 플래그 되돌리기.
- **상태 머신 + 트래커** — 모든 페이지 상태는 `docs/migration/tracker.json`에
  (`analyzed → planned → generated → verified → e2e-passed → parity-passed → flipped → done`).

## 전제조건

이 플러그인은 **툴링**이며, 마이그레이션 프로젝트가 작업 공간을 준비했다고 가정합니다:

- **v2 모노레포**: `apps/legacy-*`(마이그레이션 대상 Angular 앱), `apps/web-*`(신규 RR v7 앱),
  `packages/`(공유 패키지)
- **Node + pnpm**(pnpm workspaces), E2E·시각 게이트용 **Playwright 브라우저**(`npx playwright
  install`)
- 분석 가능한 **레거시 Angular 소스**
- 플러그인 **설정** — `fm-init` 1회 실행(`.claude/frontend-migration-plugin.json` +
  `docs/migration/tracker.json` 생성)

> v2 모노레포가 아직 없다면, 그 스캐폴딩은 마이그레이션 프로젝트의 Phase 0 인프라 작업
> (OMH-455 / OMH-502)이며 이 플러그인이 만들지 않습니다.

## 타깃 스택

React Router v7(framework mode) · TypeScript(strict) · Tailwind · shadcn/ui · TanStack Query ·
Zustand · axios · react-hook-form + zod · i18next · dayjs · Vitest + MSW · **Playwright**(E2E +
시각 회귀 — fe-plugin agent-browser와의 의도적 분기).

## 빠른 시작 — 첫 페이지 마이그레이션

전제조건 충족 후:

```
# 0. 1회 설정
/frontend-migration-plugin:fm-init
#    레거시/모노레포 레이아웃 감지, config + tracker 작성. PC 우선.

# 1. (Phase 0) 보안 선결 + 페이지가 쓸 공유 로직 추출
/frontend-migration-plugin:fm-secret-audit                 # 레거시 secret 인벤토리 (posture; OMH-477)
/frontend-migration-plugin:fm-analyze hotel-booking-info   # → analysis.json (의존·게이트·공유후보)
/frontend-migration-plugin:fm-extract --from hotel-booking-info   # 순수 로직 → packages/shared-*

# 2. 페이지 루프
/frontend-migration-plugin:fm-plan hotel-booking-info      # → migration-plan.json (트리·렌더링·게이트·e2e 시나리오)
/frontend-migration-plugin:fm-gen hotel-booking-info       # RR v7 페이지 TDD → 상태: generated
/frontend-migration-plugin:fm-verify hotel-booking-info    # build/tsc/vitest → verified   (게이트 1)
/frontend-migration-plugin:fm-e2e hotel-booking-info       # Playwright + dual-run → e2e-passed   (게이트 2)
/frontend-migration-plugin:fm-parity hotel-booking-info    # 시각/계약/webview/telemetry → parity-passed   (게이트 3)

# 3. 라우트 플립 (2개 PR)
/frontend-migration-plugin:fm-route hotel-booking-info --flag-off   # 코드 PR (플래그 OFF)
/frontend-migration-plugin:fm-route hotel-booking-info --flag-on    # 한 줄 플립 PR (게이트 전부 통과 시)

# 언제든: 모든 페이지 현황
/frontend-migration-plugin:fm-progress
```

각 단계는 `docs/migration/{app}/{page}/`에 산출물을 쓰고 트래커 상태를 진행시킵니다. 게이트
실패 시 `fm-fix <page>`(어느 게이트인지 자동 감지) 후 해당 게이트 재실행.

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

## 게이트

라우트 플립(`fm-route --flag-on`)은 셋 다 통과해야 허용됩니다.

| 게이트 | 스킬 | 검사 | 실패 시 |
| --- | --- | --- | --- |
| 1 · 기술 | `fm-verify` | build, `tsc`(composite 인식), Vitest | `fm-fix` (verify-fix) |
| 2 · 기능 | `fm-e2e` | Playwright 사용자 플로우; 레거시 dual-run; 스테이징 결제 게이트웨이 | `fm-fix` (e2e-fix) |
| 3 · 패리티 | `fm-parity` | 레거시 대비 시각 회귀, API 계약 동결, WebView 브리지 왕복, 텔레메트리 dual-fire | `fm-fix` (parity-fix) |

## 스킬

`fm-init` · `fm-analyze` · `fm-extract` · `fm-plan` · `fm-gen` · `fm-verify` · `fm-fix` ·
`fm-e2e` · `fm-parity` · `fm-route` · `fm-progress` · `fm-delta` · `fm-clean-code` ·
`fm-test-review` · `fm-secret-audit`

각 스킬의 입출력·구동 에이전트·트래커 상태는 `docs/skill-reference.md` 참고.

## 문제 해결 / FAQ

- **게이트가 실패했다.** `/frontend-migration-plugin:fm-fix <page>` — 최신 실패 리포트에서
  모드(verify/e2e/parity) 자동 감지, 최소 수정 후 게이트 재실행. 이후 해당 게이트 재실행으로 확인.
- **마이그레이션 후 레거시 페이지가 바뀌었다.** `/frontend-migration-plugin:fm-delta <page>` —
  변경분만 재마이그레이션하고 누적 수정 보존(대규모 시 전체 `fm-gen` 폴백). PostToolUse 훅이 경고.
- **`fm-gen`이 중단됐다.** 다시 실행 — `generation-state.json`으로 마지막 미완료 단계부터 resume.
- **"Another operation is in progress."** 페이지 `.lock` 점유 중. 30분 초과 시 stale로 자동 해제.
- **`fm-gen`이 공유 패키지 누락이라 한다.** 계획이 미추출 의존을 플래그한 것 — 먼저
  `/frontend-migration-plugin:fm-extract` 실행.
- **현황은?** `/frontend-migration-plugin:fm-progress`(read-only)가 앱별/페이지별 상태·게이트
  결과·다음 명령 제시.
- **시크릿/결제.** PG `merchantKey`·OAuth `client_secret` 읽기는 `shared-domain`에서 차단되어
  서버 이전(OMH-477); `fm-secret-audit`가 인벤토리화.

## 문서

- `docs/workflow.md` — 페이지 상태 머신, 게이트 체인, 토폴로지
- `docs/skill-reference.md` — 전체 스킬·에이전트 입출력·상태 효과
- `docs/build-context.md` — 빌드 경위·설계 결정·세션 간 컨텍스트
- `CLAUDE.md` — 컨벤션, 상태파일·Lock 규칙, 설계 원칙, 매핑/게이트 인덱스
- `templates/` — 매핑 카탈로그, 공유 패키지 스펙/규약, WebView 브리지, Hana SSO, Strangler Fig,
  TDD 규칙, migration-plan 스키마

영문: `README.md` · Tiếng Việt: `README.vi.md`
