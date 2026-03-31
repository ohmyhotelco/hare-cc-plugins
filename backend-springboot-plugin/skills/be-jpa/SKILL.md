---
name: be-jpa
description: "Audit JPA/Hibernate patterns, schema design, migration safety, and data integrity."
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
- If no argument: audit all files in `{sourceDir}/{basePackage}/data/`, `{sourceDir}/{basePackage}/commandmodel/`, `{sourceDir}/{basePackage}/querymodel/`, and migration files (e.g., `src/main/resources/db/migration/`)

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

4. **Schema Design**
   - NOT NULL constraints missing on required fields (enforced in DB, not just application)
   - UNIQUE constraints missing on business keys (email, external IDs)
   - Foreign keys without explicit `ON DELETE` clause
   - `FLOAT` or `DOUBLE` used for monetary values (use `BigDecimal` / `NUMERIC`)

#### Warning Issues

5. **Unbounded Queries**
   - `findAll()` without pagination on tables that could grow large
   - Missing `Pageable` parameter on list queries

6. **Missing Indexes**
   - Repository has `findBy{Field}` or `existsBy{Field}` but entity has no `@Index` on that field
   - Login/lookup queries on non-indexed columns
   - Columns used in WHERE, JOIN, or ORDER BY without index

7. **Cascade Risks**
   - `CascadeType.ALL` or `CascadeType.REMOVE` on relationships (may cause unintended deletes)
   - `orphanRemoval = true` without careful consideration

8. **Entity Design**
   - Entity does not extend `BaseEntity` (missing audit fields)
   - Missing `sequence` + `id` dual key pattern
   - Mutable `id` field (should be `updatable = false`)
   - `@Table(name = "snake_case")` does not match Flyway migration table name

9. **Data Integrity**
   - Unique constraint violations handled with generic 500 instead of domain exception
   - Missing optimistic locking (`@Version`) on entities with concurrent update risk
   - `@Transactional` method contains external calls (HTTP, email) that could hang the transaction

#### Migration Issues (skip if `config.migration == "none"`)

10. **Flyway Migration Safety**
    - Migration version does not follow sequential order (V1, V2, V3...)
    - Migration is not backward-compatible with currently deployed code
    - `ALTER TABLE ... ADD COLUMN ... NOT NULL` without multi-step approach (add nullable → backfill → add constraint)
    - `CREATE INDEX` without `CONCURRENTLY` on existing tables with data
    - `DROP TABLE` or `DROP COLUMN` without confirming no dependent code
    - Column types in migration SQL do not match entity JPA annotations

#### Suggestions (PostgreSQL-specific, skip if `config.database != "postgresql"`)

11. **PostgreSQL Optimizations**
    - `VARCHAR(255)` default where shorter length is appropriate
    - Missing `TIMESTAMPTZ` for timestamp columns (timezone awareness)
    - `LocalDateTime` instead of `OffsetDateTime` for multi-timezone data
    - Consider `BIGSERIAL` vs `SERIAL` for primary keys on high-volume tables

### Step 3: Report

Display findings in the working language:

```
JPA & Database Audit Report
===========================

Scope: {target path}
Files scanned: {count} (entities: {n}, repositories: {n}, executors: {n}, processors: {n}, migrations: {n})

Critical ({count}):
  {file}:{line} — {description}
  Suggestion: {fix}

Warnings ({count}):
  {file}:{line} — {description}
  Suggestion: {fix}

Migration Issues ({count}):
  {file} — {description}
  Suggestion: {fix}

Suggestions ({count}):
  {file}:{line} — {description}
  Suggestion: {fix}
```

If no issues found:
> "JPA & database audit passed. No issues detected."
