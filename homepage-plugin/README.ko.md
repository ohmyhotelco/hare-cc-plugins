# Homepage Plugin

> **Ohmyhotel & Co** — Astro 기반 마케팅 홈페이지 개발을 위한 Claude Code 플러그인

## 주요 기능

이 Claude Code 플러그인은 대화형 페이지/섹션 정의를 통해 프로덕션 수준의 마케팅 홈페이지 웹사이트를 생성합니다. 페이지 기획부터 코드 생성, SEO 검증, 리뷰, 수정까지 완전한 파이프라인을 제공하며, 정적 우선 콘텐츠 사이트에 최적화되어 있습니다.

주요 역량:
- **대화형 페이지 기획** — 자연어 대화를 통해 페이지와 섹션을 정의하며, 선택적으로 Figma 참조 분석 가능
- **섹션 기반 생성** — 15가지 표준 마케팅 섹션 (.astro 정적 + 인터랙티브 요소를 위한 React islands)
- **SEO 우선 아키텍처** — 정적 HTML 출력, JSON-LD 구조화 데이터, sitemap, 메타 태그, Lighthouse CI 감사
- **Astro islands** — 기본적으로 JS 없음; 인터랙티브 컴포넌트(폼, 캐러셀, 아코디언)만 하이드레이션
- **2단계 코드 리뷰** — SEO 준수(6개 차원) + 코드 품질/접근성(6개 차원)
- **Content Collections** — Zod 스키마를 사용한 타입 안전 MDX 블로그 포스트, 선택적 헤드리스 CMS 통합

## 아키텍처 개요

```
/homepage-plugin:hp-init → .claude/homepage-plugin.json
        │
        ▼
/homepage-plugin:hp-plan [page-name]
        │
        ├── Interactive: describe site purpose, pages, and per-page content
        │   └── page-planner agent → page-plan.json (per page)
        │
        ├── Optional: provide Figma screenshot for design reference
        │   └── AI vision analyzes design → refines section props
        │
        ▼
/homepage-plugin:hp-gen [page-name]
        │
        ├── Phase 1: Infrastructure   — layout, header/footer, SEO utils, i18n, styles
        ├── Phase 2: Sections & Pages — section-generator + page-assembler (per page)
        └── Phase 3: Verification     — tsc + ESLint + astro build
        │
        ▼
/homepage-plugin:hp-verify [page-name] (optional)
        │
        ▼
/homepage-plugin:hp-review [page-name]
        │
        ├── Stage 1: seo-reviewer → SEO compliance (6 dimensions)
        └── Stage 2: quality-reviewer → code quality + accessibility (6 dimensions)
        │
        ▼ (if issues found)
/homepage-plugin:hp-fix <page-name>
        │
        └── review-fixer agent → direct fixes
        │
        ▼
/homepage-plugin:hp-review [page-name] (re-review)
```

## 기술 스택

| 카테고리 | 기술 |
|----------|-----------|
| 런타임 | Node.js 22.x LTS (>= 22.12) |
| 패키지 매니저 | pnpm |
| 프레임워크 | Astro 5.x (SSG + islands architecture) |
| 언어 | TypeScript (strict) |
| UI 통합 | @astrojs/react (React 19 for interactive islands) |
| 스타일링 | Tailwind CSS (@astrojs/tailwind) |
| 컴포넌트 | shadcn/ui + Lucide icons (사내 디자인 시스템으로 교체 가능) |
| 콘텐츠 | Astro Content Collections + @astrojs/mdx, 선택적 헤드리스 CMS |
| 국제화 | Astro 내장 i18n 라우팅 |
| SEO | Static HTML + @astrojs/sitemap + JSON-LD structured data |
| 이미지 | astro:assets `<Image />` with Sharp optimization |
| 테스트 | Playwright (E2E + 비주얼) + Lighthouse CI + axe-core |
| 린팅 | ESLint v9 flat config (eslint-plugin-astro) |
| 배포 | Vercel / Netlify / CloudFlare Pages (static adapter) |

