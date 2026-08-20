---
name: be-api-review
description: "Audit REST API contracts for HTTP semantics, versioning, and consistency across RouterFunction and annotated web layers."
argument-hint: "[router-or-controller-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep
---

# REST API Contract Audit

Audit RouterFunction/HandlerFunction pairs and `@RestController` classes for HTTP semantics, URL patterns, status codes, and consistency. See `docs/decisions.md` Decision 2 for the web-layer rule this audit enforces.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, tell the user to run `/backend-webflux-plugin:be-init` first and stop
3. Read `config.webLayer` (`"functional" | "annotated"`)

### Step 1: Determine Scope

- If argument provided: audit the specified router/handler/controller file or directory
- If no argument: find all `RouterFunction<ServerResponse>` `@Bean` definitions and all `@RestController` classes in `{sourceDir}/{basePackage}/`

### Step 2: Scan for Issues

Check each router/handler pair or controller against these rules.

#### Web-Layer Consistency (see Decision 2)

- Both `RouterFunction` and `@RestController` used for the **same domain package** → **warning**: "mixed web-layer style in domain `{domain}` — pick one per CLAUDE.md's web layer rule"
- `@RestController` used anywhere while `config.webLayer == "functional"` and no documented exception is recorded for that domain → **suggestion**: confirm this is an intentional named exception (Decision 2), not a default drift
- `RouterFunction` used anywhere while `config.webLayer == "annotated"` → same, inverted

#### HTTP Method Semantics

| Method | Expected Use | Expected Status |
|--------|-------------|-----------------|
| POST (`.POST(...)` / `@PostMapping`) | Create new resource | 201 Created |
| GET (`.GET(...)` / `@GetMapping`) | Read resource(s) | 200 OK |
| PUT (`.PUT(...)` / `@PutMapping`) | Full resource replace | 200 OK |
| PATCH (`.PATCH(...)` / `@PatchMapping`) | Partial update | 200 OK |
| DELETE (`.DELETE(...)` / `@DeleteMapping`) | Remove resource | 204 No Content |

Flag violations:
- POST used for reads → **critical**: wrong verb changes API semantics for every caller
- GET used for mutations → **critical**: breaks HTTP caching/idempotency guarantees
- Functional style: handler method does not call `ServerResponse.status(...)` with a status differing from `.ok()`'s default 200 when the operation needs a non-200 status → **warning**
- Annotated style: missing `@ResponseStatus` when status differs from 200 → **warning**

#### URL Patterns

- URLs must be kebab-case: `/hr/employees`, not `/hr/Employees` or `/hr/employee_list` → **suggestion**
- Resources must be plural: `/employees`, not `/employee` → **suggestion**
- Nested resources: `/{domain}/{resources}/{id}/{sub-resources}` → **suggestion** if the nesting is inconsistent with sibling endpoints in the same domain
- No verbs in URLs: use HTTP methods instead of `/employees/create` → **warning**: verb-in-URL usually signals a missing/misused HTTP method
- No trailing slashes → **suggestion**

#### URL Versioning

- If any route under `{sourceDir}/{basePackage}/` includes a version segment (`/v1/...`, `/v2/...`), every other route in the same domain package must use the same convention → **warning**: "inconsistent API versioning in domain `{domain}` — some routes are versioned, others are not"
- If no route in the codebase uses a version segment at all, versioning is out of scope for this audit — do not flag its absence (there is no established convention to violate)
- Never invent a required version scheme; only compare routes against the convention the codebase already established

#### Request/Response DTOs

- POST/PUT body should use a Command record (from `command/` package), read via
  `request.bodyToMono(Command.class)` (functional) or `@RequestBody` (annotated) → **warning** if a raw `Map`/primitive is used instead
- GET response should use a View record (from `view/` package) → **warning**
- Path variables for resource identifiers: `request.pathVariable("id")` (functional) or `@PathVariable UUID id` (annotated) → **suggestion**
- Query parameters for filtering/pagination: `request.param("page")` (functional) or `@RequestParam` (annotated) → **suggestion**
- Handler/controller methods must return `Mono<ServerResponse>` (functional) or `Mono<T>`/`Flux<T>` (annotated) — never a materialized/blocking type → **critical**: a blocking return type blocks the Netty event loop

#### Exception Handling

