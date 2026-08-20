# Backend WebFlux Plugin

A Claude Code plugin that applies tech stack and coding conventions for Spring
WebFlux backend development with CQRS architecture and strict TDD methodology.

This plugin targets the Spring WebFlux stack end to end: WebFlux + R2DBC/MyBatis for
the data layer, `RouterFunction`/`HandlerFunction` for the web layer by default, and
CQRS for the architecture. It is self-contained — using it does not require any other
plugin in this repository to be installed. See `docs/decisions.md` for the full
data-profile rationale — read it before changing any template in this plugin.

## Tech Stack

### Language & Build
- Java (version from config, default 21)
- Build: Gradle (Kotlin DSL or Groovy DSL, from config)
- Build command: `./gradlew build` (configurable)
- Test command: `./gradlew test` (configurable)
- Always set Bash tool timeout to 10 minutes (600000ms) for Gradle commands

### Framework
- Spring Boot (version from config) with Spring WebFlux (reactive, Netty runtime)
- Spring Validation
- Project Reactor (`Mono`/`Flux`) as the reactive types throughout — never block the
  event loop; blocking work (MyBatis JDBC calls) is offloaded to
  `Schedulers.boundedElastic()` explicitly, never left to run inline

### Database & Data Profile

Read `dataProfile` from `.claude/backend-webflux-plugin.json`. Default is `"both"`.
Accepted values: `"r2dbc" | "mybatis" | "both"`. See `docs/decisions.md` Decision 1
for rationale — this plugin supports both because many real WebFlux backends are not
uniformly R2DBC: a large, pre-existing module built on WebFlux + MyBatis (blocking
JDBC offloaded to `boundedElastic`) can coexist with newer modules built on WebFlux +
R2DBC in the same system.

- **R2DBC profile**: Spring Data R2DBC, `ReactiveCrudRepository` /
  `R2dbcRepository`, `TransactionalOperator` for multi-step writes (see
  `docs/decisions.md` Decision 7 for the current — partially open — guidance on
  nested transactional composition)
- **MyBatis profile**: `mybatis-spring-boot-starter`, XML mappers under
  `src/main/resources/mapper/`, blocking calls wrapped with
  `Mono.fromCallable(...).subscribeOn(Schedulers.boundedElastic())`
- **Default guidance**: new bounded contexts default to R2DBC (simplest, purely
  reactive); use MyBatis when extending an existing MyBatis-based module's
  conventions, or when a query needs joins/complexity R2DBC's dialect doesn't
  support well
- Database: configurable (default **MySQL 8.0.33** — not PostgreSQL; see
  `docs/decisions.md` Decision 4)
- R2DBC MySQL driver: pin `io.asyncer:r2dbc-mysql:1.1.3` — never `dev.miku:*`
  (archived; see `docs/decisions.md` Decision 5)
- Migration: manual SQL files under `{resourcesDir}/migration/V{n}__{description}.sql`
  — no Flyway, no Liquibase (see `docs/decisions.md` Decision 3). Application of the
  SQL is out of this plugin's scope.

### Web Layer

Mixed by explicit rule, not a blanket ban — see `docs/decisions.md` Decision 2:

- **Default**: `RouterFunction` + `HandlerFunction` (functional endpoint style) for
  new domains. `be-crud` generates this by default.
- **Named exception**: `@RestController` returning `Mono`/`Flux` is accepted when a
  service deliberately mirrors an existing annotated-controller module (set
  `webLayer: "annotated"` in config). Never mix both styles inside one domain.

### Vendor / Outbound Integration

Applies only when a domain calls an external vendor/third-party HTTP API rather than
only this service's own database — see `templates/vendor-integration.md` for the
full pattern set (timeout, retry, circuit breaker, reconciliation via `retrieve()`,
cancel confirmation, fan-out isolation, cache/repricing, adapter-boundary
normalization). Most CRUD-only domains never need this.

- Outbound calls live in `{domain}/client/{Vendor}Client.java` — never in `data/`,
  and never inside a `TransactionalOperator`-wrapped `Mono` (Decision 7 addendum)
