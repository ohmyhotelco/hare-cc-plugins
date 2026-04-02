<!-- Synced with en version: 2026-03-19T00:00:00Z -->

[English version](README.md)

# Frontend React Plugin

> **Ohmyhotel & Co** — TDD 기반 프론트엔드 React 개발을 위한 Claude Code 플러그인

## 주요 기능

이 Claude Code 플러그인은 엄격한 Test-Driven Development를 적용하여 기능 명세서로부터 프로덕션 수준의 React 코드를 생성합니다. 구현 계획 수립부터 코드 생성, 검증, 리뷰, 수정까지 TDD 원칙에 따른 완전한 파이프라인을 제공합니다.

주요 역량:
- **TDD 코드 생성** — 6단계 파이프라인 (foundation → API → store → component → page → integration)으로 각 단계마다 엄격한 Red-Green-Refactor를 수행합니다
- **명세서 기반 계획** — 기능 명세서(planning-plugin 출력)를 분석하여 구조화된 구현 계획을 생성합니다
- **독립 실행 모드** — planning-plugin 없이 대화형 요구사항 수집을 통해 계획을 생성합니다
- **자동 리뷰** — 2단계 코드 리뷰(명세서 준수 + 품질)로 12개 채점 차원을 평가합니다
- **TDD 수정** — 동작 변경이 필요한 리뷰 이슈에 대해 테스트 우선 원칙으로 수정합니다
- **상태 일관성** — 잠금 메커니즘, 단계별 타임스탬프, 파이프라인 전반의 변경 감지를 제공합니다

## 아키텍처 개요

```
/frontend-react-plugin:fe-init → .claude/frontend-react-plugin.json
        │
        ▼
/frontend-react-plugin:fe-plan "feature" [--standalone]
        │
        ├── spec mode: reads planning-plugin output
        │   └── implementation-planner agent → plan.json
        │
        ├── standalone mode: interactive requirements gathering
        │   └── generates minimal spec stub → implementation-planner agent → plan.json
        │
        ├── incremental mode: detects spec changes after implementation
        │   └── implementation-planner agent → delta-plan.json (affected files only)
        │
        ▼
/frontend-react-plugin:fe-gen "feature"
        │
        ├── Phase 1: Foundation     — types + mocks (foundation-generator)
        ├── Phase 2: API TDD        — RED: tests → GREEN: services (tdd-cycle-runner)
        ├── Phase 3: Store TDD      — RED: tests → GREEN: stores (tdd-cycle-runner)
        ├── Phase 4: Component TDD  — RED: tests → GREEN: components (tdd-cycle-runner)
        ├── Phase 5: Page TDD       — RED: tests → GREEN: pages (tdd-cycle-runner)
        └── Phase 6: Integration    — routes + i18n + MSW setup (integration-generator)
        │
        ▼
/frontend-react-plugin:fe-verify "feature" (optional)
        │
        ▼
Loop 1 — Code Quality:
/frontend-react-plugin:fe-review "feature"
        │
        ├── Stage 1: spec-reviewer → spec compliance
        └── Stage 2: quality-reviewer → code quality
        │
        ▼ (if issues found)
/frontend-react-plugin:fe-fix "feature"
        │
        └── review-fixer agent → TDD fixes + direct fixes
        │
        ▼
/frontend-react-plugin:fe-review "feature" (re-review until pass)
        │
        ▼ (quality pass)
Loop 2 — E2E:
/frontend-react-plugin:fe-e2e "feature"
        │
        └── e2e-test-runner agent → agent-browser drives browser scenarios
        │
        ▼ (if failures)
/frontend-react-plugin:fe-fix "feature" (auto-detects E2E mode)
        │
        ▼
/frontend-react-plugin:fe-e2e "feature" (re-run until pass)
```

## 기술 스택

| Category | Technology |
|----------|-----------|
| Runtime | Node.js 22.x LTS (>= 22.12) |
| Package Manager | pnpm |
| Framework | React 19 + TypeScript (strict) |
| Build | Vite |
| Routing | React Router v7 (declarative or data mode) |
| UI | Tailwind CSS + shadcn/ui + Lucide |
| State | Zustand |
| HTTP | Axios (JWT, 401/403 interceptors) |
| Mock | MSW v2 (dev & test — network-level intercept) |
| i18n | i18next + react-i18next (ko/en/ja/vi) |
| Testing | Vitest + @testing-library/react + agent-browser (E2E) |

## 설치

이 플러그인은 GitHub 저장소를 통해 배포됩니다.

```
# 1. Register the repo as a marketplace source
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. Install the plugin (project scope — saved to .claude/settings.json, shared with the team)
/plugin install frontend-react-plugin@ohmyhotelco --scope project
```

설치 확인:
```
/plugin
```

## 업데이트 및 관리

