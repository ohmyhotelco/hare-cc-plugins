# Backend WebFlux Plugin

> **Ohmyhotel & Co** — Claude Code plugin for Spring WebFlux backend development with TDD

## What It Does

This Claude Code plugin provides a complete development pipeline for Spring WebFlux
backends using CQRS architecture and strict Test-Driven Development. It is
self-contained — installing it does not require any other plugin in this repository.
It covers the full lifecycle from CRUD scaffolding through TDD implementation,
verification (with a JaCoco coverage row), multi-dimension code review, and automated
fix — all with pipeline state tracking.

This plugin supports **both** R2DBC and MyBatis as data-layer profiles, because many
real-world WebFlux backends are not uniformly R2DBC — see `docs/decisions.md`
Decision 1 for the rationale.

Key capabilities:
- **CQRS scaffold** — Generate complete Command/Query separation CRUD (entity/mapper, repository, DTOs, router/handler or controller, manual SQL migration) in one command. This is application-level command/query separation on a single datastore, not full CQRS with a separate read-model store — see `docs/decisions.md` Decision 8
- **Dual data profile** — R2DBC (`ReactiveCrudRepository`) or MyBatis (blocking JDBC offloaded to `Schedulers.boundedElastic()`), selectable per project or per entity
- **Web layer rule, not a ban** — `RouterFunction`/`HandlerFunction` by default; `@RestController` returning `Mono`/`Flux` as a named, explicit exception
- **Strict TDD** — RED-GREEN cycle enforcement with `WebTestClient` + `StepVerifier`, work document tracking, and scenario-by-scenario implementation
- **Verification gate** — Structured build + checkstyle + test + JaCoco coverage verification as a read-only quality gate (coverage is report-only, no threshold yet)
- **Multi-dimension review** — API contract, data layer (R2DBC/MyBatis), clean code, logging, test quality, architecture (+ spec compliance when plan.json exists) — with TDD-disciplined auto-fix
- **Pipeline tracking** — Feature-level state machine with progress dashboard, demotion warnings, and staleness detection
- **State safety** — Lock mechanism, read-modify-write discipline, and subagent isolation across the pipeline
- **Standalone audits** — Independent data-layer, API, clean code, logging, test quality, and security audits usable at any time

## Architecture Overview

```
/backend-webflux-plugin:be-init → .claude/backend-webflux-plugin.json
        │
        ▼
/backend-webflux-plugin:be-plan <feature>  (optional, requires planning-plugin spec)
        │
        └── backend-planner agent → plan.json
        │
        ▼
/backend-webflux-plugin:be-crud <Entity> [field:Type ...] | --all <feature>
        │
        ├── Manual SQL migration + Entity/Mapper + Repository/Mapper XML
        ├── Command + CommandExecutor (returns Mono<Void>)
        ├── Query + QueryProcessor (returns Mono/Flux)
        ├── View DTO + Router/Handler (or Controller) + Exceptions
        └── Work document with test scenarios
        │
        ▼
/backend-webflux-plugin:be-code <feature>
        │
        └── implement agent (per scenario):
            ├── Select next - [ ] scenario
            ├── Write test (RED, WebTestClient/StepVerifier) → verify failure
            ├── Implement minimum code (GREEN) → verify pass
            └── Mark - [x] → repeat
        │
        ▼
/backend-webflux-plugin:be-verify <feature>
        │
        ├── Compilation check
        ├── Checkstyle check (if enabled)
        ├── Test check
        ├── Full build check
        └── JaCoco coverage check (report-only, no threshold)
        │
        ▼
Loop — Review & Fix:
/backend-webflux-plugin:be-review <feature>
        │
        └── code-reviewer agent (6 dimensions)
        │
        ▼ (if issues found)
/backend-webflux-plugin:be-fix <feature>
        │
        └── review-fixer agent
            ├── TDD fixes (behavioral changes — test first)
            └── Direct fixes (mechanical changes — targeted edit)
        │
        ▼
/backend-webflux-plugin:be-review <feature> (re-review until pass)
        │
        ▼
/backend-webflux-plugin:be-commit

Interrupt skills (usable at any stage):
  be-debug    — systematic debugging (4-phase hypothesis-test)
  be-progress — pipeline status dashboard
  be-build    — build + auto-fix (independent)
  be-recall   — rules reference and violation check

Standalone audits (usable independently):
  be-data, be-api-review, be-clean-code, be-logging, be-test-review, be-security, be-integrate-review
```

