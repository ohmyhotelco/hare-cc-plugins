# cc-usage-plugin

개발자 머신(Windows·macOS·Linux)의 Claude Code 훅으로, 세션마다 **어느 저장소에서 · 어떤 명령과
스킬로 · 어느 모델과 effort로 · 토큰을 얼마나** 썼는지와 커밋·PR·편집 수를 기록한다. 프롬프트
본문·도구 인자·파일 내용은 수집하지 않는다. 모든 훅이 출력 없이 끝나는 `command` 훅이라 모델
토큰을 쓰지 않는다.

[English](./README.md)

## 요구 사항

- Claude Code 2.1.2xx 이상.
- `PATH`에 Node.js 22.23.4 / 24.22.1 / 26.12.1 이상(권장 24 LTS). 2026-10-21 Node.js 보안 릴리스
  이전 버전은 먼저 올린다. 18·20·25는 지원이 끝나 패치가 없다. 확인: `node --version`.
- Windows에 Git Bash는 필요 없다. 모든 훅이 exec form(`node` + 인자)이라 셸을 거치지 않는다.

## 설치

```
/plugin marketplace add ohmyhotelco/hare-cc-plugins
/plugin install cc-usage-plugin@ohmyhotelco --scope user
```

프로젝트 하나가 아니라 머신의 모든 세션을 기록하므로 user 범위로 설치한다. 설치할 때 아래 값을
묻는다. `endpoint`를 비우면 로컬 원장만 쌓인다.

| 설정 | 뜻 |
|---|---|
| `developer` | 사람마다 고유한 본인 식별자. 모든 레코드와 업로드의 `developer` 값에 쓰인다. 영문 소문자·숫자·`.`·`_`·`-`만 남기고 나머지는 `-`로 바꾸며, 남는 글자가 없으면 `u-<해시>`가 된다. 비우면 OS 로그인 이름 |
| `team` | 모든 레코드에 붙는 팀 라벨 |
| `endpoint` | 수신 URL(HTTPS, NDJSON POST를 받고 202로 답함). 비우면 업로드 안 함 |
| `token` | 수신 측 공유 토큰, `X-Webhook-Token` 헤더로 보낸다. OS 자격 증명 저장소에 보관 |
| `flush_hours` | 업로드 간격(시간), 기본 24 |

각 설정은 환경변수 `CC_USAGE_DEVELOPER`·`CC_USAGE_TEAM`·`CC_USAGE_ENDPOINT`·`CC_USAGE_TOKEN`·
`CC_USAGE_FLUSH_HOURS`로도 줄 수 있다. `claude --plugin-dir ./cc-usage-plugin`으로 한 세션만 시험할
때도 이 방법을 쓴다. 수신 URL과 토큰은 이 저장소에 넣지 않는다.

## 무엇이 기록되나 (`ledger/<ISO 주>.jsonl`)

| kind | 시점 | 필드 |
|---|---|---|
| `session_open` | SessionStart | `~/.claude.json` `oauthAccount`의 계정 이메일·account/org uuid·seat tier(자격 증명 아님) · host · OS · 저장소 origin(자격 증명 제거) · 브랜치 · 진입점 |
| `prompt` | UserPromptSubmit | 슬래시 명령 이름만(`/review`, 본문 없음) · 글자 수 · permission mode · effort |
| `skill` | PreToolUse(Skill) | 스킬 이름(`plugin:skill`) · 인자 글자 수 |
| `subagent` | SubagentStop | agent type · agent id |
| `usage` | Stop(비동기) · SessionEnd · SubagentStop | transcript 증분 파싱 → 모델 × effort × query source별 요청 수와 input / output / cache-read / cache-create / thinking 토큰(request id 중복 제거) |
| `commit` | PostToolUse(Bash, PowerShell) | `git commit`·`cherry-pick`·`revert`·`am`이 만든 커밋과 merge 커밋. `pull`·`checkout`·`switch`·`reset`·`rebase`와 fast-forward merge로 HEAD만 움직인 경우는 세지 않음 · sha · 브랜치 |
| `pr` | PostToolUse(Bash, PowerShell) | 출력에 PR이 나온 `gh pr` / `glab mr`의 `create`·`merge` · 번호 · URL |
| `edits` | Stop · SessionEnd | Edit / Write / MultiEdit / NotebookEdit의 도구별·확장자별 횟수 · 바이트 · 파일 수(경로 없음) |
| `session_close` | SessionEnd | 종료 사유 |

모든 레코드에 `id`(UUID)·`ts`(UTC)·`plugin`(버전)·`team`·`developer`가 붙는다. 원장은
`${CLAUDE_PLUGIN_DATA}`(`~/.claude/plugins/data/<plugin id>/`, Windows는
`%USERPROFILE%\.claude\plugins\data\…`)에 있고 플러그인을 업데이트해도 남는다.

## 주간 요약 (수신 측 없이도 가능)

