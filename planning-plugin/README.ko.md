<!-- Synced with en version: 2026-02-11T12:00:00Z -->

[English version](README.md)

# Planning Plugin

> **Ohmyhotel & Co AI Planning Team** — 멀티 에이전트 기능 명세서 생성을 위한 Claude Code 플러그인

## 주요 기능

이 Claude Code 플러그인은 협업 AI 에이전트를 통해 기능 명세서 작성을 자동화합니다:

- **Analyst** — 구조화된 질문(8개 카테고리)을 통해 요구사항을 수집합니다
- **Planner** — UX 흐름과 비즈니스 로직을 검토합니다
- **Tester** — 엣지 케이스와 테스트 가능성을 평가합니다
- **Translator** — 지원 언어 간 번역을 생성합니다
- **Notion Syncer** — 최종화된 명세서를 Notion 페이지에 동기화합니다
- **DSL Generator** — 화면 정의를 구조화된 UI DSL JSON으로 변환합니다
- **Prototype Generator** — UI DSL에서 독립형 React 프로토타입을 생성합니다
- **Figma Designer** — React 프로토타입을 MCP를 통해 Figma 레이어로 변환합니다

모든 명세서는 설정된 작업 언어(Working Language)를 원본(Source of Truth)으로 작성되며, 나머지 지원 언어 번역은 자동으로 생성됩니다.

## 설치

이 플러그인은 private GitHub 저장소를 통해 배포됩니다. 설치 전 해당 저장소에 대한 git 접근 권한이 필요합니다.

**사전 요구사항**: `ohmyhotelco/hare-cc-plugins`에 대한 git 접근 권한 (SSH key 또는 `gh auth login`)

```
# 1. Register the private repo as a marketplace source
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. Install the plugin (project scope — saved to .claude/settings.json, shared with the team)
/plugin install planning-plugin@ohmyhotelco --scope project
```

설치 확인:
```
/plugin
```

> **참고**: 비대화형 환경(CI 등)에서 자동 업데이트가 필요한 경우, `GITHUB_TOKEN` 환경 변수를 설정하십시오.

## 빠른 시작

6단계로 첫 번째 명세서를 작성하실 수 있습니다:

### 1. 플러그인 설치

```
/plugin marketplace add ohmyhotelco/hare-cc-plugins
/plugin install planning-plugin@ohmyhotelco --scope project
```

### 2. 프로젝트 설정 초기화

```
/planning-plugin:init
```

`.claude/planning-plugin.json`에 작업 언어, 지원 언어, Notion URL(선택)을 설정합니다. `/planning-plugin:spec` 실행 전에 이 단계가 필요합니다 — spec 스킬이 이 파일에서 설정을 읽습니다.

### 3. 새 명세서 시작

```
/planning-plugin:spec "social login with Google and Apple"
```

### 4. Analyst의 질문에 답변

Analyst 에이전트는 먼저 프로젝트(package.json, 소스 코드, 기존 명세서)를 스캔하여 컨텍스트를 파악한 후, 8개 카테고리에 걸쳐 구체적인 질문을 합니다:

| 카테고리 | 질문 내용 |
|----------|----------|
| 목적(Purpose) | 해결하려는 핵심 문제, 지금 필요한 이유 |
| 대상 사용자(Target Users) | 사용자 역할, 권한 수준 |
| 사용자 흐름(User Flow) | 주요 사용 시나리오의 단계별 흐름 |
| 비즈니스 규칙(Business Rules) | 제약 조건, 유효성 검증 로직 |
| 데이터 및 상태(Data & State) | CRUD 작업, 상태 전이 |
| 시스템 연동(System Integration) | 기존 모듈과의 연결 방식 |
| 비기능 요구사항(Non-Functional) | 성능, 보안, 접근성 |
| 범위 및 우선순위(Scope & Priority) | MVP 범위, 후순위 항목 |

각 라운드가 끝나면 Analyst가 카테고리별 완성도를 점수로 평가합니다. 평균 점수가 7/10 이상에 도달하면 초안 작성 단계로 진행됩니다. 언제든지 "proceed"라고 입력하여 남은 질문을 건너뛸 수 있으며, 미응답 항목은 명세서에 TBD 마커로 표시됩니다.

### 5. 생성된 명세서 검토

초안이 작업 언어로 생성되고 나머지 언어로 번역이 완료되면, 두 명의 리뷰어가 순차적으로 검토합니다:

