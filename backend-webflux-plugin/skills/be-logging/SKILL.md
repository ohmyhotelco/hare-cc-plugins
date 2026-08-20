---
name: be-logging
description: "Audit Java logging patterns for SLF4J usage, structured logging, and security-sensitive log content (secrets, PII, MDC/Reactor context loss across scheduler hops). Use when checking whether log statements are safe, well-formed, and keep correlation IDs intact across Reactor's thread-hopping execution. Triggers on requests like \"check our logging\", \"audit log statements\", \"are we logging secrets or PII\", \"review log levels\", \"kiểm tra logging\", \"log có lộ thông tin nhạy cảm không\", \"로깅 점검해줘\". For a full security audit (auth, injection, IDOR, secrets in config) use be-security instead — be-logging only covers the log-statement surface, not the broader vulnerability classes; the two overlap on secrets/PII in logs, see 'See Also' below."
argument-hint: "[file-or-directory-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep
---

# Logging Pattern Audit

Audit Java source code for logging best practices: SLF4J usage, structured logging, and security.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, tell the user to run `/backend-webflux-plugin:be-init` first and stop

### Step 1: Determine Scope

- If argument provided: audit the specified file or directory
  - If the path does not exist, report `Path not found: {path}` and stop — do not
    fall back to scanning the default scope. A wrong path and a clean scan must
    never look identical to the reader.
- If no argument: audit all Java files in `{sourceDir}/{basePackage}/` (excluding
  test files)
  - If that directory does not exist or contains zero `.java` files, report
    `No source files found in {sourceDir}/{basePackage}/ — nothing to audit` and
    stop, rather than proceeding to Step 3 with `Files scanned: 0`

### Step 2: Scan for Issues

#### Critical Issues

1. **Console Output**
   - `System.out.println` in production code
   - `System.err.println` in production code
   - `printStackTrace()` calls

2. **Sensitive Data Exposure**
   - Logging passwords, tokens, secrets, or API keys
   - Logging full email addresses (should be masked)
   - Logging credit card numbers or personal identification numbers
   - Check log statements for variables named: `password`, `token`, `secret`, `key`, `credential`
   - This bucket overlaps with `be-security`'s PII & Data Exposure and Secrets &
     Configuration checks — see "See Also" below. When this scan surfaces a
     Critical finding here, treat it as a signal to run a full `be-security` pass
     on the same scope rather than treating the logging fix alone as closing the
     risk (a masked log line does not address a secret also hardcoded elsewhere).

3. **Missing Exception Logging**
   - `catch` blocks that silently swallow exceptions (empty catch or catch without logging)
   - `catch` blocks that only log the message without the stack trace: use `log.error("msg", exception)` not `log.error(exception.getMessage())`

#### Warning Issues

4. **String Concatenation**
   - Log statements using `+` for string concatenation
   - Should use `{}` placeholders: `log.info("User {} created", userId)` not `log.info("User " + userId + " created")`

5. **Wrong Log Level**
   - `log.error()` for non-error conditions
   - `log.info()` for debug-level detail
   - `log.debug()` for critical business events that should always be logged

6. **Logger Declaration**
   - Missing `private static final Logger log = LoggerFactory.getLogger(ClassName.class)`
   - Using Lombok `@Slf4j` without Lombok being enabled
   - Logger variable not named `log` (convention)

7. **MDC Set Without Reactor Context Propagation**
   - Thread-local MDC does not survive Reactor's thread-hopping execution — a value
     set with `MDC.put(...)` in one operator is silently gone by the time a
     `.subscribeOn(Schedulers.boundedElastic())` hop (this plugin's own bridge for
     MyBatis/blocking calls) or any other scheduler switch runs the next operator,
     so a naive request-ID MDC filter produces log lines that lose correlation IDs
     partway through a request
   - Flag any `MDC.put`/`MDC.get` usage, or a request-tracing filter that only sets
     MDC without also wiring Reactor Context propagation, as a **warning**: the
     fix is `Hooks.enableAutomaticContextPropagation()` (Reactor 3.5+) together with
     `io.micrometer:context-propagation` so `ThreadLocal`-backed MDC entries are
     captured into and restored from the Reactor `Context` across scheduler
     boundaries — a plain `OncePerRequestFilter` calling `MDC.put` is not sufficient
     on this stack the way it is on the blocking-MVC plugin
   - Same finding `agents/code-reviewer.md` already flags for the review agent —
     this audit skill must apply it too, not just suggest a plain MDC filter