```bash
node scripts/report.js --days 7 --json weekly.json
```

세션 수 · 요청 수 · 토큰(출력 / 캐시 읽기 / 캐시 생성 / 입력) · 저장소·모델·effort·query source별 ·
명령·스킬 상위 · 플러그인 명령 비율 · 커밋·PR·편집. 레코드 `id`마다 한 번만 센다. 다른 위치의 원장은
`CLAUDE_PLUGIN_DATA`를 지정해 집계한다.

## 업로드 계약 (선택)

`endpoint`가 있으면 비동기 Stop 훅이 원장을 배치로 올린다. SessionStart·SessionEnd에서는 올리지
않으므로 수신 측이 느려도 세션이 기다리지 않는다.

- **요청:** `POST <endpoint>&developer=<id>&week=<YYYY-Www>&id=<첫 레코드 id>`(endpoint에 쿼리가
  없으면 `&` 대신 `?`, 기존 쿼리는 유지), `Content-Type: application/x-ndjson`, 토큰이 있으면
  `X-Webhook-Token: <token>` 헤더, `Authorization` 헤더 없음. 사용자 정의 헤더가 다른 호스트로
  따라가지 않도록 리다이렉트는 거부한다.
- **본문:** 원장 줄 그대로 — UTF-8, 한 줄에 JSON 레코드 하나, 마지막 줄바꿈 포함.
- **배치:** developer 1명·ISO 주 1개(각 레코드 `ts`로 UTC에서 계산). 주나 developer가 다르면 나눠서
  보내고, 오래된 주부터 보낸다.
- **성공은 `202`뿐이다.** 그때 배치를 `send/`에서 지운다. 그 밖의 경우 배치를 남겨 두고, 다음
  시도에 같은 배치를 그대로(같은 본문·같은 쿼리) 보낸다.
- **`401`:** `endpoint`나 `token`이 바뀔 때까지 더 보내지 않는다.
- **그 밖의 상태 코드·연결 실패·15초 무응답:** 30분 이상 지난 첫 Stop에서 다시 보내고, 연속
  실패마다 간격을 두 배로 늘려 최대 6시간까지 둔다. 성공하면 간격을 되돌린다.
- **주기:** `flush_hours`마다, 또는 64 KB가 쌓이면 그 전에 보낸다.
- `endpoint`를 설정하기 전에 기록된 레코드는 올리지 않는다.
- 전달은 최소 1회다(수신 측이 저장했지만 202가 오지 않은 배치는 다시 간다). 수신 이후 단계에서
  레코드 `id`로 중복을 제거한다.
- 데이터 폴더의 `errors.log`에는 실패한 업로드의 상태 코드만 남고 URL·토큰은 남지 않는다.

쿼리 값 덕분에 노코드 수신 측(예: HTTP 트리거 자동화 플로우)이 본문을 파싱하지 않고 폴더와 파일
이름을 정할 수 있다.

## 한계

- 토큰은 이 머신의 transcript 기준이다. 클라우드 세션과 다른 머신은 빠진다. Stop 시점에
  transcript가 덜 써졌으면 다음 Stop이나 SessionEnd에서 따라잡는다.
- `claude -p`(SDK) 세션은 `entrypoint: sdk-cli`로 기록된다.
- Node가 없으면 훅이 조용히 시작에 실패한다. 세션 자체에는 영향이 없다.
- 플러그인 명령 비율은 `plugin:skill` 형식 명령만 센다. 프로젝트 로컬 스킬은 명령 상위에만 나온다.
- 설치하기 전에, 기록되는 사람에게 수집 항목·목적·보관처를 알린다.
- 지금까지는 macOS에서만 실행했다(Node 24.22.1, Claude Code 2.1.310: 시험 전체와 실세션 1회).
  Windows와 Cowork 세션은 아직 실행하지 않았다. 코드는 플랫폼 공통 Node API만 쓰지만, 그곳에서 처음
  실행해 보기 전까지는 미검증으로 본다.

## 시험

```bash
node --test cc-usage-plugin/tests/collect.test.js
```

훅 스크립트를 자식 프로세스로 실행해 로컬 수신기에 보낸다. 주·developer별 배치, 202 / 401 / 타임아웃
처리와 재시도 간격, 업로드 주기, 잠금, 커밋·PR 판정, developer 값, `report.js`를 확인한다. 한 시험이
15초 타임아웃을 기다리므로 약 20초 걸린다.

## 파일

```
cc-usage-plugin/
├── .claude-plugin/plugin.json   userConfig: developer · team · endpoint · token(sensitive) · flush_hours
├── hooks/hooks.json             훅 7개, 전부 exec form(node)
├── scripts/collect.js           훅 수집기(stdin JSON → 원장 → 배치 → POST)
├── scripts/report.js            주간 요약(JSON + 텍스트)
├── tests/collect.test.js        node:test 시험
└── docs/                        decisions.md · design/plugin-design.md · build-context.md
```