## Tech Stack

| Category | Technology |
|----------|-----------|
| Language | Java 21+ |
| Framework | Spring Boot 4.x + Spring WebFlux (reactive REST) + Spring Validation |
| Build | Gradle (Kotlin DSL or Groovy) or Maven |
| Database | MySQL 8.0.33 (default), PostgreSQL, MariaDB, H2 |
| Data Layer | R2DBC (`ReactiveCrudRepository`) and/or MyBatis (blocking, offloaded to `boundedElastic`) — see `docs/decisions.md` |
| Web Layer | RouterFunction/HandlerFunction (default) or `@RestController` (named exception) |
| Migration | Manual SQL (default, no runner tool) |
| Testing | JUnit 5 + WebTestClient + StepVerifier + AssertJ + Mockito |
| Code Quality | Checkstyle (zero tolerance: maxErrors=0, maxWarnings=0), JaCoco (report-only coverage) |
| Vendor Integration | WebClient + Resilience4j circuit breaker (only for domains with a `client/` package — see `templates/vendor-integration.md`) |
| Utilities | Lombok, UUID Creator (UUID v7) |

## Installation

```
# 1. Register the repo as a marketplace source
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. Install the plugin (project scope — saved to .claude/settings.json, shared with the team)
/plugin install backend-webflux-plugin@ohmyhotelco --scope project
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
/plugin disable backend-webflux-plugin@ohmyhotelco
/plugin enable backend-webflux-plugin@ohmyhotelco
```

**Uninstall**:
```
/plugin uninstall backend-webflux-plugin@ohmyhotelco --scope project
```

**Plugin manager UI**: Run `/plugin` to open the tabbed interface (Discover, Installed, Marketplaces, Errors).

## Quick Start

### Manual Mode (no spec)

```
1. /backend-webflux-plugin:be-init                          # configure plugin (auto-detects project)
2. /backend-webflux-plugin:be-crud Employee email:String displayName:String   # scaffold CQRS CRUD
3. /backend-webflux-plugin:be-code work/features/employee.md                  # TDD implementation
4. /backend-webflux-plugin:be-verify employee                                 # verification gate + coverage
5. /backend-webflux-plugin:be-review employee                                 # code review
6. /backend-webflux-plugin:be-commit                                          # smart commit
```

### Spec-Driven Mode (with planning-plugin)

```
1. /backend-webflux-plugin:be-init                          # configure plugin
2. /planning-plugin:pp-spec employee-management                   # create functional spec
3. /backend-webflux-plugin:be-plan employee-management      # spec → plan.json
4. /backend-webflux-plugin:be-crud --all employee-management # scaffold all entities from plan
5. /backend-webflux-plugin:be-code employee-management      # TDD (enriched work docs from plan)
6. /backend-webflux-plugin:be-verify employee               # verification gate (per entity)
7. /backend-webflux-plugin:be-review employee               # 7-dimension review (per entity)
8. /backend-webflux-plugin:be-commit                        # smart commit
```

> **Note**: Steps 1-5 use the planning-plugin **feature name** (e.g., `employee-management`).
> Steps 6-7 use individual **entity names** (e.g., `employee`, `department`) because progress is tracked per entity.
> After step 5, `be-code` displays next-step commands per entity.

## Skills Reference

### `/backend-webflux-plugin:be-init`

**Syntax**: `/backend-webflux-plugin:be-init`

**When to use**: First-time setup in a project, or reconfiguring settings.

**What happens**:
1. Auto-detects build tool (Gradle Kotlin/Groovy, Maven), Java version, Spring Boot version
2. Auto-detects base package, data profile (R2DBC/MyBatis/both), web layer style, database, migration convention
3. Checks for Checkstyle, JaCoco, and Lombok configuration
4. Writes `.claude/backend-webflux-plugin.json`
5. Creates work document directory (`work/features/` by default)

---

### `/backend-webflux-plugin:be-plan`

**Syntax**: `/backend-webflux-plugin:be-plan <feature-name>`

**When to use**: After creating a functional specification with planning-plugin, before scaffolding.

