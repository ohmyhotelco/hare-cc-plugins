---
name: be-security
description: "Audit security vulnerabilities: authentication, authorization, input validation, PII exposure, injection (including MyBatis ${} substitution), and secrets."
argument-hint: "[file-or-directory-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash
---

# Security Audit

## Role

Act as an AppSec reviewer auditing production Spring WebFlux code against the
OWASP Top 10 categories most likely to appear in this stack: auth bypass on a
`RouterFunction`/`SecurityWebFilterChain`, IDOR, injection (R2DBC/JPA-style string
concatenation **and** MyBatis XML `${}` substitution — this plugin's `dataProfile`
defaults to `"both"`, and MyBatis-profile domains are WebFlux + MyBatis), PII
exposure, and hardcoded secrets.

KPI: zero Critical/Warning findings shipped unflagged. A missed true positive is a
worse outcome than a false positive that gets excluded with a stated reason in
Step 3 — when in doubt, surface the candidate and let the exclusion reasoning carry
the doubt, rather than silently dropping it.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, tell the user to run `/backend-webflux-plugin:be-init` first and stop

### Step 1: Determine Scope

- If argument provided: audit the specified file or directory
  - If the path does not exist, report `Path not found: {path}` and stop — do not
    fall back to scanning the default scope
- If no argument: audit all files in `{sourceDir}/{basePackage}/`
  - If that directory does not exist or contains zero `.java`/`.xml` files, report
    `No source files found in {sourceDir}/{basePackage}/ — nothing to audit` and stop
- Include MyBatis XML mappers under `src/main/resources/mapper/` in scope whenever
  `dataProfile` is `"mybatis"` or `"both"` — the Injection checks in Step 2 require
  them; a scope that only walks `.java` files misses every mapper-level
  vulnerability

### Step 2: Scan for Candidate Issues

Check each in-scope file against these rules. Every match found here is a
**candidate** — it only becomes a reportable finding after it survives Step 3.

#### Critical Issues

1. **Authentication**
   - Endpoint reachable without authentication check
   - Login/verification tokens not validated on every request
   - Verification code without brute-force protection (max attempts, expiry)
   - Login response leaks whether an account exists (enumeration attack)
   - WebFlux-specific: a `SecurityWebFilterChain` (or router-level auth filter) that
     does not cover a route actually exposed by the `RouterFunction` — check the
     filter chain's path matchers against every route in the corresponding
     `{Entity}Router`, not just whether each `HandlerFunction` looks like it checks
     auth internally. A route missing from the filter chain is reachable even if
     every handler "assumes" the filter already ran.
   - WebFlux-specific: an auth/identity value read from
     `ReactiveSecurityContextHolder` outside the reactive chain that carries it (e.g.
     captured into a local variable before a `subscribeOn`/thread hop, or read in a
     `doOnNext` after crossing an `flatMap` that lost the Reactor context) — this
     silently authenticates as the wrong principal or throws, rather than failing
     the request cleanly

2. **Authorization**
   - User A can access user B's data via path variable manipulation (IDOR)
   - Missing role or permission check at the controller/handler level
   - Scoped user can access data outside their scope (e.g., branch, tenant, org)
   - WebFlux-specific: a permission check that produces a `Mono<Boolean>` (or
     similar) but is never chained into the response pipeline — e.g. called and its
     result logged or discarded instead of driving `.filterWhen(...)` or an early
     `.switchIfEmpty(Mono.error(new ForbiddenException()))`. A `Mono` that is
     evaluated but never subscribed into the actual response chain never runs, so
     the check silently passes every request regardless of its real result.