**마켓플레이스 업데이트**로 최신 플러그인 버전을 가져옵니다:
```
/plugin marketplace update ohmyhotelco
```

플러그인을 제거하지 않고 **비활성화 / 활성화**:
```
/plugin disable frontend-react-plugin@ohmyhotelco
/plugin enable frontend-react-plugin@ohmyhotelco
```

**제거**:
```
/plugin uninstall frontend-react-plugin@ohmyhotelco --scope project
```

**플러그인 관리 UI**: `/plugin`을 실행하여 탭 인터페이스(Discover, Installed, Marketplaces, Errors)를 열 수 있습니다.

## 빠른 시작

### Option A — planning-plugin과 함께 사용 (권장)

5단계로 코드를 생성하실 수 있습니다:

```
1. /frontend-react-plugin:fe-init                     # configure plugin
2. /planning-plugin:init                               # configure planning
3. /planning-plugin:spec "feature description"         # generate spec
4. /frontend-react-plugin:fe-plan {feature}            # create implementation plan
5. /frontend-react-plugin:fe-gen {feature}             # generate code (TDD)
```

### Option B — 독립 실행 (planning-plugin 없이)

기능 명세서 없이 코드를 생성합니다:

```
1. /frontend-react-plugin:fe-init                      # configure plugin
2. /frontend-react-plugin:fe-plan {feature} --standalone   # interactive requirements → plan
3. /frontend-react-plugin:fe-gen {feature}             # generate code (TDD)
```

독립 실행 모드는 대화형으로 요구사항(설명, 엔티티, 화면)을 수집하여 최소 명세서 스텁과 plan.json을 생성합니다. 제한 사항: 오류 코드, 유효성 검증 규칙, 테스트 시나리오 참조(TS-nnn), UI DSL이 포함되지 않습니다.

## 스킬 레퍼런스

### `/frontend-react-plugin:fe-init`

**구문**: `/frontend-react-plugin:fe-init`

**사용 시점**: 프로젝트에서 처음 설정하거나 설정을 재구성할 때 사용합니다.

**동작 과정**:
1. React Router 모드(declarative 또는 data)를 선택하도록 안내합니다
2. Mock-first 개발(MSW v2, 기본값: 활성화)을 선택하도록 안내합니다
3. 기본 소스 디렉토리(기본값: `app/src`)를 선택하도록 안내합니다
4. ESLint 템플릿 사용 여부(ESLint 설정이 없을 때 `eslint.config.js` 자동 생성, 기본값: 활성화)를 선택하도록 안내합니다
5. `.claude/frontend-react-plugin.json`을 생성합니다
6. 6개의 외부 스킬(React Router, Vitest, React Best Practices, Composition Patterns, Web Design Guidelines, Agent Browser)을 설치합니다
7. 다음 단계 옵션(planning-plugin 유무에 따른)을 표시합니다

---

### `/frontend-react-plugin:fe-plan`

**구문**: `/frontend-react-plugin:fe-plan <feature-name> [--standalone]`

**사용 시점**: 기능 명세서 작성 후, 또는 명세서가 없을 때 독립 실행 모드로 사용합니다.

**동작 과정**:
1. **Spec 모드** (기본): planning-plugin의 명세서와 UI DSL을 읽고, 공유 레이아웃을 감지하며, 기존 프로젝트 패턴을 분석합니다
2. **독립 실행 모드** (`--standalone`): 대화형으로 요구사항(설명, 엔티티, 화면, 언어)을 수집하고, 최소 명세서 스텁을 생성합니다
3. **증분 모드** (자동 감지): 기존 plan.json과 생성된 코드가 있으면 명세서 변경을 감지하여 전체 재생성 대신 delta plan을 생성합니다
4. **자동 감지**: 명세서가 없고 `--standalone`이 지정되지 않은 경우, 독립 실행 모드와 명세서 작성 중 선택을 안내합니다
5. Implementation Planner 에이전트를 실행하여 `plan.json` (또는 증분 모드에서는 `delta-plan.json`)을 생성합니다
6. 계획 요약(파일, TDD 단계, shadcn/ui 의존성)을 표시합니다
7. 진행 파일을 `planned` 상태로 업데이트합니다 (증분 모드에서는 기존 상태 유지)

플래너 에이전트가 분석하는 항목:
- 기존 프로젝트 패턴 (디렉토리 구조, 경로 별칭, 라우트 파일, i18n 설정, 스토어, API 서비스, MSW 설정, 테스트 인프라)
- 명세서 엔티티 → 타입, API 서비스, 스토어
- 명세서 화면 → 컴포넌트, 페이지, 라우트, i18n 키
- 명세서 테스트 시나리오 → TS-nnn 추적이 가능한 테스트 파일 계획
- shadcn/ui 누락 분석 → 설치 명령어

---

### `/frontend-react-plugin:fe-gen`

**구문**: `/frontend-react-plugin:fe-gen <feature-name>`

