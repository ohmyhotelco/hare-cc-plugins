# Frontend React Plugin

> **Ohmyhotel & Co** — Claude Code plugin for frontend React development with TDD

## What It Does

This Claude Code plugin generates production-ready React code from functional specifications using strict Test-Driven Development. It provides a complete pipeline from implementation planning through code generation, verification, review, and fix — all with TDD discipline.

Key capabilities:
- **TDD code generation** — 6-phase pipeline (foundation → API → store → component → page → integration) with strict Red-Green-Refactor per phase
- **Spec-driven planning** — Analyze functional specs (from planning-plugin) and produce structured implementation plans
- **Standalone mode** — Generate plans without planning-plugin by gathering requirements interactively
- **Automated review** — 2-stage code review (spec compliance + quality) with 12 scoring dimensions
- **TDD fix** — Fix review issues with test-first discipline for behavioral changes
- **State consistency** — Lock mechanism, phase timestamps, and staleness detection across the pipeline

## Architecture Overview

```
/frontend-react-plugin:fe-init → .claude/frontend-react-plugin.json
        │
        ▼
/frontend-react-plugin:fe-plan "feature" [--standalone]
        │
        ├── spec mode: reads planning-plugin output
        │   └── implementation-planner agent → plan.json
        │
        ├── standalone mode: interactive requirements gathering
        │   └── generates minimal spec stub → implementation-planner agent → plan.json
        │
        ├── incremental mode: detects spec changes after implementation
        │   └── implementation-planner agent → delta-plan.json (affected files only)
        │
        ▼
/frontend-react-plugin:fe-gen "feature"
        │
        ├── Phase 1: Foundation     — types + mocks (foundation-generator)
        ├── Phase 2: API TDD        — RED: tests → GREEN: services (tdd-cycle-runner)
        ├── Phase 3: Store TDD      — RED: tests → GREEN: stores (tdd-cycle-runner)
        ├── Phase 4: Component TDD  — RED: tests → GREEN: components (tdd-cycle-runner)
        ├── Phase 5: Page TDD       — RED: tests → GREEN: pages (tdd-cycle-runner)
        └── Phase 6: Integration    — routes + i18n + MSW setup (integration-generator)
        │
        ▼
/frontend-react-plugin:fe-verify "feature" (optional)
        │
        ▼
Loop 1 — Code Quality:
/frontend-react-plugin:fe-review "feature"
        │
        ├── Stage 1: spec-reviewer → spec compliance
        └── Stage 2: quality-reviewer → code quality
        │
        ▼ (if issues found)
/frontend-react-plugin:fe-fix "feature"
        │
        └── review-fixer agent → TDD fixes + direct fixes
        │
        ▼
/frontend-react-plugin:fe-review "feature" (re-review until pass)
        │
        ▼ (quality pass)
Loop 2 — E2E:
/frontend-react-plugin:fe-e2e "feature"
        │
        └── e2e-test-runner agent → agent-browser drives browser scenarios
        │
        ▼ (if failures)
/frontend-react-plugin:fe-fix "feature" (auto-detects E2E mode)
        │
        ▼
/frontend-react-plugin:fe-e2e "feature" (re-run until pass)
```

## Tech Stack

| Category | Technology |
|----------|-----------|
| Runtime | Node.js 22.x LTS (>= 22.12) |
| Package Manager | pnpm |
| Framework | React 19 + TypeScript (strict) |
| Build | Vite |
| Routing | React Router v7 (declarative or data mode) |
| UI | Tailwind CSS + shadcn/ui + Lucide |
| State | Zustand |
| HTTP | Axios (JWT, 401/403 interceptors) |
| Mock | MSW v2 (dev & test — network-level intercept) |
| i18n | i18next + react-i18next (ko/en/ja/vi) |
| Testing | Vitest + @testing-library/react + agent-browser (E2E) |

## Installation

This plugin is distributed via a GitHub repository.

```
# 1. Register the repo as a marketplace source
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. Install the plugin (project scope — saved to .claude/settings.json, shared with the team)
/plugin install frontend-react-plugin@ohmyhotelco --scope project
```

Verify the installation:
```
/plugin
```

## Update & Management

**Update marketplace** to pull the latest plugin versions:
```
/plugin marketplace update ohmyhotelco
```

**Disable / Enable** a plugin without uninstalling:
```
/plugin disable frontend-react-plugin@ohmyhotelco
/plugin enable frontend-react-plugin@ohmyhotelco
```

