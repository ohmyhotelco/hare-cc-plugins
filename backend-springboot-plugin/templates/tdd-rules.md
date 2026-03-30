# TDD Rules for Spring Boot

Adapted from [obra/superpowers](https://github.com/obra/superpowers) for Spring Boot, Gradle, and JUnit 5.

## Iron Law

No production code without a failing test first.

## Red-Green-Refactor Cycle

1. **RED**: Write exactly one test that fails for the right reason
2. **GREEN**: Write the minimum production code to make the test pass
3. **REFACTOR**: Improve implementation without changing behavior
4. **VERIFY**: Run the full test class after each step

## Verification is Mandatory

Actually run the build/test and check the output. Never skip verification.

```bash
# Run specific test class (always 10-minute timeout)
./gradlew test --tests {fullTestClassName}

# Run full build
./gradlew build
```

## Test Types

### Integration Test (`@SpringBootTest`)

Primary test type. Tests full HTTP request-response cycle.

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class PostTests {

    @Autowired
    TestRestTemplate restTemplate;

    @Test
    void valid_request_returns_201_Created() {
        var command = new CreateEmployee("user@example.com", "John");
        var response = restTemplate.postForEntity("/hr/employees", command, Void.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
    }
}
```

### Repository Test (`@DataJpaTest`)

For complex query logic that warrants isolated testing.

```java
@DataJpaTest
class EmployeeRepositoryTests {

    @Autowired
    EmployeeRepository repository;

    @Test
    void find_by_email_returns_matching_employee() {
        // given
        var employee = createEmployee("test@example.com");
        repository.save(employee);

        // when
        var found = repository.findByEmail("test@example.com");

        // then
        assertThat(found).isPresent();
    }
}
```

## Stub-First Approach

Before writing a test, ensure the production class/method exists (even if empty) so the test fails on the assertion, not on a compilation error.

```java
// Step 1: Create empty method signature
public void execute(CreateEmployee command) {
    // will be implemented after test fails
}

// Step 2: Write test that calls this method and asserts expected behavior
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
- Use `@TestComponent @Primary` for test doubles (no Mockito)
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

- Never test mock behavior -- assert on actual HTTP responses or return values
- Never add test-only methods to production classes
- Never mock without understanding dependency side effects
- Never skip the RED phase -- if the test passes immediately, investigate
- Never run individual test methods -- always run the entire test class
- Never modify a failed test to make it pass -- fix the production code instead