**사용 시점**: `fe-plan`이 plan.json을 생성한 후에 사용합니다.

**동작 과정**:
1. 계획을 검증하고 기존 생성 상태를 확인합니다 (재개 지원)
2. 동일 기능에 대한 동시 작업을 방지하기 위해 잠금을 획득합니다
3. 6개 TDD 단계를 순차적으로 실행하며, 각 단계는 별도의 에이전트 세션에서 수행됩니다:

| Phase | Agent | 수행 내용 |
|-------|-------|----------|
| Foundation | foundation-generator | 타입, 목 팩토리/픽스처/핸들러, 공유 레이아웃 |
| API TDD | tdd-cycle-runner | RED: API 테스트 → GREEN: API 서비스 |
| Store TDD | tdd-cycle-runner | RED: 스토어 테스트 → GREEN: Zustand 스토어 |
| Component TDD | tdd-cycle-runner | RED: 컴포넌트 테스트 → GREEN: 컴포넌트 |
| Page TDD | tdd-cycle-runner | RED: 페이지 테스트 → GREEN: 페이지 (4-state) |
| Integration | integration-generator | 라우트, i18n, MSW 전역 설정, barrel exports |

4. 각 TDD 단계는 정확한 재개 지원을 위해 `completedAt` 타임스탬프를 기록합니다
5. 테스트 통과율과 파일 목록을 포함한 종합 결과를 표시합니다
6. 잠금을 해제하고 진행 상태를 업데이트합니다

**델타 모드**: `delta-plan.json`이 존재하면 (증분 모드의 `fe-plan`이 생성), `fe-gen`은 영향 받는 단계와 파일만 실행합니다. 변경 없는 단계는 건너뜁니다. 수정 작업은 delta-modifier 에이전트가, 신규 파일 생성은 tdd-cycle-runner가 범위를 제한하여 처리합니다.

**재개 지원**: 생성이 중단된 경우, `fe-gen`을 다시 실행하면 기존 상태를 감지하고 마지막 미완료 단계부터 재개를 제안합니다. 단계 수준의 최신성 검사 — `plan.json`이 특정 단계 완료 후에 수정된 경우, 해당 단계부터 다시 실행할 수 있습니다.

**실패 시**: 각 단계에서 재시도, 건너뛰기, 중단 옵션을 제공합니다. 건너뛰거나 실패한 단계가 있으면 `gen-failed` 상태가 됩니다 (불완전한 코드가 리뷰 파이프라인에 진입하는 것을 방지합니다).

---

### `/frontend-react-plugin:fe-verify`

**구문**: `/frontend-react-plugin:fe-verify <feature-name>`

**사용 시점**: 코드 생성 후 정확성을 검증할 때 사용합니다. 선택 사항이며 `fe-review`로 직접 이동할 수 있습니다.

**동작 과정**:
1. TypeScript 컴파일러(`tsc`)를 실행합니다
2. ESLint를 실행합니다 (설정된 경우)
3. Vite 빌드를 실행합니다
4. Vitest를 실행합니다
5. 각 게이트의 통과/실패를 보고합니다

---

### `/frontend-react-plugin:fe-review`

**구문**: `/frontend-react-plugin:fe-review <feature-name>`

**사용 시점**: 코드 생성 후 (또는 이슈 수정 후) 코드 품질을 리뷰할 때 사용합니다.

**동작 과정**:
1. 동시 작업을 방지하기 위해 잠금을 획득합니다
2. 명세서 변경 감지 (생성 이후 명세서가 수정된 경우 경고합니다)
3. **Stage 1 — Spec Review**: Spec Reviewer 에이전트가 요구사항 커버리지, UI 충실도, i18n 완성도, 접근성, 라우트 커버리지(5개 차원, 1-10점)를 검사합니다
4. **Stage 2 — Quality Review** (spec review 통과 시에만): Quality Reviewer 에이전트가 단일 책임, 일관된 패턴, 하드코딩된 문자열 없음, 오류 처리, TypeScript 엄격성, 컨벤션 준수, 아키텍처(7개 차원, 1-10점)를 검사합니다
5. 완전한 이슈 상세(refs, fixHints, missingArtifact가 보강됨)가 포함된 리뷰 보고서를 저장합니다
6. 잠금을 해제하고 진행 상태를 업데이트합니다

**상태 결과**:
- 양쪽 모두 깨끗하게 통과 → `done`
- 경고와 함께 통과 → `reviewed`
- 어느 쪽이든 실패 → `review-failed`

---

### `/frontend-react-plugin:fe-fix`

**구문**: `/frontend-react-plugin:fe-fix <feature-name>`

**사용 시점**: `fe-review`에서 이슈가 발견된 후에 사용합니다.

