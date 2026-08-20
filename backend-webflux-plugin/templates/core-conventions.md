# Core Conventions (agent-facing)

Trimmed, execution-facing subset of the plugin `CLAUDE.md` for subagents that
generate or review code (`implement`, `code-reviewer`, `review-fixer`,
`backend-planner`) and for `be-code` itself. Omits sections these do not act on
directly — § Pipeline, § Commit Standards, § Build Standards, § Configuration
reference, § Documentation Language, § Repository Structure. Read the full
`CLAUDE.md` instead when a task actually needs one of those.

## Tech Stack (need-to-know)

- Java (version from config), Gradle, Spring Boot + WebFlux (reactive, Netty runtime)
- `Mono`/`Flux` throughout — never block the event loop; blocking work (MyBatis JDBC)
  is offloaded to `Schedulers.boundedElastic()` explicitly, never left inline
- Lombok `@Getter @Setter` on entities when `config.lombokEnabled == true`
- UUID Creator for UUID v7 generation (`UuidCreator.getTimeOrderedEpoch()`)
- Checkstyle zero-tolerance (`maxErrors=0, maxWarnings=0`) when `config.checkstyle == true`

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
- Use `snake_case` for test method names: `duplicate_email_returns_409_Conflict`
- Always add a final newline when creating a new code file
- Write self-explanatory code; avoid comments unless requested
- Work in the smallest possible increments
- **Never call `.block()` / `.blockFirst()` / `.blockLast()` in production code** —
  this defeats the entire point of the reactive stack. `.block()` is only acceptable
  inside `StepVerifier`-free test setup code, and even there `StepVerifier` is
  preferred.

## Entity Conventions (summary — see the profile-specific template for the full code)

Unless explicitly overridden in the feature document:
- `sequence`: Long, auto-increment DB primary key (internal only)
- `id`: UUID v7, unique — external identifier (immutable)
- `createdAt`, `updatedAt`: set explicitly by the executor (no auditing-listener
  equivalent exists for R2DBC/MyBatis in this plugin)
- Table name matches entity name in `snake_case`

## API Conventions

- `POST` create (201), `GET` read (200), `PUT` full replace (200), `PATCH` partial
  update (200), `DELETE` remove (204)
- URL: kebab-case, plural resources: `/hr/employees/{id}/profile-image`
- Domain exceptions mapped to HTTP status via a router-level `onErrorResume` chain
  (functional style) or `@ExceptionHandler` (annotated style)

## CQRS Scope Note

Application-level command/query separation — separate packages and DTOs for writes
vs. reads — not full CQRS with a separate read-model store or eventual consistency.
Both sides go through the same repository/mapper against the same tables. See
`docs/decisions.md` Decision 8 before describing this pattern as "full CQRS."

## Verification Philosophy

"Evidence before claims, always." 5-Step Gate: IDENTIFY the target to verify → RUN
the verification tool (build, test, checkstyle, coverage) → READ the full output →
VERIFY it matches the claim → CLAIM the result citing evidence.

| Thought | Reality |
|---------|---------|
| "Should work" / "probably fine" | Run the build. Evidence or silence. |
| "The change is small, no need to verify" | Small changes cause big bugs. Verify always. |
| "Tests passed, so it's correct" | Tests cover what was written, not what was missed. Check the spec. |
| "Compilation passed, so the build will too" | Compilation != checkstyle != tests. |
| "It returned a value, so the reactive chain worked" | A `Mono` never subscribed to never runs. Verify with `StepVerifier` or a real call. |
