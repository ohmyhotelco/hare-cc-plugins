# Backend Spring Boot Plugin

> **Ohmyhotel & Co** — TDD 기반 Spring Boot 백엔드 개발용 Claude Code 플러그인

## 소개

CQRS 아키텍처와 엄격한 TDD(테스트 주도 개발)를 적용하여 Spring Boot 백엔드의 전체 개발 파이프라인을 제공하는 Claude Code 플러그인입니다. CRUD 스캐폴딩부터 TDD 구현, 검증, 6차원 코드 리뷰, 자동 수정까지 파이프라인 상태 추적과 함께 전체 라이프사이클을 지원합니다.

주요 기능:
- **CQRS 스캐폴딩** — Command/Query 분리 구조의 완전한 CRUD(엔티티, 리포지토리, DTO, 컨트롤러, 마이그레이션)를 한 번에 생성
- **엄격한 TDD** — 작업 문서 추적과 시나리오별 구현을 통한 RED-GREEN 사이클 강제
- **검증 게이트** — 빌드 + Checkstyle + 테스트 구조화 검증 (읽기 전용 품질 게이트)
- **6차원 리뷰** — API 계약, JPA 패턴, 클린 코드, 로깅, 테스트 품질, 아키텍처 — TDD 기반 자동 수정 포함
- **파이프라인 추적** — 피처별 상태 머신 + 진행률 대시보드, 강등 경고, 변경 감지
- **상태 안전** — 잠금 메커니즘, 읽기-수정-쓰기 규칙, 서브에이전트 격리
- **독립 감사** — JPA, API, 클린 코드, 로깅, 테스트 품질 감사를 언제든 독립 실행 가능

## 아키텍처 개요

```
/backend-springboot-plugin:be-init → .claude/backend-springboot-plugin.json
        │
        ▼
/backend-springboot-plugin:be-crud <Entity> [field:Type ...]
        │
        ├── Flyway 마이그레이션 + 엔티티 + 리포지토리
        ├── Command + CommandExecutor
        ├── Query + QueryProcessor
        ├── View DTO + Controller + Exception
        └── 테스트 시나리오 작업 문서
        │
        ▼
/backend-springboot-plugin:be-code <feature>
        │
        └── implement 에이전트 (시나리오별):
            ├── 다음 - [ ] 시나리오 선택
            ├── 테스트 작성 (RED) → 실패 확인
            ├── 최소 코드 구현 (GREEN) → 통과 확인
            └── - [x] 표시 → 반복
        │
        ▼
/backend-springboot-plugin:be-verify <feature>
        │
        ├── 컴파일 검사
        ├── Checkstyle 검사 (활성화 시)
        ├── 테스트 검사
        └── 전체 빌드 검사
        │
        ▼
루프 — 리뷰 & 수정:
/backend-springboot-plugin:be-review <feature>
        │
        └── code-reviewer 에이전트 (6차원)
        │
        ▼ (이슈 발견 시)
/backend-springboot-plugin:be-fix <feature>
        │
        └── review-fixer 에이전트
            ├── TDD 수정 (동작 변경 — 테스트 먼저)
            └── 직접 수정 (기계적 변경 — 타겟 편집)
        │
        ▼
/backend-springboot-plugin:be-review <feature> (통과할 때까지 재리뷰)
        │
        ▼
/backend-springboot-plugin:be-commit

인터럽트 스킬 (어느 단계에서든 사용 가능):
  be-debug    — 체계적 디버깅 (4단계 가설-검증)
  be-progress — 파이프라인 상태 대시보드
  be-build    — 빌드 + 자동 수정 (독립 실행)

독립 감사 (파이프라인과 무관하게 사용 가능):
  be-jpa, be-api-review, be-clean-code, be-logging, be-test-review
```

## 기술 스택

