# Homepage Plugin

Astro 5, Tailwind CSS, shadcn/ui, SEO 최적화를 활용한 회사 마케팅 및 홈페이지 웹사이트 구축을 위한 Claude Code 플러그인입니다.

## 빠른 시작

```bash
# 1. 플러그인 설정 초기화
/homepage-plugin:hp-init

# 2. 페이지와 섹션을 대화형으로 정의
/homepage-plugin:hp-plan

# 3. Astro 페이지 및 컴포넌트 생성
/homepage-plugin:hp-gen

# 4. 빌드 품질 검증
/homepage-plugin:hp-verify

# 5. SEO + 코드 품질 리뷰
/homepage-plugin:hp-review

# 6. 리뷰 이슈 수정 (필요 시)
/homepage-plugin:hp-fix
```

## 아키텍처

### 파이프라인

```
hp-init → hp-plan → hp-gen → hp-verify → hp-review → hp-fix
                                                       ↓
                                                  hp-review (재리뷰)
```

### 스킬

| 스킬 | 커맨드 | 역할 |
|---|---|---|
| hp-init | `/homepage-plugin:hp-init` | 프로젝트 설정 (콘텐츠 전략, i18n, 배포 대상) |
| hp-plan | `/homepage-plugin:hp-plan [page]` | 대화형 페이지/섹션 정의 |
| hp-gen | `/homepage-plugin:hp-gen [page]` | Astro 페이지 및 섹션 생성 (3단계) |
| hp-verify | `/homepage-plugin:hp-verify [page]` | 빌드 + Lighthouse + 접근성 검증 |
| hp-review | `/homepage-plugin:hp-review [page]` | 2단계 코드 리뷰 (SEO + 품질) |
| hp-fix | `/homepage-plugin:hp-fix <page>` | 리뷰 이슈 수정 |

### 에이전트

| 에이전트 | 모델 | 역할 |
|---|---|---|
| page-planner | Opus | 설명/Figma 분석 → page-plan.json |
| section-generator | Opus | .astro 섹션 + React island 생성 |
| page-assembler | Opus | 섹션 조립 → 페이지 + SEO + i18n |
| seo-reviewer | Sonnet | 6차원 SEO 감사 |
| quality-reviewer | Sonnet | 6차원 품질 + 접근성 감사 |
| review-fixer | Opus | 리뷰 이슈 직접 수정 |

## 기술 스택

| 영역 | 기술 |
|---|---|
| 프레임워크 | Astro 5.x (SSG + islands 아키텍처) |
| 언어 | TypeScript (strict) |
| 스타일링 | Tailwind CSS |
| 컴포넌트 | shadcn/ui + Lucide 아이콘 (자사 디자인 시스템으로 교체 가능) |
| 콘텐츠 | Astro Content Collections + MDX, 선택적 Headless CMS |
| i18n | Astro 내장 i18n 라우팅 |
| SEO | 정적 HTML + @astrojs/sitemap + JSON-LD |
| 테스트 | Vitest + Playwright + Lighthouse CI + axe-core |
| 린팅 | ESLint v9 flat config |

## 설정

`.claude/homepage-plugin.json` (hp-init으로 생성):

```json
{
  "framework": "astro",
  "contentStrategy": "mdx",
  "i18nLocales": ["ko", "en"],
  "defaultLocale": "ko",
  "deployTarget": "vercel",
  "eslintTemplate": true
}
```

## 섹션 카탈로그

15개 마케팅 섹션 지원:

| 섹션 | 타입 | 인터랙티브 |
|---|---|---|
| HeroSection | 정적 | — |
| FeaturesSection | 정적 | — |
| TestimonialsSection | Island (선택) | Carousel |
| CTASection | 정적 | — |
| PricingSection | Island (선택) | Toggle |
| FAQSection | Island | Accordion |
| StatsSection | 정적 | — |
| LogoCloudSection | 정적 | — |
| NewsletterSection | Island | Form |
| ContactSection | Island | Form |
| TeamSection | 정적 | — |
| TimelineSection | 정적 | — |
| GallerySection | Island (선택) | Lightbox |
| FooterSection | 정적 | — |
| HeaderSection | Island | Mobile nav |

`hp-plan`에서 커스텀 섹션도 지원합니다.

## 통신 언어

스킬은 설정의 `defaultLocale`을 읽습니다:
- `ko` → 한국어
- `en` → 영어
- `vi` → 베트남어
