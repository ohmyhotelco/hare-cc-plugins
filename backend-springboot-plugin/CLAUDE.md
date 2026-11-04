# backend-springboot-plugin — maintainer notes

This file is for people editing the plugin. It is **not loaded into any agent's context** (plugin-root
`CLAUDE.md` files are not injected); shared rules for agents live in `skills/be-spring-shared/SKILL.md` and are
preloaded through each agent's `skills:` frontmatter. Do not put agent-facing rules here.

- Plugin-relative paths in agent and skill bodies use `${CLAUDE_PLUGIN_ROOT}`; launches use
  `subagent_type: "backend-springboot-plugin:<agent>"`, because other plugins ship agents with the same names.
- After editing: `claude plugin validate backend-springboot-plugin` and `scripts/check-plugin-consistency.py backend-springboot-plugin`; bump `version` in `plugin.json`, the marketplace entry and the root README label together.

## Pipeline

```
be-plan (spec) → be-crud (scaffold) → be-code (TDD) → be-verify → be-review ↔ be-fix → be-commit
   ↕                                       ↕                          ↕
backend-planner agent              implement agent            code-reviewer agent
(spec → plan.json)                (RED → GREEN cycle)     (6+1 dimension review)

  be-plan is optional: without a planning-plugin spec, be-crud accepts manual field:Type input.
  be-crud is recommended: it generates the CQRS scaffold (entity, repository, commands, queries, controller) that be-code builds upon. Skipping be-crud means be-code starts TDD from scratch without scaffold.
  When plan.json exists, be-crud and be-code auto-detect spec-driven mode.

Interrupt skills (usable at any stage):
  be-debug — systematic debugging (4-phase hypothesis-test methodology)
  be-progress — pipeline status dashboard
  be-build — build + auto-fix (independent of pipeline)
  be-recall — rules reference and violation check

Standalone audit skills (usable independently):
  be-jpa, be-api-review, be-clean-code, be-logging, be-test-review, be-security
```

### Pipeline State Machine

Note: `planned` status is tracked in the spec progress file (by `be-plan`), not in the backend pipeline. The backend pipeline starts at `scaffolded` when `be-crud` is used, or at `implementing` when `be-code` is run directly without `be-crud`.

```
scaffolded → implementing → implemented → verified ─→ reviewed ─→ be-commit
                                                   └→ done ────→ be-commit
                                    ↓            ↓          ↓
                              verify-failed  review-failed  fixing
                                    ↓            ↓          ↓
                                be-build     be-fix    be-review
                                    ↓            ↓     (re-review)
                                be-verify    fixing → reviewed/done
                                    ↓
                                verified

At any point:
  be-debug → resolved | escalated
  resolved → (re-enter pipeline at appropriate stage)
  escalated → (manual intervention, then re-enter)
```

State is tracked in `{workDocDir}/.progress/{feature}.json`. See `templates/progress-schema.md` for the full schema.

## Agent Coordination

### Subagent Isolation Principle

Subagents never inherit session history. Coordinator skills construct only the parameters each agent needs — no conversation context leaks between phases. This prevents context pollution and ensures fresh judgment per task.

## Agents

- `backend-planner` -- Spec analysis agent that reads functional specifications and produces a structured backend implementation plan (plan.json)
- `implement` -- TDD-based feature implementation from work documents or scenario lists
- `build-doctor` -- Gradle build execution, failure diagnosis, and automatic fix with retry
- `code-reviewer` -- Multi-dimension code review (API, JPA, clean code, logging, tests, architecture, + optional spec compliance)
- `review-fixer` -- TDD-disciplined fixer that reads review reports and applies targeted fixes
- `debugger` -- Systematic debugger using 4-phase methodology (reproduce, hypothesize, test, confirm)

## Skills

### Core Pipeline

| Skill | Purpose |
|-------|---------|
| `/backend-springboot-plugin:be-init` | Initialize plugin config for the project |
| `/backend-springboot-plugin:be-plan` | Analyze planning-plugin spec and produce backend plan.json |
| `/backend-springboot-plugin:be-crud` | CQRS CRUD scaffold generation (manual or spec-driven) |
| `/backend-springboot-plugin:be-code` | TDD-driven feature implementation |
| `/backend-springboot-plugin:be-verify` | Verification gate (build + checkstyle + tests) |
| `/backend-springboot-plugin:be-review` | Orchestrated code review (6 dimensions + optional spec compliance) |
| `/backend-springboot-plugin:be-fix` | TDD-disciplined fix from review report |
| `/backend-springboot-plugin:be-commit` | Smart commit from staged changes |

### Utility

| Skill | Purpose |
|-------|---------|
| `/backend-springboot-plugin:be-build` | Build + auto-diagnose + auto-fix (3 retries) |
| `/backend-springboot-plugin:be-debug` | Systematic debugging (4-phase hypothesis-test) |
| `/backend-springboot-plugin:be-recall` | Rules reference and violation check |
| `/backend-springboot-plugin:be-progress` | Pipeline status dashboard with state tracking |

### Standalone Audits

| Skill | Purpose |
|-------|---------|
| `/backend-springboot-plugin:be-jpa` | JPA/Hibernate pattern audit |
| `/backend-springboot-plugin:be-api-review` | REST API contract audit |
| `/backend-springboot-plugin:be-clean-code` | DRY/KISS/YAGNI code audit |
| `/backend-springboot-plugin:be-logging` | Structured logging audit |
| `/backend-springboot-plugin:be-test-review` | Test quality audit |
| `/backend-springboot-plugin:be-security` | Security vulnerability audit |

## Templates

- `tdd-rules.md` -- TDD rules adapted for Spring Boot / Gradle / JUnit 5 (used by: implement, review-fixer agents)
- `cqrs-module.md` -- CQRS module structure reference with code examples (used by: be-crud, implement agent)
- `entity-conventions.md` -- Entity, Repository, DTO record conventions (used by: be-crud, implement agent)
- `test-scenario-template.md` -- Minimal scenario template (used by: be-code when drafting new scenarios)
- `work-document-template.md` -- Full work document template (used by: be-crud for scaffold generation)
- `checkstyle-config.md` -- Checkstyle zero-tolerance configuration reference
- `progress-schema.md` -- Pipeline state file schema and status transitions
- `plan-schema.md` -- Backend plan.json schema and type mapping reference (used by: backend-planner, be-crud)

## Configuration

`.claude/backend-springboot-plugin.json` (created by `/backend-springboot-plugin:be-init`):

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

- `javaVersion`: Java toolchain version (e.g., "21")
- `springBootVersion`: Spring Boot version (e.g., "4.0.2")
- `buildTool`: `"gradle-kotlin"` | `"gradle-groovy"` | `"maven"`
- `buildCommand`: Full build command (default: `./gradlew build`)
- `testCommand`: Test-only command (default: `./gradlew test`)
- `basePackage`: Root Java package (e.g., "com.example")
- `sourceDir`: Main source directory (default: `src/main/java`)
- `testDir`: Test source directory (default: `src/test/java`)
- `architecture`: `"cqrs"` (default) -- determines package structure and templates
- `database`: `"postgresql"` | `"mysql"` | `"h2"` | `"mariadb"`
- `migration`: `"flyway"` | `"liquibase"` | `"none"`
- `checkstyle`: Whether checkstyle is enabled (default: true)
- `lombokEnabled`: Whether Lombok is used (default: true)
- `workDocDir`: Directory for work documents (default: `work/features`)
- `workingLanguage`: Language for user-facing output (`"en"` | `"ko"` | `"vi"`)