## 설치

이 플러그인은 GitHub 저장소를 통해 배포됩니다.

```
# 1. 저장소를 마켓플레이스 소스로 등록
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. 플러그인 설치 (프로젝트 범위 — .claude/settings.json에 저장, 팀과 공유)
/plugin install homepage-plugin@ohmyhotelco --scope project
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
/plugin disable homepage-plugin@ohmyhotelco
/plugin enable homepage-plugin@ohmyhotelco
```

**제거**:
```
/plugin uninstall homepage-plugin@ohmyhotelco --scope project
```

**플러그인 매니저 UI**: `/plugin`을 실행하면 탭 인터페이스(Discover, Installed, Marketplaces, Errors)가 열립니다.

## 빠른 시작

```
1. /homepage-plugin:hp-init                           # 플러그인 설정
2. /homepage-plugin:hp-plan                           # 대화형으로 페이지와 섹션 정의
3. /homepage-plugin:hp-gen                            # Astro 페이지 및 컴포넌트 생성
4. /homepage-plugin:hp-verify                         # 빌드 품질 검증 (선택사항)
5. /homepage-plugin:hp-review                         # SEO + 품질 코드 리뷰
6. /homepage-plugin:hp-fix {page}                     # 리뷰 이슈 수정 (해당 시)
```

## 스킬 레퍼런스

### `/homepage-plugin:hp-init`

**구문**: `/homepage-plugin:hp-init`

**사용 시점**: 프로젝트에서 최초 설정 시 또는 설정을 재구성할 때.

**동작 내용**:
1. 콘텐츠 전략 선택 (MDX, 헤드리스 CMS, 또는 둘 다)
2. i18n 로케일 및 기본 로케일 설정
3. 배포 대상 선택 (Vercel, Netlify, CloudFlare, static)
4. ESLint 템플릿 선호도 설정
5. `.claude/homepage-plugin.json` 파일 작성
6. 2개의 외부 스킬 설치 (Web Design Guidelines, Composition Patterns)
7. 다음 단계 안내 표시

---

### `/homepage-plugin:hp-plan`

**구문**: `/homepage-plugin:hp-plan [page-name]`

**사용 시점**: 홈페이지의 페이지와 섹션을 정의할 때. 코드 생성 전에 실행.

**동작 내용**:
1. 사이트 목적 질문 (기업 홈페이지, 제품 랜딩, 포트폴리오 등)
2. 필요한 페이지 질문 — 사이트 유형에 따른 기본값 제안
3. 각 페이지별로 표시할 콘텐츠 질문 — 사용자가 자연어로 설명
4. 설명을 15가지 표준 섹션 유형에 매칭 (섹션 카탈로그 참조)
5. 페이지별 섹션 구성 제안, 사용자 확인/수정
6. 공유 레이아웃 질문 (헤더/푸터 구조)
7. 선택적 Figma 참조 수집 (스크린샷 또는 URL) — 디자인 분석용
8. page-planner 에이전트 실행하여 페이지별 `page-plan.json` 생성
9. 페이지, 섹션, 공유 컴포넌트, 다음 단계 요약 표시

**재실행 지원**: 새 페이지 추가, 전체 교체, 또는 특정 페이지 편집 가능. `[page-name]` 인자를 사용하면 해당 페이지만 기획.

---

### `/homepage-plugin:hp-gen`

**구문**: `/homepage-plugin:hp-gen [page-name]`

**사용 시점**: `hp-plan`이 페이지 계획을 생성한 후.

**동작 내용**:
1. 페이지 계획을 검증하고 기존 생성 상태 확인 (재개 지원)
2. 동시 실행 방지를 위한 잠금 획득
3. 3개 단계를 순차적으로 실행, 각 단계는 별도 에이전트 세션에서 수행:

| 단계 | 에이전트 | 수행 내용 |
|-------|-------|-------------|
| 인프라 | page-assembler | Layout, header/footer, SEO utils, i18n, styles, Content Collections |
| 섹션 및 페이지 | section-generator + page-assembler | .astro 섹션, React islands, 페이지 조립 (페이지별) |
| 검증 | (직접) | TypeScript, ESLint, Astro build |

