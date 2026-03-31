# Backend Spring Boot Plugin

> **Ohmyhotel & Co** — Claude Code plugin for Spring Boot backend development with TDD

## What It Does

This Claude Code plugin provides a complete development pipeline for Spring Boot backends using CQRS architecture and strict Test-Driven Development. It covers the full lifecycle from CRUD scaffolding through TDD implementation, verification, multi-dimension code review, and automated fix — all with pipeline state tracking.

Key capabilities:
- **CQRS scaffold** — Generate complete Command/Query separation CRUD (entity, repository, DTOs, controller, migration) in one command
- **Strict TDD** — RED-GREEN cycle enforcement with work document tracking and scenario-by-scenario implementation
- **Verification gate** — Structured build + checkstyle + test verification as a read-only quality gate
- **6-dimension review** — API contract, JPA patterns, clean code, logging, test quality, architecture — with TDD-disciplined auto-fix
- **Pipeline tracking** — Feature-level state machine with progress dashboard, demotion warnings, and staleness detection
- **State safety** — Lock mechanism, read-modify-write discipline, and subagent isolation across the pipeline
- **Standalone audits** — Independent JPA, API, clean code, logging, and test quality audits usable at any time

## Architecture Overview

```
/backend-springboot-plugin:be-init → .claude/backend-springboot-plugin.json
        │
        ▼
/backend-springboot-plugin:be-crud <Entity> [field:Type ...]
        │
        ├── Flyway migration + Entity + Repository
        ├── Command + CommandExecutor
        ├── Query + QueryProcessor
        ├── View DTO + Controller + Exceptions
        └── Work document with test scenarios
        │
        ▼
/backend-springboot-plugin:be-code <feature>
        │
        └── implement agent (per scenario):
            ├── Select next - [ ] scenario
            ├── Write test (RED) → verify failure
            ├── Implement minimum code (GREEN) → verify pass
            └── Mark - [x] → repeat
        │
        ▼
/backend-springboot-plugin:be-verify <feature>
        │
        ├── Compilation check
        ├── Checkstyle check (if enabled)
        ├── Test check
        └── Full build check
        │
        ▼
Loop — Review & Fix:
/backend-springboot-plugin:be-review <feature>
        │
        └── code-reviewer agent (6 dimensions)
        │
        ▼ (if issues found)
/backend-springboot-plugin:be-fix <feature>
        │
        └── review-fixer agent
            ├── TDD fixes (behavioral changes — test first)
            └── Direct fixes (mechanical changes — targeted edit)
        │
        ▼
/backend-springboot-plugin:be-review <feature> (re-review until pass)
        │
        ▼
/backend-springboot-plugin:be-commit

Interrupt skills (usable at any stage):
  be-debug    — systematic debugging (4-phase hypothesis-test)
  be-progress — pipeline status dashboard
  be-build    — build + auto-fix (independent)

Standalone audits (usable independently):
  be-jpa, be-api-review, be-clean-code, be-logging, be-test-review
```

## Tech Stack

| Category | Technology |
|----------|-----------|
| Language | Java 21+ |
| Framework | Spring Boot 4.x + Spring MVC (REST) + Spring Validation |
| Build | Gradle (Kotlin DSL or Groovy) or Maven |
| Database | PostgreSQL (default), MySQL, MariaDB, H2 |
| ORM | Spring Data JPA (Hibernate) |
| Migration | Flyway (default), Liquibase, or none |
| Testing | JUnit 5 + TestRestTemplate + AssertJ (no Mockito) |
| Code Quality | Checkstyle (zero tolerance: maxErrors=0, maxWarnings=0) |
| Utilities | Lombok, UUID Creator (UUID v7) |

## Installation

```
# 1. Register the repo as a marketplace source
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. Install the plugin (project scope — saved to .claude/settings.json, shared with the team)
/plugin install backend-springboot-plugin@ohmyhotelco --scope project
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
/plugin disable backend-springboot-plugin@ohmyhotelco
/plugin enable backend-springboot-plugin@ohmyhotelco
```

**Uninstall**:
```
/plugin uninstall backend-springboot-plugin@ohmyhotelco --scope project
```

**Plugin manager UI**: Run `/plugin` to open the tabbed interface (Discover, Installed, Marketplaces, Errors).

## Quick Start