**What happens**:
1. Detects spec at `docs/specs/{feature}/.progress/{feature}.json`
2. Validates spec status (must be `reviewing` or `finalized`)
3. Reads spec files + UI DSL (if available) via `backend-planner` agent
4. Extracts entities, commands, queries, endpoints, exceptions, validation rules, test scenarios
5. Produces `docs/specs/{feature}/.implementation/backend/plan.json`
6. Updates spec progress file with `implementation.backend` status

---

### `/backend-webflux-plugin:be-crud`

**Syntax**: `/backend-webflux-plugin:be-crud <EntityName> [field:Type ...]` or `/backend-webflux-plugin:be-crud --all <feature-name>`

**When to use**: Creating a new domain entity with full CQRS structure.

**Modes**:
- **Manual**: `be-crud Employee email:String displayName:String` — specify fields directly
- **Spec-driven**: `be-crud Employee` — auto-reads from plan.json when available
- **Batch**: `be-crud --all employee-management` — scaffolds all entities from plan in dependency order

**What happens**:
1. Generates next manual SQL migration version automatically (not applied — see `docs/decisions.md` Decision 3)
2. Creates entity (R2DBC) or POJO + mapper (MyBatis) with dual key (sequence + UUID v7) and field columns
3. Creates repository (R2DBC) or mapper interface + XML (MyBatis), command/executor, query/processor, view DTO
4. Creates router + handler (default) or `@RestController` (named exception) with REST endpoints
5. Creates domain exceptions
6. Generates work document with initial test scenarios
7. Sets pipeline status to `scaffolded`
8. (Spec-driven) Includes all commands/queries/endpoints/exceptions from plan.json

---

### `/backend-webflux-plugin:be-code`

**Syntax**: `/backend-webflux-plugin:be-code <feature-name or work-doc-path>`

**When to use**: After scaffolding, or when a work document with `- [ ]` scenarios is ready.

**What happens**:
1. If given a feature name: explores existing code, drafts test scenarios, asks for approval
2. If given a work document path: reads existing `- [ ]` scenarios directly
3. Checks for pipeline demotion (warns if status would regress)
4. Acquires lock on progress file
5. Launches `implement` agent for each scenario: RED (write test, verify failure) → GREEN (implement, verify pass)
6. Runs full build after all scenarios complete
7. Updates pipeline status (`implemented` or `implementing`)
8. Releases lock

---

### `/backend-webflux-plugin:be-verify`

**Syntax**: `/backend-webflux-plugin:be-verify [feature-name]`

**When to use**: After implementation, as a quality gate before review. Read-only — does NOT fix anything.

**What happens**:
1. Checks for pipeline demotion (warns if review progress would be lost)
2. Checks work document staleness (warns if scenarios added since last implementation)
3. Acquires lock
4. Runs 5 checks sequentially: compilation, checkstyle, tests, full build, JaCoco coverage (report-only)
5. Produces structured verification report
6. Updates pipeline status (`verified` or `verify-failed` — the Coverage row never affects this verdict)
7. Releases lock

---

### `/backend-webflux-plugin:be-review`

**Syntax**: `/backend-webflux-plugin:be-review <feature-name or target-path>`

**When to use**: After verification, or directly after implementation, to review code quality.

**What happens**:
1. Resolves target (feature name → source directory, or direct path)
2. Checks work document staleness (warns if scenarios added since last implementation)
3. Acquires lock
4. Launches `code-reviewer` agent evaluating 6 dimensions:
   - API Contract (HTTP semantics, URLs, status codes, web-layer consistency)
   - Data Layer (R2DBC/MyBatis — blocking-call detection, transactions, indexes)
   - Clean Code (DRY, KISS, YAGNI, naming)
   - Logging (SLF4J, MDC across reactive schedulers, security)
   - Test Quality (naming, StepVerifier assertions, coverage)
   - Architecture Compliance (CQRS package/DTO separation, naming conventions — see `docs/decisions.md` Decision 8 for what "CQRS" means in this plugin)
   - Spec Compliance (when plan.json exists — FR/BR/E-nnn/TS-nnn coverage)
5. Saves `review-report-{feature}.json` with scored dimensions and enriched issues (severity, suggestion, refs)
6. Updates pipeline status (`done` / `reviewed` / `review-failed`)
7. Releases lock

**Verdict rules**:
- **PASS**: All dimensions >= 7, no critical issues
- **FAIL**: Any dimension < 7 OR any critical issue

---