- **Planner** — 사용자 여정, 비즈니스 로직, 오류 UX, 연동, 범위의 5개 차원을 평가합니다
- **Tester** — 테스트 가능성, 엣지 케이스, 상태 전이, 오류 처리, 인수 기준(Acceptance Criteria)의 5개 차원을 평가합니다

점수, 중요/주요 이슈, 제안된 테스트 케이스가 포함된 통합 요약을 확인하실 수 있습니다.

### 6. 피드백 반영 및 최종화

각 이슈에 대해 **Accept** / **Reject** / **Modify** / **Defer** 중 하나를 선택합니다. 변경 후 번역은 자동으로 동기화됩니다. 두 리뷰어의 점수가 모두 8/10 이상이 되면 플러그인이 최종화를 제안합니다.

```
/planning-plugin:progress social-login
```

언제든지 이 명령어로 진행 상황을 확인하실 수 있습니다.

## 스킬 레퍼런스

### `/planning-plugin:init`

**구문**: `/planning-plugin:init`

**사용 시점**: 프로젝트에서 첫 번째 명세서를 생성하기 전에 플러그인 설정을 구성할 때 사용합니다.

**동작 과정**:
1. 프로젝트 디렉토리에 `.claude/planning-plugin.json`을 생성합니다
2. 작업 언어(`en`, `ko`, 또는 `vi`)를 선택하도록 안내합니다
3. 번역 대상 지원 언어를 설정하도록 안내합니다
4. 자동 동기화를 위한 Notion 상위 페이지 URL을 선택적으로 설정합니다

**예시**:
```
/planning-plugin:init
```

---

### `/planning-plugin:spec`

**구문**: `/planning-plugin:spec "feature description"`

**사용 시점**: 새로운 기능 명세서를 처음부터 작성할 때 사용합니다.

**동작 과정**:
1. `docs/specs/{feature}/` 하위에 디렉토리 구조를 생성합니다
2. Analyst 에이전트가 프로젝트를 스캔하고 구조화된 질문을 합니다
3. 템플릿을 기반으로 작업 언어 명세서가 5개 파일로 생성됩니다
4. 나머지 지원 언어 번역이 병렬로 생성됩니다
5. Planner와 Tester가 순차적으로 검토 및 점수를 매깁니다
6. 피드백을 반영하고, 번역이 동기화되며, 반복하거나 최종화합니다

**예시**:
```
/planning-plugin:spec "reservation cancellation policy with partial refunds"
```

해당 기능의 명세서 디렉토리가 이미 존재하는 경우, 플러그인이 이어서 진행할지 새로 시작할지 확인합니다.

---

### `/planning-plugin:review`

**구문**: `/planning-plugin:review feature-name`

**사용 시점**: 작업 언어 명세서를 수동으로 편집한 후, Planner와 Tester의 새로운 리뷰로 품질을 재확인할 때 사용합니다.

**동작 과정**:
1. `docs/specs/{feature}/{workingLanguage}/` 디렉토리에서 명세서를 찾습니다
2. 이미 최종화된 명세서인 경우 경고합니다 (리뷰 시 상태가 `reviewing`으로 변경됩니다)
3. Planner 리뷰 후 Tester 리뷰가 순차적으로 진행됩니다 (Tester는 Planner의 피드백을 참조합니다)
4. 이전 라운드 대비 점수 추이가 포함된 통합 피드백을 제시합니다
5. 이슈를 반영하면 번역이 자동으로 동기화됩니다

**예시**:
```
/planning-plugin:review social-login
```

---

### `/planning-plugin:translate`

**구문**: `/planning-plugin:translate feature-name [--file=<name>]`

**사용 시점**: 작업 언어 명세서를 직접 편집한 후 나머지 지원 언어 번역을 동기화할 때 사용합니다.

**동작 과정**:
1. 작업 언어 원본 명세서 디렉토리를 읽습니다
2. 각 대상 언어에 대해 Translator 에이전트를 병렬로 실행합니다
3. `--file=<name>`이 지정된 경우 해당 파일만 재번역합니다 (예: `--file=requirements`로 `requirements.md`만 번역)
4. 진행 파일의 동기화 타임스탬프를 업데이트합니다
5. Translator가 모호한 내용에 남긴 `<!-- NEEDS_REVIEW -->` 마커가 있으면 보고합니다

**예시**:
```
/planning-plugin:translate social-login                    # 전체 동기화 (모든 파일)
/planning-plugin:translate social-login --file=requirements  # requirements.md만 동기화
```