| 범주 | 기술 |
|------|------|
| 언어 | Java 21+ |
| 프레임워크 | Spring Boot 4.x + Spring MVC (REST) + Spring Validation |
| 빌드 | Gradle (Kotlin DSL 또는 Groovy) 또는 Maven |
| 데이터베이스 | PostgreSQL (기본), MySQL, MariaDB, H2 |
| ORM | Spring Data JPA (Hibernate) |
| 마이그레이션 | Flyway (기본), Liquibase, 또는 none |
| 테스팅 | JUnit 5 + TestRestTemplate + AssertJ (Mockito 미사용) |
| 코드 품질 | Checkstyle (무관용: maxErrors=0, maxWarnings=0) |
| 유틸리티 | Lombok, UUID Creator (UUID v7) |

## 설치

```
# 1. 마켓플레이스 소스 등록
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. 플러그인 설치 (프로젝트 범위 — .claude/settings.json에 저장, 팀 공유)
/plugin install backend-springboot-plugin@ohmyhotelco --scope project
```

설치 확인:
```
/plugin
```

## 업데이트 & 관리

**마켓플레이스 업데이트**로 최신 플러그인 버전 가져오기:
```
/plugin marketplace update ohmyhotelco
```

**비활성화 / 활성화** (제거하지 않고):
```
/plugin disable backend-springboot-plugin@ohmyhotelco
/plugin enable backend-springboot-plugin@ohmyhotelco
```

**제거**:
```
/plugin uninstall backend-springboot-plugin@ohmyhotelco --scope project
```

**플러그인 관리 UI**: `/plugin`을 실행하여 탭 인터페이스(Discover, Installed, Marketplaces, Errors)를 열 수 있습니다.

## 빠른 시작

```
1. /backend-springboot-plugin:be-init                          # 플러그인 설정 (프로젝트 자동 감지)
2. /backend-springboot-plugin:be-crud Employee email:String displayName:String   # CQRS CRUD 스캐폴딩
3. /backend-springboot-plugin:be-code work/features/employee.md                  # TDD 구현
4. /backend-springboot-plugin:be-verify employee                                 # 검증 게이트
5. /backend-springboot-plugin:be-review employee                                 # 6차원 리뷰
6. /backend-springboot-plugin:be-commit                                          # 스마트 커밋
```

## 스킬 상세

### `/backend-springboot-plugin:be-init`

**구문**: `/backend-springboot-plugin:be-init`

**사용 시점**: 프로젝트 최초 설정 또는 설정 재구성 시.

**동작**:
1. 빌드 도구(Gradle Kotlin/Groovy, Maven), Java 버전, Spring Boot 버전 자동 감지
2. 베이스 패키지, 데이터베이스 타입, 마이그레이션 도구 자동 감지
3. Checkstyle 및 Lombok 설정 확인
4. `.claude/backend-springboot-plugin.json` 생성
5. 작업 문서 디렉토리 생성 (기본: `work/features/`)

---

### `/backend-springboot-plugin:be-crud`

**구문**: `/backend-springboot-plugin:be-crud <엔티티명> [필드:타입 ...]`

**사용 시점**: 새 도메인 엔티티와 CQRS 구조 전체를 생성할 때.

**동작**:
1. 다음 Flyway 마이그레이션 버전 자동 생성
2. BaseEntity 상속, 이중 키(sequence + UUID v7), 필드 컬럼으로 엔티티 생성
3. 리포지토리, Command/Executor, Query/Processor, View DTO 생성
4. Controller(record 기반 DI) + REST 엔드포인트 생성
5. 도메인 예외 클래스 생성
6. 초기 테스트 시나리오가 포함된 작업 문서 생성
7. 파이프라인 상태를 `scaffolded`로 설정

---

### `/backend-springboot-plugin:be-code`

**구문**: `/backend-springboot-plugin:be-code <피처명 또는 작업문서 경로>`

**사용 시점**: 스캐폴딩 후, 또는 `- [ ]` 시나리오가 준비된 작업 문서가 있을 때.

