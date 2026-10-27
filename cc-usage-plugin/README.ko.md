# cc-usage-plugin

개발자 머신(Windows·macOS·Linux)의 Claude Code 훅으로, 세션마다 **어느 저장소에서 · 어떤 명령과
스킬로 · 어느 모델과 effort로 · 토큰을 얼마나** 썼는지와 커밋·PR·편집 수를 기록한다. 프롬프트
본문·도구 인자·파일 내용·파일 경로는 수집하지 않는다. 모든 훅이 출력 없이 끝나는 `command` 훅이라
기록에는 모델 토큰을 쓰지 않는다. 설정 명령 하나(`/cc-usage-plugin:cc-init`)는 모델에게 목록으로
보이지 않고, 직접 실행할 때만 토큰을 쓴다.

[English](./README.md)

## 요구 사항

- exec form 훅 `args`를 지원하는 Claude Code(지금까지 2.1.310에서 실행).
- Node.js 22.23.4 / 24.22.1 / 26.12.1 이상(권장 24 LTS). 2026-10-21 Node.js 보안 릴리스 이전 버전은
  먼저 올린다. 18·20·25는 지원이 끝나 패치가 없다. 확인: `node --version`. Node는 Claude Code가 보는
  `PATH`에 있어야 한다. 셸용 버전 관리자로만 설치한 Node는 데스크톱 앱에서 시작한 세션에서 보이지
  않을 수 있다.
- 저장소·브랜치·커밋·PR 필드를 위해 `PATH`에 `git`.
- Windows에 Git Bash는 필요 없다. 모든 훅이 exec form(`node` + 인자)이라 셸을 거치지 않는다.
- 설정 명령을 쓰려면 `PATH`에 `claude` 명령. 설정값은 이 명령(`claude plugin configure`, 2.1.311에서
  확인)으로 저장한다.

## 설치

```
/plugin marketplace add ohmyhotelco/hare-cc-plugins
/plugin install cc-usage-plugin@ohmyhotelco --scope user
```

프로젝트 하나가 아니라 머신의 모든 세션을 기록하므로 user 범위로 설치한다. 그다음 아래 순서로
설정한다.

1. Claude Code에서 `/cc-usage-plugin:cc-init <developer> [team]`. 어떤 설정이 되어 있고 훅이 무엇을
   기록했는지 보여 준 뒤, 수신 측이 볼 값으로 정규화한 developer와 team을 저장한다. 인자를 주지
   않으면 물어본다.
2. 수신 URL과 토큰을 받은 경우에만: Claude Code 밖의 터미널에서 1단계가 출력한
   `node "…/scripts/init.js" secrets --plugin …` 명령을 출력된 그대로 실행한다(기본이 아닌 설정 폴더면
   `--config-dir`도 붙어 있다). 두 값을 화면에 보이지 않게 입력받고,
   URL과 토큰을 업로드 계약과 대조한 뒤 저장한다. developer를 설정하기 전에는 거부하고, 파이프나 파일이
   아니라 터미널에서만 입력받는다. URL과 토큰을 채팅에 쓰지
   않는다. 쓰면 세션 기록에 남는다.
3. Claude Code 세션을 새로 시작한다. 설정은 다음 세션부터 적용된다. `/cc-usage-plugin:cc-init`을
   다시 실행하면 업로드를 포함한 상태를 언제든 볼 수 있다.

`endpoint`를 비우면 로컬 원장만 쌓인다. 같은 설정은 Claude Code의
`/plugin configure cc-usage-plugin@ohmyhotelco`로도 고칠 수 있지만, 이때는 위의 확인을 거치지 않는다.

Claude Code 설정 폴더를 여럿 쓰면(`CLAUDE_CONFIG_DIR`, 예: 계정마다 하나) 폴더마다 플러그인·설정·원장이
따로다. 폴더마다 플러그인을 설치하고 같은 developer로 `cc-init`을 실행한다. 설치하지 않은 폴더의 세션은
기록되지 않는다. 한 폴더 안에서 `/login`으로 계정을 바꾸는 경우는 따로 할 일이 없다.