### `/backend-webflux-plugin:be-fix`

**Syntax**: `/backend-webflux-plugin:be-fix <feature-name>`

**When to use**: After `be-review` finds issues.

**What happens**:
1. Reads `review-report-{feature}.json`
2. Checks fix round counter (blocks after 3 rounds — asks user before continuing)
3. Acquires lock
4. Launches `review-fixer` agent which classifies each issue:
   - **TDD-required**: Behavioral changes — writes failing test first, then fixes
   - **Direct-fix**: Mechanical changes (naming, annotations) — targeted edit
   - **Skip**: Issue already resolved
   - **Escalated**: Requires architectural change beyond auto-fix scope
5. Runs full build verification after fixes
6. Produces `fix-report.json`
7. Updates pipeline status and releases lock

**Review-fix loop**:
```
be-review → FAIL → be-fix → be-review → PASS → be-commit
              ^                 |
              └─────────────────┘ (if still failing)
```

---

### `/backend-webflux-plugin:be-build`

**Syntax**: `/backend-webflux-plugin:be-build`

**When to use**: When build fails and you want auto-diagnosis and fix. Independent of pipeline.

**What happens**:
1. Launches `build-doctor` agent
2. Categorizes errors: compilation, test, checkstyle, dependency, configuration
3. Applies targeted fixes with up to 3 retries
4. Reports all changes applied

---

### `/backend-webflux-plugin:be-debug`

**Syntax**: `/backend-webflux-plugin:be-debug <error-description or feature-name>`

**When to use**: For runtime errors, test failures, or build issues at any point in the pipeline.

**What happens**:
1. Gathers problem context (error messages, stack traces, related source files)
2. Acquires lock (if feature context available)
3. Launches `debugger` agent with 4-phase methodology:
   - **Reproduce**: Parse error, confirm reproducibility
   - **Hypothesize**: Form exactly 3 ranked hypotheses
   - **Test**: Apply fix per hypothesis, verify, revert if failed
   - **Confirm**: Regression check + full build
4. If all 3 hypotheses fail: escalates for manual intervention
5. Updates pipeline status (`resolved` or `escalated`) and releases lock

---

### `/backend-webflux-plugin:be-commit`

**Syntax**: `/backend-webflux-plugin:be-commit`

**When to use**: After pipeline reaches `done` or `reviewed` status.

**What happens**: Runs pre-commit security scan (secrets, dangerous files), then creates a commit from staged changes following project conventions (English, present tense, 50-char subject, no prefix, no test mentions). Aborts if secrets are detected.

---

### `/backend-webflux-plugin:be-recall`

**Syntax**: `/backend-webflux-plugin:be-recall [section]`

**When to use**: To reference rules or check for violations in recent work.

**What happens**: Displays rules from CLAUDE.md by section (commit, tdd, build, coding, api, data) and checks recent work for violations. Can auto-fix simple violations (e.g., missing final newline).

---

### `/backend-webflux-plugin:be-progress`

**Syntax**: `/backend-webflux-plugin:be-progress [feature-name]`

**When to use**: At any time to check the current pipeline status.

**What happens**:
- **Without feature name**: Summary table of all features with pipeline status, scenario progress, verification result, review score, and fix round
- **With feature name**: Detailed view with pipeline history (verification, review, fix, debug), completed/remaining scenarios, work document staleness check, and next-step guidance

## Standalone Audits

These skills run independently of the pipeline. Use them at any time for targeted audits.

| Skill | What it checks |
|-------|---------------|
| `be-api-review` | HTTP method semantics, URL patterns (kebab-case, plural), status codes, pagination, error responses, mixed web-layer style |
| `be-data` | Blocking calls on the event loop, missing transaction wrapping, unbounded queries, missing indexes, schema design, migration safety, data integrity — R2DBC and MyBatis |
| `be-clean-code` | DRY/KISS/YAGNI violations, god classes, deep nesting, long methods, naming issues |
| `be-logging` | System.out usage, sensitive data exposure, string concatenation, wrong log levels, MDC across reactive schedulers |
| `be-test-review` | Naming conventions, StepVerifier/assertion quality, anti-patterns, coverage analysis, slow test detection |
| `be-security` | Authentication, authorization, input validation, PII exposure, injection, secrets |
| `be-integrate-review` | Timeout/retry/circuit-breaker hazards, ambiguous-timeout reconciliation, cancel-confirmation ordering, vendor fan-out isolation — only applies to a domain with a `client/` package |