**동작**:
1. 피처명이 주어지면: 기존 코드 탐색, 테스트 시나리오 초안 작성, 승인 요청
2. 작업 문서 경로가 주어지면: 기존 `- [ ]` 시나리오 직접 읽기
3. 파이프라인 강등 확인 (상태가 역행하면 경고)
4. 진행 파일 잠금 획득
5. 각 시나리오에 대해 `implement` 에이전트 실행: RED (테스트 작성, 실패 확인) → GREEN (구현, 통과 확인)
6. 모든 시나리오 완료 후 전체 빌드 실행
7. 파이프라인 상태 업데이트 (`implemented` 또는 `implementing`)
8. 잠금 해제

---

### `/backend-springboot-plugin:be-verify`

**구문**: `/backend-springboot-plugin:be-verify [피처명]`

**사용 시점**: 구현 후 리뷰 전 품질 게이트로. 읽기 전용 — 아무것도 수정하지 않음.

**동작**:
1. 파이프라인 강등 확인 (리뷰 진행도가 손실되면 경고)
2. 작업 문서 변경 감지 (마지막 구현 이후 시나리오가 추가되었으면 경고)
3. 잠금 획득
4. 4가지 검사 순차 실행: 컴파일, Checkstyle, 테스트, 전체 빌드
5. 구조화된 검증 리포트 생성
6. 파이프라인 상태 업데이트 (`verified` 또는 `verify-failed`)
7. 잠금 해제

---

### `/backend-springboot-plugin:be-review`

**구문**: `/backend-springboot-plugin:be-review <피처명 또는 대상 경로>`

**사용 시점**: 검증 후, 또는 구현 직후 코드 품질 리뷰 시.

**동작**:
1. 대상 해석 (피처명 → 소스 디렉토리, 또는 직접 경로)
2. 작업 문서 변경 감지 (마지막 구현 이후 시나리오가 추가되었으면 경고)
3. 잠금 획득
4. `code-reviewer` 에이전트 실행, 6개 차원 평가:
   - API 계약 (HTTP 시맨틱, URL, 상태 코드)
   - JPA 패턴 (N+1, 트랜잭션, 인덱스)
   - 클린 코드 (DRY, KISS, YAGNI, 네이밍)
   - 로깅 (SLF4J, MDC, 보안)
   - 테스트 품질 (네이밍, 어서션, 커버리지)
   - 아키텍처 준수 (CQRS, 네이밍 규칙)
5. `review-report.json` 저장 (차원별 점수 + 보강된 이슈: severity, fixHint, refs)
6. 파이프라인 상태 업데이트 (`done` / `reviewed` / `review-failed`)
7. 잠금 해제

**판정 기준**:
- **PASS**: 모든 차원 >= 7, 심각 이슈 0
- **FAIL**: 어떤 차원이라도 < 7 또는 심각 이슈 존재

---

### `/backend-springboot-plugin:be-fix`

**구문**: `/backend-springboot-plugin:be-fix <피처명>`

**사용 시점**: `be-review`에서 이슈가 발견된 후.

**동작**:
1. `review-report.json` 읽기
2. 수정 라운드 카운터 확인 (3라운드 후 차단 — 계속할지 사용자 확인)
3. 잠금 획득
4. `review-fixer` 에이전트 실행, 각 이슈 분류:
   - **TDD 필요**: 동작 변경 — 실패 테스트 먼저 작성 후 수정
   - **직접 수정**: 기계적 변경 (네이밍, 어노테이션) — 타겟 편집
   - **건너뛰기**: 이미 해결된 이슈
   - **에스컬레이션**: 자동 수정 범위를 벗어난 아키텍처 변경 필요
5. 수정 후 전체 빌드 검증 실행
6. `fix-report.json` 생성
7. 파이프라인 상태 업데이트 및 잠금 해제

**리뷰-수정 루프**:
```
be-review → FAIL → be-fix → be-review → PASS → be-commit
              ^                 |
              └─────────────────┘ (여전히 실패 시)
```

---

### `/backend-springboot-plugin:be-build`

**구문**: `/backend-springboot-plugin:be-build`

**사용 시점**: 빌드 실패 시 자동 진단 및 수정이 필요할 때. 파이프라인과 독립.

**동작**:
1. `build-doctor` 에이전트 실행
2. 오류 분류: 컴파일, 테스트, Checkstyle, 의존성, 설정
3. 최대 3회 재시도로 타겟 수정 적용
4. 적용된 변경 사항 리포트