4. `generation-state.json`에 단계별 진행 상태 기록 (재개 지원)
5. 잠금 해제 및 진행 상태 업데이트

**재개 지원**: 생성이 중단되면 `hp-gen`을 다시 실행하면 완료된 단계를 감지하고 마지막 미완료 단계/페이지부터 재개를 제안합니다.

---

### `/homepage-plugin:hp-verify`

**구문**: `/homepage-plugin:hp-verify [page-name]`

**사용 시점**: 코드 생성 후 정확성을 검증할 때. 선택사항 — `hp-review`로 바로 진행해도 됩니다.

**동작 내용**:
1. TypeScript 컴파일러 실행 (`tsc`)
2. ESLint 실행 (필요 시 템플릿에서 설정 자동 생성)
3. Astro 빌드 실행 (`astro build`)
4. Lighthouse CI 실행 (성능/접근성/SEO >= 90 목표)
5. 각 게이트별 pass/fail 결과 보고
6. 각 게이트별 통과/실패 보고

---

### `/homepage-plugin:hp-review`

**구문**: `/homepage-plugin:hp-review [page-name]`

**사용 시점**: 코드 생성 후 (또는 이슈 수정 후) 코드 품질을 리뷰할 때.

**동작 내용**:
1. 동시 실행 방지를 위한 잠금 획득
2. **1단계 — SEO 리뷰**: seo-reviewer 에이전트가 메타데이터 완전성, 구조화 데이터, 제목 계층구조, 이미지 최적화, sitemap/robots, 성능 지표를 검사 (6개 차원, 0-10점)
3. **2단계 — 품질 리뷰** (SEO 통과 시에만): quality-reviewer 에이전트가 접근성 WCAG AA, 반응형 디자인, 컴포넌트 구성, TypeScript 엄격성, i18n 완전성, Astro 컨벤션을 검사 (6개 차원, 0-10점)
4. 병합된 리뷰 보고서를 이슈 상세(심각도, 파일, 줄, fixHint)와 함께 저장
5. 잠금 해제 및 진행 상태 업데이트

**상태 결과**:
- 모두 깨끗하게 통과 → `done`
- 경고와 함께 통과 → `reviewed`
- 하나라도 실패 → `review-failed`

---

### `/homepage-plugin:hp-fix`

**구문**: `/homepage-plugin:hp-fix <page-name>`

**사용 시점**: `hp-review`에서 이슈가 발견된 후.

**동작 내용**:
1. 사전 조건 검증 (페이지 계획, 리뷰 보고서, 진행 상태)
2. 동시 실행 방지를 위한 잠금 획득
3. review-fixer 에이전트 실행 — 모든 이슈에 대해 직접 수정 적용 (섹션이 프레젠테이션 위주이므로 TDD 분류 없음)
4. 수정 후 검증 실행 (tsc + ESLint + astro build)
5. 수정 보고서 표시 및 재리뷰 안내
6. 잠금 해제 및 진행 상태 업데이트

**수정 라운드**: 3라운드 후에도 이슈가 지속되면 경고. 계획 수정 또는 수동 개입을 제안.

## 전체 파이프라인 워크플로우

### 1단계: 초기화

```
/homepage-plugin:hp-init
```

콘텐츠 전략(MDX/헤드리스 CMS), i18n 로케일, 배포 대상, ESLint 선호도를 설정합니다. 접근성 및 컴포지션 패턴을 위한 외부 스킬을 설치합니다.

### 2단계: 페이지 및 섹션 정의

```
/homepage-plugin:hp-plan
```

page-planner 에이전트가 사용자의 자연어 설명과 선택적 Figma 참조를 구조화된 페이지 계획으로 종합합니다. 각 페이지 계획은 다음을 매핑합니다:

- 페이지 목적 → SEO 메타데이터 (title, description, OG tags, JSON-LD types)
- 콘텐츠 설명 → 표준 섹션 유형 (15개 내장 + 커스텀)
- 인터랙티브 요구사항 → React island 분류 (client:load vs client:visible)
- 공유 요소 → 레이아웃 구조 (header, footer, navigation)
- 번역 → i18n 네임스페이스 및 키 그룹

### 3단계: 코드 생성

```
/homepage-plugin:hp-gen
```

3단계의 코드 생성을 실행합니다:
1. **인프라** — 공유 레이아웃, header/footer, SEO 유틸리티, i18n 설정, Content Collection 설정
2. **섹션 및 페이지** — 페이지별: 섹션 생성 (.astro + React islands), SEO 메타데이터와 함께 페이지 조립
3. **검증** — TypeScript, ESLint, Astro build

### 4단계: 검증 (선택사항)

```
/homepage-plugin:hp-verify
```

Lighthouse CI 성능 예산(목표: 모든 카테고리 90 이상)을 포함한 전체 검증.

### 5단계: 리뷰

```
/homepage-plugin:hp-review
```

2단계 리뷰: SEO 준수를 먼저 확인(메타데이터, 구조화 데이터, 이미지, 성능), 그 다음 코드 품질(접근성, 반응형, TypeScript, i18n, Astro 컨벤션).

### 6단계: 수정 및 재리뷰

```
/homepage-plugin:hp-fix {page}
/homepage-plugin:hp-review {page}
```

리뷰가 통과할 때까지 반복합니다. fix 스킬은 직접 수정을 적용하고 각 배치 후 검증합니다.

## 에이전트

### Page Planner

**역할**: 사용자 입력 분석 → 페이지 계획 (`page-plan.json`).

분석 전용 에이전트 — 소스 코드를 생성하지 않습니다. 사용자의 페이지 설명, 섹션 선택, 선택적 Figma 참조를 구조화된 계획으로 종합합니다. 표준 패턴을 위해 섹션 카탈로그를 상호 참조하고 페이지 간 공유 섹션을 감지합니다. Opus 모델을 사용합니다.

### Section Generator

**역할**: `.astro` 섹션 + React island 생성.

페이지 계획에서 개별 섹션 컴포넌트를 생성합니다. 기본적으로 정적 `.astro` 파일을 생성하며, 인터랙티브 요소(폼, 캐러셀, 아코디언)에만 React `.tsx` island를 추가합니다. 필요한 shadcn/ui 컴포넌트를 설치하고 i18n 번역 키를 생성합니다.

### Page Assembler

**역할**: 섹션 조립 → 전체 페이지 + 인프라.

생성된 섹션을 레이아웃 통합, SEO 메타데이터 (`generateMetadata` 동등), JSON-LD 구조화 데이터, i18n 연결과 함께 완전한 Astro 페이지로 조립합니다. 첫 번째 페이지 생성 시 공유 인프라(레이아웃, header/footer, SEO 유틸리티, i18n 설정, Content Collections 설정)를 생성합니다.

### SEO Reviewer

**역할**: SEO 준수 리뷰 (6개 차원).

메타데이터 완전성, 구조화 데이터 유효성, 제목 계층구조, 이미지 최적화, sitemap/robots 커버리지, 성능 지표를 평가하는 읽기 전용 에이전트입니다. 각 차원을 0-10점으로 평가하고 상세 이슈(심각도, 파일, 줄, fixHint)를 제공합니다.

### Quality Reviewer

**역할**: 코드 품질 + 접근성 리뷰 (6개 차원).

접근성(WCAG 2.1 AA), 반응형 디자인, 컴포넌트 구성, TypeScript 엄격성, i18n 완전성, Astro 컨벤션 준수를 평가하는 읽기 전용 에이전트입니다. SEO 리뷰가 통과한 경우에만 실행됩니다.

### Review Fixer

**역할**: 리뷰 이슈 직접 수정.