## Full Pipeline Workflow

### Step 1: Initialize

```
/backend-webflux-plugin:be-init
```

Auto-detects your project settings (build tool, Java version, Spring Boot version, base package, data profile, web layer, database, migration convention). Creates `.claude/backend-webflux-plugin.json`.

### Step 2: Scaffold CRUD

```
/backend-webflux-plugin:be-crud Employee email:String displayName:String
```

Generates the complete CQRS structure: manual SQL migration, entity/mapper, repository/mapper, command/executor, query/processor, view, router+handler (or controller), exceptions, and a work document with initial test scenarios.

### Step 3: Implement with TDD

```
/backend-webflux-plugin:be-code work/features/employee.md
```

The `implement` agent processes each `- [ ]` scenario one at a time:
1. **RED** — Write test (`WebTestClient` or `StepVerifier`), run test class, verify failure
2. **GREEN** — Write minimum code, run entire test class, verify all pass
3. **Mark** — Update `- [ ]` to `- [x]`, move to next

### Step 4: Verify

```
/backend-webflux-plugin:be-verify employee
```

Read-only gate: compilation, checkstyle, tests, full build, JaCoco coverage (report-only). Reports pass/fail without fixing.

### Step 5: Review

```
/backend-webflux-plugin:be-review employee
```

Multi-dimension code review (6 core + optional spec compliance) with scored dimensions. Issues include severity, suggestions, and refs tracing back to API endpoints or test scenarios.

### Step 6: Fix & Re-Review

```
/backend-webflux-plugin:be-fix employee
/backend-webflux-plugin:be-review employee
```

Iterate until review passes. TDD discipline for behavioral changes, direct edit for mechanical changes. Fix rounds are tracked — warns after 3 rounds.

### Step 7: Commit

```
/backend-webflux-plugin:be-commit
```

## Agents

### Backend Planner

**Role**: Spec analysis agent for spec-driven scaffold mode.

Reads planning-plugin functional specifications and UI DSL, extracts entities, commands, queries, endpoints, exceptions, validation rules, and test scenarios, and produces a structured `plan.json`. Computes entity dependency order for scaffold sequence. Uses the Opus model.

### Implement

**Role**: TDD-based feature implementation from work documents.

Processes `- [ ]` scenarios one at a time following strict RED-GREEN cycle. For each scenario: write test → verify failure → implement minimum code → verify all tests pass → mark complete. Maximum 3 consecutive test failures before escalation. Uses the Opus model.

### Build Doctor

**Role**: Build failure diagnosis and automatic fix.

Categorizes build errors (compilation, test, checkstyle, dependency, configuration) and applies targeted fixes. Retries up to 3 times. Uses the Sonnet model.

### Code Reviewer

**Role**: Multi-dimension code review (6 dimensions).

Read-only agent that evaluates API contract, data layer (R2DBC/MyBatis), clean code, logging, test quality, and architecture compliance. Produces a structured review report with severity-ranked issues. Each issue includes dimension, severity, file, line, rule, message, suggestion, and refs (traceability to API endpoints or test scenarios). Uses the Opus model.

### Review Fixer

**Role**: TDD-disciplined review issue fixer.

Classifies each issue as TDD-required (behavioral change — test first), direct-fix (mechanical change), skip (already resolved), or escalated (requires manual intervention). Maximum 3 attempts per TDD fix before escalating. Uses the Opus model.

### Debugger

**Role**: Systematic debugging with 4-phase methodology.

Reproduce → Hypothesize (exactly 3) → Test → Confirm. Classifies errors as type-error, test-failure, build-error, runtime-error, config-error, or migration-error. Escalates if all 3 hypotheses fail. Uses the Opus model.

## Configuration

`.claude/backend-webflux-plugin.json` (created by `be-init`):

```json
{
  "javaVersion": "21",
  "springBootVersion": "4.0.2",
  "buildTool": "gradle-kotlin",
  "buildCommand": "./gradlew build",
  "testCommand": "./gradlew test",
  "basePackage": "com.example",
  "sourceDir": "src/main/java",
  "testDir": "src/test/java",
  "architecture": "cqrs",
  "dataProfile": "both",
  "webLayer": "functional",
  "database": "mysql",
  "migration": "manual-sql",
  "checkstyle": true,
  "coverage": true,
  "lombokEnabled": true,
  "workDocDir": "work/features",
  "workingLanguage": "en"
}
```

