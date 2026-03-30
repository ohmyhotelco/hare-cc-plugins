# Backend Spring Boot Plugin

CQRS 아키텍처, 엄격한 TDD 방법론, Gradle 빌드 자동화, 파이프라인 상태 추적, 리뷰-수정 루프를 지원하는 Spring Boot 백엔드 개발용 Claude Code 플러그인입니다.

## 주요 기능

- **CQRS 스캐폴딩**: Command/Query 분리 구조의 완전한 CRUD를 한 번에 생성
- **엄격한 TDD**: 작업 문서 추적과 함께 RED-GREEN 사이클 강제
- **검증 게이트**: 빌드 + Checkstyle + 테스트 구조화 검증
- **리뷰-수정 루프**: 6차원 코드 리뷰 + TDD 기반 자동 수정 + 재리뷰 사이클
- **빌드 닥터**: 빌드 실패 자동 진단 및 수정 (최대 3회 재시도)
- **체계적 디버깅**: 4단계 가설-검증 방법론
- **파이프라인 추적**: 피처별 상태 머신 + 진행률 대시보드
- **스마트 커밋**: 프로젝트 규칙에 맞는 커밋 메시지 자동 생성

## 파이프라인

```
be-init → be-crud (스캐폴딩) → be-code (TDD) → be-verify → be-review ↔ be-fix → be-commit
                                     ↕                          ↕
                              implement 에이전트          code-reviewer 에이전트
                            (RED → GREEN 사이클)         (6차원 리뷰)

인터럽트 스킬 (어느 단계에서든 사용 가능):
  be-debug    — 체계적 디버깅 (4단계 가설-검증)
  be-progress — 파이프라인 상태 대시보드
  be-build    — 빌드 + 자동 수정 (독립 실행)

독립 감사:
  be-jpa, be-api-review, be-clean-code, be-logging, be-test-review
```

### 파이프라인 상태 머신

```
scaffolded → implementing → implemented → verified → reviewed → done
                                  ↓            ↓          ↓
                            verify-failed  review-failed  fixing
                                  ↓            ↓          ↓
                              be-build     be-fix    be-review (재리뷰)
```

## 설치

```bash
claude plugin add ./backend-springboot-plugin
```

프로젝트에서 초기화:

```
/backend-springboot-plugin:be-init
```

## 스킬

### 핵심 파이프라인

| 스킬 | 설명 |
|------|------|
| `be-init` | 플러그인 설정 초기화 (프로젝트 설정 자동 감지) |
| `be-crud <엔티티>` | CQRS CRUD 스캐폴딩 생성 |
| `be-code <피처>` | TDD 기반 기능 구현 |
| `be-verify [피처]` | 검증 게이트 (빌드 + Checkstyle + 테스트) |
| `be-review <피처>` | 6차원 통합 코드 리뷰 |
| `be-fix <피처>` | 리뷰 리포트 기반 TDD 수정 |
| `be-commit` | staged 변경사항에서 스마트 커밋 |

### 유틸리티

| 스킬 | 설명 |
|------|------|
| `be-build` | 빌드 + 자동 진단 + 자동 수정 (3회 재시도) |
| `be-debug <피처>` | 체계적 디버깅 (4단계 가설-검증) |
| `be-recall [섹션]` | 개발 규칙 확인 + 위반 검출 |
| `be-progress [피처]` | 파이프라인 상태 대시보드 |

### 독립 감사

| 스킬 | 설명 |
|------|------|
| `be-api-review` | REST API 계약 감사 (HTTP 시맨틱, URL 패턴) |
| `be-jpa` | JPA/Hibernate 패턴 감사 (N+1, 지연 로딩, 트랜잭션) |
| `be-clean-code` | DRY/KISS/YAGNI 코드 감사 |
| `be-logging` | 구조화 로깅 감사 (SLF4J, MDC, 보안) |
| `be-test-review` | 테스트 품질 감사 (명명, 커버리지, 타이밍) |

## 에이전트

| 에이전트 | 모델 | 설명 |
|---------|------|------|
| `implement` | opus | 작업 문서 기반 TDD 구현 |
| `build-doctor` | sonnet | 빌드 실패 진단 및 자동 수정 |
| `code-reviewer` | opus | 다차원 코드 리뷰 (6개 차원) |
| `review-fixer` | opus | 리뷰 리포트 기반 TDD 수정 |
| `debugger` | opus | 체계적 디버깅 (4단계 가설-검증) |

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

## 지원 기술 스택

- Java 21+ / Spring Boot 4.x
- Gradle (Kotlin DSL 또는 Groovy) 또는 Maven
- PostgreSQL, MySQL, MariaDB, H2
- Spring Data JPA / Flyway 또는 Liquibase
- JUnit 5 / Checkstyle / Lombok