---

### `/planning-plugin:progress`

**구문**: `/planning-plugin:progress [feature-name]`

**사용 시점**: 하나 또는 모든 명세서의 진행 상황을 확인할 때 사용합니다.

**동작 과정**:

기능명을 지정한 경우 — 상세 상태를 표시합니다:
```
Feature: social-login
Status: reviewing
Current Round: 2

Review History:
┌───────┬─────────────────┬──────────────────┬──────────────────┐
│ Round │ Planner Score   │ Tester Score     │ Key Decisions    │
├───────┼─────────────────┼──────────────────┼──────────────────┤
│   1   │ 6/10            │ 5/10             │ Added error UX   │
│   2   │ 7/10            │ 6/10             │ Expanded tests   │
└───────┴─────────────────┴──────────────────┴──────────────────┘

Translation Status:
  Korean (ko):      Synced — Last synced: 2025-01-15T10:30:00Z
  Vietnamese (vi):  Synced — Last synced: 2025-01-15T10:30:00Z

Open Questions: 2
```

기능명을 지정하지 않은 경우 — 모든 명세서의 요약 테이블을 표시합니다:
```
Specifications Overview:
┌──────────────────┬────────────┬───────┬─────────┬─────────┬────────────┐
│ Feature          │ Status     │ Round │ Planner │ Tester  │ Translated │
├──────────────────┼────────────┼───────┼─────────┼─────────┼────────────┤
│ social-login     │ reviewing  │   2   │  7/10   │  6/10   │ ko✓ vi✓    │
│ user-profile     │ finalized  │   3   │  9/10   │  8/10   │ ko✓ vi✓    │
│ notifications    │ drafting   │   0   │   —     │   —     │ ko✗ vi✗    │
└──────────────────┴────────────┴───────┴─────────┴─────────┴────────────┘
```

---

### `/planning-plugin:migrate-language`

**구문**: `/planning-plugin:migrate-language feature-name --to=vi`

**사용 시점**: 프로젝트를 다른 언어로 작업하는 팀원에게 이관하거나, 기존 명세서의 작업 언어를 변경할 때 사용합니다.

**동작 과정**:
1. 대상 언어의 번역 파일이 이미 존재하는지 검증합니다
2. 진행 파일을 업데이트하여 새 작업 언어를 설정합니다
3. 새 source 파일에서 동기화 헤더를 제거합니다
4. 모든 번역을 동기화 필요(out of sync) 상태로 표시합니다
5. 다음 단계를 안내합니다 (새 source 편집, 준비 시 재번역)

**예시**:
```
/planning-plugin:migrate-language social-login --to=vi
```

---

### `/planning-plugin:sync-notion`

**구문**: `/planning-plugin:sync-notion feature-name [--lang=xx]`

**사용 시점**: 최종화된 명세서를 Notion에 수동으로 동기화하거나, 편집 후 재동기화할 때 사용합니다. 최종화 및 번역 후 자동 동기화가 실행되지만, 언제든지 수동으로 트리거할 수 있습니다.

**동작 과정**:
1. 지정된 기능 및 언어의 명세서 파일을 읽습니다 (기본값: 작업 언어)
2. 설정된 `notionParentPageUrl` 하위에 Notion 페이지를 생성하거나 업데이트합니다
3. 페이지 제목 형식: `[{feature}] {lang} - Functional Specification`
4. Notion 페이지 URL을 진행 파일의 `notion` 필드에 저장합니다

**예시**:
```
/planning-plugin:sync-notion social-login
/planning-plugin:sync-notion social-login --lang=ko
```

> **참고**: `.claude/planning-plugin.json`에 `notionParentPageUrl`이 설정되어 있어야 합니다.

---

### `/planning-plugin:design`

**구문**: `/planning-plugin:design feature-name [--stage=dsl|prototype|figma]`

**사용 시점**: 명세서 최종화 후 UI DSL, React 프로토타입, 그리고 선택적으로 Figma 디자인을 생성할 때 사용합니다.

**동작 과정** (전체 파이프라인):
1. **Stage 1 — DSL 생성**: DSL Generator 에이전트가 `screens.md`, `data-model.md`, `requirements.md`를 읽고, `docs/specs/{feature}/ui-dsl/`에 구조화된 UI DSL JSON 파일을 생성합니다 (화면 인덱스 + 내비게이션 맵이 포함된 `manifest.json`과 화면별 `screen-{id}.json`)
2. **Stage 2 — 프로토타입 생성**: Prototype Generator 에이전트가 UI DSL을 읽고, `src/prototypes/{feature}/`에 독립형 Vite + React + TypeScript + TailwindCSS + shadcn/ui 프로젝트를 생성합니다
3. **Stage 3 — Figma 생성** (선택): Figma Designer 에이전트가 React 프로토타입 코드를 읽고, `generate_figma_design` MCP 도구를 통해 Figma 레이어로 변환합니다

