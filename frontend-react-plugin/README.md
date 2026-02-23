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
| React Router | `/frontend-react-plugin:react-router` | React Router v7 Declarative 모드 라우팅 패턴, 네비게이션, URL 값, 인증/RBAC 라우트 가드 |

## Roadmap

- [x] Tech stack specification
- [x] React Router routing skill
- [ ] Code generation agent
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