| 설정 | 뜻 |
|---|---|
| `developer` | 사람마다 배정한 본인 식별자. 모든 레코드에 찍히고 정규화한 값이 업로드의 `developer`가 된다. 소문자로 바꾸고 a–z·숫자·`.`·`_`·`-`만 남기며 나머지는 `-`로 바꾼다. 남는 글자가 없으면 `u-<해시>`. 표기 둘이 같은 값이 될 수 있으므로(`Alex Kim`, `alex-kim`) 정규화 뒤에도 서로 다른 값으로 배정한다. 비우면 OS 로그인 이름을 쓰고 업로드하지 않는다. 지금 설정된 값이 찍힌 레코드만 올리므로 endpoint보다 먼저 설정한다. 다른 값이 찍힌 레코드 — 값을 설정하기 전의 OS 로그인 이름이나 이전 값 — 는 로컬에만 남는다. OS 로그인 이름과 같은 값을 배정하면 같은 값이므로, 그 이름으로 먼저 기록된 레코드도 올라간다 |
| `team` | 모든 레코드에 붙는 팀 라벨 |
| `endpoint` | 수신 URL. HTTPS(평문 `http`는 127.0.0.1·localhost·[::1]만), NDJSON POST를 받고 202로 답함. 비우면 업로드 안 함 |
| `token` | 수신 측 공유 토큰, `X-Webhook-Token` 헤더로 보낸다 |
| `flush_hours` | 업로드 간격(시간), 기본 24 |

`endpoint`와 `token`은 sensitive로 표시되어 있어 Claude Code가 `settings.json`이 아닌 보안 자격 증명
저장소에 보관한다. `init.js`도 같은 `claude plugin configure`로 저장하고 두 값을 출력하지 않는다. 각 설정은 환경변수 `CC_USAGE_DEVELOPER`·`CC_USAGE_TEAM`·`CC_USAGE_ENDPOINT`·
`CC_USAGE_TOKEN`·`CC_USAGE_FLUSH_HOURS`로도 줄 수 있다. `claude --plugin-dir ./cc-usage-plugin`으로 한
세션만 시험할 때도 이 방법을 쓴다. 수신 URL과 토큰은 이 저장소에 넣지 않는다.

## 무엇이 기록되나 (`ledger/<ISO 주>.jsonl`)

모든 레코드에 `id`(UUID)·`kind`·`ts`(UTC)·`plugin`(버전)·`team`·`developer`·`session_id`·`cwd`(세션의
작업 폴더 절대 경로)가 들어간다.

| kind | 시점 | 필드 |
|---|---|---|
| `session_open` | SessionStart | `.claude.json` `oauthAccount`의 계정 이메일·account/org uuid·seat tier·billing type(자격 증명 아님) · host · OS · OS 사용자 · 저장소 origin(호스트와 경로만) · 저장소 폴더 이름 · 브랜치 · 모델 · 시작 방식 · permission mode · 진입점 |
| `prompt` | UserPromptSubmit | 슬래시 명령 이름만(`/review`, 본문 없음. 경로로 시작하는 프롬프트는 기록하지 않음) · 글자 수 · permission mode · effort |
| `skill` | PreToolUse(Skill) | 스킬 이름(`plugin:skill`) · 인자 글자 수 · agent type |
| `subagent` | SubagentStop | agent type · agent id |
| `usage` | Stop(비동기) · SessionEnd · SubagentStop | transcript 증분 파싱 → 모델 × effort × query source별 요청 수와 input / output / cache-read / cache-create / thinking 토큰(request id 중복 제거) · 브랜치 · Claude Code 버전 · agent id · 기록 시점에 로그인된 계정 이메일(세션 도중 `/login`으로 바꾸면 그 뒤 사용량은 새 계정에 붙는다) |
| `commit` | PostToolUse(Bash, PowerShell) | 그 명령이 만든 커밋 — `git commit`·`cherry-pick`·`revert`·`am`이나 `merge`가 만든 merge 커밋 — 중 HEAD에 새로 들어왔고 15분 안에 저장소의 `user.email`로 만들어졌으며 이 세션에서 아직 세지 않은 것. `pull`·`checkout`·`switch`·`reset`·`rebase`·`stash pop`과 fast-forward merge로 움직인 HEAD는 세지 않음 · 수 · sha · 이전 sha · 브랜치 · op |
| `pr` | PostToolUse(Bash, PowerShell) | 명령줄을 셸 단어로 읽어(따옴표 안이나 `echo` 뒤의 글은 명령이 아님) 찾은 `gh pr` / `glab mr` 명령 중, 출력에 PR URL이 있는 `create`, 또는 인자로 PR 번호나 URL을 주었고 출력에 오류가 없는 `merge`(gh는 터미널 밖에서 성공해도 아무것도 출력하지 않음). `--help`와 `--disable-auto`는 세지 않고, `--auto`와 merge queue는 merge를 요청한 시점에 센다 · 번호 · URL · action |
| `edits` | Stop · SessionEnd | Edit / Write / MultiEdit / NotebookEdit의 도구별·확장자별 횟수 · 쓴 바이트 · 직전 Stop 이후 파일 수(해시로 셈, 경로 없음) |
| `session_close` | SessionEnd | 종료 사유 |

