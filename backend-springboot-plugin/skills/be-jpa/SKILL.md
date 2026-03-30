---
name: be-jpa
description: "Audit JPA/Hibernate patterns for N+1 queries, lazy loading, and transaction issues."
argument-hint: "[file-or-directory-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash
---

# JPA Pattern Audit

Audit JPA/Hibernate code for common performance and correctness issues.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, tell the user to run `/backend-springboot-plugin:be-init` first and stop
3. Read `config.database` to determine database-specific checks

### Step 1: Determine Scope

- If argument provided: audit the specified file or directory
- If no argument: audit all files in `{sourceDir}/{basePackage}/data/`, `{sourceDir}/{basePackage}/commandmodel/`, and `{sourceDir}/{basePackage}/querymodel/`

### Step 2: Scan for Issues

Check each file against these rules:

#### Critical Issues

1. **N+1 Query Detection**
   - Entity has `@OneToMany` or `@ManyToMany` collection without `@BatchSize` or `@EntityGraph`
   - Query processor accesses a lazy collection inside a loop
   - Repository method returns entities with collections that are accessed in the caller

2. **Missing @Transactional**
   - CommandExecutor modifies data (calls `save`, `delete`, `saveAll`) without `@Transactional`
   - Multiple repository calls in a single executor method without transaction boundary

3. **Lazy Loading Outside Transaction**
   - Entity with lazy collections returned from a `@Transactional` method and accessed outside

#### Warning Issues

4. **Unbounded Queries**
   - `findAll()` without pagination on tables that could grow large
   - Missing `Pageable` parameter on list queries

5. **Missing Indexes**
   - Repository has `findBy{Field}` or `existsBy{Field}` but entity has no `@Index` on that field
   - Login/lookup queries on non-indexed columns

6. **Cascade Risks**
   - `CascadeType.ALL` or `CascadeType.REMOVE` on relationships (may cause unintended deletes)
   - `orphanRemoval = true` without careful consideration

7. **Entity Design**
   - Entity does not extend `BaseEntity` (missing audit fields)
   - Missing `sequence` + `id` dual key pattern
   - Mutable `id` field (should be `updatable = false`)

#### Suggestions (PostgreSQL-specific, skip if `config.database != "postgresql"`)

8. **PostgreSQL Optimizations**
   - `VARCHAR(255)` default where shorter length is appropriate
   - Missing `TIMESTAMPTZ` for timestamp columns (timezone awareness)
   - Consider `BIGSERIAL` vs `SERIAL` for primary keys on high-volume tables

### Step 3: Report

Display findings in the working language:

```
JPA Audit Report
================

Scope: {target path}
Files scanned: {count}

Critical ({count}):
  {file}:{line} — {description}
  Suggestion: {fix}

Warnings ({count}):
  {file}:{line} — {description}
  Suggestion: {fix}

Suggestions ({count}):
  {file}:{line} — {description}
  Suggestion: {fix}
```

If no issues found:
> "JPA audit passed. No issues detected."
