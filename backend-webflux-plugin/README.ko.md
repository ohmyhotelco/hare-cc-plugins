# Backend WebFlux Plugin

> **Ohmyhotel & Co** — TDD 기반 Spring WebFlux 백엔드 개발용 Claude Code 플러그인

## 번역 안내

전체 한국어 번역은 아직 완료되지 않았습니다. 이 문서는 플러그인이 제공하는 내용을
간단히 요약합니다 — 전체 최신 문서는 `README.md`(영문)와 `docs/decisions.md`(데이터
프로필, 웹 레이어, 마이그레이션, 데이터베이스, 드라이버, 커버리지 도구 결정 기록)를
참고하세요.

## 이 플러그인이 제공하는 것

CQRS 아키텍처와 엄격한 TDD를 사용하는 완전한 Spring WebFlux 백엔드 개발 파이프라인:

- 데이터 계층: **R2DBC와 MyBatis 동시 지원** (`dataProfile`: `r2dbc` | `mybatis` |
  `both`, 기본값 `both`)
- 웹 계층: **`RouterFunction`/`HandlerFunction` 기본, `@RestController`는 명시적
  예외**
- 마이그레이션: **수동 SQL 파일** (`src/main/resources/migration/`), Flyway/Liquibase
  미사용
- 데이터베이스 기본값: **MySQL 8.0.33**
- 테스트: **`WebTestClient`/`@DataR2dbcTest`/`StepVerifier`**, Mockito를 자유롭게 사용
- 커버리지: **JaCoco, 리포트 전용 게이트** (임계값 실패 없음)
- 벤더/외부 연동(해당 시): `templates/vendor-integration.md`에 따른 타임아웃,
  재시도, 서킷 브레이커

파이프라인 구조(`be-init` → `be-crud` → `be-code` → `be-verify` → `be-review` ↔
`be-fix` → `be-commit`), 상태 머신, 잠금 메커니즘에 대한 전체 설명은 `README.md`를
참고하세요.

전체 최신 문서는 `README.md`를 확인하세요.