**Uninstall**:
```
/plugin uninstall frontend-react-plugin@ohmyhotelco --scope project
```

**Plugin manager UI**: Run `/plugin` to open the tabbed interface (Discover, Installed, Marketplaces, Errors).

## Quick Start

### Option A — With planning-plugin (recommended)

Get from zero to generated code in 5 steps:

```
1. /frontend-react-plugin:fe-init                     # configure plugin
2. /planning-plugin:init                               # configure planning
3. /planning-plugin:spec "feature description"         # generate spec
4. /frontend-react-plugin:fe-plan {feature}            # create implementation plan
5. /frontend-react-plugin:fe-gen {feature}             # generate code (TDD)
```

### Option B — Standalone (without planning-plugin)

Generate code without a functional spec:

```
1. /frontend-react-plugin:fe-init                      # configure plugin
2. /frontend-react-plugin:fe-plan {feature} --standalone   # interactive requirements → plan
3. /frontend-react-plugin:fe-gen {feature}             # generate code (TDD)
```

Standalone mode gathers requirements interactively (description, entities, screens) and generates a minimal spec stub + plan.json. Limitations: no error codes, validation rules, test scenario references (TS-nnn), or UI DSL.

## Skills Reference

### `/frontend-react-plugin:fe-init`

**Syntax**: `/frontend-react-plugin:fe-init`

**When to use**: First-time setup in a project, or reconfiguring settings.

**What happens**:
1. Prompts for React Router mode (declarative or data)
2. Prompts for mock-first development (MSW v2, default: enabled)
3. Prompts for base source directory (default: `app/src`)
4. Prompts for ESLint template usage (auto-generate `eslint.config.js` if none exists, default: enabled)
5. Writes `.claude/frontend-react-plugin.json`
6. Installs 6 external skills (React Router, Vitest, React Best Practices, Composition Patterns, Web Design Guidelines, Agent Browser)
7. Displays next-step options (with or without planning-plugin)

---

### `/frontend-react-plugin:fe-plan`

**Syntax**: `/frontend-react-plugin:fe-plan <feature-name> [--standalone]`

**When to use**: After creating a functional spec, or standalone when no spec exists.

**What happens**:
1. **Spec mode** (default): reads the planning-plugin spec and UI DSL, detects shared layouts, analyzes existing project patterns
2. **Standalone mode** (`--standalone`): gathers requirements interactively (description, entities, screens, language), generates a minimal spec stub
3. **Incremental mode** (auto-detected): when existing plan.json + generated code exist, offers to detect spec changes and produce a delta plan instead of regenerating from scratch
4. **Auto-detection**: if no spec found and `--standalone` not specified, offers a choice between standalone mode and creating a spec first
5. Launches the implementation-planner agent to produce `plan.json` (or `delta-plan.json` in incremental mode)
6. Displays plan summary (files, TDD phases, shadcn/ui dependencies)
7. Updates progress file with `planned` status (or preserves existing status in incremental mode)

The planner agent analyzes:
- Existing project patterns (directory structure, path aliases, route files, i18n config, stores, API services, MSW setup, test infrastructure)
- Spec entities → types, API services, stores
- Spec screens → components, pages, routes, i18n keys
- Spec test scenarios → test file plan with TS-nnn traceability
- shadcn/ui gaps → installation commands

---

### `/frontend-react-plugin:fe-gen`

**Syntax**: `/frontend-react-plugin:fe-gen <feature-name>`

**When to use**: After `fe-plan` produces a plan.json.

**What happens**:
1. Validates plan and checks for existing generation state (resume support)
2. Acquires a lock to prevent concurrent operations on the same feature
3. Executes 6 TDD phases sequentially, each in a separate agent session:

| Phase | Agent | What it does |
|-------|-------|-------------|
| Foundation | foundation-generator | Types, mock factories/fixtures/handlers, shared layouts |
| API TDD | tdd-cycle-runner | RED: API tests → GREEN: API services |
| Store TDD | tdd-cycle-runner | RED: store tests → GREEN: Zustand stores |
| Component TDD | tdd-cycle-runner | RED: component tests → GREEN: components |
| Page TDD | tdd-cycle-runner | RED: page tests → GREEN: pages (4-state) |
| Integration | integration-generator | Routes, i18n, MSW global setup, barrel exports |