**동작 과정**:
1. 사전 조건을 검증합니다 (계획, 리뷰 보고서, 상태)
2. 마지막 리뷰 이후 소스 코드 변경을 감지합니다 (이미 해결되었을 수 있는 이슈에 대해 경고합니다)
3. 동시 작업을 방지하기 위해 잠금을 획득합니다
4. 이슈를 수정 전략별로 분류합니다:
   - **TDD-required**: 동작 변경 — 테스트를 먼저 작성한 후 수정합니다
   - **Direct-fix**: 기계적 변경(오타, 누락된 import) — 직접 수정합니다
   - **Regen-required**: 전체 파일 누락 — `fe-gen` 재실행이 필요한 단계로 표시합니다
5. Review Fixer 에이전트를 실행합니다
6. 테스트 수와 파일 변경 사항을 포함한 수정 보고서를 표시합니다
7. 재리뷰를 안내하고 잠금을 해제합니다

**수정 라운드**: 3라운드 후에도 이슈가 남아 있으면 경고합니다. 계획 수정 또는 디버깅을 제안합니다.

---

### `/frontend-react-plugin:fe-e2e`

**구문**: `/frontend-react-plugin:fe-e2e <feature-name>`

**사용 시점**: `fe-review` 통과 후 (Loop 2 진입점). 엔드투엔드 브라우저 테스트를 실행합니다.

**동작 과정**:
1. 사전 조건을 검증합니다 (계획, 생성된 코드, plan.json의 E2E 시나리오, agent-browser CLI)
2. E2E 시나리오 URL을 정의된 라우트와 대조 검증합니다
3. `VITE_ENABLE_MOCKS=true`로 Vite 개발 서버를 시작합니다
4. 런타임 헬스체크를 실행합니다 (앱이 오류 없이 로드되는지 확인)
5. e2e-test-runner 에이전트를 실행하여 브라우저 시나리오를 구동합니다
6. 개발 서버를 중지하고 E2E 결과를 표시합니다
7. 진행 파일을 E2E 상태로 업데이트합니다

**E2E 수정 루프**: 시나리오가 실패하면 `fe-fix`(E2E 모드 자동 감지)를 실행한 후 `fe-e2e`를 재실행합니다. 모든 시나리오가 통과할 때까지 반복합니다.

---

### `/frontend-react-plugin:fe-debug`

**구문**: `/frontend-react-plugin:fe-debug <feature-name>`

**사용 시점**: 파이프라인의 어느 시점에서든 런타임 버그나 복잡한 이슈에 사용합니다.

**동작 과정**:
1. 4단계 방법론으로 Debugger 에이전트를 실행합니다:
   - **Root Cause Investigation**: 오류 분석, 코드 경로 추적, 명세서/계획과 비교
   - **Pattern Analysis**: 동일 패턴의 버그 검색, 이슈 유형 분류 (generation-bug, plan-bug, spec-bug, environment)
   - **Hypothesis Testing**: 최대 3개의 가설을 수립하고 순차적으로 테스트 (3-strike 에스컬레이션)
   - **Implementation**: 최소한의 TDD 수정 적용 및 검증
2. 3개의 가설이 모두 실패하면 구조적 분석 및 권장 사항과 함께 에스컬레이션합니다

---

### `/frontend-react-plugin:fe-progress`

**구문**: `/frontend-react-plugin:fe-progress [feature-name]`

**사용 시점**: 언제든지 현재 파이프라인 상태를 확인하고 싶을 때 사용합니다.

**동작 과정**:
- **기능명 지정 시**: 상세 상태 표시 — 구현 상태, TDD 단계 완료율, 검증 결과, 리뷰 점수, 수정 라운드, E2E 결과, 델타 이력, 스펙 최신성 확인, 다음 단계 안내.
- **기능명 미지정 시**: 모든 기능의 요약 테이블 표시 — 상태, 생성 진행률, 리뷰 점수, 수정 라운드, E2E 결과, 델타 상태.

## 전체 파이프라인 워크플로우

### 단계 1: 초기화

```
/frontend-react-plugin:fe-init
```

라우터 모드(declarative/data), mock-first 토글, 기본 디렉토리를 설정합니다. 라우팅, 테스트, 성능, 컴포지션, 접근성을 위한 외부 스킬을 설치합니다.

### 단계 2: 구현 계획 생성

```
/frontend-react-plugin:fe-plan {feature}
```

Implementation Planner 에이전트가 기능 명세서를 읽고 (또는 독립 실행 모드에서 요구사항을 수집하고) 기존 프로젝트를 분석하여 `plan.json`을 생성합니다. 계획은 모든 명세서 요소를 구체적인 파일로 매핑합니다:

- 엔티티 → TypeScript 인터페이스 + DTO
- CRUD 작업 → Axios 서비스 모듈
- 화면 → Zustand 스토어 + 컴포넌트 + 페이지
- 내비게이션 → 라우트 설정
- 사용자 대면 텍스트 → i18n 네임스페이스 + 키
- 테스트 시나리오 → 소스 추적이 가능한 테스트 파일