단계는 순차적으로 실행됩니다 (1→2→3). `--stage`를 사용하여 개별 단계를 독립적으로 실행할 수 있습니다.

**예시**:
```
/planning-plugin:design social-login                    # 전체 파이프라인 (단계 1→2→3)
/planning-plugin:design social-login --stage=dsl        # DSL 생성만
/planning-plugin:design social-login --stage=prototype  # 프로토타입 생성만
/planning-plugin:design social-login --stage=figma      # Figma 생성만
```

> **참고**: Stage 3 (Figma)은 선택 사항이며 Figma MCP 설정이 필요합니다.

## 전체 워크플로우 가이드

### 단계 1: 요구사항 수집

`/planning-plugin:spec`을 실행하면 **Analyst 에이전트**가 먼저 프로젝트를 자동으로 스캔합니다:

- `package.json`, `README.md`, `CLAUDE.md` 및 유사한 메타데이터를 읽습니다
- 디렉토리 구조 및 소스 코드 구성을 매핑합니다
- 기존 API, 데이터 모델 및 관련 기능을 식별합니다
- `docs/specs/`에서 이전에 작성된 명세서를 확인합니다

이후 컨텍스트 요약을 생성하고 8개 카테고리에 걸쳐 카테고리당 2~3개의 질문을 합니다. 질문은 코드베이스의 구체적인 발견 사항을 참조합니다 (예: "기존 `UserService`를 발견했습니다 — 새 기능이 이와 연동되어야 합니까?").

**완성도 점수** — 각 답변 라운드 이후:

| 점수 | 의미 |
|------|------|
| 0-3 | 치명적 공백 — 이 정보 없이는 명세서 작성이 불가합니다 |
| 4-6 | 부분적 — 명세서 작성은 가능하나 상당한 가정이 필요합니다 |
| 7-8 | 양호 — 견고한 명세서를 작성하기에 충분합니다 |
| 9-10 | 우수 — 포괄적이며 공백이 없습니다 |

**기준**: 8개 카테고리 전체의 평균이 7 이상이어야 진행됩니다. 미달 시 Analyst가 가장 취약한 카테고리를 대상으로 추가 질문을 합니다.

**이 단계를 위한 팁**:
- 상세하고 구체적인 답변을 제공하십시오 — 모호한 답변은 모호한 명세서를 만듭니다
- "모르겠습니다" 또는 "나중에 결정"이라고 답해도 됩니다 — 해당 항목은 TBD로 표시됩니다
- 언제든지 "proceed"라고 입력하여 남은 질문을 건너뛰고 초안 작성으로 이동할 수 있습니다
- Analyst는 한 번에 하나의 카테고리씩 또는 관련된 카테고리를 묶어서 질문하므로 부담이 되지 않습니다

### 단계 2: 명세서 초안 생성

플러그인이 답변 내용을 기반으로 5개 템플릿 파일을 채웁니다 (선택적 읽기를 위해 분리됨):

1. **개요(Overview)** — 목적, 대상 사용자, 성공 지표(KPI)
2. **사용자 스토리(User Stories)** — ID, 역할, 목표, 우선순위 (P0/P1/P2)
3. **기능 요구사항(Functional Requirements)** — 각 항목의 비즈니스 규칙(BR-xxx) 및 인수 기준(AC-xxx)
4. **화면 정의(Screen Definitions)** — 레이아웃, 컴포넌트, 화면별 사용자 액션
5. **데이터 모델(Data Model)** — 엔티티, 필드, 타입, 관계
6. **오류 처리(Error Handling)** — 오류 코드, 조건, 사용자 메시지, 해결 방법
7. **비기능 요구사항(Non-Functional Requirements)** — 성능, 보안, 접근성, 국제화(i18n)
8. **테스트 시나리오(Test Scenarios)** — Given/When/Then 형식
9. **미결 사항(Open Questions)** — 컨텍스트 및 상태가 포함된 미해결 항목
10. **리뷰 이력(Review History)** — 라운드별 점수 및 결정 사항