4. Each TDD phase tracks `completedAt` timestamps for precise resume support
5. Displays comprehensive results with test pass rates and file lists
6. Releases the lock and updates progress

**Delta mode**: When a `delta-plan.json` exists (created by `fe-plan` in incremental mode), `fe-gen` offers to execute only the affected phases and files. Unchanged phases are skipped entirely. Modifications use the delta-modifier agent; new files use tdd-cycle-runner with scoped inputs.

**Resume support**: If generation is interrupted, re-running `fe-gen` detects the existing state and offers to resume from the last incomplete phase. Plan freshness is checked at the phase level — if `plan.json` was modified after a specific phase completed, you can choose to re-run from that phase onward.

**On failure**: Each phase offers retry, skip, or stop options. Skipped or failed phases result in `gen-failed` status (prevents incomplete code from entering the review pipeline).

---

### `/frontend-react-plugin:fe-verify`

**Syntax**: `/frontend-react-plugin:fe-verify <feature-name>`

**When to use**: After code generation to verify correctness. Optional — you can go directly to `fe-review`.

**What happens**:
1. Runs TypeScript compiler (`tsc`)
2. Runs ESLint (if configured)
3. Runs Vite build
4. Runs Vitest
5. Reports pass/fail for each gate

---

### `/frontend-react-plugin:fe-review`

**Syntax**: `/frontend-react-plugin:fe-review <feature-name>`

**When to use**: After code generation (or after fixing issues) to review code quality.

**What happens**:
1. Acquires a lock to prevent concurrent operations
2. Checks spec staleness (warns if spec was modified after generation)
3. **Stage 1 — Spec Review**: spec-reviewer agent checks requirement coverage, UI fidelity, i18n completeness, accessibility, route coverage (5 dimensions, scored 1-10)
4. **Stage 2 — Quality Review** (only when spec review passes): quality-reviewer agent checks single responsibility, consistent patterns, no hardcoded strings, error handling, TypeScript strictness, convention compliance, architecture (7 dimensions, scored 1-10)
5. Saves review report with complete issue details (enriched with refs, fixHints, missingArtifact)
6. Releases the lock and updates progress

**Status outcomes**:
- Both pass clean → `done`
- Pass with warnings → `reviewed`
- Either fails → `review-failed`

---

### `/frontend-react-plugin:fe-fix`

**Syntax**: `/frontend-react-plugin:fe-fix <feature-name>`

**When to use**: After `fe-review` finds issues.

**What happens**:
1. Validates prerequisites (plan, review report, status)
2. Detects source code changes since last review (warns about potentially already-resolved issues)
3. Acquires a lock to prevent concurrent operations
4. Classifies issues into fix strategies:
   - **TDD-required**: Behavioral changes — writes test first, then fixes
   - **Direct-fix**: Mechanical changes (typos, missing imports) — fixes directly
   - **Regen-required**: Entire files missing — marks phases for `fe-gen` re-run
5. Launches review-fixer agent
6. Displays fix report with test counts and file changes
7. Guides re-review and releases lock

**Fix rounds**: Warns after 3 rounds if issues persist. Suggests plan revision or debugging.

---

### `/frontend-react-plugin:fe-e2e`

**Syntax**: `/frontend-react-plugin:fe-e2e <feature-name>`

**When to use**: After `fe-review` passes (Loop 2 entry point). Runs end-to-end browser tests.

**What happens**:
1. Validates prerequisites (plan, generated code, E2E scenarios in plan.json, agent-browser CLI)
2. Validates E2E scenario URLs against defined routes
3. Starts a Vite dev server with `VITE_ENABLE_MOCKS=true`
4. Runs a runtime health check (verifies app loads without errors)
5. Launches the e2e-test-runner agent to drive browser scenarios
6. Stops the dev server and displays E2E results
7. Updates progress file with E2E status

**E2E fix loop**: If scenarios fail, run `fe-fix` (auto-detects E2E mode) then re-run `fe-e2e`. Repeat until all scenarios pass.

---

### `/frontend-react-plugin:fe-debug`

**Syntax**: `/frontend-react-plugin:fe-debug <feature-name>`

**When to use**: For runtime bugs or complex issues at any point in the pipeline.

