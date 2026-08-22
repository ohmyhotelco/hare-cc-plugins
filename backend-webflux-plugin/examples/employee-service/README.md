# employee-service (sample)

Sample service generated to demonstrate `backend-webflux-plugin`'s conventions and
verification gate — a sample service that compiles and passes its own verification
gate. It follows the CQRS
package layout in `templates/cqrs-module.md`, the R2DBC entity/repository conventions
in `templates/entity-conventions-r2dbc.md` (DTOs in `templates/entity-conventions.md`),
and the functional (`RouterFunction`/`HandlerFunction`) web layer default from
`templates/web-layer-functional.md` / `docs/decisions.md` Decision 2.

## Data profile used here

This sample uses the **R2DBC** profile (not MyBatis) for simplicity — a real project
using `dataProfile: "both"` would also have a MyBatis-profile entity demonstrating the
`Schedulers.boundedElastic()` offload pattern from
`templates/entity-conventions-mybatis.md`; that second example was not generated here
due to time constraints, but the pattern itself is fully documented in the template.

## Runtime database

This sample runs against an **in-memory H2** database via R2DBC
(`src/main/resources/schema.sql`), not MySQL, so it builds and runs with zero external
services. `docs/decisions.md` Decision 4 sets the plugin's real production default to
MySQL 8.0.33 via `io.asyncer:r2dbc-mysql` (Decision 5) — that driver is included in
this project's `build.gradle.kts` as a `runtimeOnly` dependency to demonstrate the
correct pin, and `src/main/resources/migration/V1__create_employee_table.sql` is the
real MySQL-syntax migration `be-crud` would generate. It is not applied by this
sample; `src/main/resources/schema.sql` is a hand-kept H2-dialect translation used
only so the sample can run standalone.

## Running the verification gate

Requires JDK 21+.

```bash
./gradlew classes testClasses   # compilation
./gradlew checkstyleMain checkstyleTest   # checkstyle (zero-tolerance, config/checkstyle/checkstyle.xml)
./gradlew test                  # tests (WebTestClient integration + StepVerifier unit/repository tests)
./gradlew build                 # full build
./gradlew jacocoTestReport      # coverage report (report-only, no threshold -- see docs/decisions.md Decision 6)
```

All five pass as of this writing. `./gradlew build` runs compilation, checkstyle, and
tests together; `jacocoTestReport` is `finalizedBy` from `test`, so a plain
`./gradlew test` also produces `build/reports/jacoco/test/jacocoTestReport.xml`.
Last verified line coverage: **81/85 lines (95.3%)** — reported for informational
purposes per the report-only gate, not enforced as a threshold.

## What's demonstrated

- CQRS package layout: `command/`, `commandmodel/`, `query/`, `querymodel/`, `view/`,
  `data/`, `hr/api/` (domain package)
- R2DBC entity with explicit `@Column` on every field including `@Id` (see the comment
  in `Employee.java` — an H2Dialect identifier-casing subtlety this sample caught and
  that is now documented in `templates/entity-conventions-r2dbc.md`)
- `RouterFunction` + `HandlerFunction` functional web layer (default per Decision 2)
- `Mono.defer(...)` wrapping validation so a synchronous throw becomes a proper
  reactive error signal at subscription time (see the comment in
  `CreateEmployeeCommandExecutor.java`, backported to `templates/entity-conventions-r2dbc.md`)
- `WebTestClient` + `@AutoConfigureWebTestClient` integration tests (`PostTests`,
  `GetTests`) — Spring Boot 4 requires the explicit annotation and the
  `spring-boot-webtestclient` dependency; it is no longer bundled/auto-applied via
  `spring-boot-starter-test` alone
- `@DataR2dbcTest` repository test with `StepVerifier` (`EmployeeRepositoryTests`) —
  note its package moved in Spring Boot 4 to
  `org.springframework.boot.data.r2dbc.test.autoconfigure.DataR2dbcTest`, and it
  requires the separate `spring-boot-starter-data-r2dbc-test` dependency
- Mockito + `StepVerifier` unit test for the command executor
  (`CreateEmployeeCommandExecutorTests`) — Mockito is a first-class testing tool in
  this plugin (see `templates/tdd-rules.md`)
- JaCoco coverage wired report-only, no `jacocoTestCoverageVerification` rule