---

### `/backend-springboot-plugin:be-debug`

**구문**: `/backend-springboot-plugin:be-debug <오류설명 또는 피처명>`

**사용 시점**: 런타임 오류, 테스트 실패, 빌드 이슈 등 파이프라인 어느 시점에서든.

**동작**:
1. 문제 컨텍스트 수집 (오류 메시지, 스택 트레이스, 관련 소스 파일)
2. 잠금 획득 (피처 컨텍스트가 있는 경우)
3. `debugger` 에이전트 실행, 4단계 방법론:
   - **재현**: 오류 파싱, 재현 가능성 확인
   - **가설 수립**: 정확히 3개의 가설을 우선순위로 수립
   - **검증**: 가설별 수정 적용, 검증, 실패 시 원복
   - **확인**: 회귀 검사 + 전체 빌드
4. 3개 가설 모두 실패 시: 수동 개입 필요로 에스컬레이션
5. 파이프라인 상태 업데이트 (`resolved` 또는 `escalated`) 및 잠금 해제

---

### `/backend-springboot-plugin:be-commit`

**구문**: `/backend-springboot-plugin:be-commit`

**사용 시점**: 파이프라인이 `done` 또는 `reviewed` 상태에 도달한 후.

**동작**: 프로젝트 규칙에 따라 staged 변경사항으로 커밋 생성 (영문, 현재 시제, 50자 제목, 접두사 없음, 테스트 코드 언급 없음).

---

### `/backend-springboot-plugin:be-recall`

**구문**: `/backend-springboot-plugin:be-recall [섹션]`

**사용 시점**: 규칙 확인 또는 최근 작업의 위반 사항 검출 시.

**동작**: CLAUDE.md에서 섹션별 규칙 표시 (commit, tdd, build, coding, api, jpa) 및 최근 작업의 위반 사항 검출. 간단한 위반(예: 최종 줄바꿈 누락)은 자동 수정 가능.

---

### `/backend-springboot-plugin:be-progress`

**구문**: `/backend-springboot-plugin:be-progress [피처명]`

**사용 시점**: 현재 파이프라인 상태를 확인할 때 언제든.

**동작**:
- **피처명 없이**: 모든 피처의 요약 테이블 (파이프라인 상태, 시나리오 진행률, 검증 결과, 리뷰 점수, 수정 라운드)
- **피처명 포함**: 상세 보기 (파이프라인 히스토리, 완료/남은 시나리오, 작업 문서 변경 감지, 다음 단계 안내)

## 독립 감사

이 스킬들은 파이프라인과 독립적으로 실행됩니다. 타겟 감사가 필요할 때 언제든 사용하세요.

| 스킬 | 검사 항목 |
|------|----------|
| `be-api-review` | HTTP 메서드 시맨틱, URL 패턴 (kebab-case, 복수형), 상태 코드, 페이지네이션, 오류 응답 |
| `be-jpa` | N+1 쿼리, @Transactional 누락, 지연 로딩 위험, 무제한 쿼리, 인덱스 누락, 캐스케이드 |
| `be-clean-code` | DRY/KISS/YAGNI 위반, 갓 클래스, 깊은 중첩, 긴 메서드, 네이밍 이슈 |
| `be-logging` | System.out 사용, 민감 데이터 노출, 문자열 연결, 잘못된 로그 레벨, MDC 사용 |
| `be-test-review` | 네이밍 규칙, 어서션 품질, 안티패턴, 커버리지 분석, 느린 테스트 감지 |

## 전체 파이프라인 워크플로

### 1단계: 초기화

```
/backend-springboot-plugin:be-init
```

프로젝트 설정 자동 감지 (빌드 도구, Java 버전, Spring Boot 버전, 베이스 패키지, 데이터베이스, 마이그레이션 도구). `.claude/backend-springboot-plugin.json` 생성.

### 2단계: CRUD 스캐폴딩

```
/backend-springboot-plugin:be-crud Employee email:String displayName:String
```

