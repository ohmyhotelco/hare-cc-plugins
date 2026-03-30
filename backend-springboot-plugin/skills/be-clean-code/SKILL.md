---
name: be-clean-code
description: "Audit code for DRY, KISS, YAGNI, naming, and refactoring opportunities."
argument-hint: "[file-or-directory-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep
---

# Clean Code Audit

Audit Java source code for clean code principles: DRY, KISS, YAGNI, naming, and structure.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, tell the user to run `/backend-springboot-plugin:be-init` first and stop

### Step 1: Determine Scope

- If argument provided: audit the specified file or directory
- If no argument: audit all Java files in `{sourceDir}/{basePackage}/`

### Step 2: Scan for Issues

#### DRY (Don't Repeat Yourself)

- Duplicate code blocks across classes (>5 lines of similar logic)
- Copy-pasted validation logic that should be extracted to a shared validator
- Repeated DTO-to-entity mapping that could use a shared mapper method

#### KISS (Keep It Simple)

- Overly complex conditional logic (>3 nested if/else)
- Method doing too many things (>30 lines)
- Unnecessary abstraction layers (interface with single implementation that will never change)
- Complex stream operations where a simple loop would be clearer

#### YAGNI (You Ain't Gonna Need It)

- Unused methods (defined but never called)
- Unused fields in classes
- Over-engineered factory patterns for simple object creation
- Generic implementations for single-use cases
- Unused imports

#### Naming

- Single-letter variable names (except loop counters `i`, `j`, `k`)
- Generic names: `data`, `info`, `temp`, `result`, `obj`, `item`
- Boolean variables without `is`/`has`/`can` prefix context
- Methods that don't describe their action
- Classes that don't describe their responsibility
- Inconsistency with naming conventions table in CLAUDE.md

#### Structure

- God classes: files exceeding 300 lines
- Deep nesting: more than 3 levels of indentation
- Long parameter lists: methods with >5 parameters
- Missing `record` usage: classes that should be records (immutable DTOs with only fields and constructor)
- Mutable state where immutable would suffice

### Step 3: Report

Display findings in the working language:

```
Clean Code Audit
================

Files scanned: {count}

DRY Issues ({count}):
  {file}:{line} — {description}

KISS Issues ({count}):
  {file}:{line} — {description}

YAGNI Issues ({count}):
  {file}:{line} — {description}

Naming Issues ({count}):
  {file}:{line} — {description}

Structure Issues ({count}):
  {file}:{line} — {description}
```

If no issues found:
> "Clean code audit passed. Code is clean and well-structured."