리뷰어가 식별한 SEO 및 품질 이슈를 수정합니다. 홈페이지 섹션이 주로 프레젠테이션 위주이므로 모든 수정은 직접 수정(TDD 분류 없음)입니다. 이슈당 최대 3회 재시도. 해결 불가능한 이슈는 에스컬레이션합니다.

## 스킬

| 스킬 | 명령어 | 설명 |
|-------|---------|-------------|
| Init | `/homepage-plugin:hp-init` | 플러그인 설정 및 외부 스킬 설치 |
| Plan | `/homepage-plugin:hp-plan` | 대화형 페이지/섹션 정의 및 기획 |
| Gen | `/homepage-plugin:hp-gen` | Astro 페이지 및 섹션 생성 (3단계 파이프라인) |
| Verify | `/homepage-plugin:hp-verify` | TypeScript, ESLint, Astro build, Lighthouse CI 검증 |
| Review | `/homepage-plugin:hp-review` | 2단계 코드 리뷰 (SEO + 품질/접근성) |
| Fix | `/homepage-plugin:hp-fix` | 직접 수정으로 리뷰 이슈 해결 |

### 외부 스킬 (init으로 설치)

| 스킬 | 소스 | 설명 |
|-------|--------|-------------|
| Web Design Guidelines | `vercel-labs/agent-skills` | 접근성/디자인 감사 (100개 이상 규칙) |
| Composition Patterns | `vercel-labs/agent-skills` | 컴포넌트 컴포지션 패턴 (10개 규칙) |

## 설정

이 플러그인은 프로젝트 디렉토리의 `.claude/homepage-plugin.json`을 사용합니다 (`/homepage-plugin:hp-init`으로 생성):

```json
{
  "framework": "astro",
  "contentStrategy": "mdx",
  "i18nLocales": ["ko", "en"],
  "defaultLocale": "ko",
  "deployTarget": "aws",
  "eslintTemplate": true
}
```

| 필드 | 설명 | 기본값 |
|-------|-------------|---------|
| `framework` | 프레임워크 (향후 확장을 위해 예약) | `"astro"` |
| `contentStrategy` | 콘텐츠 관리 방식 (`"mdx"` \| `"headless-cms"` \| `"both"`) | `"mdx"` |
| `i18nLocales` | 지원 로케일 코드 | `["ko", "en"]` |
| `defaultLocale` | 기본 로케일 (사이트 및 스킬 출력 언어) | `"ko"` |
| `deployTarget` | 배포 대상 (`"aws"` \| `"vercel"` \| `"netlify"` \| `"cloudflare"` \| `"static"`) | `"aws"` |
| `eslintTemplate` | ESLint 설정이 없을 때 자동 생성 | `true` |

## 생성되는 프로젝트 구조

```
src/
├── pages/                          ← Astro file-based routing
│   ├── index.astro
│   ├── about.astro
│   └── blog/
│       ├── index.astro
│       └── [slug].astro
├── layouts/
│   └── MarketingLayout.astro       ← Header + Footer + <slot />
├── components/
│   ├── sections/                   ← .astro static sections
│   ├── islands/                    ← React interactive components (client: directives)
│   ├── ui/                         ← shadcn/ui components
│   └── layout/                     ← Header, Footer, Navigation
├── content/
│   ├── config.ts                   ← Content Collection schemas (Zod)
│   └── blog/                       ← MDX blog posts
├── i18n/                           ← Translation JSON files
├── lib/
│   ├── structured-data.ts          ← JSON-LD generators
│   └── cms.ts                      ← Headless CMS client (optional)
└── styles/
    └── globals.css
```

## 섹션 카탈로그

15가지 표준 마케팅 섹션을 제공합니다. `hp-plan`을 통해 커스텀 섹션도 지원됩니다.