**What happens**:
1. Launches the debugger agent with a 4-phase methodology:
   - **Root Cause Investigation**: Analyze errors, trace code paths, compare against spec/plan
   - **Pattern Analysis**: Search for same-pattern bugs, classify issue type (generation-bug, plan-bug, spec-bug, environment)
   - **Hypothesis Testing**: Formulate up to 3 hypotheses and test sequentially (3-strike escalation)
   - **Implementation**: Apply minimal TDD fix with verification
2. If all 3 hypotheses fail, escalates with structural analysis and recommendations

---

### `/frontend-react-plugin:fe-progress`

**Syntax**: `/frontend-react-plugin:fe-progress [feature-name]`

**When to use**: At any time to check the current pipeline status.

**What happens**:
- **With feature name**: Shows detailed status — implementation status, TDD phase completion, verification results, review scores, fix rounds, E2E results, delta history, spec staleness check, and next-step guidance.
- **Without feature name**: Shows a summary table of all features with status, generation progress, review scores, fix rounds, E2E results, and delta state.

## Full Pipeline Workflow

### Step 1: Initialize

```
/frontend-react-plugin:fe-init
```

Sets router mode (declarative/data), mock-first toggle, and base directory. Installs external skills for routing, testing, performance, composition, and accessibility.

### Step 2: Create Implementation Plan

```
/frontend-react-plugin:fe-plan {feature}
```

The implementation-planner agent reads the functional spec (or gathers requirements in standalone mode) and analyzes your existing project to produce `plan.json`. The plan maps every spec element to concrete files:

- Entities → TypeScript interfaces + DTOs
- CRUD operations → Axios service modules
- Screens → Zustand stores + components + pages
- Navigation → route configuration
- User-facing text → i18n namespace + keys
- Test scenarios → test files with source traceability

### Step 3: Generate Code (TDD)

```
/frontend-react-plugin:fe-gen {feature}
```

Executes 6 phases of strict TDD. Each TDD phase (2-5):
1. **RED** — Write tests first, run vitest, verify they fail
2. **GREEN** — Write minimal implementation to make tests pass
3. **REFACTOR** — Clean up while keeping tests green

External skills are loaded per-phase: Vitest for TDD phases, Composition Patterns for components, React Best Practices for pages, React Router for integration.

### Step 4: Verify (optional)

```
/frontend-react-plugin:fe-verify {feature}
```

### Step 5: Review

```
/frontend-react-plugin:fe-review {feature}
```

Two-stage review with enriched issue reports (refs, fix hints, missing artifact classification).

### Step 6: Fix & Re-Review

```
/frontend-react-plugin:fe-fix {feature}
/frontend-react-plugin:fe-review {feature}
```

Iterate until review passes. The fix skill applies TDD discipline for behavioral changes and direct fixes for mechanical changes.

### Step 7: E2E Test

```
/frontend-react-plugin:fe-e2e {feature}
```

After review passes, run end-to-end browser tests. The e2e-test-runner agent drives agent-browser through multi-page user flows defined in plan.json, verifying against MSW mock data.

### Step 8: E2E Fix & Re-test

```
/frontend-react-plugin:fe-fix {feature}
/frontend-react-plugin:fe-e2e {feature}
```

If E2E scenarios fail, `fe-fix` auto-detects E2E mode (by comparing report timestamps) and fixes root causes. Iterate until all E2E scenarios pass.

## Agents

### Implementation Planner

**Role**: Spec analysis → implementation plan (plan.json).

Analysis-only agent — does not generate any source code. Reads functional spec, UI DSL (if available), and existing project patterns. Produces a structured plan covering types, API services, stores, components, pages, routes, i18n, mocks, tests, and TDD build order. In standalone mode, infers types and generates default CRUD operations from minimal spec stubs. Uses the Opus model.

### Foundation Generator

**Role**: Types + mock infrastructure generation.

Generates TypeScript interfaces, DTOs, enums, mock factories, fixtures, and MSW handlers. Verifies with `tsc`. No TDD (infrastructure only).

### TDD Cycle Runner

**Role**: Strict Red-Green TDD cycle per phase.

Executes one TDD phase (api, store, component, or page). Writes tests first (RED — must verify failure), then writes minimal implementation (GREEN — must verify pass). Each test references spec test scenarios via `// TS-nnn` comments.

### Integration Generator

**Role**: Routes + i18n + MSW global setup + full verification.

Generates feature route definitions, i18n namespace registration, barrel exports, and MSW global aggregation. Auto-integrates into existing central route files and i18n config. Runs full verification (tsc, vitest, build).