### 단계 3: 코드 생성 (TDD)

```
/frontend-react-plugin:fe-gen {feature}
```

엄격한 TDD로 6단계를 수행합니다. 각 TDD 단계(2-5):
1. **RED** — 테스트를 먼저 작성하고, vitest를 실행하여 실패를 확인합니다
2. **GREEN** — 테스트를 통과시키기 위한 최소한의 구현을 작성합니다
3. **REFACTOR** — 테스트를 통과시킨 상태에서 정리합니다

외부 스킬은 단계별로 로드됩니다: TDD 단계에는 Vitest, 컴포넌트에는 Composition Patterns, 페이지에는 React Best Practices, 통합에는 React Router.

### 단계 4: 검증 (선택)

```
/frontend-react-plugin:fe-verify {feature}
```

### 단계 5: 리뷰

```
/frontend-react-plugin:fe-review {feature}
```

보강된 이슈 보고서(refs, fix hints, missing artifact 분류)를 포함한 2단계 리뷰를 수행합니다.

### 단계 6: 수정 및 재리뷰

```
/frontend-react-plugin:fe-fix {feature}
/frontend-react-plugin:fe-review {feature}
```

리뷰가 통과할 때까지 반복합니다. 수정 스킬은 동작 변경에 대해 TDD 원칙을 적용하고, 기계적 변경에 대해서는 직접 수정합니다.

### 단계 7: E2E 테스트

```
/frontend-react-plugin:fe-e2e {feature}
```

리뷰 통과 후, 엔드투엔드 브라우저 테스트를 실행합니다. e2e-test-runner 에이전트가 plan.json에 정의된 다중 페이지 사용자 플로우를 agent-browser로 구동하여 MSW 목 데이터에 대해 검증합니다.

### 단계 8: E2E 수정 및 재테스트

```
/frontend-react-plugin:fe-fix {feature}
/frontend-react-plugin:fe-e2e {feature}
```

E2E 시나리오가 실패하면 `fe-fix`가 E2E 모드를 자동 감지(보고서 타임스탬프 비교)하여 근본 원인을 수정합니다. 모든 E2E 시나리오가 통과할 때까지 반복합니다.

## 에이전트

### Implementation Planner

**역할**: 명세서 분석 → 구현 계획 (plan.json).

분석 전용 에이전트로 소스 코드를 생성하지 않습니다. 기능 명세서, UI DSL(사용 가능한 경우), 기존 프로젝트 패턴을 읽습니다. 타입, API 서비스, 스토어, 컴포넌트, 페이지, 라우트, i18n, 목, 테스트, TDD 빌드 순서를 포함하는 구조화된 계획을 생성합니다. 독립 실행 모드에서는 최소 명세서 스텁으로부터 타입을 추론하고 기본 CRUD 작업을 생성합니다. Opus 모델을 사용합니다.

### Foundation Generator

**역할**: 타입 + 목 인프라 생성.

TypeScript 인터페이스, DTO, 열거형, 목 팩토리, 픽스처, MSW 핸들러를 생성합니다. `tsc`로 검증합니다. TDD를 수행하지 않습니다 (인프라 전용).

### TDD Cycle Runner

**역할**: 단계별 엄격한 Red-Green TDD 사이클.

하나의 TDD 단계(api, store, component, page)를 수행합니다. 테스트를 먼저 작성하고 (RED — 반드시 실패를 확인), 최소한의 구현을 작성합니다 (GREEN — 반드시 통과를 확인). 각 테스트는 `// TS-nnn` 주석으로 명세서 테스트 시나리오를 참조합니다.

### Integration Generator

**역할**: 라우트 + i18n + MSW 전역 설정 + 전체 검증.

기능 라우트 정의, i18n 네임스페이스 등록, barrel exports, MSW 전역 집계를 생성합니다. 기존 중앙 라우트 파일과 i18n 설정에 자동으로 통합합니다. 전체 검증(tsc, vitest, build)을 실행합니다.

### Spec Reviewer

**역할**: 명세서 준수 리뷰 (5개 차원).

생성된 코드를 기능 명세서와 비교합니다. 요구사항 커버리지, UI 충실도, i18n 완성도, 접근성, 라우트 커버리지를 평가합니다. 이슈에 refs(FR-nnn), fix hints, missing artifact 분류를 보강합니다.

### Quality Reviewer

**역할**: 코드 품질 리뷰 (7개 차원).

단일 책임, 일관된 패턴, 하드코딩된 문자열 없음, 오류 처리, TypeScript 엄격성, 컨벤션 준수, 아키텍처를 평가합니다. Spec Review가 통과한 경우에만 실행됩니다.

### Review Fixer

**역할**: TDD 원칙에 따른 리뷰 이슈 수정.