정보가 불충분한 섹션에는 TBD 마커가 표시됩니다. 초안은 `docs/specs/{feature}/{workingLanguage}/`에 5개 파일로 저장되며 상태는 `DRAFT`로 설정됩니다:
- `{feature}-spec.md` — 개요, 사용자 스토리, 스펙 파일 인덱스, 미결 사항, 리뷰 이력
- `requirements.md` — 기능 요구사항
- `screens.md` — 화면 정의
- `data-model.md` — 데이터 모델, 오류 처리
- `test-scenarios.md` — 비기능 요구사항, 테스트 시나리오

### 단계 3: 번역

Translator 에이전트가 병렬로 실행되어 나머지 지원 언어 버전을 생성합니다. 번역 규칙:

- **번역 대상**: 섹션 제목, 설명, 사용자 스토리, 비즈니스 규칙, 오류 메시지
- **영어 유지**: 기술 용어 (API, endpoint, schema, CRUD, JWT, OAuth, REST, GraphQL 등), 코드 블록, 필드명, ID (US-001, FR-001 등), 상태 값 (DRAFT, FINALIZED, TBD)
- **문체**: 한국어는 격식체(합쇼체/하십시오체) 사용; 베트남어는 격식 기술 문체 사용
- **모호성 처리**: 번역된 용어가 불명확할 경우, 괄호 안에 영어 원문을 병기합니다

각 번역 파일 상단에 동기화 타임스탬프 주석이 추가됩니다.

### 단계 4: 리뷰 사이클

리뷰는 순차적으로 진행됩니다 — Planner가 먼저 진행하고, Tester는 Planner의 피드백을 참조하여 중복 발견을 방지합니다.

**Planner**가 평가하는 5개 차원:
1. 사용자 여정 완성도(User Journey Completeness) — 모든 경로가 문서화되었는지, 진입점이 식별되었는지
2. 비즈니스 로직 명확성(Business Logic Clarity) — 규칙이 명시적인지, 엣지 케이스가 처리되었는지
3. 오류 및 엣지 케이스 UX(Error & Edge Case UX) — 사용자 메시지, 로딩/빈 상태, 확인 다이얼로그
4. 연동 일관성(Integration Consistency) — 기존 시스템 패턴과의 정합성
5. 범위 및 실현 가능성(Scope & Feasibility) — MVP가 명확히 구분되었는지, 의존성이 식별되었는지

**Tester**가 평가하는 5개 차원:
1. 요구사항의 테스트 가능성(Testability of Requirements) — 측정 가능한 인수 기준, 검증 가능한 테스트
2. 엣지 케이스 및 경계 조건(Edge Cases & Boundary Conditions) — 입력 제한, null 값, 동시 접근
3. 상태 전이(State Transitions) — 모든 전이가 문서화되었는지, 유효하지 않은 전이가 처리되었는지
4. 오류 처리 완성도(Error Handling Completeness) — 오류 코드 매핑, 재시도 전략 정의
5. 인수 기준 및 테스트 시나리오(Acceptance Criteria & Test Scenarios) — Given/When/Then 커버리지, 부정 케이스

두 에이전트 모두 각 차원을 1-10점으로 평가하며 이슈를 심각도별로 분류합니다:

| 심각도 | 의미 |
|--------|------|
| **Critical** | 명세서대로 구현 또는 테스트가 불가합니다. 개발을 차단합니다. |
| **Major** | 해결하지 않으면 재작업이나 버그로 이어질 수 있는 중요한 공백입니다. |
| **Minor** | 작은 개선 사항으로, 개발을 차단하지 않습니다. |
| **Suggestion** | 있으면 좋은 개선 사항으로, 후순위로 미룰 수 있습니다. |

Tester는 발견된 모든 Critical 및 Major 이슈에 대해 구체적인 테스트 케이스(Given/When/Then)를 제안합니다.

### 단계 5: 피드백 반영

리뷰어가 제기한 각 이슈에 대해 네 가지 액션 중 하나를 선택합니다:

| 액션 | 동작 |
|------|------|
| **Accept** | 제안이 작업 언어 명세서에 그대로 반영됩니다 |
| **Reject** | 사유를 기재하고 이슈를 기각합니다 |
| **Modify** | 제안을 수정하여 반영합니다 |
| **Defer** | 이슈를 미결 사항(Open Questions) 섹션으로 이동합니다 |