```
1. /backend-springboot-plugin:be-init                          # configure plugin (auto-detects project)
2. /backend-springboot-plugin:be-crud Employee email:String displayName:String   # scaffold CQRS CRUD
3. /backend-springboot-plugin:be-code work/features/employee.md                  # TDD implementation
4. /backend-springboot-plugin:be-verify employee                                 # verification gate
5. /backend-springboot-plugin:be-review employee                                 # 6-dimension review
6. /backend-springboot-plugin:be-commit                                          # smart commit
```

## Skills Reference

### `/backend-springboot-plugin:be-init`

**Syntax**: `/backend-springboot-plugin:be-init`

**When to use**: First-time setup in a project, or reconfiguring settings.

**What happens**:
1. Auto-detects build tool (Gradle Kotlin/Groovy, Maven), Java version, Spring Boot version
2. Auto-detects base package, database type, migration tool
3. Checks for Checkstyle and Lombok configuration
4. Writes `.claude/backend-springboot-plugin.json`
5. Creates work document directory (`work/features/` by default)

---

### `/backend-springboot-plugin:be-crud`

**Syntax**: `/backend-springboot-plugin:be-crud <EntityName> [field:Type ...]`

**When to use**: Creating a new domain entity with full CQRS structure.

**What happens**:
1. Generates next Flyway migration version automatically
2. Creates entity with BaseEntity, dual key (sequence + UUID v7), and field columns
3. Creates repository, command/executor, query/processor, view DTO
4. Creates controller (record-based DI) with REST endpoints
5. Creates domain exceptions
6. Generates work document with initial test scenarios
7. Sets pipeline status to `scaffolded`

---

### `/backend-springboot-plugin:be-code`

**Syntax**: `/backend-springboot-plugin:be-code <feature-name or work-doc-path>`

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

### `/backend-springboot-plugin:be-verify`

**Syntax**: `/backend-springboot-plugin:be-verify [feature-name]`

**When to use**: After implementation, as a quality gate before review. Read-only — does NOT fix anything.

**What happens**:
1. Checks for pipeline demotion (warns if review progress would be lost)
2. Checks work document staleness (warns if scenarios added since last implementation)
3. Acquires lock
4. Runs 4 checks sequentially: compilation, checkstyle, tests, full build
5. Produces structured verification report
6. Updates pipeline status (`verified` or `verify-failed`)
7. Releases lock

---

### `/backend-springboot-plugin:be-review`

**Syntax**: `/backend-springboot-plugin:be-review <feature-name or target-path>`

**When to use**: After verification, or directly after implementation, to review code quality.

**What happens**:
1. Resolves target (feature name → source directory, or direct path)
2. Checks work document staleness (warns if scenarios added since last implementation)
3. Acquires lock
4. Launches `code-reviewer` agent evaluating 6 dimensions:
   - API Contract (HTTP semantics, URLs, status codes)
   - JPA Patterns (N+1, transactions, indexes)
   - Clean Code (DRY, KISS, YAGNI, naming)
   - Logging (SLF4J, MDC, security)
   - Test Quality (naming, assertions, coverage)
   - Architecture Compliance (CQRS, naming conventions)
5. Saves `review-report.json` with scored dimensions and enriched issues (severity, fixHint, refs)
6. Updates pipeline status (`done` / `reviewed` / `review-failed`)
7. Releases lock

**Verdict rules**:
- **PASS**: All dimensions >= 7, no critical issues
- **FAIL**: Any dimension < 7 OR any critical issue

---

### `/backend-springboot-plugin:be-fix`

**Syntax**: `/backend-springboot-plugin:be-fix <feature-name>`

**When to use**: After `be-review` finds issues.

**What happens**:
1. Reads `review-report.json`
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

### `/backend-springboot-plugin:be-build`

**Syntax**: `/backend-springboot-plugin:be-build`

**When to use**: When build fails and you want auto-diagnosis and fix. Independent of pipeline.

**What happens**:
1. Launches `build-doctor` agent
2. Categorizes errors: compilation, test, checkstyle, dependency, configuration
3. Applies targeted fixes with up to 3 retries
4. Reports all changes applied

---

### `/backend-springboot-plugin:be-debug`

**Syntax**: `/backend-springboot-plugin:be-debug <error-description or feature-name>`

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

### `/backend-springboot-plugin:be-commit`

**Syntax**: `/backend-springboot-plugin:be-commit`

**When to use**: After pipeline reaches `done` or `reviewed` status.

**What happens**: Creates a commit from staged changes following project conventions (English, present tense, 50-char subject, no prefix, no test mentions).

---

### `/backend-springboot-plugin:be-recall`

**Syntax**: `/backend-springboot-plugin:be-recall [section]`

**When to use**: To reference rules or check for violations in recent work.