- `WebClient` on Reactor Netty `HttpClient`, with connect-timeout and read-timeout
  configured separately, plus an independent `.timeout(Duration)` on the reactive
  chain itself
- Resilience4j (configurable, default enabled for a domain with a `client/` package)
  for circuit breaking — one named `CircuitBreaker` instance per vendor, never one
  shared across vendors
- Retry only idempotent operations (`retrieve`, `cancel`), never a blind retry on a
  create/booking call without vendor-side idempotency support; always
  backoff + jitter + a hard attempt cap, and never retry a 4xx

### Utilities
- Lombok (configurable, default enabled)
- UUID Creator for UUID v7 generation

### Testing
- JUnit 5 (Mockito is allowed here — reactive collaborators are frequently mocked
  with `Mono.just(...)` / `StepVerifier`, unlike the blocking-MVC plugin's
  real-Spring-context-only rule)
- `@SpringBootTest` + `WebTestClient` for API integration tests (not
  `TestRestTemplate` — it is a blocking client and does not exercise the reactive
  pipeline realistically)
- `@DataR2dbcTest` for R2DBC repository tests (not `@DataJpaTest` — there is no JPA
  in this plugin)
- MyBatis mapper tests use `@MybatisTest` (or a plain `@SpringBootTest` slice with an
  embedded/test datasource) plus `StepVerifier` once the mapper call is wrapped in
  `Mono`/`Flux`
- `StepVerifier` for asserting `Mono`/`Flux` behavior directly (`expectNext`,
  `verifyComplete`, `expectError`)
- AssertJ for assertions on materialized results
- `@ParameterizedTest` + `@ValueSource` / `@MethodSource` for multi-value scenarios

### Code Quality
- Checkstyle (configurable, default enabled) with zero tolerance (maxErrors=0, maxWarnings=0)
- **Coverage**: JaCoco line coverage, report-only in this plugin's initial gate — no
  threshold enforced yet (see `docs/decisions.md` Decision 6 and `be-verify`)

## Architecture: CQRS Pattern

Read `architecture` from `.claude/backend-webflux-plugin.json`. Default is `cqrs`.

**Scope note**: this is application-level command/query separation — separate
packages and DTOs for writes vs. reads — not full CQRS with a separate read-model
store or eventual consistency. Both sides go through the same repository/mapper
against the same tables. See `docs/decisions.md` Decision 8 before describing this
pattern to a user as "full CQRS" or promising independent read/write scaling.

### Package Structure (CQRS)

```
{basePackage}/
├── {App}Application.java
├── command/                    <- Request command DTOs (records)
│   └── Create{Entity}.java
├── commandmodel/               <- Command execution logic, returns Mono<Void>/Mono<Id>
│   └── Create{Entity}CommandExecutor.java
├── query/                      <- Request query DTOs (records)
│   ├── Get{Entity}Page.java
│   └── Find{Entity}.java
├── querymodel/                 <- Query processing logic, returns Mono<T>/Flux<T>
│   ├── Get{Entity}PageQueryProcessor.java
│   └── Find{Entity}QueryProcessor.java
├── view/                       <- Response view DTOs (records)
│   └── {Entity}View.java
├── data/                       <- Entities and repositories (R2DBC) or mappers (MyBatis)
│   ├── {Entity}.java
│   ├── {Entity}Repository.java        <- R2DBC profile
│   ├── {Entity}Mapper.java            <- MyBatis profile (interface, @Mapper)
│   └── BaseEntity.java
├── config/                     <- Spring configuration beans (router config lives here
│                                   for the functional web-layer default)
├── {domain}/                   <- Domain-specific business logic
│   ├── api/                    <- RouterFunction + HandlerFunction (default) or
│   │                               @RestController (named exception, see Decision 2)
│   │   └── {Entity}Router.java / {Entity}Handler.java
│   ├── client/                 <- Outbound vendor calls, only if this domain calls
│   │   └── {Vendor}Client.java     an external vendor -- see templates/vendor-integration.md
│   ├── {Description}Exception.java
│   └── {Entity}PropertyValidator.java
└── ...
```

### Data Flow