변경 사항이 반영된 후, Translator 에이전트가 나머지 언어 버전을 자동으로 동기화합니다 (부분 번역 — 변경된 섹션만 재번역됩니다).

### 단계 6: 수렴 및 최종화

플러그인은 각 리뷰 라운드 이후 다음 수렴 규칙을 적용합니다:

- **두 점수 모두 >= 8/10인 경우**: "두 리뷰어 모두 만족합니다. 최종화하시겠습니까?"
- **라운드마다 점수가 향상되는 경우**: "점수가 향상되고 있습니다. 한 라운드 더 진행하시겠습니까?"
- **3라운드 동안 개선이 없는 경우**: "3라운드 후 남아 있는 미결 사항은 다음과 같습니다. 현 상태로 최종화하시겠습니까?"

최종 결정은 항상 사용자에게 있습니다. 최종화 시:

1. 모든 언어 버전에서 명세서 상태가 `FINALIZED`로 변경됩니다
2. 진행 파일의 상태가 `finalized`로 업데이트됩니다
3. 요약이 제공됩니다: 총 라운드 수, 최종 점수, 주요 결정 사항, 남은 미결 사항
4. 다음 단계가 제안됩니다:
   - `/planning-plugin:design {feature}` — UI DSL, React 프로토타입, Figma 디자인 생성
   - `/planning-plugin:review {feature}` — 언제든지 재검토
   - 작업 언어 명세서를 직접 편집 후 `/planning-plugin:translate {feature}`로 동기화

## 에이전트

### Analyst

**역할**: 구조화된 대화를 통한 요구사항 수집

두 단계로 운영됩니다: (A) 자동 프로젝트 컨텍스트 분석 (기술 스택, API, 모델, 기존 명세서에 대한 코드베이스 스캔), 이후 (B) 8개 카테고리에 걸친 구조화된 질문과 완성도 점수 평가. Opus 모델을 사용합니다. 각 카테고리를 0-10점으로 평가하며, 전체 평균이 7 이상이어야 초안 작성 단계로 진행됩니다.

### Planner

**역할**: 명세서의 제품 및 UX 검토

5개 차원을 평가합니다: 사용자 여정 완성도, 비즈니스 로직 명확성, 오류/엣지 케이스 UX, 연동 일관성, 범위 실현 가능성. Opus 모델을 사용합니다. 이슈는 critical/major/minor/suggestion으로 분류되며, 모든 이슈에 구체적인 제안이 포함됩니다. 잘 작성된 섹션은 `approved_sections`에서 인정합니다.

### Tester

**역할**: 테스트 가능성 및 엣지 케이스 검토

5개 차원을 평가합니다: 요구사항의 테스트 가능성, 엣지 케이스 및 경계 조건, 상태 전이, 오류 처리 완성도, 인수 기준(Acceptance Criteria). Sonnet 모델을 사용합니다. Planner의 피드백을 항상 참조하여 중복을 방지합니다. 모든 Critical 및 Major 이슈에 대해 구체적인 테스트 케이스(Given/When/Then)를 제안합니다.

### Translator

**역할**: 지원 언어(en/ko/vi) 간 번역

markdown 구조, 기술 용어, 코드 블록, ID를 보존하면서 명세서를 번역합니다. Sonnet 모델을 사용합니다. 전체 번역(새 명세서)과 부분 번역(리뷰 변경 후 섹션 단위 업데이트)을 지원합니다. 동기화 타임스탬프 주석을 추가하고 모호한 번역에는 `<!-- NEEDS_REVIEW -->` 마커를 표시합니다.

### Notion Syncer

**역할**: 최종화된 명세서를 Notion 페이지에 동기화

설정된 상위 페이지 URL 하위에 Notion 페이지를 생성하거나 업데이트합니다. 명세서 markdown을 Notion 블록으로 변환하며, 구조와 서식을 보존합니다. 향후 업데이트를 위해 페이지 URL을 진행 파일에 저장합니다. Sonnet 모델을 사용합니다. 최종화 및 번역 후 자동으로 트리거되거나, `/planning-plugin:sync-notion`을 통해 수동으로 실행할 수 있습니다.

### DSL Generator

**역할**: 화면 정의를 구조화된 UI DSL JSON으로 변환

최종화된 명세서의 `screens.md`, `data-model.md`, `requirements.md`를 읽고, `docs/specs/{feature}/ui-dsl/`에 구조화된 JSON 파일을 생성합니다. 출력물에는 `manifest.json`(화면 인덱스 + 내비게이션 맵)과 화면별 `screen-{id}.json`이 포함됩니다. shadcn/ui 컴포넌트 어휘만을 사용합니다. Opus 모델을 사용합니다.

