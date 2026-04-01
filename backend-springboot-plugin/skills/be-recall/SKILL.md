---
name: be-recall
description: "Recall development rules and check for violations."
argument-hint: "[commit | tdd | build | coding | api | jpa]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Recall Rules

Display development rules and check recent work for violations.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, show general rules from the plugin CLAUDE.md (no project-specific checks)

### Step 1: Parse Argument

Map argument to section:

| Argument | Section | Source |
|----------|---------|--------|
| (none) | All rules summary | CLAUDE.md (all sections) |
| `commit` | Commit Standards | CLAUDE.md § Commit Standards |
| `tdd` | TDD Process + Test Scenario Writing | CLAUDE.md § TDD + Scenario Rules |
| `build` | Build Standards | CLAUDE.md § Build Standards |
| `coding` | Coding Standards + Entity/DTO Conventions | CLAUDE.md § Coding Standards |
| `api` | API Conventions + Naming | CLAUDE.md § API Conventions + Naming Conventions |
| `jpa` | Entity Conventions | templates/entity-conventions.md |

### Step 2: Display Rules

Read the relevant section(s) from the plugin CLAUDE.md and display them clearly in the working language.

For each rule, show:
- The rule statement
- A brief example (if applicable)

### Step 3: Check for Violations

Based on the section, scan recent work for violations:

#### `commit` violations:
- Run `git log --oneline -5` and check each message against commit rules
- Flag: wrong tense, prefix usage, exceeds 50 chars, lowercase start, etc.

#### `tdd` violations:
- Scan test files in `{testDir}` for:
  - Test methods not using `snake_case`
  - Missing assertions
  - Test scenario format issues in work documents

#### `build` violations:
- Check if `build/` directory exists and has recent output
- Check for common configuration issues

#### `coding` violations:
- Scan recently modified Java files (from `git diff --name-only HEAD~3`) for:
  - Missing final newline
  - Class where `record` should be used (DTOs)
  - Non-standard naming (check against naming conventions table)

#### `api` violations:
- Scan controller classes for:
  - Wrong HTTP method mapping
  - Non-kebab-case URLs
  - Missing `@ResponseStatus`
  - Singular resource names in URLs

#### `jpa` violations:
- Scan entity classes for:
  - Missing `BaseEntity` extension
  - Missing `sequence` + `id` dual key pattern
  - Missing `@Table` annotation
  - Non-snake_case table names

### Step 4: Report

Display violations found with:
- File path and line number
- Rule violated
- Suggested fix

If no violations found:
> "No violations detected. All rules are being followed."

If violations can be auto-fixed (e.g., missing final newline):
> "Auto-fixable violations found. Apply fixes? (y/n)"

Apply fixes only with user confirmation.
