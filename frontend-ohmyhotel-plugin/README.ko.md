# Frontend Ohmyhotel Plugin (한국어)

[`ohmyhotelco/ohmyhotel-frontend`](https://github.com/ohmyhotelco/ohmyhotel-frontend) 저장소의
**작업 방법**을 담은 Claude Code 플러그인입니다. 대상은 V3 "All New B2C" 사이트(`apps/www` — `www`와
`m` 두 호스트를 받는 반응형 React Router v7 SSR 앱 하나)와 같은 저장소에 나중에 들어올 앱들입니다.
`frontend-react-plugin`(뼈대)과 `frontend-migration-plugin`(선별)을 **독립 복사**해 Claude 5 세대
에이전트와 현재 Claude Code 플러그인 규격(워크플로, 백그라운드 하위 에이전트, `${CLAUDE_PLUGIN_ROOT}`)에
맞게 다시 썼습니다. 커맨드 prefix는 `fo-`입니다.

> 상태: v0.1.0 — 커맨드 세트 완성, 감사 완료, 전구간 실행은 아직. 커맨드 22·에이전트 17·워크플로 7·
> 스크립트 10이 `claude plugin validate`, 저장소 일관성 검사, eval 스위트, Codex + Claude 3라운드 감사를
> 통과했습니다. `fo-init`·`fo-spec-sync`·`fo-plan`은 실제 저장소와 스펙으로 돌려 봤고, `fo-gen`과 게이트는
> 앱 스캐폴드(V3 계획 Phase 0-B) 뒤에 첫 실행이 가능합니다. 플러그인은 제품 앱이나 제품 규칙을 **담지
> 않습니다.**

## 하는 일

화면 생성에 V3 구축이 필요로 하는 다섯 가지를 둘러 씌웁니다.
1. **스펙 스냅샷이 정본** — 기획 첨부를 `specs/`에 바이트 그대로 반입하고 해시·원장에 기록. 계획과
   테스트는 id와 줄 번호로 스펙을 인용합니다.
2. **화면당 답안지 3종** — 스펙(항상), Figma 프레임(화면), 동결된 monorepo의 V2 구현(로직). 앱별로
   켜고 끕니다.
3. **5단계 TDD 생성** — foundation → api-tdd → component-tdd → page-tdd → integration. 첫 실패
   단계에서 멈추고 재개되는 워크플로입니다.
4. **증거가 있는 게이트 체인** — verify, visual(Figma 대조), E2E, contract(제품 규칙 목록), SEO,
   review. 모든 결과는 tree hash와 함께 기록되어 stale 여부를 계산합니다.
5. **준비 상태 = 장부** — 빅뱅 전환은 증거가 있는 닫힌 항목의 목록입니다. 플러그인은 증명만 하고
   트래픽은 절대 돌리지 않습니다.

## 개념 (먼저 읽기)

- **화면 = 스펙 단위.** `apps/www/app/screens/<nn>-<screen>/`에 뷰(`<Screen>.tsx`), headless 훅
  (`use<Screen>.ts`), 테스트, 목, 기계용 계획(`implementation-plan.json`), 사람용 스펙
  (`<Screen>.spec.md`, 5블록)이 있습니다. id는 스펙 id(`01-main-page` … `12-city-landing`).
- **제품 규칙은 제품 레포에, 플러그인에는 없음.** 3층: 기획 스펙에 있는 규칙은 `specs/`에서 직접 읽고,
  스펙에 없는 개발·CTO 결정은 `docs/adr/`와 `docs/rules/*.json`(기계 검사 목록, **형식**만 플러그인이
  `templates/rule-lists.md`로 정의)에 두며, 플러그인은 방법만 가집니다. 스펙이 바뀌면 제품 레포 PR이고
  플러그인 릴리스는 필요 없습니다.
- **다중 에이전트 체인은 워크플로, 명령은 스크립트, 진입점·승인은 스킬.** 대화형 세션에서 하위
  에이전트는 백그라운드로 돌기 때문에 스킬은 같은 턴에 에이전트가 돌아온다고 가정하지 않습니다.
  `fo-gen`·`fo-review`·`fo-fix`·`fo-visual`·`fo-contract`·`fo-seo`는 `workflows/`의 스크립트,
  `fo-verify`·`fo-progress`·`fo-cutover`는 `bin/` 스크립트, 승인(계획 서명, 고칠 리뷰 클러스터 선택)은
  실행 사이에 있습니다.
- **e2e 트리는 하나.** `templates/e2e-playwright.md`가 `<app.dir>/e2e/`를 고정합니다(`fixtures.ts`, `support/`,
  `support/pages/<screen>.ts`, `screens/<screen>/<TS-id>.spec.ts`, `visual/<screen>.spec.ts`,
  `seo/<screen>.<aspect>.spec.ts`). 폴더가 역할을, 파일명이 id를 정하고 접미사는 `.spec.ts` 하나, 실행 산출물은
  `e2e/` 밖. V2 monorepo의 `e2e/`는 규칙이 "기존 스펙을 따르라"뿐이어서 접미사 십여 종과 커밋된 산출물
  349개로 흩어졌습니다. 여기서는 `fo-verify-run`의 `e2e-layout` 검사가 트리 밖의 파일에 게이트를 실패시킵니다.
- **해시 정의는 하나.** `bin/fo-screen-hash`가 화면 증거의 범위(화면 폴더에서 `<Screen>.spec.md` 제외,
  라우트 모듈, ui-kit 갭, 패키지 추가분)를 정합니다. 생산자·소비자 모두 이걸 호출합니다. 자기 Playwright
  스펙을 쓰는 게이트는 그 해시를 따로 기록(`--spec-path`)하므로 뒤 게이트가 앞 게이트를 stale로 만들지
  않습니다.
- **트래커보다 증거.** `docs/gates/<app>/<screen>/<gate>.json`이 기록이고,
  `docs/gates/<app>/progress.json`은 `fo-evidence`와 `fo-progress-set`만 쓰는 색인입니다(파일 잠금,
  원자적 교체). `fo-progress`는 게이트를 current / skipped(이유 있음) / stale / unverifiable /
  blocked / missing으로 분류하고, 현행 pass 외에는 전부 차단 사유이며, 차단 사유가 없어야 `done`입니다.
- **리뷰어는 전수 보고, 거르는 건 사람.** 리뷰어 4종(스펙·품질·테스트·보안)은 모든 발견을 심각도·
  확신도와 함께 보고하고, 워크플로가 파일별로 묶으며, 사용자가 고칠 클러스터를 고릅니다. 리뷰어 하나라도
  결과가 없으면 리뷰는 `incomplete`이지 "적은 눈으로 통과"가 아닙니다.
- **재생성이 아니라 델타.** 스펙 스냅샷이 바뀌면 `fo-plan-hash --check`가 어느 계획 항목의 인용 구절이
  바뀌었는지, 사라졌는지, 어떤 새 요구사항이 인용되지 않았는지 말해 줍니다. `fo-plan`은
  `delta-plan.json`을 쓰고 `fo-gen --delta`가 기존 파일에 적용해 누적된 수정을 지킵니다.
- **Claude 5 지침 문체.** 이유가 붙은 평서문. `MUST`/`NEVER` 대문자 없음, 재검증 지시 없음(모델이
  스스로 검증하므로; *도구를 실행해 결과를 기록하는* 단계는 증거이므로 유지), 경고 대신 완료 조건,
  사건 이력은 지침이 아니라 `docs/build-context.md`에.

## 전제 조건

이 플러그인은 도구입니다. 제품 저장소가 제공해야 하는 것:

- 앱 스캐폴드(`apps/www/app/root.tsx`, 라우트, `react-router.config.ts`), monorepo에서 subtree로
  들여온 `packages/shared-*`, GitHub Packages의 `@ohmyhotelco/design-system` 설치(`.npmrc`에는
  `${GITHUB_TOKEN}` 자리표시자만), Node + pnpm/npm, `vitest`, `typescript`, 브라우저가 설치된
  `@playwright/test`.
- 기획 스냅샷이 있는 `specs/`(`fo-spec-sync`가 반입)와 담당자가 ADR과 함께 채운 `docs/rules/*.json`
  (`fo-init`은 빈 틀만 — 빈 목록은 pass가 아니라 보고되는 갭).
- 재사용 화면: 아카이브된 monorepo의 로컬 클론과 ADR에 기록된 동결 커밋(`legacySource.frozenCommit`).
  `fo-analyze`는 `TBD`를 거부합니다.
- 비주얼 게이트: 파일 키가 있는 `docs/figma-manifest.json`, PNG를 커밋하려면 환경변수 `FIGMA_TOKEN`
  (토큰은 어디에도 기록되지 않음).
- 선택: `fo-audit-codex`용 Codex CLI(없으면 자동 skip).

## 대상 스택

React 19 · React Router v7 framework 모드(SSR, 화면 URL당 라우트 모듈 하나) · 워크스페이스 API
패키지(`@ohmyhotelco/shared-data`) 위의 TanStack Query · 디자인 시스템 위 어댑터를 쓰는
react-hook-form + zod · 언어별 평면 i18n JSON 하나 위의 `useT()`(5개 언어) · 클라이언트 스토어 없음 ·
dayjs · Vitest + Testing Library + MSW · Playwright. 저장소가 고정하므로 설정에 프로필·knob 필드가
없습니다.

## 빠른 시작 — 첫 화면

```
# 0. 1회 설정 (.claude/frontend-ohmyhotel-plugin.json + 제품 레포 스캐폴드)
/frontend-ohmyhotel-plugin:fo-init

# 1. 기획 스펙을 스냅샷으로 반입 (specs/MANIFEST.md에 티켓·sha256·내용 해시)
/frontend-ohmyhotel-plugin:fo-spec-sync 01-main-page ~/Downloads/main-page-spec_v1.9_20261002.zip --ticket OMH-794

# 2. 답안지 (화면에 해당하는 것만)
/frontend-ohmyhotel-plugin:fo-figma --app www --screen 01-main-page --page UI_Main   # 프레임 → 매니페스트 (+ FIGMA_TOKEN 있으면 PNG)
/frontend-ohmyhotel-plugin:fo-analyze --app www --screen 10-booking-history          # 재사용 화면: V2 동작 → analysis.json
/frontend-ohmyhotel-plugin:fo-extract --app www --screen 10-booking-history          # 공용 후보 → packages/shared-*

# 3. 계획 → 승인 → 생성
/frontend-ohmyhotel-plugin:fo-plan --app www --screen 01-main-page    # 계획 + <Screen>.spec.md, 승인 질문으로 끝남
/frontend-ohmyhotel-plugin:fo-gen  --app www --screen 01-main-page    # 워크플로: foundation → api-tdd → component-tdd → page-tdd → integration

# 4. 게이트 (순서대로; docs/gates/www/01-main-page/<gate>.json 기록)
/frontend-ohmyhotel-plugin:fo-verify   --app www --screen 01-main-page
/frontend-ohmyhotel-plugin:fo-visual   --app www --screen 01-main-page
/frontend-ohmyhotel-plugin:fo-e2e      --app www --screen 01-main-page
/frontend-ohmyhotel-plugin:fo-contract --app www --screen 01-main-page
/frontend-ohmyhotel-plugin:fo-seo      --app www --screen 01-main-page

# 5. 리뷰 → 수정 → 재검증
/frontend-ohmyhotel-plugin:fo-review --app www --screen 01-main-page
/frontend-ohmyhotel-plugin:fo-fix    --app www --screen 01-main-page

# 6. 수동 게이트 2종 — 다른 증거와 같은 방식으로 기록
echo '{"reviewer":"<디자이너>","note":"Figma 리뷰 <날짜>"}' | fo-evidence --app www --screen 01-main-page --gate designerReview --result pass
echo '{"ticket":"OMH-715","comment":"<코멘트 id>"}'          | fo-evidence --app www --screen 01-main-page --gate planningAcceptance --result pass

# 언제든: 화면별 현황과 다음 커맨드
/frontend-ohmyhotel-plugin:fo-progress --app www

# 전환 전: 전환 장부
/frontend-ohmyhotel-plugin:fo-cutover --app www init     # 1회; 이후 check · close <item> --evidence <link> · add …
```

스펙이 나중에 개정되면: `fo-spec-sync`(stale 계획 표시) → `fo-plan`(`delta-plan.json`) →
`fo-gen --delta` → 게이트 다시.

## 게이트

`fo-progress`에서 화면이 `done`이 되는 조건은 모든 행이 *현행* pass(또는 이유가 있는 검증된 skip)이고
리뷰에 deferred 클러스터가 없는 것입니다. `fo-cutover`의 `screens-all-gates` 항목은 그때만 닫힙니다.

| 게이트 | 커맨드 | 실행 | 검사 | 실패 시 |
| --- | --- | --- | --- | --- |
| verify | `fo-verify` | `bin/fo-verify-run` | `react-router typegen` + `tsc`, API 패키지 자체 `tsc`/`vitest`(추가분), ESLint, 화면 Vitest, i18n 키 커버리지, `e2e-layout`(e2e 트리 위치 검사·추적된 산출물 없음). `--only`는 진단용(`partial`, 미등록) | `fo-fix --from verify` |
| visual | `fo-visual` | 워크플로 | 상태 × 뷰포트 × 언어별 Playwright 캡처 + 깨짐 검사(오버플로·콘솔 오류·깨진 이미지·잘린 텍스트·769 경계), 프레임 있는 조합은 Figma 병렬 비교 | `fo-review` / `fo-fix --from visual` |
| e2e | `fo-e2e` | 에이전트 | 스펙 TS 시나리오를 Playwright 스펙으로, 시나리오별 trace 경로 | `fo-fix --from e2e` |
| contract | `fo-contract` | 워크플로 | 규칙 목록별 워커(`externalUrls`·`webviewContract`·`sensitiveQueryKeys`·`requestConventions`) + 텔레메트리. 빈 목록은 보고되는 갭 | `fo-fix --from contract` 또는 담당자가 항목 추가 |
| seo | `fo-seo` | 워크플로 | head 메타 vs 메타 템플릿, canonical/hreflang, sitemap/robots 호스트, 구조화 데이터, 슬러그 — SEO 참조 스펙 기준 | `fo-fix --from seo`; 스펙 충돌은 SEO 오너 |
| review | `fo-review` | 워크플로 | 스펙 준수·코드 품질·테스트 품질(앵커를 스펙까지 추적)·보안 — 전수, 클러스터링 | 승인한 클러스터로 `fo-fix` |
| designerReview, planningAcceptance | `fo-evidence --gate …` | 수동 | 누가 리뷰했는지 / 어느 티켓 코멘트로 인수했는지 사람이 기록 | — |

## 스킬

| 스킬 | 역할 | 실행 |
| --- | --- | --- |
| `fo-init` | 설정 + 제품 레포 스캐폴드 | 스킬 |
| `fo-spec-sync` | 기획 첨부를 불변 스냅샷으로 반입, 원장 행, stale 계획 표시 | 스킬 + `bin/fo-spec-import` |
| `fo-analyze` | 동결 monorepo의 V2 구현 → permalink 달린 `analysis.json` | 에이전트 1(`legacy-analyzer`) |
| `fo-extract` | 공용 패키지 후보 → `packages/shared-*` TDD | 에이전트 순차(`package-extractor`) |
| `fo-figma` | 프레임(상태 × 뷰포트) → 매니페스트, 토큰 있으면 PNG | 에이전트 1(`figma-extractor`) + `bin/fo-figma-export` |
| `fo-plan` | 스펙 + 답안지 + 규칙 목록 → 계획·화면 스펙, 스펙 변경 시 델타, 승인 | 에이전트 1(`implementation-planner`) + `bin/fo-plan-hash` |
| `fo-gen` | 5단계 TDD 생성, 재개, `--delta` | 워크플로 `fo-gen` |
| `fo-verify` · `fo-visual` · `fo-e2e` · `fo-contract` · `fo-seo` | 게이트 | 스크립트 · 워크플로 · 에이전트 · 워크플로 · 워크플로 |
| `fo-review` → `fo-fix` | 리뷰어 4 → 클러스터 → 선택 → 클러스터별 수정 → 재검증 | 워크플로 |
| `fo-progress` | 화면 × 게이트 행렬, 차단 사유, 다음 커맨드 | `bin/fo-progress-report` |
| `fo-cutover` | 전환 장부(computed / list / manual 항목, 증거) | `bin/fo-cutover-check` |
| `fo-debug` · `fo-clean-code` · `fo-test-review` · `fo-security` · `fo-audit-codex` | 디버깅, 독립 감사, Codex 2차 의견 | 에이전트 1씩 |

워크플로(`workflows/`): `fo-probe`(스모크 테스트 — 모든 에이전트가 런타임에서 해석되는지; 에이전트
추가·Claude Code 업그레이드 뒤 실행), `fo-gen`, `fo-visual`, `fo-contract`, `fo-seo`, `fo-review`,
`fo-fix`.

## 스크립트 (`bin/`, 플러그인 활성 시 `PATH`)

`fo-tree-hash`(내용 해시) · `fo-screen-hash`(**화면 증거 범위의 정의**) · `fo-spec-import` ·
`fo-plan-hash`(`--check`: changed / hashless / unresolved / uncited) · `fo-verify-run` ·
`fo-evidence`(증거 파일 + 색인, 해시 없는 pass 거부, `--spec-path`) · `fo-progress-set`(게이트 외
트래커 필드의 유일한 잠금 기록기) · `fo-progress-report` · `fo-figma-export` · `fo-cutover-check`.

## 문제 해결 / FAQ

- **`fo-gen`이 preflight에서 멈춘다.** 앱 셸(`apps/www/app/root.tsx`)·디자인 시스템 패키지·vitest가
  없는 것 — 제품 레포의 Phase 0-B 작업이지 화면의 일이 아닙니다. 메시지가 빠진 것을 말해 줍니다.
- **게이트가 `unverifiable`.** 증거 파일과 트래커가 어긋나거나, 파일이 없거나, 해시를 못 구한 것
  (중단된 실행, 손 편집). 게이트를 다시 돌리고 `progress.json`은 절대 손으로 고치지 않습니다.
- **고친 직후 게이트가 `stale`.** 정상입니다 — 수정이 화면 해시를 바꿨습니다. `fo-verify` 후 앞서
  통과했던 게이트들을 다시 돌립니다. Playwright 게이트는 자기 스펙 파일이 바뀌어도 stale입니다.
- **스펙을 바꿨는데 `fo-plan`이 "계획 현행"이라 한다.** 인용된 구절 밖의 변경이고, 사라진 섹션도 없고,
  인용 안 된 새 FR/US/TS도 없을 때만 그 지름길을 탑니다. 아니면 델타를 씁니다. 의심되면
  `fo-plan-hash --check` 출력을 보세요.
- **`fo-contract`가 "규칙 미기록"이라 한다.** `docs/rules/` 목록이 비어 있습니다 — 담당자가 ADR과
  함께 항목을 추가할 때까지 갭이 보이고 전환 항목이 열려 있습니다.
- **`fo-cutover`가 `screens-all-gates`를 못 닫는다.** `fo-progress --blocked`가 화면별 이유를
  보여 줍니다. 정당하게 해당 없는 게이트(회원 전용 화면의 SEO, 시나리오 없는 E2E)는 해당 커맨드가
  이유와 함께 `skipped`로 기록하고 검증된 것으로 칩니다.
- **"다른 실행이 화면을 잡고 있다."** `runId`가 살아 있는 `.claude/frontend-ohmyhotel/<app>/<screen>/*.lock`
  — 기다리거나 잡은 세션을 확인하세요. 지우지 마세요.
- **`FIGMA_TOKEN`이 없다.** `fo-figma`는 노드 id만 기록하고, `fo-visual`은 Figma MCP로 인라인 비교하며
  "커밋된 참조 이미지 없음"을 보고합니다.

## 개발

```bash
claude plugin validate frontend-ohmyhotel-plugin
scripts/check-plugin-consistency.py frontend-ohmyhotel-plugin
claude plugin eval frontend-ohmyhotel-plugin --ablation none --runs 1
claude --plugin-dir ./frontend-ohmyhotel-plugin
```

## 문서

- `docs/design/plugin-design.md` — 결정 P1~P10, 설정 스키마, 커맨드 세트, 조율 모델, 에이전트 표,
  지침 작성 규칙, 복사 매트릭스, 작업 순서, CTO Q&A.
- `docs/build-context.md` — 각 테스트와 감사 라운드가 무엇을 왜 바꿨는지.
- `CLAUDE.md` — 유지보수 메모(에이전트 컨텍스트에는 실리지 않음; 에이전트 규칙은
  `skills/fo-shared/SKILL.md`).
- `templates/` — 규칙 목록 형식, 계획 스키마, 5블록 화면 스펙, TDD 규칙, E2E, i18n 키 커버리지,
  폼 어댑터, 서버 상태, 전환 장부, Codex 감사, `fo-init` 스캐폴드 텍스트.

영문 원본: `README.md`.

## 라이선스

MIT