CQRS 구조 전체 생성: Flyway 마이그레이션, 엔티티, 리포지토리, Command/Executor, Query/Processor, View, Controller, 예외 클래스, 초기 테스트 시나리오 작업 문서.

### 3단계: TDD 구현

```
/backend-springboot-plugin:be-code work/features/employee.md
```

`implement` 에이전트가 각 `- [ ]` 시나리오를 하나씩 처리:
1. **RED** — 테스트 작성, 테스트 클래스 실행, 실패 확인
2. **GREEN** — 최소 코드 작성, 전체 테스트 클래스 실행, 모두 통과 확인
3. **표시** — `- [ ]`를 `- [x]`로 업데이트, 다음 시나리오로 이동

### 4단계: 검증

```
/backend-springboot-plugin:be-verify employee
```

읽기 전용 게이트: 컴파일, Checkstyle, 테스트, 전체 빌드. 수정 없이 통과/실패 보고.

### 5단계: 리뷰

```
/backend-springboot-plugin:be-review employee
```

6차원 코드 리뷰 (차원별 점수). 이슈에는 심각도, 수정 힌트, API 엔드포인트/테스트 시나리오 참조(refs) 포함.

### 6단계: 수정 & 재리뷰

```
/backend-springboot-plugin:be-fix employee
/backend-springboot-plugin:be-review employee
```

리뷰 통과까지 반복. 동작 변경은 TDD, 기계적 변경은 직접 편집. 수정 라운드 추적 — 3라운드 후 경고.

### 7단계: 커밋

```
/backend-springboot-plugin:be-commit
```

## 에이전트

### Implement

**역할**: 작업 문서 기반 TDD 구현.

`- [ ]` 시나리오를 하나씩 엄격한 RED-GREEN 사이클로 처리. 시나리오별: 테스트 작성 → 실패 확인 → 최소 코드 구현 → 모든 테스트 통과 확인 → 완료 표시. 3회 연속 테스트 실패 시 에스컬레이션. Opus 모델 사용.

### Build Doctor

**역할**: 빌드 실패 진단 및 자동 수정.

빌드 오류 분류 (컴파일, 테스트, Checkstyle, 의존성, 설정) 및 타겟 수정 적용. 최대 3회 재시도. Sonnet 모델 사용.

### Code Reviewer

**역할**: 6차원 코드 리뷰.

읽기 전용 에이전트. API 계약, JPA 패턴, 클린 코드, 로깅, 테스트 품질, 아키텍처 준수를 평가. 심각도별로 정렬된 이슈와 함께 구조화된 리뷰 리포트 생성. 각 이슈에 차원, 심각도, 파일, 라인, 규칙, 메시지, 제안, refs(API 엔드포인트/시나리오 추적) 포함. Opus 모델 사용.

### Review Fixer

**역할**: TDD 기반 리뷰 이슈 수정.

이슈를 TDD 필요(동작 변경 — 테스트 먼저), 직접 수정(기계적 변경), 건너뛰기(이미 해결), 에스컬레이션(수동 개입 필요)으로 분류. TDD 수정당 최대 3회 시도 후 에스컬레이션. Opus 모델 사용.

### Debugger

**역할**: 4단계 방법론을 사용한 체계적 디버깅.

재현 → 가설 수립(정확히 3개) → 검증 → 확인. 오류를 type-error, test-failure, build-error, runtime-error, config-error, migration-error로 분류. 3개 가설 모두 실패 시 에스컬레이션. Opus 모델 사용.

## 설정

`.claude/backend-springboot-plugin.json` (`be-init`이 생성):

```json
{
  "javaVersion": "21",
  "springBootVersion": "4.0.2",
  "buildTool": "gradle-kotlin",
  "buildCommand": "./gradlew build",
  "testCommand": "./gradlew test",
  "basePackage": "com.example",
  "sourceDir": "src/main/java",
  "testDir": "src/test/java",
  "architecture": "cqrs",
  "database": "postgresql",
  "migration": "flyway",
  "checkstyle": true,
  "lombokEnabled": true,
  "workDocDir": "work/features",
  "workingLanguage": "ko"
}
```