#### Suggestions

8. **Structured Logging**
   - Consider key-value pairs in log messages for easier parsing
   - Suggest consistent log message format across the project

### Step 3: Report

Read `workingLanguage` from `.claude/backend-webflux-plugin.json` (Step 0). Emit
the report below with the section labels translated per the table; everything
else — file paths, code identifiers, variable/method names, and fix-suggestion
code snippets — stays untranslated regardless of `workingLanguage`, since those
values are not natural language and translating them would break copy-paste use.

| Label (template placeholder) | en | ko | vi |
|---|---|---|---|
| Title | Logging Audit | 로깅 감사 | Kiểm tra Logging |
| Files scanned | Files scanned | 스캔한 파일 | Số file đã quét |
| Critical | Critical | 심각 | Nghiêm trọng |
| Warnings | Warnings | 경고 | Cảnh báo |
| Suggestions | Suggestions | 제안 | Đề xuất |

```
{Title}
=============

{Files scanned}: {count}

{Critical} ({count}):
  {file}:{line} — {description}
  Fix: {suggestion}

{Warnings} ({count}):
  {file}:{line} — {description}
  Fix: {suggestion}

{Suggestions} ({count}):
  {description}
```

Always print all three sections, even at zero — `{Critical} (0):`,
`{Warnings} (0):`, `{Suggestions} (0):` with no lines under them. A clean scan
must show it actually ran (files scanned > 0, three explicit zero-counts) so it
cannot be mistaken for a scan that silently found nothing to look at.

## Error Handling

- **Config missing** — see Step 0; stop with the `be-init` instruction.
- **Path argument does not exist** — see Step 1; stop with `Path not found`, do not
  silently fall back to the default scope.
- **Zero files in scope** — see Step 1; stop and say so explicitly rather than
  emitting a `Files scanned: 0` report with all-zero counts that reads as "scanned
  everything, found nothing" — those are different outcomes.
- **File unreadable (permissions, binary, encoding)** — skip the file, note it
  under the report (e.g. `Skipped: {file} — {reason}`), and continue scanning the
  rest of the scope rather than aborting the whole audit.

## Worked Examples

### Example 1 — easy case: console output + string concatenation

Input code (`EmployeeHandler.java`):

```java
public Mono<ServerResponse> create(ServerRequest request) {
    System.out.println("Creating employee: " + request.pathVariable("id"));
    ...
}
```

Report output (English):

```
Logging Audit
=============

Files scanned: 1

Critical (1):
  EmployeeHandler.java:2 — System.out.println used instead of SLF4J logger
  Fix: Replace with a declared `log` field: `log.info("Creating employee: {}",
    request.pathVariable("id"))`.

Warnings (1):
  EmployeeHandler.java:2 — String concatenation in log message ("Creating
    employee: " + id)
  Fix: Use `{}` placeholders: `log.info("Creating employee: {}", id)` instead of
    `+` concatenation.

Suggestions (0):
```

### Example 2 — tricky case: MDC set inside a filter, lost across a scheduler hop

Input code (`RequestTracingFilter.java` + `EmployeeMapper` usage):

```java
public class RequestTracingFilter implements WebFilter {
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        MDC.put("requestId", exchange.getRequest().getId());
        return chain.filter(exchange);
    }
}
// later, in a MyBatis-backed query processor:
return Mono.fromCallable(() -> employeeMapper.findById(id))
    .subscribeOn(Schedulers.boundedElastic());
```

Report output (English), applying Rule 7:

```
Warnings (1):
  RequestTracingFilter.java:3 — MDC.put("requestId", ...) set without Reactor
    Context propagation; the value is lost once execution crosses the
    .subscribeOn(Schedulers.boundedElastic()) hop in the MyBatis query path, so
    log lines emitted from the offloaded call lose the requestId correlation.
  Fix: Add `Hooks.enableAutomaticContextPropagation()` (Reactor 3.5+) plus the
    `io.micrometer:context-propagation` dependency so MDC entries are captured
    into and restored from the Reactor Context across scheduler boundaries — a
    plain WebFilter calling MDC.put alone is not sufficient on this stack.
```

## See Also

- `be-security` — Sensitive Data Exposure findings here (Rule 2) overlap with
  be-security's PII & Data Exposure and Secrets & Configuration checks. Run
  be-security for the full vulnerability surface (auth, injection, IDOR) when a
  logging audit turns up a Critical secrets/PII finding — be-logging only tells
  you the log line is unsafe, not whether the same value is exposed elsewhere.