### Prototype Generator

**역할**: UI DSL에서 독립형 React 프로토타입 생성

UI DSL JSON을 읽고, `src/prototypes/{feature}/`에 완전한 Vite + React + TypeScript + TailwindCSS + shadcn/ui 프로젝트를 생성합니다. 목업 데이터, 페이지 라우팅, 참조된 모든 shadcn/ui 컴포넌트를 포함합니다. 프로토타입은 독립형으로, 메인 프로젝트에 대한 의존성이 없습니다. Opus 모델을 사용합니다.

### Figma Designer

**역할**: MCP를 통해 React 프로토타입을 Figma 레이어로 변환

React 프로토타입 코드를 읽고, `generate_figma_design` MCP 도구를 사용하여 컴포넌트, 레이아웃, 스타일을 Figma 레이어로 변환합니다. 이 단계는 선택 사항이며 Figma MCP 설정이 필요합니다. Sonnet 모델을 사용합니다.

## 설정

플러그인은 사용자 프로젝트 디렉토리의 `.claude/planning-plugin.json`을 사용하여 설정합니다 (`/planning-plugin:init`으로 생성):

```json
{
  "workingLanguage": "en",
  "supportedLanguages": ["en", "ko", "vi"],
  "notionParentPageUrl": ""
}
```

| 필드 | 설명 | 기본값 |
|------|------|--------|
| `workingLanguage` | 명세서 작성 및 리뷰에 사용할 언어 (`en`, `ko`, 또는 `vi`) | `"en"` |
| `supportedLanguages` | 번역을 유지할 모든 언어 | `["en", "ko", "vi"]` |
| `notionParentPageUrl` | 자동 동기화를 위한 Notion 상위 페이지 URL | `""` |

작업 언어를 변경하려면 새 명세서를 생성하기 전에 `.claude/planning-plugin.json`을 편집하십시오. 기존 명세서는 원래의 작업 언어를 유지합니다 (진행 파일에 저장됨).

## 출력 구조

```
docs/specs/{feature}/
├── {workingLanguage}/                     ← Source of truth (작업 언어)
│   ├── {feature}-spec.md                  ← 인덱스: 개요, 사용자 스토리, 미결 사항, 리뷰 이력
│   ├── requirements.md                    ← 기능 요구사항
│   ├── screens.md                         ← 화면 정의
│   ├── data-model.md                      ← 데이터 모델, 오류 처리
│   └── test-scenarios.md                  ← 비기능 요구사항, 테스트 시나리오
├── {target_lang_1}/                       ← 번역 (동일 파일 구조)
│   ├── {feature}-spec.md
│   ├── requirements.md
│   ├── screens.md
│   ├── data-model.md
│   └── test-scenarios.md
├── {target_lang_2}/                       ← 번역 (동일 파일 구조)
│   └── ...
├── ui-dsl/                                ← UI DSL JSON (디자인 파이프라인 출력)
│   ├── manifest.json                      ← 화면 인덱스 + 내비게이션 맵
│   └── screen-{id}.json                   ← 화면별 컴포넌트 정의
└── .progress/
    └── {feature}.json                     ← Workflow state

src/prototypes/{feature}/                  ← React 프로토타입 (독립형 Vite 프로젝트)
├── package.json
├── src/
│   ├── App.tsx
│   ├── pages/                             ← 화면당 하나의 페이지 컴포넌트
│   └── mocks/                             ← 프로토타입용 목업 데이터
└── ...
```

## 스펙 템플릿 섹션

1. 개요(Overview) — 목적, 대상 사용자, 성공 지표
2. 사용자 스토리(User Stories)
3. 기능 요구사항(Functional Requirements)
4. 화면 정의(Screen Definitions)
5. 데이터 모델(Data Model)
6. 오류 처리(Error Handling)
7. 비기능 요구사항(Non-Functional Requirements)
8. 테스트 시나리오(Test Scenarios)
9. 미결 사항(Open Questions)
10. 리뷰 이력(Review History)

## 팁 및 모범 사례

- **상세한 기능 설명을 제공하십시오** — 초기 `/planning-plugin:spec` 명령에 더 많은 컨텍스트를 제공할수록 Analyst의 질문이 더 정확해집니다. "Social login"도 괜찮지만, "social login with Google and Apple for both web and mobile apps, replacing the current email-only signup"이 훨씬 좋습니다.

