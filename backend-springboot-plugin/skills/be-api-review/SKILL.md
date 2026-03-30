---
name: be-api-review
description: "Audit REST API contracts for HTTP semantics, versioning, and consistency."
argument-hint: "[controller-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep
---

# REST API Contract Audit

Audit REST controllers for HTTP semantics, URL patterns, status codes, and consistency.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, tell the user to run `/backend-springboot-plugin:be-init` first and stop

### Step 1: Determine Scope

- If argument provided: audit the specified controller file or directory
- If no argument: find all `@RestController` classes in `{sourceDir}/{basePackage}/`

### Step 2: Scan for Issues

Check each controller against these rules:

#### HTTP Method Semantics

| Method | Expected Use | Expected Status |
|--------|-------------|-----------------|
| `@PostMapping` | Create new resource | 201 Created |
| `@GetMapping` | Read resource(s) | 200 OK |
| `@PutMapping` | Full resource replace | 200 OK |
| `@PatchMapping` | Partial update | 200 OK |
| `@DeleteMapping` | Remove resource | 204 No Content |

Flag violations:
- POST used for reads
- GET used for mutations
- Missing `@ResponseStatus` when status differs from 200

#### URL Patterns

- URLs must be kebab-case: `/hr/employees`, not `/hr/Employees` or `/hr/employee_list`
- Resources must be plural: `/employees`, not `/employee`
- Nested resources: `/{domain}/{resources}/{id}/{sub-resources}`
- No verbs in URLs: use HTTP methods instead of `/employees/create`
- No trailing slashes

#### Request/Response DTOs

- POST/PUT body should use a Command record (from `command/` package)
- GET response should use a View record (from `view/` package)
- Path variables for resource identifiers: `@PathVariable UUID id`
- Query parameters for filtering/pagination: `@RequestParam`

#### Exception Handling

- Controllers should have `@ExceptionHandler` methods for domain exceptions
- Or use a global `@ControllerAdvice`
- Each domain exception must map to a specific HTTP status code
- Missing exception handlers leave exceptions as 500 Internal Server Error

#### Pagination

- List endpoints should accept `page` and `size` parameters
- Maximum page size should be enforced (capped at a reasonable limit like 20)
- Response should include pagination metadata (total count, current page)

#### Consistency

- All controllers in the same domain should follow the same patterns
- Naming should match the naming conventions table in CLAUDE.md
- Controller should be a `record` class (for CQRS architecture)

### Step 3: Report

Display findings in the working language:

```
API Contract Audit
==================

Controllers reviewed: {count}
Endpoints reviewed: {count}

Issues:
  {severity} | {controller}:{method} | {rule} — {description}
  Suggestion: {fix}

Endpoint Summary:
  {method} {url} → {status} {response type}
```
