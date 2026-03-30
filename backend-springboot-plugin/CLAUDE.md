# Backend Spring Boot Plugin

A Claude Code plugin that applies tech stack and coding conventions for Spring Boot backend development with CQRS architecture and strict TDD methodology.

## Tech Stack

### Language & Build
- Java (version from config, default 21)
- Build: Gradle (Kotlin DSL or Groovy DSL, from config)
- Build command: `./gradlew build` (configurable)
- Test command: `./gradlew test` (configurable)
- Always set Bash tool timeout to 10 minutes (600000ms) for Gradle commands

### Framework
- Spring Boot (version from config)
- Spring MVC (REST)
- Spring Validation

### Database & ORM
- Database: configurable (default PostgreSQL)
- ORM: Spring Data JPA (Hibernate)
- Migration: configurable (default Flyway)
- JPA Auditing: `@EnableJpaAuditing` for automatic `createdAt`/`updatedAt`
- `open-in-view: false` (mandatory)

### Utilities
- Lombok (configurable, default enabled)
- UUID Creator for UUID v7 generation

### Testing
- JUnit 5 (no Mockito)
- `@SpringBootTest` + `TestRestTemplate` for API integration tests
- `@DataJpaTest` for repository tests
- AssertJ for assertions
- `@ParameterizedTest` + `@ValueSource` / `@MethodSource` for multi-value scenarios

### Code Quality
- Checkstyle (configurable, default enabled) with zero tolerance (maxErrors=0, maxWarnings=0)

## Architecture: CQRS Pattern

Read `architecture` from `.claude/backend-springboot-plugin.json`. Default is `cqrs`.

### Package Structure (CQRS)

```
{basePackage}/
├── {App}Application.java
├── command/                    <- Request command DTOs (records)
│   └── Create{Entity}.java
├── commandmodel/               <- Command execution logic
│   └── Create{Entity}CommandExecutor.java
├── query/                      <- Request query DTOs (records)
│   ├── Get{Entities}.java
│   └── Find{Entity}.java
├── querymodel/                 <- Query processing logic
│   ├── Get{Entity}PageQueryProcessor.java
│   └── Find{Entity}QueryProcessor.java
├── view/                       <- Response view DTOs (records)
│   └── {Entity}View.java
├── data/                       <- Entities and repositories
│   ├── {Entity}.java
│   ├── {Entity}Repository.java
│   └── BaseEntity.java
├── config/                     <- Spring configuration beans
├── {domain}/                   <- Domain-specific business logic
│   ├── api/                    <- REST controllers
│   │   └── {Entity}Controller.java
│   ├── {Description}Exception.java
│   └── {Entity}PropertyValidator.java
└── ...
```

### Data Flow

```
HTTP Request
  → Controller (record class, DI via constructor)
    → Command/Query DTO
      → CommandExecutor / QueryProcessor (@Component record)
        → Repository (Spring Data JPA)
          → Entity
    → View DTO (response)
```

## Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Entity | `{Name}` | `Employee` |
| Repository | `{Name}Repository` | `EmployeeRepository` |
| Command | `{Action}{Name}` | `CreateEmployee` |
| Command Executor | `{Command}CommandExecutor` | `CreateEmployeeCommandExecutor` |
| Query | `{Action}{Name}` | `GetEmployees` |
| Query Processor | `{Query}QueryProcessor` | `GetEmployeePageQueryProcessor` |
| View | `{Name}View` | `EmployeeView` |
| Controller | `{Name}Controller` (record) | `EmployeeController` |
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

### Entity Conventions

Unless explicitly overridden in the feature document:
- Extends `BaseEntity` (`createdAt`, `updatedAt` via JPA Auditing)
- `sequence`: Long, `@GeneratedValue(IDENTITY)` -- DB primary key (internal only)
- `id`: UUID v7, unique -- external identifier (immutable)
- `@Table(name = "snake_case")` -- table name matches entity name in snake_case
- Column naming: Spring default `camelCase` to `snake_case` (implicit naming strategy)
- Indexes and unique constraints: define per entity in feature document

### DTO Conventions

```java
public record CreateEmployee(String email, String displayName) {}
public record EmployeeView(UUID id, String email, String displayName) {}
```

### Controller Conventions (Record-based DI)

```java
@RestController
public record EmployeeController(
    CreateEmployeeCommandExecutor createExecutor,
    GetEmployeePageQueryProcessor pageProcessor,
    FindEmployeeQueryProcessor findProcessor
) {
    @PostMapping("/hr/employees")
    @ResponseStatus(HttpStatus.CREATED)
    public void create(@RequestBody CreateEmployee command) {
        createExecutor.execute(command);
    }
}
```

## API Conventions

- RESTful style: HTTP methods define the action
  - `POST` -- create (201 Created)
  - `GET` -- read (200 OK)
  - `PUT` -- full replace (200 OK)
  - `PATCH` -- partial update (200 OK)
  - `DELETE` -- remove (204 No Content)
- URL: kebab-case, plural resources: `/hr/employees/{id}/profile-image`
- Error responses: domain exceptions mapped to HTTP status codes via `@ExceptionHandler`

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

### TDD Implementation Workflow