```
HTTP Request
  → RouterFunction routes to HandlerFunction (or @RestController method)
    → Command/Query DTO
      → CommandExecutor / QueryProcessor (@Component record, returns Mono/Flux)
        → Repository (R2DBC) or Mapper (MyBatis, offloaded to boundedElastic)
          → Entity
    → View DTO (response), materialized by Reactor's Mono/Flux pipeline
```

## Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Entity | `{Name}` | `Employee` |
| Repository (R2DBC) | `{Name}Repository` | `EmployeeRepository` |
| Mapper (MyBatis) | `{Name}Mapper` | `EmployeeMapper` |
| Command | `{Action}{Name}` | `CreateEmployee` |
| Command Executor | `{Command}CommandExecutor` | `CreateEmployeeCommandExecutor` |
| Query | `{Action}{Name}` | `GetEmployeePage` |
| Query Processor | `{Query}QueryProcessor` | `GetEmployeePageQueryProcessor` |
| View | `{Name}View` | `EmployeeView` |
| Router | `{Name}Router` | `EmployeeRouter` |
| Handler | `{Name}Handler` | `EmployeeHandler` |
| Controller (annotated exception) | `{Name}Controller` (record) | `EmployeeController` |
| Vendor client | `{Vendor}Client` | `AcmeClient` |
| Exception | `{Description}Exception` | `DuplicateEmailException` |
| Test | `{HttpMethod}Tests` | `PostTests` |

## Coding Standards

- Use `var` when the type is obvious from context; avoid when it harms readability
- Use Java `record` for all DTO-like classes (Command, View, Query)
- Use Lombok `@Getter @Setter` for entities (when `lombokEnabled: true`)
- Use `snake_case` for test method names: `duplicate_email_returns_409_Conflict`
- Always add a final newline when creating a new code file
- Write self-explanatory code; avoid comments unless requested
- Work in the smallest possible increments
- **Never call `.block()` / `.blockFirst()` / `.blockLast()` in production code** —
  this defeats the entire point of the reactive stack. `.block()` is only acceptable
  inside `StepVerifier`-free test setup code, and even there `StepVerifier` is
  preferred.

### Entity Conventions

See `templates/entity-conventions-r2dbc.md` or `templates/entity-conventions-mybatis.md` for the full profile-specific templates (`templates/entity-conventions.md` holds the DTO/exception/validator templates shared by both).
Unless explicitly overridden in the feature document:
- `sequence`: Long, auto-increment DB primary key (internal only)
- `id`: UUID v7, unique — external identifier (immutable)
- `createdAt`, `updatedAt`: set explicitly by the executor (no `@EnableJpaAuditing`
  equivalent exists for R2DBC/MyBatis in this plugin — see the template for the
  exact pattern used instead)
- Table name matches entity name in `snake_case`
- Indexes and unique constraints: define per entity in feature document, applied via
  manual SQL migration (Decision 3)

### DTO Conventions

```java
public record CreateEmployee(String email, String displayName) {}
public record EmployeeView(UUID id, String email, String displayName) {}
```

## API Conventions

- RESTful style: HTTP methods define the action
  - `POST` -- create (201 Created)
  - `GET` -- read (200 OK)
  - `PUT` -- full replace (200 OK)
  - `PATCH` -- partial update (200 OK)
  - `DELETE` -- remove (204 No Content)
- URL: kebab-case, plural resources: `/hr/employees/{id}/profile-image`
- Error responses: domain exceptions mapped to HTTP status codes via a router-level
  `onErrorResume` chain (functional style) or `@ExceptionHandler` (annotated style)

## Test-Driven Development

### TDD Process

1. Write a list of the test scenarios you want to cover
2. Turn exactly one item on the list into an actual, concrete, runnable test
3. Change the code to make the test (and all previous tests) pass
4. Optionally refactor to improve the implementation design
5. Until the list is empty, go back to step 2

### TDD Rules

- The list of test scenarios must be prepared in advance
- Do not write more than one test at a time
- Do not write code that is not required to pass a test (no speculative code)
- Never modify a failed test; if a test needs to change, update it manually