각 이슈를 TDD-required(동작 변경 — 테스트 우선), direct-fix(기계적 변경), regen-required(파일 누락)로 분류합니다. 적절한 원칙에 따라 수정을 적용합니다.

### Delta Modifier

**역할**: 증분 명세서 변경 적용.

`delta-plan.json`을 기반으로 기존 구현 파일을 수정합니다. review-fixer 패턴을 따릅니다: 동작 변경(새 UI 동작, 새 폼 필드)은 TDD로, 구조적 변경(타입 추가, 팩토리 업데이트, 라우트 연결)은 직접 편집으로 처리합니다. foundation 생성, 코드 제거, 의존성 캐스케이드 수정을 처리합니다. 축적된 모든 리뷰/수정 작업을 보존합니다.

### E2E Test Runner

**역할**: agent-browser를 통한 E2E 테스트 실행.

plan.json에 정의된 다중 페이지 사용자 플로우를 헤드리스 Chromium으로 구동합니다. snapshot → interact → re-snapshot → assert → screenshot 사이클을 사용합니다. 픽스처 데이터에서 동적 라우트 파라미터를 해석합니다. 실패를 assertion, agent-error, timeout으로 분류합니다. Opus 모델을 사용합니다.

### Debugger

**역할**: 4단계 방법론을 사용한 체계적 디버깅.

Root Cause Investigation → Pattern Analysis → Hypothesis Testing (3-strike 제한) → Implementation. 이슈 유형별 분류 (generation-bug, plan-bug, spec-bug, environment). 3개의 가설이 모두 실패하면 구조적 분석과 함께 에스컬레이션합니다.

## 스킬

| Skill | Command | 설명 |
|-------|---------|------|
| Init | `/frontend-react-plugin:fe-init` | 플러그인 설정 및 외부 스킬 일괄 설치 |
| Plan | `/frontend-react-plugin:fe-plan` | 기능 명세서 분석 (또는 요구사항 수집) 및 구현 계획 생성 |
| Gen | `/frontend-react-plugin:fe-gen` | 구현 계획 기반 프로덕션 코드 생성 (TDD) |
| Verify | `/frontend-react-plugin:fe-verify` | 생성된 코드에 대한 TypeScript, 빌드, 테스트 검증 실행 |
| Review | `/frontend-react-plugin:fe-review` | 2단계 코드 리뷰 (명세서 준수 + 품질) |
| Fix | `/frontend-react-plugin:fe-fix` | TDD 원칙에 따른 리뷰 이슈 수정 |
| E2E | `/frontend-react-plugin:fe-e2e` | agent-browser를 통한 E2E 브라우저 테스트 실행 |
| Debug | `/frontend-react-plugin:fe-debug` | 가설 테스트 및 에스컬레이션을 포함한 체계적 디버깅 |
| Progress | `/frontend-react-plugin:fe-progress` | 전체 또는 특정 기능의 구현 파이프라인 상태 표시 |

### 외부 스킬 (init으로 설치)

| Skill | Source | 설명 |
|-------|--------|------|
| React Router v7 | `remix-run/agent-skills` | 라우팅 패턴 (설정된 모드에 따라) |
| Vitest | `antfu/skills` | 테스트 패턴 |
| React Best Practices | `vercel-labs/agent-skills` | React 성능 최적화 (57개 규칙) |
| Composition Patterns | `vercel-labs/agent-skills` | 컴포넌트 컴포지션 패턴 (10개 규칙) |
| Web Design Guidelines | `vercel-labs/agent-skills` | 접근성/디자인 감사 (100개 이상 규칙) |
| Agent Browser | `vercel-labs/agent-browser` | E2E 브라우저 자동화 CLI |

## 설정

플러그인은 프로젝트 디렉토리의 `.claude/frontend-react-plugin.json`을 사용합니다 (`/frontend-react-plugin:fe-init`으로 생성):

```json
{
  "routerMode": "declarative",
  "mockFirst": true,
  "baseDir": "app/src",
  "appDir": "app",
  "eslintTemplate": true
}
```

| Field | 설명 | Default |
|-------|------|---------|
| `routerMode` | React Router v7 모드 (`"declarative"` 또는 `"data"`) | `"declarative"` |
| `mockFirst` | MSW v2 mock-first 개발 활성화 | `true` |
| `baseDir` | 생성되는 소스 코드의 기본 디렉토리 | `"app/src"` |
| `appDir` | `vite.config.*`와 `package.json`이 있는 디렉토리 — 모든 빌드/테스트 명령이 여기서 실행됨 | `baseDir`에서 자동 도출 |
| `eslintTemplate` | ESLint 설정이 없을 때 번들 템플릿으로 `eslint.config.js` 자동 생성 | `true` |

## 생성되는 프로젝트 구조