**What happens**: Displays rules from CLAUDE.md by section (commit, tdd, build, coding, api, jpa) and checks recent work for violations. Can auto-fix simple violations (e.g., missing final newline).

---

### `/backend-springboot-plugin:be-progress`

**Syntax**: `/backend-springboot-plugin:be-progress [feature-name]`

**When to use**: At any time to check the current pipeline status.

**What happens**:
- **Without feature name**: Summary table of all features with pipeline status, scenario progress, verification result, review score, and fix round
- **With feature name**: Detailed view with pipeline history (verification, review, fix, debug), completed/remaining scenarios, work document staleness check, and next-step guidance

## Standalone Audits

These skills run independently of the pipeline. Use them at any time for targeted audits.

| Skill | What it checks |
|-------|---------------|
| `be-api-review` | HTTP method semantics, URL patterns (kebab-case, plural), status codes, pagination, error responses |
| `be-jpa` | N+1 queries, missing @Transactional, lazy loading risks, unbounded queries, missing indexes, cascades |
| `be-clean-code` | DRY/KISS/YAGNI violations, god classes, deep nesting, long methods, naming issues |
| `be-logging` | System.out usage, sensitive data exposure, string concatenation, wrong log levels, MDC usage |
| `be-test-review` | Naming conventions, assertion quality, anti-patterns, coverage analysis, slow test detection |

## Full Pipeline Workflow

### Step 1: Initialize

```
/backend-springboot-plugin:be-init
```

Auto-detects your project settings (build tool, Java version, Spring Boot version, base package, database, migration tool). Creates `.claude/backend-springboot-plugin.json`.

### Step 2: Scaffold CRUD

```
/backend-springboot-plugin:be-crud Employee email:String displayName:String
```

Generates the complete CQRS structure: Flyway migration, entity, repository, command/executor, query/processor, view, controller, exceptions, and a work document with initial test scenarios.

### Step 3: Implement with TDD

```
/backend-springboot-plugin:be-code work/features/employee.md
```

The `implement` agent processes each `- [ ]` scenario one at a time:
1. **RED** — Write test, run test class, verify failure
2. **GREEN** — Write minimum code, run entire test class, verify all pass
3. **Mark** — Update `- [ ]` to `- [x]`, move to next

### Step 4: Verify

```
/backend-springboot-plugin:be-verify employee
```

Read-only gate: compilation, checkstyle, tests, full build. Reports pass/fail without fixing.

### Step 5: Review

```
/backend-springboot-plugin:be-review employee
```

6-dimension code review with scored dimensions. Issues include severity, fix hints, and refs tracing back to API endpoints or test scenarios.

### Step 6: Fix & Re-Review

```
/backend-springboot-plugin:be-fix employee
/backend-springboot-plugin:be-review employee
```

Iterate until review passes. TDD discipline for behavioral changes, direct edit for mechanical changes. Fix rounds are tracked — warns after 3 rounds.

### Step 7: Commit

```
/backend-springboot-plugin:be-commit
```

## Agents

### Implement

**Role**: TDD-based feature implementation from work documents.

Processes `- [ ]` scenarios one at a time following strict RED-GREEN cycle. For each scenario: write test → verify failure → implement minimum code → verify all tests pass → mark complete. Maximum 3 consecutive test failures before escalation. Uses the Opus model.

### Build Doctor

**Role**: Build failure diagnosis and automatic fix.

Categorizes build errors (compilation, test, checkstyle, dependency, configuration) and applies targeted fixes. Retries up to 3 times. Uses the Sonnet model.

### Code Reviewer

**Role**: Multi-dimension code review (6 dimensions).

Read-only agent that evaluates API contract, JPA patterns, clean code, logging, test quality, and architecture compliance. Produces a structured review report with severity-ranked issues. Each issue includes dimension, severity, file, line, rule, message, suggestion, and refs (traceability to API endpoints or test scenarios). Uses the Opus model.

### Review Fixer

**Role**: TDD-disciplined review issue fixer.

Classifies each issue as TDD-required (behavioral change — test first), direct-fix (mechanical change), skip (already resolved), or escalated (requires manual intervention). Maximum 3 attempts per TDD fix before escalating. Uses the Opus model.

### Debugger

**Role**: Systematic debugging with 4-phase methodology.

Reproduce → Hypothesize (exactly 3) → Test → Confirm. Classifies errors as type-error, test-failure, build-error, runtime-error, config-error, or migration-error. Escalates if all 3 hypotheses fail. Uses the Opus model.

## Configuration