See `templates/tdd-rules.md` for the full WebFlux-adapted rules (`WebTestClient`,
`@DataR2dbcTest`, `StepVerifier`).

## Commit Standards

1. Write in English
2. Use present tense in the subject line ("Add feature" not "Added feature")
3. Keep the subject line to 50 characters or less
4. Add a blank line between the subject and body
5. Keep the body to 72 characters or less per line
6. Only break lines within a paragraph when exceeding 72 characters
7. Do not mention test code in commit messages
8. Do not use any prefix (fix:, feat:, docs:, etc.) in the subject line
9. Start with an uppercase letter (exception: lowercase identifiers with justification)
10. Do not include tool advertisements, branding, or promotional content
11. Only operate on already-staged changes -- never stage additional files
12. Ensure all intended changes are staged before invoking commit
13. Use separate git commands to stage files before committing

## Build Standards

- Execute build command with 10-minute Bash tool timeout (600000ms)
- Always run full build before committing changes
- Address all errors and warnings systematically
- Categorize errors: compilation, test failures, dependency issues, configuration problems, checkstyle violations
- Apply systematic error resolution with targeted fixes

## Verification Philosophy

A principle applied across all agents and skills: **"Evidence before claims, always."**

5-Step Gate:
1. **IDENTIFY** -- identify the target to verify
2. **RUN** -- execute verification tool (build, test, checkstyle, coverage)
3. **READ** -- review the full output (exit code, error count, coverage %)
4. **VERIFY** -- determine whether the output matches the claim
5. **CLAIM** -- report the result citing evidence

Verification Red Flags -- these thoughts mean you are rationalizing:

| Thought | Reality |
|---------|---------|
| "Should work" / "probably fine" | Run the build. Evidence or silence. |
| "The change is small, no need to verify" | Small changes cause big bugs. Verify always. |
| "I already verified this earlier" | Code changed since. Verify again. |
| "Tests passed, so it's correct" | Tests cover what was written, not what was missed. Check the spec. |
| "Compilation passed, so the build will too" | Compilation != checkstyle != tests. Different tools catch different errors. |
| "I'll verify at the end" | Errors compound. Verify at each step. |
| "The error is unrelated to my change" | Prove it. Run the verification. |
| "It returned a value, so the reactive chain worked" | A `Mono` that's never subscribed to never runs. Verify with `StepVerifier` or an actual HTTP call, not by reading the code. |

## Pipeline

```
be-plan (spec) → be-crud (scaffold) → be-code (TDD) → be-verify → be-review ↔ be-fix → be-commit
   ↕                                       ↕                          ↕
backend-planner agent              implement agent            code-reviewer agent
(spec → plan.json)                (RED → GREEN cycle)     (6+1 dimension review)

  be-plan is optional: without a planning-plugin spec, be-crud accepts manual field:Type input.
  be-crud is recommended: it generates the CQRS scaffold (entity, repository/mapper, commands,
  queries, router/controller) that be-code builds upon. Skipping be-crud means be-code starts
  TDD from scratch without scaffold.
  When plan.json exists, be-crud and be-code auto-detect spec-driven mode.

Interrupt skills (usable at any stage):
  be-debug — systematic debugging (4-phase hypothesis-test methodology)
  be-progress — pipeline status dashboard
  be-build — build + auto-fix (independent of pipeline)
  be-recall — rules reference and violation check

Standalone audit skills (usable independently):
  be-data, be-api-review, be-clean-code, be-logging, be-test-review, be-security, be-integrate-review

Automated entry point: the `jira-auto` agent runs this same be-crud → be-code → be-verify →
(be-review + be-security) → be-fix → be-commit chain end to end from a Jira ticket, stopping
at be-commit — it never pushes, opens a pull request, or touches the Jira issue itself.
be-security only runs for tickets that add a new entity/endpoint (or mention anything
security-sensitive); be-verify and be-review always run regardless of ticket size.
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
                                    │
                             (verified includes a Coverage row —
                              report-only, no threshold failure)

At any point:
  be-debug → resolved | escalated
  resolved → (re-enter pipeline at appropriate stage)
  escalated → (manual intervention, then re-enter)
```

