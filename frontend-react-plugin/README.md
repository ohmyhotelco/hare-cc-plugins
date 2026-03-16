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
| Init | `/frontend-react-plugin:fe-init` | Plugin setup and batch installation of external skills |
| Plan | `/frontend-react-plugin:fe-plan` | Analyze functional spec and generate implementation plan |
| Gen | `/frontend-react-plugin:fe-gen` | Generate production code based on implementation plan |
| Verify | `/frontend-react-plugin:fe-verify` | Run TypeScript, build, and test verification on generated code |
| Review Code | `/frontend-react-plugin:fe-review` | 2-stage code review (spec compliance + quality) |
| Debug | `/frontend-react-plugin:fe-debug` | Systematic debugging with hypothesis testing and escalation |

### External Skills (installed by init)

| Skill | Source | Description |
|-------|--------|-------------|
| React Router v7 | `remix-run/agent-skills` | Routing patterns (per mode) |
| Vitest | `antfu/skills` | Testing patterns |
| React Best Practices | `vercel-labs/agent-skills` | React performance optimization (57 rules) |
| Composition Patterns | `vercel-labs/agent-skills` | Component composition patterns (10 rules) |
| Web Design Guidelines | `vercel-labs/agent-skills` | Accessibility/design audit (100+ rules) |

## Code Generation Workflow

1. Write functional spec using planning-plugin → `docs/specs/{feature}/`
2. (Recommended) `/planning-plugin:design {feature}` → Generate UI DSL + prototype
3. `/frontend-react-plugin:fe-plan {feature}` → Generate implementation plan + review
4. `/frontend-react-plugin:fe-gen {feature}` → Generate production code

## Roadmap

- [x] Tech stack specification
- [x] React Router routing skill
- [x] External skills integration (vercel-labs/agent-skills)
- [x] Code generation agent
- [x] Verification skill
- [x] Code review skill (spec compliance + quality)
- [x] Debug skill (systematic debugging)
- [ ] Component template library
- [ ] i18n setup skill
- [ ] Auth/RBAC pattern templates
- [x] Hook handlers (session-init, implementation validation)

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
