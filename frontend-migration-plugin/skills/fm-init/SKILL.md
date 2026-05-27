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

Install (or verify) the skills the pipeline loads per phase. Do **not** auto-install npm
dependencies — display the commands and let the user run them.

- **Playwright** — E2E + visual regression (`npx playwright install` for browsers).
- **Vitest** — unit/component TDD.
- **React Router** mode skill — routing patterns for the target `routerMode`.

If a skill or its CLI is missing, list it and the install command; do not fail setup.

### Step 7: Report

Summarize in `workingLanguage`:
- Config path and key values (apps, currentApp, workingLanguage).
- Tracker location.
- Any missing external skills / CLIs with install hints.
- Next step: `Run /frontend-migration-plugin:fm-analyze <target>` once the analyzer
  (AA-41) is available, or `/frontend-migration-plugin:fm-secret-audit` for the Phase 0
  security pre-work.