State is tracked in `{workDocDir}/.progress/{feature}.json`. See `templates/progress-schema.md` for the full schema.

### Demotion Warning

Running a skill from an earlier pipeline stage demotes the status. Skills must warn the user and obtain confirmation before demotion. For example, running `be-code` when status is `verified` resets the pipeline to `implementing`, discarding verification and review progress.

### State File Safety

**Lock file**: Skills that modify progress files must acquire `{workDocDir}/.progress/.lock` before writing. Release on completion or failure. Stale locks (older than 30 minutes) are automatically removed.

Lock file format:
```json
{ "lockedAt": "{ISO 8601}", "operation": "be-code", "feature": "{feature}" }
```

## Agent Coordination

### Subagent Isolation Principle

Subagents never inherit session history. Coordinator skills construct only the parameters each agent needs — no conversation context leaks between phases. This prevents context pollution and ensures fresh judgment per task.

## Agents

- `backend-planner` -- Spec analysis agent that reads functional specifications and produces a structured backend implementation plan (plan.json)
- `implement` -- TDD-based feature implementation from work documents or scenario lists
- `build-doctor` -- Gradle build execution, failure diagnosis, and automatic fix with retry
- `code-reviewer` -- Multi-dimension code review (API, data layer, clean code, logging, tests, architecture, + optional spec compliance)
- `review-fixer` -- TDD-disciplined fixer that reads review reports and applies targeted fixes
- `debugger` -- Systematic debugger using 4-phase methodology (reproduce, hypothesize, test, confirm)
- `jira-auto` -- Orchestrator that implements a ticket's own stated Technical Approach directly when present, or drafts a Proposed Solution and stops for user confirmation when not, classifies the ticket into a tier (easy/normal/extreme) to scale the review gate, and drives the full be-crud → be-code → be-verify → (be-review + be-security) → be-fix → be-commit pipeline end to end via the Skill tool, instead of running each be-* skill by hand

## Skills

### Core Pipeline

| Skill | Purpose |
|-------|---------|
| `/backend-webflux-plugin:be-init` | Initialize plugin config for the project |
| `/backend-webflux-plugin:be-plan` | Analyze planning-plugin spec and produce backend plan.json |
| `/backend-webflux-plugin:be-crud` | CQRS CRUD scaffold generation (manual or spec-driven) |
| `/backend-webflux-plugin:be-code` | TDD-driven feature implementation |
| `/backend-webflux-plugin:be-verify` | Verification gate (build + checkstyle + tests + coverage) |
| `/backend-webflux-plugin:be-review` | Orchestrated code review (6 dimensions + optional spec compliance) |
| `/backend-webflux-plugin:be-fix` | TDD-disciplined fix from review report |
| `/backend-webflux-plugin:be-commit` | Smart commit from staged changes |

### Utility

| Skill | Purpose |
|-------|---------|
| `/backend-webflux-plugin:be-build` | Build + auto-diagnose + auto-fix (3 retries) |
| `/backend-webflux-plugin:be-debug` | Systematic debugging (4-phase hypothesis-test) |
| `/backend-webflux-plugin:be-recall` | Rules reference and violation check |
| `/backend-webflux-plugin:be-progress` | Pipeline status dashboard with state tracking |

### Standalone Audits

| Skill | Purpose |
|-------|---------|
| `/backend-webflux-plugin:be-data` | R2DBC / MyBatis data-layer pattern audit |
| `/backend-webflux-plugin:be-api-review` | REST API contract audit (RouterFunction + annotated) |
| `/backend-webflux-plugin:be-clean-code` | DRY/KISS/YAGNI code audit |
| `/backend-webflux-plugin:be-logging` | Structured logging audit |
| `/backend-webflux-plugin:be-test-review` | Test quality audit |
| `/backend-webflux-plugin:be-security` | Security vulnerability audit |
| `/backend-webflux-plugin:be-integrate-review` | Vendor/outbound-integration audit (timeout, retry, circuit breaker, reconciliation) |

## Templates