- **TBD 항목을 영원히 방치하지 마십시오** — TBD 마커는 진행을 가능하게 하지만, 최종화 전에 반드시 돌아와서 해결하십시오. Planner와 Tester가 미해결 TBD를 이슈로 지적합니다.

- **수동 편집을 환영합니다** — 언제든지 작업 언어 명세서를 직접 편집하실 수 있습니다. 편집 후 `/planning-plugin:translate feature-name`으로 번역을 동기화하고, `/planning-plugin:review feature-name`으로 품질을 재확인하십시오.

- **타겟 번역을 위해 `--file`을 사용하십시오** — 하나의 파일만 변경한 경우, 전체 명세서를 재번역하는 대신 `/planning-plugin:translate feature-name --file=requirements`를 사용하십시오.

- **정기적으로 상태를 확인하십시오** — `/planning-plugin:progress` (인수 없이)를 사용하여 모든 명세서를 한눈에 확인하십시오. 특히 여러 기능을 동시에 작업할 때 유용합니다.

- **세션 재개** — 워크플로우 진행 중에 Claude Code를 종료하면, 플러그인이 재시작 시 진행 중인 명세서를 자동으로 감지하여 알려줍니다. `/planning-plugin:progress`로 중단 지점을 확인한 후 `/planning-plugin:spec`으로 재개하십시오.

- **완벽한 점수를 쫓지 마십시오** — 3라운드 후 점수가 정체되면, 플러그인이 미결 사항과 함께 최종화를 제안합니다. 이것이 올바른 선택인 경우가 많습니다 — 미결 사항이 문서화된 최종 명세서가 끝없이 리뷰되는 초안보다 유용합니다.

- **주요 변경 후 리뷰하십시오** — 최종화 이후에도 `/planning-plugin:review`로 언제든지 재검토할 수 있습니다. 이 경우 상태가 `reviewing`으로 변경되어 추가 반복이 가능합니다.

- **작업 언어를 변경하려면** — 두 가지 시나리오가 있습니다:
  - *새 명세서의 경우*: `.claude/planning-plugin.json`에서 `workingLanguage`를 원하는 언어로 설정하십시오 (예: `"vi"`). 이후 생성되는 모든 명세서가 해당 언어로 작성됩니다.
  - *기존 명세서의 경우*: `/planning-plugin:migrate-language feature-name --to=vi`를 실행하십시오. 대상 언어 번역을 새 source of truth로 전환하고, 나머지 번역을 동기화 필요 상태로 표시하며, 명세서의 상태(status)는 유지됩니다. 대상 언어의 번역 파일이 먼저 존재해야 합니다 — 필요한 경우 `/planning-plugin:translate`를 먼저 실행하십시오.

## 디렉토리 구조

```
agents/          Agent definitions (analyst, planner, tester, translator, notion-syncer, dsl-generator, prototype-generator, figma-designer)
skills/          Skill entry points (init, spec, review, translate, progress, design, migrate-language, sync-notion)
hooks/           Lifecycle hook configuration
scripts/         Hook handler scripts
templates/       Spec templates + UI DSL schema (spec-overview.md, requirements.md, screens.md, data-model.md, test-scenarios.md, ui-dsl-schema.json)
docs/specs/      Generated specifications (언어 디렉토리당 5개 파일 + ui-dsl/)
src/prototypes/  Generated React prototypes (기능별 독립형 Vite 프로젝트)
```

## 규칙

- 기술 용어 (API, endpoint, schema, CRUD)는 모든 번역에서 영어로 유지됩니다
- 모든 에이전트 리뷰는 작업 언어 명세서 디렉토리만을 대상으로 합니다
- 명세서는 언어 디렉토리당 5개 파일로 분리됩니다 — `{feature}-spec.md`이 인덱스 파일이며, 상세 파일(`requirements.md`, `screens.md`, `data-model.md`, `test-scenarios.md`)이 나머지를 담당합니다
- UI DSL과 프로토타입은 shadcn/ui 컴포넌트 어휘만을 사용합니다 (Card, Table, Button, Dialog, Alert, Badge, Form, Input, Select 등)
- 프로토타입은 메인 프로젝트에 대한 의존성이 없는 독립형 Vite 프로젝트입니다
- Figma 생성은 선택 사항이며 Figma MCP 설정이 필요합니다

## 작성자

Justin Choi — Ohmyhotel & Co AI Planning Team