```
{baseDir}/
├── layouts/                        ← Shared layouts (cross-feature, uses <Outlet />)
├── features/{feature}/
│   ├── types/                      ← TypeScript interfaces, DTOs, enums
│   ├── api/                        ← Axios service modules
│   ├── stores/                     ← Zustand stores
│   ├── components/                 ← Shared components (forms, tables)
│   ├── pages/                      ← Page components (4-state: loading/empty/error/success)
│   ├── mocks/                      ← MSW factories, fixtures, handlers
│   ├── __tests__/                  ← Test files (api, store, component, page)
│   ├── routes.tsx                  ← Feature route definitions (auto-integrated)
│   └── i18n.ts                     ← Feature i18n registration (auto-integrated)
├── components/ui/                  ← shadcn/ui components
├── mocks/                          ← Global MSW setup (server.ts, browser.ts, handlers.ts)
├── locales/                        ← i18n JSON files
└── ...
```

## 파이프라인 상태 파일

`docs/specs/{feature}/.implementation/frontend/` 하위의 상태 파일:

| File | 용도 |
|------|------|
| `plan.json` | 구현 계획 (fe-gen의 입력) |
| `generation-state.json` | 타임스탬프가 포함된 단계별 진행 추적 (재개 지원) |
| `review-report.json` | 보강된 이슈 상세가 포함된 전체 리뷰 결과 (fe-fix의 입력) |
| `fix-report.json` | 전략별 분류가 포함된 수정 결과 |
| `e2e-report.json` | 시나리오 상세가 포함된 E2E 테스트 결과 (fe-fix E2E 모드의 입력) |
| `debug-report.json` | 가설 로그가 포함된 디버그 세션 결과 |
| `delta-plan.json` | 증분 명세서 변경 계획 (델타 fe-gen의 입력, 실행 후 아카이브) |
| `.lock` | 동시 실행 방지 (30분 후 자동 만료) |

### 진행 상태 머신

```
planned → generated → verified → reviewed → done
             ↓    ↘       ↓         ↓    ↓
         gen-failed  ↘ verify-failed ↓  review-failed
                      ↘     ↓        ↓      ↓
                       → resolved  fixing → (re-review → reviewed/review-failed)
                         escalated    ↓  ↘ generated (regen-required → fe-gen)
                            ↓    escalated
                      (manual intervention)
```

### 상태 파일 안전성

- **잠금 메커니즘**: 상태 파일을 수정하는 스킬은 시작 전에 `.lock`을 획득합니다. 동일 기능에 대한 fe-gen/fe-verify/fe-review/fe-fix/fe-e2e의 동시 실행을 방지합니다. 만료된 잠금(30분 초과)은 자동으로 제거됩니다.
- **Read-Modify-Write 규칙**: 쓰기 전에 항상 최신 파일 내용을 읽습니다. 변경된 필드만 병합하며 기존 필드를 모두 보존합니다.
- **단계 타임스탬프**: 각 TDD 단계는 정확한 재개 및 계획 최신성 검사를 위해 `completedAt`을 기록합니다.
- **변경 감지**: fe-fix는 마지막 리뷰 이후 소스 파일이 변경된 경우 경고합니다. fe-review는 생성 이후 명세서가 변경된 경우 경고합니다.

## 훅(Hooks)

플러그인은 자동으로 실행되는 두 개의 라이프사이클 훅을 등록합니다:

### SessionStart — `session-init.sh`

Claude Code 세션이 시작될 때 실행됩니다. 다음 항목을 확인합니다:
- **설정**: `.claude/frontend-react-plugin.json`을 로드하고 현재 설정을 보고합니다
- **누락된 스킬**: 외부 스킬이 설치되지 않은 경우 경고합니다
- **파이프라인 상태**: 모든 기능을 스캔하고 현재 상태와 다음 단계 안내를 보고합니다:
  - `planned` → `fe-gen`을 제안합니다
  - `generated` → `fe-verify` 또는 `fe-review`를 제안합니다
  - `gen-failed` → `fe-gen` 재시도를 제안합니다
  - `verified` → `fe-review`를 제안합니다
  - `verify-failed` → `fe-debug`를 제안합니다
  - `reviewed` → `fe-fix` (경고 해결) 또는 `fe-e2e`를 제안합니다 (E2E 인식)
  - `review-failed` → `fe-fix` 후 `fe-review`를 제안합니다
  - `fixing` → `fe-review` 또는 `fe-e2e`를 제안합니다 (E2E 수정 모드 자동 감지, regen이 필요한 경우 `fe-gen`)
  - `resolved` → `fe-verify` 또는 `fe-review`를 제안합니다
  - `escalated` → 수동 개입이 필요하다고 경고합니다
  - `done` → E2E 미실행 시 `fe-e2e`를 제안하고, 그 외에는 완료를 보고합니다 (E2E 인식)

### PostToolUse — `validate-implementation.sh`

