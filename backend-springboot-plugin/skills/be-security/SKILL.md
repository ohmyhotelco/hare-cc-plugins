---
name: be-security
description: "Audit security vulnerabilities: authentication, authorization, input validation, PII exposure, injection, and secrets."
argument-hint: "[file-or-directory-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash
---

# Security Audit

Audit Spring Boot code for security vulnerabilities based on OWASP Top 10 patterns.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, tell the user to run `/backend-springboot-plugin:be-init` first and stop

### Step 1: Determine Scope

- If argument provided: audit the specified file or directory
- If no argument: audit all files in `{sourceDir}/{basePackage}/`

### Step 2: Scan for Issues

Check each file against these rules:

#### Critical Issues

1. **Authentication**
   - Endpoint reachable without authentication check
   - Login/verification tokens not validated on every request
   - Verification code without brute-force protection (max attempts, expiry)
   - Login response leaks whether an account exists (enumeration attack)

2. **Authorization**
   - User A can access user B's data via path variable manipulation (IDOR)
   - Missing role or permission check at the controller level
   - Scoped user can access data outside their scope (e.g., branch, tenant, org)

3. **Injection**
   - `@Query` with string concatenation (`"... " + param`)
   - Native queries without `?` or `:param` placeholders
   - `Runtime.exec()` or `ProcessBuilder` with user-controlled input
   - `@Query` built from user input without parameterization

#### Warning Issues

4. **Input Validation**
   - `@RequestBody` without `@Valid` annotation
   - Path variables or query parameters without bounds validation
   - String inputs without length limits (oversized payload risk)
   - Validation not applied in the controller layer before reaching executors

5. **PII & Data Exposure**
   - Sensitive fields (email, phone, address, SSN) logged without masking
   - API response contains internal identifiers (e.g., `sequence`, internal DB keys)
   - Error responses expose stack traces, class names, or internal state
   - Sensitive data stored without encryption where regulations require it

6. **Secrets & Configuration**
   - Credentials hardcoded in `application.yml` or `application.properties` (not externalized)
   - JWT or signing secrets committed to the repository
   - Docker Compose files using default passwords
   - API keys or tokens in source code

#### Suggestions

7. **Headers & Transport**
   - `@CrossOrigin("*")` on authenticated endpoints
   - Missing security headers (Content-Security-Policy, X-Content-Type-Options)
   - Sensitive endpoints without rate limiting

### Step 3: Report

Display findings in the working language:

```
Security Audit Report
=====================

Scope: {target path}
Files scanned: {count}
Risk Level: CRITICAL / HIGH / MEDIUM / LOW

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

If no issues found:
> "Security audit passed. No issues detected."

## Red Flags

Always flag these patterns:

- `@Query` with string concatenation (`"... " + param`)
- Missing `@Valid` on `@RequestBody` parameters
- Internal DB key (`sequence`, auto-increment ID) exposed in API response
- Endpoints without authentication or authorization check
- PII fields (email, phone, name) in log statements without masking
- Hardcoded strings matching: `password=`, `secret=`, `api_key=`, `jdbc:`
- `@CrossOrigin("*")` on authenticated endpoints
- Error responses exposing class names or stack traces
- `Runtime.exec` or `ProcessBuilder` with non-constant arguments