| 섹션 | 유형 | 인터랙티브 요소 |
|---|---|---|
| HeroSection | Static | — |
| FeaturesSection | Static | — |
| TestimonialsSection | Island (optional) | Carousel |
| CTASection | Static | — |
| PricingSection | Island (optional) | Monthly/yearly toggle |
| FAQSection | Island | Accordion |
| StatsSection | Static | — |
| LogoCloudSection | Static | — |
| NewsletterSection | Island | Email form |
| ContactSection | Island | Contact form + validation |
| TeamSection | Static | — |
| TimelineSection | Static | — |
| GallerySection | Island (optional) | Lightbox |
| FooterSection | Static | — |
| HeaderSection | Island | Mobile navigation |

**Static** = `.astro` 컴포넌트, 빌드 시 정적 HTML로 렌더링 (JS 없음).
**Island** = `.astro` 래퍼 + React `.tsx` 컴포넌트, `client:load` 또는 `client:visible`로 하이드레이션.

## 상태 파일

`docs/pages/{page-name}/` 하위의 상태 파일:

| 파일 | 용도 |
|------|---------|
| `page-plan.json` | 섹션, SEO 메타데이터, i18n 설정을 포함한 페이지 계획 (hp-gen 입력) |
| `.progress/{page-name}.json` | 파이프라인 진행 상태 추적 |
| `.implementation/homepage/generation-state.json` | 타임스탬프 포함 단계별 진행 상태 (재개 지원) |
| `.implementation/homepage/review-report.json` | 병합된 리뷰 결과 (SEO + 품질) |
| `.implementation/homepage/fix-report.json` | 라운드 추적 포함 수정 결과 |
| `.implementation/homepage/.lock` | 동시 실행 방지 (30분 후 자동 만료) |

공유 레이아웃 계획: `docs/pages/_shared/layout-plan.json`

### 진행 상태 머신

```
planned → generated → verified → reviewed → done
             ↓            ↓         ↓
        gen-failed   verify-failed  review-failed
                                    ↓
                               fixing → (re-review)
                               escalated
```

### 상태 파일 안전성

- **잠금 메커니즘**: 상태 파일을 수정하는 스킬은 시작 전에 `.lock`을 획득합니다. 같은 페이지에서 hp-gen/hp-fix/hp-review의 동시 실행을 방지합니다. 오래된 잠금(30분 초과)은 자동 제거됩니다. 잠금 형식: `lockedBy`, `lockedAt`, `pageName`을 포함한 JSON.
- **Read-Modify-Write 규칙**: 쓰기 전에 항상 최신 파일 내용을 읽습니다. 변경된 필드만 병합 — 기존 필드를 모두 보존합니다.
- **재개 지원**: `generation-state.json`이 완료된 단계/페이지를 타임스탬프와 함께 추적하여 정확한 재개 감지가 가능합니다.
- **오래된 데이터 감지**: validate-pages.sh가 코드 생성 이후 페이지 계획이 수정되면 경고합니다.

## 훅

이 플러그인은 자동으로 실행되는 두 개의 라이프사이클 훅을 등록합니다:

### SessionStart — `session-init.sh`

Claude Code 세션이 시작될 때 실행됩니다. 다음을 확인합니다:
- **설정**: `.claude/homepage-plugin.json`을 로드하고 현재 설정을 보고
- **누락된 스킬**: 외부 스킬이 설치되지 않은 경우 경고
- **파이프라인 상태**: 모든 페이지를 스캔하고 현재 상태와 다음 단계 안내를 보고:
  - `planned` → `hp-gen` 제안
  - `generated` → `hp-verify` 또는 `hp-review` 제안
  - `gen-failed` → `hp-gen` 재시도 제안
  - `verify-failed` → 오류 확인 제안
  - `review-failed` → `hp-fix` 후 `hp-review` 제안
  - `fixing` → `hp-review` (재리뷰) 제안
  - `escalated` → 수동 개입 필요 경고
  - `done` → 완료 보고

### PostToolUse — `validate-pages.sh`

모든 `Write` 또는 `Edit` 도구 호출 후 실행됩니다. `docs/pages/` 하위 파일에서만 활성화:
- **오래된 데이터 감지**: 구현 상태가 계획 이후 단계인데 페이지 계획이나 상태 파일이 수정되면 생성된 코드가 동기화되지 않았을 수 있다고 경고