### Spec Reviewer

**Role**: Spec compliance review (5 dimensions).

Compares generated code against the functional spec. Evaluates requirement coverage, UI fidelity, i18n completeness, accessibility, and route coverage. Enriches issues with refs (FR-nnn), fix hints, and missing artifact classification.

### Quality Reviewer

**Role**: Code quality review (7 dimensions).

Evaluates single responsibility, consistent patterns, no hardcoded strings, error handling, TypeScript strictness, convention compliance, and architecture. Supports pipeline mode (invoked by fe-review after spec review passes) and standalone mode (invoked by fe-clean-code for ad-hoc audits).

### Security Auditor

**Role**: Frontend security vulnerability audit.

Scans for XSS vectors (dangerouslySetInnerHTML, eval, innerHTML), auth token storage issues (localStorage), secrets exposure (hardcoded API keys), data safety issues (console logging PII, open redirects), and configuration concerns (CSP, CORS, source maps). Produces a text report with risk level assessment.

### Test Reviewer

**Role**: Test quality audit (7 dimensions).

Evaluates assertion quality, Testing Library best practices, async patterns, test structure, coverage analysis, timing gates (optional — measures actual test execution times via vitest), and anti-patterns. Produces a text report with scored dimensions.

### Review Fixer

**Role**: TDD-disciplined review issue fixer.

Classifies each issue as TDD-required (behavioral change — test first), direct-fix (mechanical change), or regen-required (missing files). Applies fixes with appropriate discipline.

### Delta Modifier

**Role**: Incremental spec change applier.

Modifies existing implementation files based on `delta-plan.json`. Follows the review-fixer pattern: TDD for behavioral changes (new UI behavior, new form fields), direct edit for structural changes (type additions, factory updates, route wiring). Handles foundation creates, code removal, and dependency cascade modifications. Preserves all accumulated review/fix work.

### E2E Test Runner

**Role**: E2E test execution via agent-browser.

Drives headless Chromium through multi-page user flows defined in plan.json. Uses snapshot → interact → re-snapshot → assert → screenshot cycle. Resolves dynamic route parameters from fixture data. Classifies failures as assertion, agent-error, or timeout. Uses the Opus model.

### Debugger

**Role**: Systematic debugging with 4-phase methodology.

Root Cause Investigation → Pattern Analysis → Hypothesis Testing (3-strike limit) → Implementation. Classifies issues by type (generation-bug, plan-bug, spec-bug, environment). Escalates after 3 failed hypotheses with structural analysis.

## Skills

| Skill | Command | Description |
|-------|---------|-------------|
| Init | `/frontend-react-plugin:fe-init` | Plugin setup and batch installation of external skills |
| Plan | `/frontend-react-plugin:fe-plan` | Analyze functional spec (or gather requirements) and generate implementation plan |
| Gen | `/frontend-react-plugin:fe-gen` | Generate production code based on implementation plan (TDD) |
| Verify | `/frontend-react-plugin:fe-verify` | Run TypeScript, build, and test verification on generated code |
| Review | `/frontend-react-plugin:fe-review` | 2-stage code review (spec compliance + quality) |
| Fix | `/frontend-react-plugin:fe-fix` | Fix review issues with TDD discipline |
| E2E | `/frontend-react-plugin:fe-e2e` | Run E2E browser tests via agent-browser |
| Debug | `/frontend-react-plugin:fe-debug` | Systematic debugging with hypothesis testing and escalation |
| Progress | `/frontend-react-plugin:fe-progress` | Show implementation pipeline status for all or a specific feature |

### Standalone Audit Skills

Independent audit skills that run outside the pipeline. No progress tracking, no lock files, no feature context required.

| Skill | Command | Description |
|-------|---------|-------------|
| Security | `/frontend-react-plugin:fe-security` | Security vulnerability audit (XSS, auth tokens, secrets, client-side data safety) |
| Clean Code | `/frontend-react-plugin:fe-clean-code` | Clean code audit (7 quality dimensions — standalone mode of quality-reviewer) |
| Test Review | `/frontend-react-plugin:fe-test-review` | Test quality audit (assertions, Testing Library, async patterns, coverage, timing gates) |

Usage: `fe-security [path]`, `fe-clean-code [path]`, `fe-test-review [test-path]`

These skills can be run at any time on any code, not just pipeline-generated features.

### External Skills (installed by init)

