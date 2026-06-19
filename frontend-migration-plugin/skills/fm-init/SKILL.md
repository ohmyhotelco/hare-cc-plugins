---
name: fm-init
description: "Use when setting up Frontend Migration Plugin for a project — detects the legacy Angular apps and monorepo layout, writes the plugin config, and initializes the migration tracker."
argument-hint: ""
user-invocable: true
allowed-tools: Read, Write, Glob, Bash
---

# Initialize Frontend Migration Plugin

Set up `.claude/frontend-migration-plugin.json` and the migration tracker for this project,
detecting the legacy Angular apps and the v2 monorepo layout.

All user-facing output in this skill is in the configured `workingLanguage` (default `ko`).

## Instructions

### Step 1: Check Existing Configuration

1. Check if `.claude/frontend-migration-plugin.json` already exists.
2. If it exists, show the current config and ask whether to reconfigure (overwrite). If the
   user declines, stop here.

### Step 2: Detect the Monorepo Layout

1. Determine `monorepoRoot` (default: current directory `.`).
2. Glob for candidate app directories and shared packages:
   - Legacy Angular: directories containing `angular.json` or `src/app/` with Angular
     modules (e.g. `apps/legacy-pc`, `apps/legacy-mobile`).
   - New RR v7 targets: directories with `react-router.config.*` or a Vite + RR v7 setup
     (e.g. `apps/web-pc`, `apps/web-mobile`, `apps/web-hana`). These may not exist yet —
     that is expected before the migration starts.
   - `packagesDir` (default `packages`).
3. Present what was detected and let the user confirm or correct each path.

### Step 3: Configure Apps

For each surface (`pc`, `mobile`, `hana`), gather:

- `legacyDir`, `targetDir`, `appDir` (the dir holding `vite.config.*`/`tsconfig.json`/
  `package.json`; defaults to `targetDir`)
- `domain`, `port`
- `ssr` — `mixed` (PC, Mobile) | `spa` (Hana)
- `webview` — `false` (PC) | `true` (Mobile) | `"unknown"` (Hana, pending confirmation)
- `sso` — `true` (Hana) | `false`

PC-first: configure `pc` fully. Offer sensible defaults for `mobile`/`hana` (scaffolded,
validated later) from the migration plan topology. Do not block setup on Mobile/Hana
details — they can be refined when those phases begin.

### Step 4: Other Settings

- `currentApp` — default `pc`.
- `workingLanguage` — `ko` (default) | `en` | `vi`.
- `externalSkills` — default `true` (install Playwright, Vitest, React Router skills in
  Step 6).
- `eslintTemplate` — default `true`. When `true`, generators auto-scaffold `eslint.config.js`
  from `templates/eslint-config.md` where none exists (ESLint is a hard verify check). `false`
  skips ESLint. See CLAUDE.md → "Lint & Format Gate".
- `prettierTemplate` — default `true`. When `true`, generators auto-scaffold `prettier.config.js`
  from `templates/prettier-config.md` where none exists (Prettier is advisory only). `false`
  skips formatting.
- `codexAudit` — default `true`. When `true`, the pipeline runs an independent **Codex audit** of
  each stage's artifact (advisory; auto-skips if Codex is absent). See CLAUDE.md → "Codex
  Independent Audit". Detect the Codex CLI/runtime here (e.g. `command -v codex`); if absent, warn
  that audits will be skipped (do not fail setup, record the flag regardless).
- `codexAuditStages` — default all seven stages (`analyze`, `plan`, `gen`, `verify`, `e2e`,
  `parity`, `route`). Narrows which stages the in-loop Codex audit covers.
- `stagingConfig` — the staging `baseUrl` + payment-gateway **test** endpoints (`nicePay` /
  `eximbay` / `kakaoPay`, OMH-459) that `fm-e2e` hands to `e2e-test-runner` for transactional
  scenarios (never production). Scaffold it empty for PC-first; offer to fill it when a
  transactional page is reached. See CLAUDE.md → "Configuration".

### Step 5: Write Config and Initialize Tracker

1. Write `.claude/frontend-migration-plugin.json` with the gathered values (schema in the
   plugin `CLAUDE.md` → "Configuration").
2. Create `docs/migration/tracker.json` if absent:
   ```json
   {
     "apps": { "pc": { "pages": {} }, "mobile": { "pages": {} }, "hana": { "pages": {} } },
     "packages": {},
     "updatedAt": "{ISO timestamp}"
   }
   ```
3. Create the `docs/migration/` directory tree as needed.

### Step 6: Install External Skills (when `externalSkills` is true)

Install the shared skills the pipeline loads per phase, using the **same mechanism as
`frontend-react-plugin`'s `fe-init`** (`npx skills add … -a claude-code -y --copy` — vendored
into `.claude/skills/`). For each row, check the Check Path first; install only if missing, then
verify. Do **not** auto-install npm dependencies — display the commands and let the user run them.

| Skill | Check Path | Install Command |
| --- | --- | --- |
| React Router (framework mode) | `.claude/skills/react-router-framework-mode/SKILL.md` | `npx skills add remix-run/agent-skills --skill react-router-framework-mode -a claude-code -y --copy` |
| Vitest | `.claude/skills/vitest/SKILL.md` | `npx skills add antfu/skills --skill vitest -a claude-code -y --copy` |
| React Best Practices | `.claude/skills/vercel-react-best-practices/SKILL.md` | `npx skills add vercel-labs/agent-skills --skill vercel-react-best-practices -a claude-code -y --copy` |
| Composition Patterns | `.claude/skills/vercel-composition-patterns/SKILL.md` | `npx skills add vercel-labs/agent-skills --skill vercel-composition-patterns -a claude-code -y --copy` |

For each row: (1) check whether the Check Path file exists, (2) if missing run the Install
Command, (3) verify installation succeeded.

> React Router uses the **framework-mode** skill (not `declarative`/`data`, which are
> `frontend-react-plugin`'s library-mode skills) — this migration's target is RR v7 framework mode
> with per-route SSR/SSG/SPA, so there is no `routerMode` to interpolate.

**Playwright** is a CLI, not a skill — verify it and install browsers separately (E2E +
visual-regression gates depend on it):
```bash
npx playwright install   # browsers
```
Trace analysis is built into the CLI (`npx playwright show-trace <trace.zip>`) — the agent's
DevTools for `fm-fix` (e2e-fix), no install needed. Note: Playwright's own **test agents**
(planner / generator / healer, via `npx playwright init-agents --loop=claude`) install to
`.claude/agents/` plus a Playwright MCP `.mcp.json` — they are a **separate subagent system, not a
loadable skill**, and this plugin does **not** adopt them (it already has equivalents —
`migration-planner` / `e2e-test-runner` / `migration-fixer` — plus the legacy dual-run the healer
cannot do). See CLAUDE.md → "External Skills".

The agents load each SKILL.md **per phase**, guarded by existence (vitest → all TDD phases;
`vercel-composition-patterns` → components; `vercel-react-best-practices` → pages, applied
**SSR-aware** because framework mode is not a Vite SPA; `react-router-framework-mode` →
routing/integration). If a skill or its CLI is missing, list it with its install command; never
fail setup — an absent skill is skipped, not an error.

### Step 7: Report

Summarize in `workingLanguage`:
- Config path and key values (apps, currentApp, workingLanguage).
- Tracker location.
- Any missing external skills / CLIs with install hints.
- Next step: `Run /frontend-migration-plugin:fm-analyze <target>` once the analyzer
  (AA-41) is available, or `/frontend-migration-plugin:fm-secret-audit` for the Phase 0
  security pre-work.
