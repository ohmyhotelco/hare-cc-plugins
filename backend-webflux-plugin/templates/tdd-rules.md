# TDD Rules for WebFlux

Adapted from [obra/superpowers](https://github.com/obra/superpowers) for Spring
WebFlux, Gradle, JUnit 5, and Project Reactor's `StepVerifier`.

## Iron Law

No production code without a failing test first.

## Red-Green-Refactor Cycle

1. **RED**: Write exactly one test that fails for the right reason
2. **GREEN**: Write the minimum production code to make the test pass
3. **REFACTOR**: Improve implementation without changing behavior
4. **VERIFY**: Run the full test class after each step

## Verification is Mandatory

Actually run the build/test and check the output. Never skip verification. A `Mono`
or `Flux` that is never subscribed to never runs — reading the code is not
verification for reactive chains; `StepVerifier` or an actual `WebTestClient` call is.

```bash
# Run specific test class (always 10-minute timeout)
./gradlew test --tests {fullTestClassName}

# Run full build
./gradlew build
```

## Test Types

### Integration Test (`@SpringBootTest` + `WebTestClient`)

Primary test type. Tests full HTTP request-response cycle through the reactive
pipeline. **Not a blocking synchronous HTTP test client** — that hides reactive
pipeline bugs (e.g., a chain that never subscribes) that `WebTestClient` catches.

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureWebTestClient // Spring Boot 4: WebTestClient is no longer auto-applied
                            // by spring-boot-starter-test alone; this annotation and
                            // the org.springframework.boot:spring-boot-webtestclient
                            // dependency (transitively pulled in by
                            // spring-boot-starter-webflux-test) are both required.
class PostTests {

    @Autowired
    WebTestClient webTestClient;

    @Test
    void valid_request_returns_201_Created() {
        var command = new CreateEmployee("user@example.com", "John");

        webTestClient.post().uri("/hr/employees")
            .bodyValue(command)
            .exchange()
            .expectStatus().isCreated();
    }
}
```

### Repository Test (`@DataR2dbcTest`) — R2DBC profile

For complex query logic that warrants isolated testing. **Not the JPA repository-slice
annotation used by the MVC plugin** — there is no JPA in this plugin. Requires the
`org.springframework.boot:spring-boot-starter-data-r2dbc-test` dependency (Spring Boot
4 moved this out of the bundled `spring-boot-test-autoconfigure` module); import from
`org.springframework.boot.data.r2dbc.test.autoconfigure.DataR2dbcTest` — a different
package than the pre-Spring-Boot-4 location.

```java
@DataR2dbcTest
class EmployeeRepositoryTests {

    @Autowired
    EmployeeRepository repository;

    @Test
    void find_by_email_returns_matching_employee() {
        var employee = createEmployee("test@example.com");

        StepVerifier.create(repository.save(employee).then(repository.findByEmail("test@example.com")))
            .assertNext(found -> assertThat(found).isNotNull())
            .verifyComplete();
    }
}
```

### Mapper Test (`@MybatisTest` or `@SpringBootTest` slice) — MyBatis profile

```java
@SpringBootTest
class EmployeeMapperTests {

    @Autowired
    EmployeeMapper mapper;

    @Test
    void find_by_email_returns_matching_employee() {
        var employee = createEmployee("test@example.com");
        mapper.insert(employee);

        var found = mapper.findByEmail("test@example.com");

        assertThat(found).isNotNull();
    }
}
```

Mapper tests call the mapper directly (blocking, no `StepVerifier` needed) — the
reactive wrapping (`Mono.fromCallable` + `boundedElastic`) is tested one layer up, at
the CommandExecutor/QueryProcessor test, with `StepVerifier`.

### Reactive Unit Test (`StepVerifier`)

For asserting `Mono`/`Flux` behavior directly, without going through HTTP:

```java
@Test
void execute_completes_without_error_for_valid_command() {
    var command = new CreateEmployee("user@example.com", "John");

    StepVerifier.create(executor.execute(command))
        .verifyComplete();
}

@Test
void execute_errors_with_duplicate_email_exception() {
    // given: employee already exists with this email
    StepVerifier.create(executor.execute(duplicateCommand))
        .expectError(DuplicateEmailException.class)
        .verify();
}
```

## Mockito is Allowed in This Plugin

Mockito is a first-class testing tool here, not restricted to real-Spring-context
tests only: reactive collaborators are frequently mocked and stubbed with `Mono.just(...)` /
`Flux.just(...)` / `Mono.error(...)` return values, because constructing a full
reactive pipeline for every unit is expensive and StepVerifier-level unit tests are a
first-class, encouraged test type here (not just integration tests). Use Mockito for
isolating a CommandExecutor/QueryProcessor from its repository/mapper in unit tests;
use `WebTestClient` + a real Spring context for the outer integration test that
proves the whole chain is actually subscribed and wired correctly.

## Stub-First Approach

Before writing a test, ensure the production class/method exists (even if empty) so the test fails on the assertion, not on a compilation error.

```java
// Step 1: Create empty method signature returning an empty reactive type
public Mono<Void> execute(CreateEmployee command) {
    return Mono.empty(); // will be implemented after test fails
}

// Step 2: Write test that calls this method and asserts expected behavior via StepVerifier
// Step 3: Test fails on assertion (RED)
// Step 4: Implement minimum code (GREEN)
```

## Test Method Naming

Use `snake_case` in English, present tense:

```java
void duplicate_email_returns_409_Conflict() { }
void empty_display_name_returns_400_Bad_Request() { }
void valid_request_creates_employee_and_sends_email() { }
```

## Test Data

- Use generator classes with atomic counters for unique data
- Use `@TestComponent @Primary` for test doubles, or Mockito mocks — both are
  acceptable in this plugin (see "Mockito is Allowed" above)
- Use `@ParameterizedTest` + `@ValueSource` / `@MethodSource` for multiple inputs

```java
public class EmailGenerator {
    private static final AtomicInteger counter = new AtomicInteger(0);

    public static String next() {
        return "user" + counter.incrementAndGet() + "@test.com";
    }
}
```

## Anti-Patterns

- Never assert on a `Mono`/`Flux` object's shape without subscribing — `StepVerifier`
  or `.block()` (test code only) is mandatory to actually run the chain
- Never test mock behavior in the outer integration test -- assert on actual HTTP
  responses via `WebTestClient`
- Never add test-only methods to production classes
- Never call a blocking mapper method inside a reactive chain without
  `Schedulers.boundedElastic()` — even in tests, this hides the exact bug the
  offload pattern exists to prevent
- Never skip the RED phase -- if the test passes immediately, investigate
- Never run individual test methods -- always run the entire test class
- Never modify a failed test to make it pass -- fix the production code instead