- Functional style: the handler method's reactive chain must include `.onErrorResume(...)` for every domain exception the executor/processor can throw, mapping each to a specific HTTP status → **critical** if any domain exception has no mapping (falls through to 500)
- Annotated style: controller should have `@ExceptionHandler` methods, or use a global `@ControllerAdvice` → **critical** under the same condition
- Each domain exception must map to a specific HTTP status code → **warning** if mapped but to a generic/wrong status
- Missing exception handling leaves exceptions as 500 Internal Server Error (WebFlux's default error handling) — this is the failure mode the critical severity above is protecting against

#### Pagination

- List endpoints should accept `page` and `size` parameters → **warning** if a list endpoint (returns `Flux`/`List`/a `*Page` view) has neither
- Maximum page size must be enforced. Read `maxPageSize` from `.claude/backend-webflux-plugin.json` if present and check the handler/processor clamps `size` to it → **critical** if `maxPageSize` is configured but not enforced; if `maxPageSize` is not configured and no clamp exists in code → **suggestion**: "no max page size enforced for `{endpoint}` — add a `maxPageSize` config value or a hardcoded clamp"
- Response should include pagination metadata (total count, current page) → **warning** if a `*Page` view is returned without them

#### Consistency

- All routers/handlers or controllers in the same domain should follow the same patterns → **warning**
- Naming should match the naming conventions table in CLAUDE.md (`{Name}Router`, `{Name}Handler`, or `{Name}Controller`) → **suggestion**
- Handler should be a `record` class with constructor DI (matches CQRS conventions); Controller (annotated style) should also be a `record` class → **suggestion**

### Step 3: Report

For every issue, record the exact `file:line` from the Grep/Read output that surfaced it — never report a rule violation without the location that backs it. If a rule cannot be checked for a given endpoint (e.g. no domain exceptions to enumerate), skip it silently rather than guessing.

Display findings in the working language:

```
API Contract Audit
==================

Web layer: {config.webLayer}
Routers/Handlers reviewed: {count}
Controllers reviewed: {count}
Endpoints reviewed: {count}

Issues:
  {severity} | {file}:{line} | {router/handler/controller}:{method} | {rule} — {description}
  Suggestion: {fix}

Endpoint Summary:
  {method} {url} → {status} {response type}
```

### Worked Example

Input: `be-api-review src/main/java/com/example/hr/employee/api/EmployeeHandler.java`

Grep finds `.PUT("/hr/employees/{id}", handler::updateEmployee)` at line 22, and
`updateEmployee` (line 41) returns `ServerResponse.ok().bodyValue(view)` with no
`onErrorResume` around the `Mono` chain, while `UpdateEmployeeCommandExecutor`
(read separately) can throw `EmployeeNotFoundException`.

```
API Contract Audit
==================

Web layer: functional
Routers/Handlers reviewed: 1
Controllers reviewed: 0
Endpoints reviewed: 1

Issues:
  critical | EmployeeHandler.java:41 | EmployeeHandler:updateEmployee | Exception Handling — EmployeeNotFoundException thrown by UpdateEmployeeCommandExecutor has no .onErrorResume mapping; falls through to 500
  Suggestion: add .onErrorResume(EmployeeNotFoundException.class, e -> ServerResponse.status(404).bodyValue(...)) to the chain

Endpoint Summary:
  PUT /hr/employees/{id} → 200 OK EmployeeView
```

A tricky case: the domain mixes `RouterFunction` and `@RestController`, and `config.webLayer == "functional"`. Grep finds `BookingRouter.java` (RouterFunction, line 18) and `BookingLegacyController.java` (`@RestController`, line 12) both under `booking/api/`, with no exception noted in `docs/decisions.md`. Also `BookingRouter` uses `/v2/bookings` while `BookingLegacyController` uses `/bookings` with no version segment.

```
API Contract Audit
==================

Web layer: functional
Routers/Handlers reviewed: 1
Controllers reviewed: 1
Endpoints reviewed: 2

Issues:
  warning | BookingLegacyController.java:12 | booking domain | Web-Layer Consistency — mixed web-layer style in domain `booking` (BookingRouter.java:18 uses RouterFunction, BookingLegacyController.java:12 uses @RestController); pick one per CLAUDE.md's web layer rule
  Suggestion: confirm with the team whether BookingLegacyController is an intentional named exception (Decision 2); if so, record it in docs/decisions.md, otherwise migrate it to RouterFunction

  warning | BookingLegacyController.java:12 | booking domain | URL Versioning — inconsistent API versioning in domain `booking` (BookingRouter.java:18 uses /v2/bookings, BookingLegacyController.java:12 uses /bookings with no version segment)
  Suggestion: align BookingLegacyController's route to the /v2/ convention already established by BookingRouter

Endpoint Summary:
  GET /v2/bookings/{id} → 200 OK BookingView
  GET /bookings/{id} → 200 OK BookingView
```