| Field | Description | Default |
|-------|-------------|---------|
| `javaVersion` | Java toolchain version | `"21"` |
| `springBootVersion` | Spring Boot version | `"4.0.2"` |
| `buildTool` | `"gradle-kotlin"` / `"gradle-groovy"` / `"maven"` | `"gradle-kotlin"` |
| `buildCommand` | Full build command | `"./gradlew build"` |
| `testCommand` | Test-only command | `"./gradlew test"` |
| `basePackage` | Root Java package | `"com.example"` |
| `sourceDir` | Main source directory | `"src/main/java"` |
| `testDir` | Test source directory | `"src/test/java"` |
| `architecture` | Architecture pattern — determines package structure and templates | `"cqrs"` |
| `dataProfile` | `"r2dbc"` / `"mybatis"` / `"both"` — see `docs/decisions.md` Decision 1 | `"both"` |
| `webLayer` | `"functional"` (RouterFunction) / `"annotated"` (@RestController) — see `docs/decisions.md` Decision 2 | `"functional"` |
| `database` | `"mysql"` / `"postgresql"` / `"h2"` / `"mariadb"` | `"mysql"` |
| `migration` | `"manual-sql"` / `"flyway"` / `"liquibase"` (only if explicitly opted in) | `"manual-sql"` |
| `checkstyle` | Whether Checkstyle is enabled | `true` |
| `coverage` | Whether the JaCoco coverage row runs (report-only, no threshold) | `true` |
| `lombokEnabled` | Whether Lombok is used | `true` |
| `workDocDir` | Directory for work documents | `"work/features"` |
| `workingLanguage` | Language for user-facing output (`"en"` / `"ko"` / `"vi"`) | `"en"` |

## CQRS Package Structure

> Application-level command/query separation on one datastore — `data/` is shared by
> both sides, not a separate read-model store. See `docs/decisions.md` Decision 8.

```
{basePackage}/
├── {App}Application.java
├── command/                    <- Request command DTOs (records)
│   └── Create{Entity}.java
├── commandmodel/               <- Command execution logic, returns Mono<Void>
│   └── Create{Entity}CommandExecutor.java
├── query/                      <- Request query DTOs (records)
│   └── Get{Entity}Page.java
├── querymodel/                 <- Query processing logic, returns Mono/Flux
│   └── Get{Entity}PageQueryProcessor.java
├── view/                       <- Response view DTOs (records)
│   └── {Entity}View.java
├── data/                       <- Entities/POJOs and repositories/mappers
│   ├── {Entity}.java
│   ├── {Entity}Repository.java   <- R2DBC profile
│   └── {Entity}Mapper.java       <- MyBatis profile
├── config/                     <- Spring configuration beans (router config)
└── {domain}/                   <- Domain-specific business logic
    ├── api/                    <- RouterFunction + HandlerFunction (default)
    │   ├── {Entity}Router.java
    │   └── {Entity}Handler.java
    │   (or {Entity}Controller.java when webLayer: "annotated")
    └── {Description}Exception.java
```

## Pipeline State

### State Files

State is tracked in `{workDocDir}/.progress/{feature}.json`.

| File | Purpose |
|------|---------|
| `{feature}.json` | Pipeline status, scenario counts, verification/review/fix/debug history |
| `review-report-{feature}.json` | Review results with scored dimensions and enriched issues |
| `fix-report-{feature}.json` | Fix results with strategy breakdown (TDD/direct/escalated) |
| `.lock` | Concurrent execution prevention (auto-expires after 30 min) |

### State Machine

Note: `planned` status is tracked in the spec progress file (by `be-plan`), not in the backend pipeline.

```
scaffolded → implementing → implemented → verified ─→ reviewed ─→ be-commit
                                                   └→ done ────→ be-commit
                                    ↓            ↓          ↓
                              verify-failed  review-failed  fixing
                                    ↓            ↓          ↓
                                be-build     be-fix    be-review (re-review)
                                    ↓            ↓
                                verified     fixing → reviewed/done

At any point:
  be-debug → resolved | escalated
  resolved → (re-enter pipeline at appropriate stage)
  escalated → (manual intervention, then re-enter)
```