| Skill | Source | Description |
|-------|--------|-------------|
| React Router v7 | `remix-run/agent-skills` | Routing patterns (per configured mode) |
| Vitest | `antfu/skills` | Testing patterns |
| React Best Practices | `vercel-labs/agent-skills` | React performance optimization (57 rules) |
| Composition Patterns | `vercel-labs/agent-skills` | Component composition patterns (10 rules) |
| Web Design Guidelines | `vercel-labs/agent-skills` | Accessibility/design audit (100+ rules) |
| Agent Browser | `vercel-labs/agent-browser` | CLI for E2E browser automation |

## Configuration

The plugin uses `.claude/frontend-react-plugin.json` in the project directory (created by `/frontend-react-plugin:fe-init`):

```json
{
  "routerMode": "declarative",
  "mockFirst": true,
  "baseDir": "app/src",
  "appDir": "app",
  "eslintTemplate": true
}
```

| Field | Description | Default |
|-------|-------------|---------|
| `routerMode` | React Router v7 mode (`"declarative"` or `"data"`) | `"declarative"` |
| `mockFirst` | Enable MSW v2 mock-first development | `true` |
| `baseDir` | Base directory for generated source code | `"app/src"` |
| `appDir` | Directory containing `vite.config.*` and `package.json` — all build/test commands run here | Auto-derived from `baseDir` |
| `eslintTemplate` | Auto-generate `eslint.config.js` from bundled template when no ESLint config exists | `true` |

## Generated Project Structure

```
{baseDir}/
├── layouts/                        ← Shared layouts (cross-feature, uses <Outlet />)
├── features/{feature}/
│   ├── types/                      ← TypeScript interfaces, DTOs, enums
│   ├── api/                        ← Axios service modules
│   ├── stores/                     ← Zustand stores
│   ├── components/                 ← Shared components (forms, tables)
│   ├── pages/                      ← Page components (4-state: loading/empty/error/success)
│   ├── mocks/                      ← MSW factories, fixtures, handlers
│   ├── __tests__/                  ← Test files (api, store, component, page)
│   ├── routes.tsx                  ← Feature route definitions (auto-integrated)
│   └── i18n.ts                     ← Feature i18n registration (auto-integrated)
├── components/ui/                  ← shadcn/ui components
├── mocks/                          ← Global MSW setup (server.ts, browser.ts, handlers.ts)
├── locales/                        ← i18n JSON files
└── ...
```

## Pipeline State Files

State files under `docs/specs/{feature}/.implementation/frontend/`:

| File | Purpose |
|------|---------|
| `plan.json` | Implementation plan (input for fe-gen) |
| `generation-state.json` | Phase progress tracking with timestamps (enables resume) |
| `review-report.json` | Full review results with enriched issue details (input for fe-fix) |
| `fix-report.json` | Fix results with strategy breakdown |
| `e2e-report.json` | E2E test results with scenario details (input for fe-fix E2E mode) |
| `debug-report.json` | Debug session results with hypothesis log |
| `delta-plan.json` | Incremental spec change plan (input for delta fe-gen, archived after execution) |
| `.lock` | Concurrent execution prevention (auto-expires after 30 min) |

### Progress State Machine

```
planned → generated → verified → reviewed → done
             ↓    ↘       ↓         ↓    ↓
         gen-failed  ↘ verify-failed ↓  review-failed
                      ↘     ↓        ↓      ↓
                       → resolved  fixing → (re-review → reviewed/review-failed)
                         escalated    ↓  ↘ generated (regen-required → fe-gen)
                            ↓    escalated
                      (manual intervention)
```

### State File Safety

- **Lock mechanism**: Skills that modify state files acquire `.lock` before starting. Prevents concurrent execution of fe-gen/fe-verify/fe-review/fe-fix/fe-e2e on the same feature. Stale locks (>30 min) are auto-removed.
- **Read-Modify-Write rule**: Always read latest file content before writing. Merge only changed fields — preserve all existing fields.
- **Phase timestamps**: Each TDD phase records `completedAt` for precise resume and plan freshness detection.
- **Staleness detection**: fe-fix warns when source files changed since last review. fe-review warns when spec changed since generation.

## Hooks

The plugin registers two lifecycle hooks that run automatically:

### SessionStart — `session-init.sh`