## 커뮤니케이션 언어

스킬은 설정 파일에서 `defaultLocale`을 읽습니다. 모든 사용자 대상 출력(요약, 질문, 피드백, 다음 단계 안내)은 설정된 로케일 언어로 제공됩니다.

언어 이름 매핑: `en` = English, `ko` = Korean, `vi` = Vietnamese.

## 팁 및 모범 사례

- **구조가 아닌 콘텐츠를 설명하세요** — `hp-plan`에서 페이지를 정의할 때 HTML 구조가 아닌 표시할 콘텐츠를 설명하세요("고객 후기", "가격표"). 플래너가 설명을 섹션 카탈로그에 매칭합니다.

- **Figma 참조를 제공하세요** — Figma 디자인이 있다면 `hp-plan`에 스크린샷을 전달하세요. AI 비전 분석이 구체적인 세부사항(색상, 간격, 콘텐츠)을 섹션 props로 추출합니다.

- **기본은 정적입니다** — 진정한 인터랙티비티가 필요하지 않다면 React islands를 요청하지 마세요. 정적 `.astro` 섹션은 JavaScript가 없어 최고의 Lighthouse 점수를 달성합니다.

- **배포 전 SEO를 리뷰하세요** — 배포 전에 항상 `hp-review`를 실행하세요. SEO 리뷰가 누락된 메타 태그, 깨진 구조화 데이터, 검색 순위에 직접 영향을 미치는 제목 계층구조 문제를 감지합니다.

- **수정 후 재리뷰를 건너뛰지 마세요** — `hp-fix` 이후 항상 `hp-review`를 실행하세요. 수정-리뷰 사이클이 회귀를 방지합니다.

- **재개는 안전합니다** — 생성이 중단되면 `hp-gen`을 다시 실행하기만 하면 됩니다. 완료된 단계와 페이지를 감지하고 마지막 미완료 지점부터 재개합니다.

- **잠금이 상태를 보호합니다** — 같은 페이지에서 `hp-gen`과 `hp-fix`를 동시에 실행하지 마세요. 잠금 메커니즘이 상태 파일 손상을 방지합니다.

- **페이지를 점진적으로 추가하세요** — 초기 생성 후, `hp-plan {page-name}`을 사용하여 기존 페이지에 영향을 주지 않고 새 페이지를 하나씩 추가하세요.

## 로드맵

- [x] 기술 스택 명세 (Astro 5 + Tailwind + shadcn/ui)
- [x] 섹션 카탈로그 (15가지 표준 마케팅 섹션)
- [x] 대화형 페이지 기획 (hp-plan)
- [x] 코드 생성 (3단계 파이프라인)
- [x] SEO 검증 (Lighthouse CI)
- [x] 2단계 코드 리뷰 (SEO + 품질/접근성)
- [x] 수정 스킬 (직접 수정)
- [x] 상태 일관성 (잠금, 타임스탬프, 재개)
- [x] 훅 핸들러 (session-init, page validation)
- [ ] Figma MCP 통합 (자동 디자인 동기화)
- [ ] 블로그 템플릿 라이브러리 (사전 구축된 MDX 레이아웃)
- [ ] CMS 어댑터 템플릿 (Sanity, Contentful)
- [ ] 성능 모니터링 통합 (Web Analytics, Sentry)

## 디렉토리 구조

```
agents/          에이전트 정의 (page-planner, section-generator, page-assembler,
                 seo-reviewer, quality-reviewer, review-fixer)
skills/          스킬 진입점 (hp-init, hp-plan, hp-gen, hp-verify, hp-review, hp-fix)
hooks/           라이프사이클 훅 설정
scripts/         훅 핸들러 스크립트 (session-init.sh, validate-pages.sh)
templates/       템플릿 파일 (section-catalog, page-module, seo-checklist, eslint-config, astro-conventions)
docs/            문서
```

## 저자

Justin Choi — Ohmyhotel & Co
