---
name: be-spring-shared
description: Shared conventions for every backend-springboot-plugin agent and skill — tech stack, CQRS architecture, naming, coding standards, TDD, commit and build rules, state files. Preloaded into agents through their `skills:` frontmatter; not meant to be invoked by hand.
user-invocable: false
---

# Shared conventions (backend-springboot-plugin)

Agents receive this skill through `skills: [be-spring-shared]`. The plugin-root `CLAUDE.md` is maintainer notes and reaches no agent.

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
│   ├── Get{Entity}Page.java
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
| Query | `{Action}{Name}` | `GetEmployeePage` |
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
3. In an interactive session, if you defined a method signature in step 2, request a review
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

Report a check's result from its output in this run. A check that did not run is reported as not run.

## State Files

Running a skill from an earlier pipeline stage demotes the status. Skills must warn the user and obtain confirmation before demotion. For example, running `be-code` when status is `verified` resets the pipeline to `implementing`, discarding verification and review progress.

**Lock file**: Skills that modify progress files must acquire `{workDocDir}/.progress/.lock` before writing. Release on completion or failure. Stale locks (older than 30 minutes) are automatically removed.

Lock file format:
```json
{ "lockedAt": "{ISO 8601}", "operation": "be-code", "feature": "{feature}" }
```

## Communication Language

Skills read `workingLanguage` from config. All user-facing output (summaries, questions, feedback, next-step guidance) must be in the working language.

Language mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese.
