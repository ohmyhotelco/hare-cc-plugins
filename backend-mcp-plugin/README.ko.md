# Backend MCP Plugin

> **Ohmyhotel & Co** — Spring AI 기반 MCP(Model Context Protocol) 서버를 엄격한 TDD로 개발하기 위한 Claude Code 플러그인

[English](./README.md) | [Tiếng Việt](./README.vi.md) | [한국어](./README.ko.md)

## 개요

LLM 클라이언트가 호출하는 **MCP 도구**가 곧 제품인 Spring Boot 서비스를 위한 개발 파이프라인입니다.

- **도구 description이 곧 계약** — 모든 tools/list 응답마다 클라이언트로 전송되므로 간결한
  템플릿으로 작성하고, contract snapshot으로 고정하며, changelog와 함께 의도적으로만 변경
- **호출자는 모델** — 업스트림 텍스트는 신뢰할 수 없는 입력(sanitize, PII 마스킹), 결과는 행 수
  제한과 기계 판독 가능한 경고, 오류는 코드화
- **서버는 대리인** — 인바운드 OAuth2 + 도구별 RBAC, 업스트림에는 자체 범위 제한 자격 증명
  사용(토큰 패스스루 금지), ArchUnit으로 read-only 강제, 모든 호출 감사 로그
- **업스트림은 외부 시스템** — 타임아웃, 전송 계층 한정 재시도, rate limit, circuit breaker,
  호출자별 RBAC를 재적용하는 캐시

## 설치

```
/plugin marketplace add ohmyhotelco/hare-cc-plugins
/plugin install backend-mcp-plugin@ohmyhotelco --scope project
```

초기화 단계가 없습니다. 모든 스킬이 시작 시 `scripts/detect-project.sh`를 실행해 빌드(Gradle 전용),
Java/Boot/Spring AI 버전, MCP 전송 방식(webmvc/webflux/stdio), 패키지, 도구 등록 방식, 보안,
contract snapshot/changelog, checkstyle/JaCoCo 적용 여부를 매번 감지합니다(캐시 없음, 코드와 어긋나지
않음). Spring AI MCP server starter가 없으면 명확한 메시지와 함께 중단합니다.

선택적 정책 파일 `.claude/backend-mcp-plugin.json`은 기본값(`readOnly`, `workDocDir`,
`workingLanguage`)을 바꾸거나 잘못 감지된 값(예: `toolsPackage`)을 덮어쓸 때만 필요합니다.

## 파이프라인

```
mcp-plan → mcp-code → mcp-verify → mcp-review ↔ mcp-fix → mcp-commit
```

| 스킬 | 용도 |
|------|------|
| `mcp-plan` | Jira 태스크 / 태스크 설명 / 업스트림 API 문서 / 스펙 → 도구 `plan.json` |
| `mcp-code` | 도구 명세 + TDD 구현, 마지막에 통제된 contract snapshot 갱신 |
| `mcp-verify` | 게이트: 컴파일, 테스트, contract(snapshot + changelog), 빌드, 선택적 checkstyle/coverage; `--fix`는 빌드 자동 수정 루프를 먼저 실행 |
| `mcp-review` | 7개 차원 리뷰(도구 계약, 업스트림, 보안, 클린 코드, 로깅·감사, 테스트, 아키텍처) + 스펙 준수; `--dimension <key>`로 단일 차원 감사 |
| `mcp-fix` | 리뷰 보고서 기반 수정 — 동작은 TDD, 기계적 수정은 직접, 계약 변경은 snapshot + changelog |
| `mcp-commit` | 스테이징된 변경으로 커밋: 트리 검사, 시크릿 스캔, snapshot/changelog 쌍 검사 |
| `mcp-debug` | 전송·업스트림 문제를 포함한 4단계 디버깅 |
| `mcp-progress` | 파이프라인 상태 대시보드 |
| `mcp-recall` | 규칙 조회 및 위반 검사 |

에이전트, 설정, 상태 머신 등 전체 내용은 `README.md`와 `CLAUDE.md`를 참고하세요.