`.claude/backend-springboot-plugin.json` (created by `be-init`):

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
  "database": "postgresql",
  "migration": "flyway",
  "checkstyle": true,
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
| `database` | `"postgresql"` / `"mysql"` / `"h2"` / `"mariadb"` | `"postgresql"` |
| `migration` | `"flyway"` / `"liquibase"` / `"none"` | `"flyway"` |
| `checkstyle` | Whether Checkstyle is enabled | `true` |
| `lombokEnabled` | Whether Lombok is used | `true` |
| `workDocDir` | Directory for work documents | `"work/features"` |
| `workingLanguage` | Language for user-facing output (`"en"` / `"ko"` / `"vi"`) | `"en"` |

## CQRS Package Structure

```
{basePackage}/
├── {App}Application.java
├── command/                    <- Request command DTOs (records)
│   └── Create{Entity}.java
├── commandmodel/               <- Command execution logic
│   └── Create{Entity}CommandExecutor.java
├── query/                      <- Request query DTOs (records)
│   └── Get{Entities}.java
├── querymodel/                 <- Query processing logic
│   └── Get{Entity}PageQueryProcessor.java
├── view/                       <- Response view DTOs (records)
│   └── {Entity}View.java
├── data/                       <- Entities and repositories
│   ├── {Entity}.java
│   ├── {Entity}Repository.java
│   └── BaseEntity.java
├── config/                     <- Spring configuration beans
└── {domain}/                   <- Domain-specific business logic
    ├── api/                    <- REST controllers
    │   └── {Entity}Controller.java
    └── {Description}Exception.java
```

## Pipeline State

### State Files

State is tracked in `{workDocDir}/.progress/{feature}.json`.

| File | Purpose |
|------|---------|
| `{feature}.json` | Pipeline status, scenario counts, verification/review/fix/debug history |
| `review-report.json` | Review results with scored dimensions and enriched issues |
| `fix-report.json` | Fix results with strategy breakdown (TDD/direct/escalated) |
| `.lock` | Concurrent execution prevention (auto-expires after 30 min) |

### State Machine

```
scaffolded → implementing → implemented → verified → reviewed → done
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

- **Review the work document before coding** — `be-crud` generates initial scenarios, but you can add, remove, or reorder them before running `be-code`.

- **Use be-verify as a quick gate** — It's read-only and fast. Run it after implementation to catch compilation or test issues before investing time in a full review.

- **Don't skip re-review after fixes** — Always run `be-review` after `be-fix`. The review-fix cycle ensures no regressions.

- **Use be-debug for complex issues** — If tests fail in non-obvious ways, `be-debug` provides systematic hypothesis testing rather than ad-hoc debugging.

- **Standalone audits are free** — `be-jpa`, `be-api-review`, `be-clean-code`, `be-logging`, and `be-test-review` work independently of the pipeline. Use them anytime for targeted quality checks.

- **Resume is safe** — If `be-code` is interrupted, just re-run it with the same work document. Completed scenarios (`- [x]`) are preserved, and it resumes from the next `- [ ]`.

- **Lock protects your state** — Don't run `be-code` and `be-fix` on the same feature simultaneously. The lock mechanism prevents progress file corruption.

## Roadmap

- [x] CQRS CRUD scaffold generation
- [x] TDD implementation pipeline
- [x] Verification gate
- [x] 6-dimension code review with review-fix loop
- [x] Build doctor (auto-diagnosis and fix)
- [x] Systematic debugging (4-phase hypothesis-test)
- [x] Pipeline state tracking with progress dashboard
- [x] Standalone audits (JPA, API, clean code, logging, test quality)
- [x] State safety (lock, demotion, staleness, subagent isolation)
- [ ] Planning-plugin integration (spec-driven scaffold)
- [ ] Multi-module project support
- [ ] Event-driven architecture templates (Kafka, RabbitMQ)
- [ ] Security audit skill (OWASP, Spring Security)

## Directory Structure

```
agents/          Agent definitions (implement, build-doctor, code-reviewer,
                 review-fixer, debugger)
skills/          Skill entry points (be-init, be-crud, be-code, be-verify,
                 be-review, be-fix, be-commit, be-build, be-debug, be-recall,
                 be-progress, be-jpa, be-api-review, be-clean-code, be-logging,
                 be-test-review)
templates/       Template files (tdd-rules, cqrs-module, entity-conventions,
                 test-scenario-template, work-document-template, checkstyle-config,
                 progress-schema)
docs/            Documentation
```

## Author

Justin Choi — Ohmyhotel & Co