Runs when a Claude Code session starts. Checks for:
- **Configuration**: Loads `.claude/frontend-react-plugin.json` and reports current settings
- **Missing skills**: Warns if any external skills are not installed
- **Pipeline status**: Scans all features and reports their current state with next-step guidance:
  - `planned` → suggests `fe-gen`
  - `generated` → suggests `fe-verify` or `fe-review`
  - `gen-failed` → suggests retry `fe-gen`
  - `verified` → suggests `fe-review`
  - `verify-failed` → suggests `fe-debug`
  - `reviewed` → suggests `fe-fix` (warnings) or `fe-e2e` (with E2E awareness)
  - `review-failed` → suggests `fe-fix` then `fe-review`
  - `fixing` → suggests `fe-review` (or `fe-gen` if regen required, or `fe-e2e` if E2E fixes applied)
  - `resolved` → suggests `fe-verify` or `fe-review`
  - `escalated` → warns about manual intervention needed
  - `done` → reports completion (with E2E awareness)

### PostToolUse — `validate-implementation.sh`

Runs after every `Write` or `Edit` tool call. Only activates on files under `docs/specs/`:
- **Staleness detection**: If a spec file or plan.json is edited while implementation status is post-planned, warns that generated code may be out of sync

## Communication Language

Feature-level skills (fe-plan, fe-gen, fe-verify, fe-review, fe-fix, fe-e2e, fe-debug, fe-progress) read `workingLanguage` from the progress file. All user-facing output (summaries, questions, feedback, next-step guidance) is in the working language.

Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese.

## Tips & Best Practices

- **Review the plan before generating** — `plan.json` is editable. Adjust file names, route paths, or test cases before running `fe-gen`.

- **Use mock-first for rapid iteration** — With `mockFirst: true`, run `VITE_ENABLE_MOCKS=true pnpm dev` to develop against MSW mocks without a backend. When the backend is ready, just remove the environment variable.

- **Don't skip re-review after fixes** — Always run `fe-review` after `fe-fix`. The fix-review cycle ensures no regressions.

- **Use fe-debug for runtime issues** — If tests pass but the app behaves incorrectly, `fe-debug` provides systematic hypothesis testing rather than ad-hoc debugging.

- **Standalone mode is a quick start, not a shortcut** — It generates simpler plans without error codes, validation rules, or test scenario references. For production features, invest in a proper spec with planning-plugin.

- **Use incremental mode when specs change** — After modifying a spec on generated code, run `fe-plan` again. It auto-detects existing implementation and offers incremental mode, which regenerates only affected files while preserving all review/fix work. Large deltas (>60% of files) trigger a warning suggesting full regeneration.

- **Resume is safe** — If generation is interrupted, just re-run `fe-gen`. It detects completed phases and resumes. Phase-level timestamps ensure accurate freshness checks.

- **Lock protects your state** — Don't run `fe-gen` and `fe-fix` on the same feature simultaneously. The lock mechanism prevents state file corruption.

## Roadmap

- [x] Tech stack specification
- [x] React Router routing skill
- [x] External skills integration (vercel-labs/agent-skills)
- [x] Code generation agent (6-phase TDD)
- [x] Verification skill
- [x] Code review skill (spec compliance + quality)
- [x] Fix skill (TDD-disciplined)
- [x] Debug skill (systematic debugging)
- [x] Standalone mode (fe-plan without planning-plugin)
- [x] State consistency (lock, timestamps, staleness detection)
- [x] Hook handlers (session-init, implementation validation)
- [x] E2E testing skill (agent-browser integration)
- [x] Delta regeneration (incremental spec change handling)
- [ ] Component template library
- [ ] i18n setup skill
- [ ] Auth/RBAC pattern templates

## Directory Structure

```
agents/          Agent definitions (planner, foundation-generator, tdd-cycle-runner,
                 integration-generator, spec-reviewer, quality-reviewer, security-auditor,
                 test-reviewer, review-fixer, delta-modifier, e2e-test-runner, debugger)
skills/          Skill entry points (fe-init, fe-plan, fe-gen, fe-verify, fe-review, fe-fix,
                 fe-e2e, fe-debug, fe-progress, fe-security, fe-clean-code, fe-test-review)
hooks/           Lifecycle hook configuration
scripts/         Hook handler scripts (session-init.sh, validate-implementation.sh)
templates/       Template files (feature-module.md, tdd-rules.md, eslint-config.md, e2e-testing.md)
docs/            Documentation
```

## Author

Justin Choi — Ohmyhotel & Co
