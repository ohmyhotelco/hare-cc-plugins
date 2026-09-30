# TDD Rules for MCP Tools

Adapted from [obra/superpowers](https://github.com/obra/superpowers) for Spring AI MCP servers,
Gradle and JUnit 5.

## Iron Law

No production code without a failing test first. A tool description, a `@ToolParam`, and a
registration entry are production code too — they change the published contract.

**One bounded exception — the tool stub**: a new tool's first scenario may create its signature,
description, `@ToolParam`s (verbatim from the work document) and registration before a red test
(§ Stub-First Approach). The stub is gated by the Contract Scenario: its drift is accepted only
through `templates/contract-snapshot.md` § 2, never by editing the snapshot early. Nothing else
precedes a failing test.

## Red-Green-Refactor Cycle

1. **RED**: Write exactly one test that fails for the right reason
2. **GREEN**: Write the minimum production code to make the test pass
3. **REFACTOR**: Improve implementation without changing behavior
4. **VERIFY**: Run the full test class after each step

## Verification is Mandatory

Actually run the test and read the result. Never skip verification.

```bash
# Run one test class (always 10-minute timeout)
./gradlew test --tests {fullTestClassName}
# multi-module build: the owning subproject's task -- `--tests` on the root task fails in every
# subproject that lacks the class ("No tests found for given includes")
./gradlew :{module}:test --tests {fullTestClassName}

# Run full build
./gradlew build
```

## Test Types

### Tool unit test (primary)

The tool class with its upstream client mocked and the real sanitizer/masker. Covers input
validation, the upstream call it makes, scoping, sanitizing/masking, and error mapping.

```java
@ExtendWith(MockitoExtension.class)
class BookingToolsTest {

    @Mock
    UpstreamClient upstream;

    @Mock
    UserPermissionService permissions;

    private BookingTools tools;

    @BeforeEach
    void setUp() {
        var rbac = new RbacAuthorizationService(permissions, upstream);
        tools = new BookingTools(upstream, rbac, new PiiMasker(), new OutputSanitizer());
    }

    @Test
    void range_longer_than_31_days_is_rejected_before_calling_upstream() {
        assertThatThrownBy(() -> tools.getHotelBookings("2026-01-01", "2026-03-01", null))
                .isInstanceOf(McpToolException.class)
                .extracting("code").isEqualTo("INVALID_INPUT");
        verifyNoInteractions(upstream);
    }

    @Test
    void guest_name_is_masked_to_first_character() {
        when(upstream.getHotelBookings(any())).thenReturn(resultWithGuest("Nguyen Van A"));

        var result = tools.getHotelBookings("2026-01-01", "2026-01-02", null);

        assertThat(result.items().get(0).guestName()).isEqualTo("N***");
    }
}
```

### RBAC test

- **Method-level** (`@PreAuthorize`, `@RateLimiter`) is enforced by a Spring proxy — a plain
  Mockito unit test calls the raw object and proves nothing. Test it through a proxy:
  `@SpringBootTest` + `@WithMockUser`, or `ProxyFactory` with
  `AuthorizationManagerBeforeMethodInterceptor.preAuthorize()` (the bean resolver must see
  `@rbac`) — allowed caller, denied caller
- **Row/field scoping** (the tool's or aspect's own code) stays in unit tests: field-scoped
  caller, and the fail-closed default (an empty entitlement sees nothing)
- Drive the context explicitly (`SecurityContextHolder` / `@WithMockUser`); clear it in `@AfterEach`

### Upstream client test

`MockRestServiceServer` bound to the client's `RestClient.Builder` (a mock web server for
`WebClient`): response mapping, each error classification, retry only on transport failure,
cache behavior. See `templates/upstream-client.md` § Testing.

### Wiring test (`@SpringBootTest`)

Registration (the tool names the server actually registers), resources, the audit aspect firing
around a tool, server `instructions` size, profile YAML sanity. Keep these few — they are slow.
Two are required when security is enabled: a **denied** call is audited as DENY and returns
`ACCESS_DENIED` (proves the aspect order in `templates/architecture.md` § Call Flow), and a failing call yields
`isError: true` with the JSON error text (`templates/tool-conventions.md` § Error model).

### Contract snapshot test and ArchUnit

Already present in the project, or added deliberately by the team when absent:
see `templates/contract-snapshot.md`. A new tool is not done until the snapshot includes it
through the deliberate-change procedure there.

## Stub-First Approach

Before writing a test, ensure the production class/method exists (even if empty) so the test
fails on the assertion, not on a compilation error.

```java
// Step 1: create the tool method returning a default value
public BookingResult getHotelBookings(String fromDate, String toDate, Integer limit) {
    return null; // implemented after the test fails
}
// Step 2: write the test; Step 3: it fails on the assertion (RED); Step 4: implement (GREEN)
```

## Test Method Naming

Follow the project's existing style — `snake_case` (`guest_name_is_masked_to_first_character`) or
descriptive camelCase (`guestNameIsMaskedToFirstCharacter`) — and never mix both in one class.
The name states the behavior, not the method called.

## Test Data

- Small factory methods or builders in the test class for upstream DTOs; one fixture per behavior
- Mockito for the upstream client and entitlement service; real `PiiMasker`/`OutputSanitizer`
  (their behavior is part of what the tool test pins)
- `@ParameterizedTest` for enum sets and invalid-input tables

## Anti-Patterns

- Never assert only that the upstream mock was called — assert the tool's result or error
- Never add test-only methods or setters to production classes
- Never skip the RED phase — if the test passes immediately, find out why
- Never run individual test methods — always the whole test class
- Never modify a failed test to make it pass — fix the production code. The contract snapshot is
  the single bounded exception, and only through `templates/contract-snapshot.md` § 2
- Never leave a `SecurityContextHolder` populated after a test