3. **Injection**
   - `@Query` with string concatenation (`"... " + param`)
   - Native queries without `?` or `:param` placeholders
   - `Runtime.exec()` or `ProcessBuilder` with user-controlled input
   - `@Query` built from user input without parameterization
   - **MyBatis XML mapper: `${param}` used for a value that originates from request
     input** (`<select>`, `<update>`, `<insert>`, `<delete>` in
     `src/main/resources/mapper/*.xml`) — `${}` performs raw string substitution before
     the SQL is prepared, so any request-controlled value passed through it is a
     direct SQL injection vector. `#{param}` is the safe form: it binds a
     `PreparedStatement` parameter and never substitutes raw text.
     `${}` is legitimate only for values the caller cannot influence — a
     column/table name chosen from a fixed enum, or a static `ORDER BY` direction
     validated against an allow-list before being passed to MyBatis — flag every
     other use as Critical. See the worked example below.

#### Warning Issues

4. **Input Validation**
   - `@RequestBody` without `@Valid` annotation
   - Path variables or query parameters without bounds validation
   - String inputs without length limits (oversized payload risk)
   - Validation not applied in the controller/handler layer before reaching
     executors

5. **PII & Data Exposure**
   - Sensitive fields (email, phone, address, SSN) logged without masking
   - API response contains internal identifiers (e.g., `sequence`, internal DB keys)
   - Error responses expose stack traces, class names, or internal state
   - Sensitive data stored without encryption where regulations require it

6. **Secrets & Configuration**
   - Credentials hardcoded in `application.yml` or `application.properties` (not
     externalized)
   - JWT or signing secrets committed to the repository
   - Docker Compose files using default passwords
   - API keys or tokens in source code

#### Suggestions

7. **Headers & Transport**
   - `@CrossOrigin("*")` on authenticated endpoints
   - Missing security headers (Content-Security-Policy, X-Content-Type-Options)
   - Sensitive endpoints without rate limiting

### Step 3: Verify Each Candidate

Do not skip this step — it is what separates a finding from a guess. For every
candidate from Step 2, before it is allowed into the Step 4 report, write one line
stating whether it is a true positive or excluded, and why:

- True positive: state the concrete reachable path from untrusted input to the
  sink (e.g., "`email` comes from `CreateEmployee` request body, reaches
  `${email}` in `EmployeeMapper.xml:34` unescaped").
- Excluded — not a true positive: state the specific reason. Common exclusions:
  - Test file or test fixture (`src/test/...`), not production code
  - String concatenation of constants only — no variable, or the variable is a
    compile-time constant / enum, never user input
  - `${}` used only for a value already validated against a fixed allow-list
    before reaching the mapper
  - Already using the safe parameterized form (`#{param}`, `?`, `:param`) — a
    surface-level string match that isn't actually the vulnerable pattern

Only true positives proceed to Step 4. Excluded candidates are not reported —
their exclusion reasoning does not need to appear in the final output by default,
but you must have produced it before dropping the candidate. If the user asks to
see what was excluded and why (e.g. "show your reasoning" / "what did you rule
out"), report the full candidate list with both true-positive and excluded lines —
the reasoning is always available on request, just not printed unprompted.

### Step 4: Report

Display findings in the working language. Use this header on every report — a
clean result carries the same evidence trail as a failing one, it just has zero
counts:

```
Security Audit Report
=====================

Scope: {target path}
Files scanned: {count}
Risk Level: CRITICAL / HIGH / MEDIUM / LOW / NONE

Critical ({count}):
  {file}:{line} — {description}
  Impact: {exploitation scenario}
  Suggestion: {fix}

Warnings ({count}):
  {file}:{line} — {description}
  Suggestion: {fix}

Suggestions ({count}):
  {file}:{line} — {description}
  Suggestion: {fix}
```

When all three counts are zero, set `Risk Level: NONE` and omit the three empty
sections rather than printing empty headers — but always print the Scope / Files
scanned / Risk Level block. Never shortcut a clean result to a bare sentence; the
header is what lets the next reader confirm the audit actually ran over the stated
scope instead of trusting an unverified claim.

## Error Handling

- **Config missing** — see Step 0; stop with the `be-init` instruction.
- **Path argument does not exist** — see Step 1; stop with `Path not found`, do not
  silently fall back to the default scope.
- **Zero files in scope** — see Step 1; stop and say so explicitly rather than
  reporting `Risk Level: NONE` for a scope that was never actually scanned — those
  are different outcomes and must not look identical.
- **File unreadable (permissions, binary, encoding)** — skip the file, list it under
  a `Skipped ({count}):` line in the report with the reason, and continue scanning
  the rest of the scope. Do not let one unreadable file abort the whole audit, and
  do not silently drop it from the file count either.

## Worked Examples

### Example 1 — JPA/R2DBC string concatenation (Critical, true positive)

Input code (`EmployeeRepository.java`):

```java
@Query("SELECT * FROM employee WHERE email = '" + email + "'")
Mono<Employee> findByEmailUnsafe(String email);
```

Step 3 verification line:
> True positive — `email` is a method parameter with no fixed set of allowed
> values, concatenated directly into the query string with no `?`/`:param`
> placeholder.

Resulting report line:
```
Critical (1):
  EmployeeRepository.java:14 — @Query built via string concatenation on `email`
  Impact: An attacker-controlled email value can inject SQL (e.g.
    `' OR '1'='1`) to bypass the WHERE clause and read arbitrary rows.
  Suggestion: Use a parameterized query — `@Query("SELECT * FROM employee WHERE
    email = :email")` with `@Param("email") String email`.
```

### Example 2 — MyBatis `${}` substitution (Critical, true positive)

Input code (`EmployeeMapper.xml`):

```xml
<select id="findByStatus" resultType="Employee">
  SELECT * FROM employee WHERE status = '${status}'
</select>
```

where `status` is bound from a `FindEmployee` query DTO populated from a request
query parameter.

Step 3 verification line:
> True positive — `status` originates from `FindEmployee.status()`, which is
> populated directly from the HTTP query parameter with no allow-list check before
> reaching the mapper; `${status}` performs raw text substitution, not parameter
> binding.

Resulting report line:
```
Critical (1):
  EmployeeMapper.xml:8 — `${status}` substitution on request-controlled value
  Impact: An attacker-controlled `status` query parameter can inject SQL (e.g.
    `x' OR '1'='1`) because ${} substitutes raw text before the statement is
    prepared.
  Suggestion: Replace with `#{status}` so MyBatis binds it as a prepared-statement
    parameter. If `status` must select a column/table name (where `#{param}` cannot
    be used), validate it against a fixed enum/allow-list before it reaches the
    mapper, and keep the ${} substitution confined to that pre-validated value.
```

### Example 3 — excluded candidate (not reported)

Input code (`EmployeeMapperTest.java`, a test file):

```java
String sql = "SELECT * FROM employee WHERE status = '" + TEST_STATUS + "'";
```

Step 3 verification line:
> Excluded — test file (`src/test/...`), not production code; `TEST_STATUS` is
> also a compile-time constant, not request input.

This candidate does not appear in the Step 4 report.

## Red Flags

Always flag these patterns:

- `@Query` with string concatenation (`"... " + param`)
- MyBatis XML `${param}` substitution on a value traceable to request input
  (query param, path variable, request body field) — `#{param}` is the safe form
- Missing `@Valid` on `@RequestBody` parameters
- Internal DB key (`sequence`, auto-increment ID) exposed in API response
- Endpoints without authentication or authorization check, including a route
  present in a `RouterFunction` but absent from the `SecurityWebFilterChain`'s path
  matchers
- PII fields (email, phone, name) in log statements without masking
- Hardcoded strings matching: `password=`, `secret=`, `api_key=`, `jdbc:`
- `@CrossOrigin("*")` on authenticated endpoints
- Error responses exposing class names or stack traces
- `Runtime.exec` or `ProcessBuilder` with non-constant arguments
