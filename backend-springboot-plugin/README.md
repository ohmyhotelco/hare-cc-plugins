# Backend Spring Boot Plugin

A Claude Code plugin for Spring Boot backend development with CQRS architecture, strict TDD methodology, Gradle build automation, pipeline state tracking, and multi-dimension code review with review-fix loop.

## Features

- **CQRS Scaffold**: Generate complete CRUD with Command/Query separation in one command
- **Strict TDD**: RED-GREEN cycle enforcement with work document tracking
- **Verification Gate**: Structured build + checkstyle + test verification before review
- **Review-Fix Loop**: 6-dimension code review with TDD-disciplined auto-fix and re-review cycle
- **Build Doctor**: Automatic build failure diagnosis and fix with retry
- **Systematic Debugging**: 4-phase hypothesis-test methodology for runtime issues
- **Pipeline Tracking**: Feature-level state machine with progress dashboard
- **Smart Commit**: Validated commit messages following project conventions

## Pipeline

```
be-init → be-crud (scaffold) → be-code (TDD) → be-verify → be-review ↔ be-fix → be-commit
                                     ↕                          ↕
                              implement agent            code-reviewer agent
                            (RED → GREEN cycle)         (6-dimension review)

Interrupt skills (usable at any stage):
  be-debug    — systematic debugging (4-phase hypothesis-test)
  be-progress — pipeline status dashboard
  be-build    — build + auto-fix (independent)

Standalone audits:
  be-jpa, be-api-review, be-clean-code, be-logging, be-test-review
```

### Pipeline State Machine

```
scaffolded → implementing → implemented → verified → reviewed → done
                                  ↓            ↓          ↓
                            verify-failed  review-failed  fixing
                                  ↓            ↓          ↓
                              be-build     be-fix    be-review (re-review)
```

## Installation

```bash
claude plugin add ./backend-springboot-plugin
```

Then initialize in your project:

```
/backend-springboot-plugin:be-init
```

## Skills

### Core Pipeline

| Skill | Description |
|-------|-------------|
| `be-init` | Initialize plugin config (auto-detects project settings) |
| `be-crud <Entity>` | CQRS CRUD scaffold generation |
| `be-code <feature>` | TDD feature implementation |
| `be-verify [feature]` | Verification gate (build + checkstyle + tests) |
| `be-review <feature>` | Orchestrated 6-dimension code review |
| `be-fix <feature>` | TDD-disciplined fix from review report |
| `be-commit` | Smart commit from staged changes |

### Utility

| Skill | Description |
|-------|-------------|
| `be-build` | Build + auto-diagnose + auto-fix (3 retries) |
| `be-debug <feature>` | Systematic debugging (4-phase hypothesis-test) |
| `be-recall [section]` | Rules reference and violation check |
| `be-progress [feature]` | Pipeline status dashboard with state tracking |

### Standalone Audits

| Skill | Description |
|-------|-------------|
| `be-api-review` | REST API contract audit (HTTP semantics, URL patterns) |
| `be-jpa` | JPA/Hibernate pattern audit (N+1, lazy loading, transactions) |
| `be-clean-code` | DRY/KISS/YAGNI code audit |
| `be-logging` | Structured logging audit (SLF4J, MDC, security) |
| `be-test-review` | Test quality audit (naming, coverage, timing) |

## Agents

| Agent | Model | Description |
|-------|-------|-------------|
| `implement` | opus | TDD-based feature implementation from work documents |
| `build-doctor` | sonnet | Build failure diagnosis and automatic fix |
| `code-reviewer` | opus | Multi-dimension code review (6 dimensions) |
| `review-fixer` | opus | TDD-disciplined fix from review reports |
| `debugger` | opus | Systematic debugging (4-phase hypothesis-test) |

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

## Supported Tech Stack

- Java 21+ / Spring Boot 4.x
- Gradle (Kotlin DSL or Groovy) or Maven
- PostgreSQL, MySQL, MariaDB, H2
- Spring Data JPA / Flyway or Liquibase
- JUnit 5 / Checkstyle / Lombok