1. Select one incomplete test scenario (`- [ ]` item)
2. If the minimum method signature is not defined, add only the method(s) needed for that scenario (empty body or default return). Do not add methods for other scenarios.
3. If you defined a method signature in step 2, request a review
4. Convert the selected scenario into a concrete, executable test
5. Run the test and check the result
6. Confirm that the test fails. If it passes unexpectedly, stop and request review
7. Understand the failure cause and write minimum code to make the test pass
8. Run the entire test class: `./gradlew test --tests {fullTestClassName}` (10-minute timeout)
9. Do not run individual test methods -- always run the entire test class
10. If the test does not pass after 3 attempts, stop and request review
11. If the build fails, analyze and fix. Repeat until the build succeeds
12. Mark the scenario as completed: `- [x] scenario description`

### Test Scenario Writing Rules

1. Write one scenario at a time (most important first)
2. Write in a single sentence
3. Write in English
4. Use the present tense
5. Refer to the system under test as `sut`
6. Do not start with a capital letter (usable as test method name)
7. Write as concisely as possible while preserving meaning
8. Write as a to-do item: `- [ ] scenario description`

### Test Structure

Test directory mirrors the API URL path:

```
API URL                     Test path
POST /hr/employees    ->    test/{basePackage}/hr/api/employees/PostTests.java
GET  /hr/employees    ->    test/{basePackage}/hr/api/employees/GetTests.java
```

Test patterns:
- `@SpringBootTest(webEnvironment = RANDOM_PORT)` + `TestRestTemplate`
- No Mockito -- pure integration tests with real Spring context
- Test doubles: `@TestComponent @Primary` fakes (e.g., `FakeEmailSender`)
- Generators: atomic counter-based test data factories (`EmailGenerator`, etc.)

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
2. **RUN** -- execute verification tool (build, test, checkstyle)
3. **READ** -- review the full output (exit code, error count)
4. **VERIFY** -- determine whether the output matches the claim
5. **CLAIM** -- report the result citing evidence

Verification Red Flags -- these thoughts mean you are rationalizing:

| Thought | Reality |
|---------|---------|
| "Should work" / "probably fine" | Run the build. Evidence or silence. |
| "The change is small, no need to verify" | Small changes cause big bugs. Verify always. |
| "I already verified this earlier" | Code changed since. Verify again. |
| "Tests passed, so it's correct" | Tests cover what was written, not what was missed. Check the spec. |
| "I'll verify at the end" | Errors compound. Verify at each step. |

## Pipeline

```
be-init → be-crud (scaffold) → be-code (TDD) → be-verify → be-review ↔ be-fix → be-commit
                                     ↕                          ↕
                              implement agent            code-reviewer agent
                            (RED → GREEN cycle)         (6-dimension review)

Interrupt skills (usable at any stage):
  be-debug — systematic debugging (4-phase hypothesis-test methodology)
  be-progress — pipeline status dashboard
  be-build — build + auto-fix (independent of pipeline)

Standalone audit skills (usable independently):
  be-jpa, be-api-review, be-clean-code, be-logging, be-test-review
```

### Pipeline State Machine

```
scaffolded → implementing → implemented → verified → reviewed → done
                                  ↓            ↓          ↓
                            verify-failed  review-failed  fixing
                                  ↓            ↓          ↓
                              be-build     be-fix    be-review
                                  ↓            ↓     (re-review)
                              verified     fixing → reviewed/done

At any point:
  be-debug → resolved | escalated
  resolved → (re-enter pipeline at appropriate stage)
  escalated → (manual intervention, then re-enter)
```

State is tracked in `{workDocDir}/.progress/{feature}.json`. See `templates/progress-schema.md` for the full schema.

## Agents

- `implement` -- TDD-based feature implementation from work documents or scenario lists
- `build-doctor` -- Gradle build execution, failure diagnosis, and automatic fix with retry
- `code-reviewer` -- Multi-dimension code review (API, JPA, clean code, logging, tests, architecture)
- `review-fixer` -- TDD-disciplined fixer that reads review reports and applies targeted fixes
- `debugger` -- Systematic debugger using 4-phase methodology (reproduce, hypothesize, test, confirm)

## Skills

### Core Pipeline

| Skill | Purpose |
|-------|---------|
| `/backend-springboot-plugin:be-init` | Initialize plugin config for the project |
| `/backend-springboot-plugin:be-crud` | CQRS CRUD scaffold generation |
| `/backend-springboot-plugin:be-code` | TDD-driven feature implementation |
| `/backend-springboot-plugin:be-verify` | Verification gate (build + checkstyle + tests) |
| `/backend-springboot-plugin:be-review` | Orchestrated 6-dimension code review |
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

## Templates

- `tdd-rules.md` -- TDD rules adapted for Spring Boot / Gradle / JUnit 5
- `cqrs-module.md` -- CQRS module structure reference with code examples
- `entity-conventions.md` -- Entity, Repository, DTO record conventions
- `test-scenario-template.md` -- Work document template for test scenarios
- `work-document-template.md` -- Full work document template
- `checkstyle-config.md` -- Checkstyle zero-tolerance configuration reference
- `progress-schema.md` -- Pipeline state file schema and status transitions

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

### Communication Language

Skills read `workingLanguage` from config. All user-facing output (summaries, questions, feedback, next-step guidance) must be in the working language.

Language mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese.
