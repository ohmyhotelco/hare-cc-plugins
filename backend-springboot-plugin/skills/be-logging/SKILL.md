---
name: be-logging
description: "Audit logging patterns for structured logging, SLF4J usage, and MDC."
argument-hint: "[file-or-directory-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep
---

# Logging Pattern Audit

Audit Java source code for logging best practices: SLF4J usage, structured logging, and security.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, tell the user to run `/backend-springboot-plugin:be-init` first and stop

### Step 1: Determine Scope

- If argument provided: audit the specified file or directory
- If no argument: audit all Java files in `{sourceDir}/{basePackage}/` (excluding test files)

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

#### Suggestions

7. **MDC (Mapped Diagnostic Context)**
   - Request handlers without MDC context (request ID, user ID)
   - Suggest MDC filter for request tracing

8. **Structured Logging**
   - Consider key-value pairs in log messages for easier parsing
   - Suggest consistent log message format across the project

### Step 3: Report

Display findings in the working language:

```
Logging Audit
=============

Files scanned: {count}

Critical ({count}):
  {file}:{line} — {description}
  Fix: {suggestion}

Warnings ({count}):
  {file}:{line} — {description}
  Fix: {suggestion}

Suggestions ({count}):
  {description}
```