모든 `Write` 또는 `Edit` 도구 호출 이후 실행됩니다. `docs/specs/` 하위 파일에서만 활성화됩니다:
- **변경 감지**: 명세서 파일 또는 plan.json이 구현 상태가 planned 이후인 상태에서 편집된 경우, 생성된 코드가 동기화되지 않았을 수 있다고 경고합니다

## 커뮤니케이션 언어

기능 수준 스킬(fe-plan, fe-gen, fe-verify, fe-review, fe-fix, fe-e2e, fe-debug, fe-progress)은 진행 파일에서 `workingLanguage`를 읽습니다. 모든 사용자 대면 출력(요약, 질문, 피드백, 다음 단계 안내)은 작업 언어로 제공됩니다.

언어 이름 매핑: `en` = English, `ko` = Korean, `vi` = Vietnamese.

## 팁 및 모범 사례

- **생성 전에 계획을 검토하십시오** — `plan.json`은 편집 가능합니다. `fe-gen`을 실행하기 전에 파일 이름, 라우트 경로, 테스트 케이스를 조정하십시오.

- **빠른 반복을 위해 mock-first를 사용하십시오** — `mockFirst: true`로 설정한 경우, `VITE_ENABLE_MOCKS=true pnpm dev`를 실행하면 백엔드 없이 MSW 목으로 개발할 수 있습니다. 백엔드가 준비되면 환경 변수만 제거하면 됩니다.

- **수정 후 재리뷰를 건너뛰지 마십시오** — `fe-fix` 후에는 반드시 `fe-review`를 실행하십시오. 수정-리뷰 사이클이 회귀를 방지합니다.

- **런타임 이슈에는 fe-debug를 사용하십시오** — 테스트는 통과하지만 앱이 잘못 동작하는 경우, `fe-debug`가 임시 디버깅 대신 체계적인 가설 테스트를 제공합니다.

- **독립 실행 모드는 빠른 시작이지 지름길이 아닙니다** — 오류 코드, 유효성 검증 규칙, 테스트 시나리오 참조 없이 단순한 계획을 생성합니다. 프로덕션 기능에는 planning-plugin으로 제대로 된 명세서를 작성하십시오.

- **명세서 변경 시 증분 모드를 사용하세요** — 생성된 코드에서 명세서를 수정한 후, `fe-plan`을 다시 실행하면 기존 구현을 자동 감지하고 증분 모드를 제안합니다. 모든 리뷰/수정 작업을 보존하면서 영향 받는 파일만 재생성합니다. 대규모 델타(파일의 60% 초과)는 전체 재생성을 권장하는 경고를 표시합니다.

- **재개는 안전합니다** — 생성이 중단된 경우 `fe-gen`을 다시 실행하면 됩니다. 완료된 단계를 감지하고 재개합니다. 단계 수준 타임스탬프가 정확한 최신성 검사를 보장합니다.

- **잠금이 상태를 보호합니다** — 동일 기능에서 `fe-gen`과 `fe-fix`를 동시에 실행하지 마십시오. 잠금 메커니즘이 상태 파일 손상을 방지합니다.

## 로드맵

- [x] 기술 스택 명세
- [x] React Router 라우팅 스킬
- [x] 외부 스킬 통합 (vercel-labs/agent-skills)
- [x] 코드 생성 에이전트 (6단계 TDD)
- [x] 검증 스킬
- [x] 코드 리뷰 스킬 (명세서 준수 + 품질)
- [x] 수정 스킬 (TDD 원칙 적용)
- [x] 디버그 스킬 (체계적 디버깅)
- [x] 독립 실행 모드 (planning-plugin 없이 fe-plan)
- [x] 상태 일관성 (잠금, 타임스탬프, 변경 감지)
- [x] 훅 핸들러 (session-init, implementation validation)
- [x] E2E 테스트 스킬 (agent-browser 통합)
- [x] 델타 재생성 (증분 명세서 변경 처리)
- [ ] 컴포넌트 템플릿 라이브러리
- [ ] i18n 설정 스킬
- [ ] Auth/RBAC 패턴 템플릿

## 디렉토리 구조

```
agents/          Agent definitions (planner, foundation-generator, tdd-cycle-runner,
                 integration-generator, spec-reviewer, quality-reviewer, review-fixer,
                 delta-modifier, e2e-test-runner, debugger)
skills/          Skill entry points (fe-init, fe-plan, fe-gen, fe-verify, fe-review, fe-fix,
                 fe-e2e, fe-debug, fe-progress)
hooks/           Lifecycle hook configuration
scripts/         Hook handler scripts (session-init.sh, validate-implementation.sh)
templates/       Template files (feature-module.md, tdd-rules.md, eslint-config.md, e2e-testing.md)
docs/            Documentation
```

## 작성자

Justin Choi — Ohmyhotel & Co