- `core-conventions.md` -- Trimmed, execution-facing subset of this file (naming table, coding standards, API conventions, verification philosophy) for subagents that never need § Pipeline/Commit/Build/Configuration (used by: be-code skill, implement/code-reviewer/review-fixer/backend-planner agents)
- `tdd-rules.md` -- TDD rules adapted for WebFlux / Gradle / JUnit 5 / StepVerifier (used by: implement, review-fixer agents)
- `cqrs-module.md` -- CQRS package layout reference, pointing to the profile/web-layer files below for actual code (used by: be-crud, implement agent)
- `entity-conventions.md` -- Shared DTO/exception/validator conventions for both data profiles, pointing to the two files below for entity/repository/executor code (used by: be-crud, implement agent)
- `entity-conventions-r2dbc.md` -- R2DBC entity, repository, CommandExecutor, and QueryProcessor templates (used by: be-crud, implement agent, only when the entity's resolved `dataProfile` is `r2dbc`)
- `entity-conventions-mybatis.md` -- MyBatis POJO, mapper, CommandExecutor, and QueryProcessor templates (used by: be-crud, implement agent, only when the entity's resolved `dataProfile` is `mybatis`)
- `web-layer-functional.md` -- RouterFunction/HandlerFunction templates (used by: be-crud, implement agent, only when `config.webLayer == "functional"`)
- `web-layer-annotated.md` -- `@RestController` templates (used by: be-crud, implement agent, only when `config.webLayer == "annotated"`)
- `vendor-integration.md` -- Timeout, retry, circuit breaker, reconciliation, and cancel-confirmation conventions for a domain that calls an external vendor (used by: be-integrate-review, implement agent when a `client/` package exists)
- `coverage-gate.md` -- JaCoco Gradle configuration reference (used by: be-verify, be-init)
- `test-scenario-template.md` -- Minimal scenario template (used by: be-code when drafting new scenarios)
- `work-document-template.md` -- Full work document template (used by: be-crud for scaffold generation)
- `checkstyle-config.md` -- Checkstyle zero-tolerance configuration reference
- `progress-schema.md` -- Pipeline state file schema and status transitions
- `plan-schema.md` -- Backend plan.json schema and type mapping reference (used by: backend-planner, be-crud)

## Configuration

`.claude/backend-webflux-plugin.json` (created by `/backend-webflux-plugin:be-init`):

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

- `javaVersion`: Java toolchain version (e.g., "21")
- `springBootVersion`: Spring Boot version (e.g., "4.0.2")
- `buildTool`: `"gradle-kotlin"` | `"gradle-groovy"` | `"maven"`
- `buildCommand`: Full build command (default: `./gradlew build`)
- `testCommand`: Test-only command (default: `./gradlew test`)
- `basePackage`: Root Java package (e.g., "com.example")
- `sourceDir`: Main source directory (default: `src/main/java`)
- `testDir`: Test source directory (default: `src/test/java`)
- `architecture`: `"cqrs"` (default) -- determines package structure and templates
- `dataProfile`: `"r2dbc"` | `"mybatis"` | `"both"` (default `"both"`) — see `docs/decisions.md` Decision 1
- `webLayer`: `"functional"` (default, RouterFunction/HandlerFunction) | `"annotated"` (@RestController exception) — see `docs/decisions.md` Decision 2
- `database`: `"mysql"` (default) | `"postgresql"` | `"h2"` | `"mariadb"`
- `migration`: `"manual-sql"` (default, no runner) | `"flyway"` | `"liquibase"` (only if a project explicitly opts back in)
- `checkstyle`: Whether checkstyle is enabled (default: true)
- `coverage`: Whether the JaCoco coverage row runs in `be-verify` (default: true; report-only, no threshold — see `docs/decisions.md` Decision 6)
- `lombokEnabled`: Whether Lombok is used (default: true)
- `workDocDir`: Directory for work documents (default: `work/features`)
- `workingLanguage`: Language for user-facing output (`"en"` | `"ko"` | `"vi"`)

### Communication Language

Skills read `workingLanguage` from config. All user-facing output (summaries, questions, feedback, next-step guidance) must be in the working language.

Language mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese.
