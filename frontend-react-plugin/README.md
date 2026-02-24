# Frontend React Plugin

> **Ohmyhotel & Co** — Claude Code plugin for frontend React development

## What It Does

This Claude Code plugin assists with frontend React development tasks. Agents, skills, and templates will be added incrementally.

## Tech Stack

| Category | Technology |
|----------|-----------|
| Runtime | Node.js 22.x LTS |
| Framework | React 19 + TypeScript |
| Build | Vite |
| Routing | React Router v7 (Declarative) |
| UI | Tailwind CSS + shadcn/ui + Lucide |
| State | Zustand |
| HTTP | Axios (JWT, 401/403 interceptors) |
| i18n | i18next (ko/en/ja/vi) |
| Testing | Vitest + Playwright |

## Installation

This plugin is distributed via a GitHub repository.

```
# 1. Register the repo as a marketplace source
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. Install the plugin (project scope)
/plugin install frontend-react-plugin@ohmyhotelco --scope project
```

Verify the installation:
```
/plugin
```

## Update & Management

```
# Update marketplace to pull the latest plugin versions
/plugin marketplace update ohmyhotelco

# Disable / Enable
/plugin disable frontend-react-plugin@ohmyhotelco
/plugin enable frontend-react-plugin@ohmyhotelco

# Uninstall
/plugin uninstall frontend-react-plugin@ohmyhotelco --scope project
```

## Skills

| Skill | Command | Description |
|-------|---------|-------------|
| Init | `/frontend-react-plugin:init` | 플러그인 설정 및 외부 스킬 일괄 설치 |
| Plan | `/frontend-react-plugin:plan` | 기능 명세 분석 → 구현 계획서 생성 |
| Gen | `/frontend-react-plugin:gen` | 구현 계획서 기반 → 프로덕션 코드 생성 |

### External Skills (installed by init)

| Skill | Source | Description |
|-------|--------|-------------|
| React Router v7 | `remix-run/agent-skills` | 라우팅 패턴 (모드별) |
| Vitest | `supabase/supabase` | 테스트 패턴 |
| React Best Practices | `vercel-labs/agent-skills` | React 성능 최적화 (57 rules) |
| Composition Patterns | `vercel-labs/agent-skills` | 컴포넌트 구성 패턴 (10 rules) |
| Web Design Guidelines | `vercel-labs/agent-skills` | 접근성/디자인 감사 (100+ rules) |

## Code Generation Workflow

1. planning-plugin으로 기능 명세 작성 → `docs/specs/{feature}/`
2. (권장) `/planning-plugin:design {feature}` → UI DSL + 프로토타입 생성
3. `/frontend-react-plugin:plan {feature}` → 구현 계획서 생성 + 검토
4. `/frontend-react-plugin:gen {feature}` → 프로덕션 코드 생성

## Roadmap

- [x] Tech stack specification
- [x] React Router routing skill
- [x] External skills integration (vercel-labs/agent-skills)
- [x] Code generation agent
- [ ] Component template library
- [ ] i18n setup skill
- [ ] Auth/RBAC pattern templates
- [ ] Hook handlers (lint, type-check)

## Directory Structure

```
agents/          Agent definitions
skills/          Skill entry points
hooks/           Lifecycle hook configuration
scripts/         Hook handler scripts
templates/       Template files
docs/            Documentation
```

## Author

Justin Choi — Ohmyhotel & Co