### State Safety

- **Lock mechanism**: Skills that modify progress files acquire `.lock` before starting. Prevents concurrent execution on the same feature. Stale locks (>30 min) are auto-removed.
- **Read-Modify-Write rule**: Always read latest file content before writing. Merge only changed fields — preserve all existing fields.
- **Demotion warning**: Running a skill from an earlier pipeline stage warns before resetting progress (e.g., re-running `be-code` when status is `verified` would discard verification).
- **Staleness detection**: `be-verify` and `be-review` warn when the work document has been modified since the last pipeline update, indicating new scenarios may not be implemented.
- **Subagent isolation**: Coordinator skills pass only required parameters to agents — no conversation context leaks between phases.

## Communication Language

Skills read `workingLanguage` from config. All user-facing output (summaries, questions, feedback, next-step guidance) is in the working language.

Language mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese.

## Tips & Best Practices

- **Read `docs/decisions.md` before changing a template** — the data-profile, web-layer, migration, database, driver, and coverage-tool choices are all recorded there with rationale. Changing `templates/entity-conventions*.md`, `templates/cqrs-module.md`, or `templates/web-layer-*.md` without reading it first risks silently reverting a decision.

- **Review the work document before coding** — `be-crud` generates initial scenarios, but you can add, remove, or reorder them before running `be-code`.

- **Use be-verify as a quick gate** — It's read-only and fast. Run it after implementation to catch compilation, test, or coverage-report issues before investing time in a full review.

- **Don't skip re-review after fixes** — Always run `be-review` after `be-fix`. The review-fix cycle ensures no regressions.

- **Use be-debug for complex issues** — If tests fail in non-obvious ways, `be-debug` provides systematic hypothesis testing rather than ad-hoc debugging.

- **Standalone audits are free** — `be-data`, `be-api-review`, `be-clean-code`, `be-logging`, `be-test-review`, `be-security`, and `be-integrate-review` work independently of the pipeline. Use them anytime for targeted quality checks.

- **Resume is safe** — If `be-code` is interrupted, just re-run it with the same work document. Completed scenarios (`- [x]`) are preserved, and it resumes from the next `- [ ]`.

- **Lock protects your state** — Don't run `be-code` and `be-fix` on the same feature simultaneously. The lock mechanism prevents progress file corruption.

## Roadmap

- [x] CQRS CRUD scaffold generation (R2DBC + MyBatis)
- [x] TDD implementation pipeline (WebTestClient + StepVerifier)
- [x] Verification gate with report-only JaCoco coverage row
- [x] Multi-dimension code review with review-fix loop (6 core + optional spec compliance)
- [x] Build doctor (auto-diagnosis and fix)
- [x] Systematic debugging (4-phase hypothesis-test)
- [x] Pipeline state tracking with progress dashboard
- [x] Standalone audits (data layer, API, clean code, logging, test quality, security, vendor integration)
- [x] State safety (lock, demotion, staleness, subagent isolation)
- [x] Pre-commit security scan (secrets, API keys, dangerous files)
- [x] Planning-plugin integration (spec-driven scaffold)
- [ ] JaCoco threshold enforcement (blocked on establishing a real coverage baseline)
- [ ] Full `TransactionalOperator` nested-composition validation (see `docs/decisions.md` Decision 7)
- [ ] Multi-module project support
- [ ] Event-driven architecture templates (Kafka, RabbitMQ)

## Directory Structure

```
agents/          Agent definitions (backend-planner, implement, build-doctor,
                 code-reviewer, review-fixer, debugger)
skills/          Skill entry points (be-init, be-plan, be-crud, be-code, be-verify,
                 be-review, be-fix, be-commit, be-build, be-debug, be-recall,
                 be-progress, be-data, be-api-review, be-clean-code, be-logging,
                 be-test-review, be-security, be-integrate-review)
templates/       Template files (plan-schema, tdd-rules, cqrs-module,
                 entity-conventions, vendor-integration, coverage-gate,
                 test-scenario-template, work-document-template,
                 checkstyle-config, progress-schema)
docs/            Documentation, including docs/decisions.md (data-profile,
                 web-layer, migration, database, driver, and coverage-tool
                 decision record — read before changing templates)
examples/        Sample generated service (see examples/employee-service/)
```

## Author

Daniel — Ohmyhotel & Co