| 필드 | 설명 | 기본값 |
|------|------|--------|
| `javaVersion` | Java 툴체인 버전 | `"21"` |
| `springBootVersion` | Spring Boot 버전 | `"4.0.2"` |
| `buildTool` | `"gradle-kotlin"` / `"gradle-groovy"` / `"maven"` | `"gradle-kotlin"` |
| `buildCommand` | 전체 빌드 명령 | `"./gradlew build"` |
| `testCommand` | 테스트 전용 명령 | `"./gradlew test"` |
| `basePackage` | 루트 Java 패키지 | `"com.example"` |
| `sourceDir` | 메인 소스 디렉토리 | `"src/main/java"` |
| `testDir` | 테스트 소스 디렉토리 | `"src/test/java"` |
| `architecture` | 아키텍처 패턴 — 패키지 구조와 템플릿 결정 | `"cqrs"` |
| `database` | `"postgresql"` / `"mysql"` / `"h2"` / `"mariadb"` | `"postgresql"` |
| `migration` | `"flyway"` / `"liquibase"` / `"none"` | `"flyway"` |
| `checkstyle` | Checkstyle 활성화 여부 | `true` |
| `lombokEnabled` | Lombok 사용 여부 | `true` |
| `workDocDir` | 작업 문서 디렉토리 | `"work/features"` |
| `workingLanguage` | 사용자 출력 언어 (`"en"` / `"ko"` / `"vi"`) | `"en"` |

## CQRS 패키지 구조

```
{basePackage}/
├── {App}Application.java
├── command/                    <- 요청 커맨드 DTO (record)
│   └── Create{Entity}.java
├── commandmodel/               <- 커맨드 실행 로직
│   └── Create{Entity}CommandExecutor.java
├── query/                      <- 요청 쿼리 DTO (record)
│   └── Get{Entities}.java
├── querymodel/                 <- 쿼리 처리 로직
│   └── Get{Entity}PageQueryProcessor.java
├── view/                       <- 응답 뷰 DTO (record)
│   └── {Entity}View.java
├── data/                       <- 엔티티 및 리포지토리
│   ├── {Entity}.java
│   ├── {Entity}Repository.java
│   └── BaseEntity.java
├── config/                     <- Spring 설정 빈
└── {domain}/                   <- 도메인별 비즈니스 로직
    ├── api/                    <- REST 컨트롤러
    │   └── {Entity}Controller.java
    └── {Description}Exception.java
```

## 파이프라인 상태

### 상태 파일

상태는 `{workDocDir}/.progress/{feature}.json`에서 추적됩니다.

| 파일 | 용도 |
|------|------|
| `{feature}.json` | 파이프라인 상태, 시나리오 수, 검증/리뷰/수정/디버그 히스토리 |
| `review-report.json` | 차원별 점수와 보강된 이슈가 포함된 리뷰 결과 |
| `fix-report.json` | 전략별 분류(TDD/직접/에스컬레이션)가 포함된 수정 결과 |
| `.lock` | 동시 실행 방지 (30분 후 자동 만료) |

### 상태 머신

```
scaffolded → implementing → implemented → verified → reviewed → done
                                  ↓            ↓          ↓
                            verify-failed  review-failed  fixing
                                  ↓            ↓          ↓
                              be-build     be-fix    be-review (재리뷰)
                                  ↓            ↓
                              verified     fixing → reviewed/done

언제든:
  be-debug → resolved | escalated
  resolved → (적절한 단계에서 파이프라인 재진입)
  escalated → (수동 개입 후 재진입)
```

### 상태 안전