원장은 `${CLAUDE_PLUGIN_DATA}` — `~/.claude/plugins/data/cc-usage-plugin-<마켓플레이스>/`
(`--plugin-dir`이면 `-inline`, Windows는 `%USERPROFILE%\.claude\plugins\data\` 아래) — 에 있고
플러그인을 업데이트해도 남는다.

## 주간 요약 (수신 측 없이도 가능)

```bash
node <플러그인 폴더>/scripts/report.js --days 7 --json weekly.json
```

플러그인 폴더는 Claude Code가 설치한 위치(`~/.claude/plugins/cache/<마켓플레이스>/cc-usage-plugin/<버전>/`)
나 이 저장소의 `cc-usage-plugin/`이다. 스크립트가 `~/.claude/plugins/data/cc-usage-plugin-*`에서 설치된
원장을 찾는다(마지막으로 기록된 것). 다른 원장은 `--data-dir <폴더>`나 `CLAUDE_PLUGIN_DATA`로 지정한다. 출력:
세션 수 · 요청 수 · 토큰(출력 / 캐시 읽기 / 캐시 생성 / 입력) · 로그인한 계정과 계정별 사용량 ·
저장소·모델·effort·query source별 · 명령·스킬 상위 · 플러그인 명령 비율 · 커밋·PR·편집. 레코드 `id`마다
한 번만 센다. 0.1.8 이전 원장의 사용량은 그 세션을 시작한 계정으로 센다. 출력에 세션 id는 나오지 않는다.

## 업로드 계약 (선택)

`endpoint`가 있으면 비동기 Stop 훅이 원장을 배치로 올린다. SessionStart·SessionEnd에서는 올리지
않으므로 수신 측이 느려도 세션이 기다리지 않는다.

- **요청:** `POST <endpoint>&developer=<id>&week=<YYYY-Www>&id=<첫 레코드 id>`(endpoint에 쿼리가
  없으면 `&` 대신 `?`, 기존 쿼리는 바이트 그대로 유지), `Content-Type: application/x-ndjson`,
  `X-Webhook-Token: <token>` 헤더, `Authorization` 헤더 없음. 사용자 정의 헤더가 다른 호스트로 따라가지
  않도록 리다이렉트는 거부한다.
- **본문:** 원장 줄 그대로 — UTF-8, 한 줄에 JSON 레코드 하나, 마지막 줄바꿈 포함.
- **배치:** developer 1명·ISO 주 1개(각 레코드 `ts`로 UTC에서 계산), 최대 1 MB. 주가 다르면 나눠서
  보내고, 오래된 주부터 보낸다. 설정된 `developer`가 찍힌 레코드만 잘라 내고, 이전 값으로 잘라 둔
  배치는 `send/`에 `.held`로 남겨 보내지 않는다. 그래서 배치가 보내는 설정과 다른 사람을 나타내는
  일이 없다.
- **성공은 `202`뿐이다.** 그때 배치를 `send/`에서 지운다. 그 밖의 경우 배치를 남겨 두고, 다음
  시도에 같은 배치를 그대로(같은 본문·같은 쿼리) 보낸다.
- **`401`:** `endpoint`나 `token`이 바뀔 때까지 더 보내지 않는다.
- **그 밖의 상태 코드·연결 실패·15초 무응답:** 30분 이상 지난 첫 Stop에서 다시 보내고, 연속
  실패마다 간격을 두 배로 늘려 최대 6시간까지 둔다. 성공하면 간격을 되돌린다.
- **주기:** `flush_hours`마다, 또는 64 KB가 쌓이면 그 전에 보낸다.
- **거부하는 설정:** endpoint가 HTTPS가 아니거나(평문 `http`는 루프백만 허용) 쿼리에 이미
  `developer`·`week`·`id`가 있거나, 토큰이 없거나, 토큰에 보이는 ASCII가 아닌 문자가 있거나(함께 복사된
  보이지 않는 문자 등), `developer`가 설정되지 않았으면 올리지 않는다.
  `errors.log`에 한 줄만 남기고 설정이 바뀔 때까지 다시 시도하지 않는다.
- endpoint 없이 기록된 레코드는 올리지 않는다. 업로드 추적은 endpoint가 있는 상태로 처음 기록할 때
  시작되고, endpoint 없이 처음 기록할 때 끝난다. 끝낼 때는 그때까지 기록된 것을 먼저 `send/`로
  잘라 두며, 이것은 endpoint를 다시 설정하면 올라간다. 그 순간 업로드가 진행 중이었거나 자르기에
  실패하면, 아직 잘리지 않은 레코드는 로컬 원장에만 남는다.
- 전달은 최소 1회다(수신 측이 저장했지만 202가 오지 않은 배치는 다시 간다). 수신 이후 단계에서
  레코드 `id`로 중복을 제거한다.
- 데이터 폴더의 `errors.log`에는 실패한 업로드의 상태 코드나 오류 코드만 남고 URL·토큰·레코드는
  남지 않는다.

쿼리 값 덕분에 수신 측이 URL만 보고 폴더와 파일 이름을 정할 수 있다.

## 한계

- 토큰은 이 머신의 transcript 기준이다. 클라우드 세션과 다른 머신은 빠진다. Stop 시점에
  transcript가 덜 써졌으면 다음 Stop이나 SessionEnd에서 따라잡는다.
- `claude -p`(SDK) 세션은 `entrypoint: sdk-cli`로 기록된다.
- `git -C <다른 저장소>`나 다른 저장소로 `cd`한 뒤 만든 커밋은 보지 못한다. 커밋·PR 판정은 세션의
  작업 폴더를 읽는다.
- 한 세션의 도구 호출이 병렬로 돌면 편집 카운터가 하나씩 빠질 수 있다.
- Node가 없으면 훅이 조용히 시작에 실패한다. 세션 자체에는 영향이 없다.
- 플러그인 명령 비율은 `plugin:skill` 형식 명령만 센다. 프로젝트 로컬 스킬은 명령 상위에만 나온다.
- 설치하기 전에, 기록되는 사람에게 수집 항목·목적·보관처를 알린다.
- `report.js`는 설정 폴더 하나의 원장만 읽는다. 폴더가 여럿이면(위) 폴더마다 `CLAUDE_CONFIG_DIR`을
  지정해 한 번씩 실행하거나, 수신 측에서 합친다.
- 비밀값 단계에는 `claude` 명령이 있는 터미널이 필요하다. 터미널이 없으면 `/plugin configure`로 같은
  설정을 넣을 수 있지만 확인은 거치지 않는다.
- 지금까지는 macOS에서만 실행했다(Node 24.22.1, Claude Code 2.1.310·2.1.311: 시험 전체와 실세션).
  Windows와 Cowork 세션은 아직 실행하지 않았다. 코드는 플랫폼 공통 Node API만 쓰지만, 그곳에서 처음
  실행해 보기 전까지는 미검증으로 본다.

## 시험

```bash
node --test 'cc-usage-plugin/tests/*.test.js'
```

`collect.test.js`는 훅 스크립트를 자식 프로세스로 실행하고, 업로드 시험은 로컬 수신기에 보낸다. 설정된
developer의 주별 배치와 1 MB 상한, 202 / 401 / 타임아웃 처리와 재시도 간격, 업로드 주기, 업로드
추적의 종료와 재시작, 거부하는 설정, 잠금, transcript 체크포인트, 커밋·PR 판정, 사용량 기록의 계정을
포함한 레코드 필드, 상태 정리, 계정별 사용량을 포함한 `report.js`를 확인한다. 한 시험이 15초 타임아웃을 기다리므로 약 25초 걸린다. 파일 권한을 쓰는
세 시험은 Windows와 root에서 건너뛴다. `init.test.js`는 가짜 `claude` 명령을 두고 `init.js`를
실행한다. 상태 보고, 설치 찾기, developer·team 저장, endpoint·token 값을 출력하지 않는지를 확인한다.
`secrets` 시험은 python3 `pty` 모듈이 만든 가상 터미널에서 돌고, 그것이 없으면(Windows) 건너뛴다.
화면에 보이지 않는지, endpoint·토큰 확인, 여러 줄 붙여 넣기, escape 시퀀스, 잘못된 UTF-8, 그리고 저장하는
동안이나 오류·Ctrl-C 직전에 입력한 값이 셸로 넘어가지 않는지를 확인한다.

## 파일

```
cc-usage-plugin/
├── .claude-plugin/plugin.json   userConfig: developer · team · endpoint(sensitive) · token(sensitive) · flush_hours
├── hooks/hooks.json             훅 7개, 전부 exec form(node)
├── skills/cc-init/SKILL.md      설정 명령, 사용자만 실행
├── scripts/collect.js           훅 수집기(stdin JSON → 원장 → 배치 → POST)
├── scripts/config.js            collect.js와 init.js가 함께 쓰는 설정 규칙
├── scripts/init.js              설정 도우미: status · set · secrets, claude plugin configure로 저장
├── scripts/report.js            주간 요약(JSON + 텍스트)
├── tests/collect.test.js        훅 node:test 시험
├── tests/init.test.js           init.js node:test 시험
└── docs/                        decisions.md · design/plugin-design.md · build-context.md
```