- **잠금 메커니즘**: 진행 파일을 수정하는 스킬은 시작 전 `.lock`을 획득. 동일 피처의 동시 실행 방지. 30분 이상 된 잠금은 자동 제거.
- **읽기-수정-쓰기 규칙**: 쓰기 전 항상 최신 파일 내용 읽기. 변경 필드만 병합 — 기존 필드 모두 유지.
- **강등 경고**: 이전 파이프라인 단계의 스킬을 실행하면 진행도 초기화 전 경고 (예: status가 `verified`일 때 `be-code` 재실행 시 검증 결과 폐기 경고).
- **변경 감지**: `be-verify`와 `be-review`는 마지막 파이프라인 업데이트 이후 작업 문서가 수정되었으면 경고 (새 시나리오가 구현되지 않았을 수 있음).
- **서브에이전트 격리**: 코디네이터 스킬은 에이전트에 필요한 파라미터만 전달 — 대화 컨텍스트가 단계 간 누출되지 않음.

## 커뮤니케이션 언어

스킬은 설정에서 `workingLanguage`를 읽습니다. 모든 사용자 향 출력(요약, 질문, 피드백, 다음 단계 안내)은 작업 언어로 표시됩니다.

언어 매핑: `en` = English, `ko` = 한국어, `vi` = Tieng Viet.

## 팁 & 모범 사례

- **코딩 전 작업 문서 검토** — `be-crud`가 초기 시나리오를 생성하지만, `be-code` 실행 전에 시나리오를 추가, 제거, 재정렬할 수 있습니다.

- **빠른 게이트로 be-verify 사용** — 읽기 전용이고 빠릅니다. 구현 후 전체 리뷰에 시간을 투자하기 전에 컴파일/테스트 이슈를 잡을 수 있습니다.

- **수정 후 재리뷰 생략 금지** — `be-fix` 후에는 항상 `be-review`를 실행하세요. 리뷰-수정 사이클이 회귀를 방지합니다.

- **복잡한 이슈에는 be-debug 사용** — 테스트가 비직관적으로 실패하면 `be-debug`가 임기응변이 아닌 체계적 가설 검증을 제공합니다.

- **독립 감사는 자유롭게** — `be-jpa`, `be-api-review`, `be-clean-code`, `be-logging`, `be-test-review`는 파이프라인과 독립적으로 동작합니다. 타겟 품질 검사가 필요할 때 언제든 사용하세요.

- **재개는 안전** — `be-code`가 중단되면 같은 작업 문서로 다시 실행하면 됩니다. 완료된 시나리오(`- [x]`)는 보존되고 다음 `- [ ]`부터 재개됩니다.

- **잠금이 상태를 보호** — 동일 피처에 `be-code`와 `be-fix`를 동시에 실행하지 마세요. 잠금 메커니즘이 진행 파일 손상을 방지합니다.

## 로드맵

- [x] CQRS CRUD 스캐폴딩 생성
- [x] TDD 구현 파이프라인
- [x] 검증 게이트
- [x] 6차원 코드 리뷰 + 리뷰-수정 루프
- [x] 빌드 닥터 (자동 진단 및 수정)
- [x] 체계적 디버깅 (4단계 가설-검증)
- [x] 파이프라인 상태 추적 + 진행률 대시보드
- [x] 독립 감사 (JPA, API, 클린 코드, 로깅, 테스트 품질)
- [x] 상태 안전 (잠금, 강등, 변경 감지, 서브에이전트 격리)
- [ ] Planning-plugin 연동 (스펙 기반 스캐폴딩)
- [ ] 멀티 모듈 프로젝트 지원
- [ ] 이벤트 기반 아키텍처 템플릿 (Kafka, RabbitMQ)
- [ ] 보안 감사 스킬 (OWASP, Spring Security)

## 디렉토리 구조

```
agents/          에이전트 정의 (implement, build-doctor, code-reviewer,
                 review-fixer, debugger)
skills/          스킬 진입점 (be-init, be-crud, be-code, be-verify,
                 be-review, be-fix, be-commit, be-build, be-debug, be-recall,
                 be-progress, be-jpa, be-api-review, be-clean-code, be-logging,
                 be-test-review)
templates/       템플릿 파일 (tdd-rules, cqrs-module, entity-conventions,
                 test-scenario-template, work-document-template, checkstyle-config,
                 progress-schema)
docs/            문서
```

## 작성자

Justin Choi — Ohmyhotel & Co
