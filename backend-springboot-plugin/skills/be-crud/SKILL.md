---
name: be-crud
description: "Generate CRUD scaffold for an entity using CQRS layered architecture."
argument-hint: "<EntityName> [field:Type ...] | --all <feature-name>"
user-invocable: true
allowed-tools: Read, Write, Glob, Bash
---

# CQRS CRUD Scaffold Generator

Generate a complete CRUD scaffold for a new entity following the project's CQRS architecture. Supports two modes:

- **Manual mode** (default): `be-crud Employee email:String displayName:String`
- **Spec-driven mode**: `be-crud Employee` (when plan.json exists) or `be-crud --all employee-management`

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, tell the user to run `/backend-springboot-plugin:be-init` first and stop
3. Read `config.architecture` — currently only `cqrs` is supported

### Step 0.5: Detect Plan Mode

Determine whether to use spec-driven or manual mode:

1. Check if `--all` flag is present in the argument:
   - If `--all {feature-name}`: `mode = "spec-all"`, `feature = {feature-name}`
   - Require plan.json to exist (see below); if not found, stop with error

2. If no `--all` flag, parse the argument:
   - If argument contains `field:Type` pairs (e.g., `Employee email:String`): `mode = "manual"`, skip to Step 1
   - If argument is only an entity name (e.g., `Employee`) with no field definitions:
     - Scan for plan.json files: glob `docs/specs/*/.implementation/backend/plan.json`
     - For each found plan.json, read and check if `entities[].name` contains the entity name
     - If found: `mode = "spec"`, extract `feature` from the path (the directory name between `specs/` and `/.implementation/`), read plan.json
     - If multiple plans contain the same entity name: list matches and ask user to choose
     - If not found: `mode = "manual"`, fall through to Step 1 (will ask for fields)

3. For `mode = "spec"` or `mode = "spec-all"`:
   - Read plan.json from `docs/specs/{feature}/.implementation/backend/plan.json`
   - If plan.json does not exist:
     > "No backend plan found. Run `/backend-springboot-plugin:be-plan {feature}` first."
     - Stop here.
   - Read `templates/plan-schema.md` for type mapping reference

4. For `mode = "spec-all"`:
   - Read `entityDependencyOrder` from plan.json
   - Acquire lock once (Step 2.6) before the first entity
   - For each entity in dependency order, execute Steps 1, 2, 2.5, 3, 3.5, 4, 5, 6 sequentially (skip Step 2.6 — lock is already held)
   - If demotion check (Step 2.5) is declined for an entity: skip that entity and proceed to the next (do not stop the entire operation)
   - Release lock once (Step 7) after all entities are processed (including when all entities were skipped)
   - Display a combined report at the end
   - Skip to Step 1 with the first entity

### Step 1: Parse Arguments

#### Manual mode (`mode = "manual"`)

Parse the argument:

- **EntityName**: PascalCase entity name (required). Example: `Employee`, `LeaveRequest`
- **Fields**: Optional field definitions in `name:Type` format. Example: `email:String displayName:String startDate:LocalDate`

If no fields are provided, ask the user:
> "What fields should `{EntityName}` have? (format: `name:Type`)"
> "Example: `email:String displayName:String status:String`"
> "Standard fields (`sequence`, `id`, `createdAt`, `updatedAt`) are added automatically."

#### Spec-driven mode (`mode = "spec"` or `mode = "spec-all"`)

Extract from `plan.json.entities[]` where `name` matches the current entity:

- **EntityName**: from `entities[].name`
- **Fields**: from `entities[].fields[]` — map each field's `javaType` and `constraints`
- **Indexes**: from `entities[].indexes[]`
- **Commands**: from `plan.json.commands[]` where `entity` matches
- **Queries**: from `plan.json.queries[]` where `entity` matches
- **Endpoints**: from `plan.json.endpoints[]` that reference matching commands/queries
- **Exceptions**: from `plan.json.exceptions[]` where `entity` matches
- **Validation Rules**: from `plan.json.validationRules[]` where `entity` matches
- **Test Scenarios**: from `plan.json.testScenarios[]` where `entity` matches

Do not ask the user for fields — they are already defined in the plan.

### Step 2: Determine Domain

#### Manual mode

Ask the user which domain this entity belongs to:
> "Which domain does `{EntityName}` belong to? (e.g., `hr`, `leave`, `attendance`)"

#### Spec-driven mode

Read domain from `plan.json.entities[].domain`.
- If domain is present and non-null: use it directly, do not ask the user.
- If domain is null or missing: fall back to manual mode for this step — ask the user which domain this entity belongs to.

This determines:
- Controller package: `{basePackage}.{domain}.api`
- Exception package: `{basePackage}.{domain}`
- API URL prefix: `/{domain}/{entities}` (pluralized, kebab-case)

### Step 2.5: Demotion Check

If `{workDocDir}/.progress/{kebab-case-entity}.json` exists:

1. Read `pipeline.status`
2. If status is `"implementing"`, `"implemented"`, `"verified"`, `"verify-failed"`, `"reviewed"`, `"review-failed"`, `"fixing"`, `"done"`, `"resolved"`, or `"escalated"`:
   > "Entity '{EntityName}' already has pipeline progress (status: '{status}'). Re-running scaffold will reset the status to 'scaffolded', discarding all pipeline history."
   > "Continue?"
   If the user declines, stop here.

**Spec-all mode**: This check is performed per entity before generating files for that entity. If the user declines, skip this entity and proceed to the next — do not stop the entire operation. The lock (Step 2.6) remains held.

### Step 2.6: Acquire Lock

1. Check if `{workDocDir}/.progress/.lock` exists
2. If it exists and `lockedAt` is less than 30 minutes ago: warn the user that another operation (`{operation}`) is in progress and stop
3. If it exists and `lockedAt` is older than 30 minutes: remove the stale lock
4. Write lock file: `{ "lockedAt": "{ISO 8601}", "operation": "be-crud", "feature": "{kebab-case-entity}" }`

**Spec-all mode**: The lock is acquired once before the first entity and held for the entire multi-entity operation. It is released once in Step 7 after all entities are processed.

### Step 3: Read Templates

Read these templates for code patterns:
- `templates/cqrs-module.md` — package layout and code templates
- `templates/entity-conventions.md` — entity and DTO conventions
- `templates/checkstyle-config.md` — checkstyle rules (only when `config.checkstyle == true`)

### Step 3.5: Check Shared Classes

Check if the following shared classes exist and generate them from `templates/entity-conventions.md` if missing:

1. `{sourceDir}/{basePackage}/data/BaseEntity.java`
   - If it does not exist: generate from the BaseEntity template
2. `{sourceDir}/{basePackage}/view/PageCarrier.java`
   - If it does not exist: generate from the Generic Pagination Wrapper template

### Step 4: Generate Files

Generate the following files in order:

#### 1. Flyway Migration

File: `src/main/resources/db/migration/V{next}__create_{snake_case_entity}_table.sql`

- Determine the next migration version number by scanning existing migrations
- Generate CREATE TABLE with: `sequence BIGSERIAL PRIMARY KEY`, `id UUID NOT NULL UNIQUE`, custom fields, `created_at TIMESTAMPTZ NOT NULL`, `updated_at TIMESTAMPTZ NOT NULL`
- Add indexes for unique fields

#### 2. Entity

File: `{sourceDir}/{basePackage}/data/{EntityName}.java`

- Extends `BaseEntity`
- `sequence` (Long, `@GeneratedValue(IDENTITY)`)
- `id` (UUID, unique, not null, updatable=false)
- Custom fields with appropriate column annotations
- Lombok `@Entity`, `@Table`, `@Getter`, `@Setter`

#### 3. Repository

File: `{sourceDir}/{basePackage}/data/{EntityName}Repository.java`

- Extends `JpaRepository<{EntityName}, Long>`
- `findById(UUID id)` method
- `existsBy{UniqueField}` for unique fields

#### 4. Command + CommandExecutor

File: `{sourceDir}/{basePackage}/command/Create{EntityName}.java`
File: `{sourceDir}/{basePackage}/commandmodel/Create{EntityName}CommandExecutor.java`

- Command: record with fields from user input
- Executor: `@Component` record with validation, duplicate check, UUID v7 generation, save

**Spec-driven enhancements**: When `mode = "spec"` or `mode = "spec-all"`:
- Generate all commands from `plan.json.commands[]` for this entity (not just Create — may include Update, Delete, or domain-specific actions)
- Include validation logic from `plan.json.commands[].validations[]` in each executor
- Include side effects as TODO comments from `plan.json.commands[].sideEffects[]`

#### 5. Query + QueryProcessor

File: `{sourceDir}/{basePackage}/query/Get{EntityName}Page.java`
File: `{sourceDir}/{basePackage}/query/Find{EntityName}.java`
File: `{sourceDir}/{basePackage}/querymodel/Get{EntityName}PageQueryProcessor.java`
File: `{sourceDir}/{basePackage}/querymodel/Find{EntityName}QueryProcessor.java`

- Get{EntityName}Page: pagination query (page, size with max 20)
- FindEntity: single lookup by UUID
- PageQueryProcessor: returns `PageCarrier<{EntityName}View>`
- FindQueryProcessor: returns `{EntityName}View`, throws 404 if not found

**Spec-driven enhancements**: When `mode = "spec"` or `mode = "spec-all"`:
- Generate all queries from `plan.json.queries[]` for this entity (may include search/filter queries)
- Use `plan.json.queries[].maxPageSize` if specified (override default 20)
- Include filter fields from `plan.json.queries[].filters[]`

#### 6. View

File: `{sourceDir}/{basePackage}/view/{EntityName}View.java`

- Record with `id` (UUID) + displayable fields

#### 7. Controller

File: `{sourceDir}/{basePackage}/{domain}/api/{EntityName}Controller.java`

- Record class with DI (executors + processors)
- POST (201), GET list (200), GET single (200/404)
- Exception handlers for domain exceptions

**Spec-driven enhancements**: When `mode = "spec"` or `mode = "spec-all"`:
- Generate all endpoints from `plan.json.endpoints[]` that reference this entity's commands/queries
- Include PUT, PATCH, DELETE endpoints if defined in the plan
- Map all exceptions from `plan.json.exceptions[]` for this entity to `@ExceptionHandler` methods

#### 8. Exceptions

File: `{sourceDir}/{basePackage}/{domain}/Duplicate{UniqueField}Exception.java` (for each unique field)
File: `{sourceDir}/{basePackage}/{domain}/{EntityName}NotFoundException.java`

**Spec-driven enhancements**: When `mode = "spec"` or `mode = "spec-all"`:
- Generate all exceptions from `plan.json.exceptions[]` for this entity
- Use the exact class names and HTTP status codes from the plan

#### 9. Work Document

File: `{workDocDir}/{kebab-case-entity}.md`

- Generate from `templates/work-document-template.md`
- Pre-fill entity fields, commands, queries, API endpoints
- Generate test scenarios as `- [ ]` items

**Spec-driven enhancements**: When `mode = "spec"` or `mode = "spec-all"`:
- Include all test scenarios from `plan.json.testScenarios[]` for this entity
- Add spec source references as comments (e.g., `<!-- FR-001, TS-001 -->`)
- Include validation rules section from `plan.json.validationRules[]`
- Include exception table from `plan.json.exceptions[]`

### Step 5: Report

Display generated files in the working language:

```
CRUD Scaffold Generated: {EntityName}
======================================

Files created:
  {list of all generated files}

API Endpoints:
  POST   /{domain}/{entities}           -> 201 Created
  GET    /{domain}/{entities}?page&size  -> 200 OK
  GET    /{domain}/{entities}/{id}       -> 200 OK / 404
  {additional endpoints if spec-driven}

Next steps:
  1. Review generated code
  2. Run /backend-springboot-plugin:be-build to verify
  3. Run /backend-springboot-plugin:be-code {workDocDir}/{kebab-case-entity}.md for TDD implementation
```

For `mode = "spec-all"`, display a combined report after all entities are scaffolded:

```
CRUD Scaffold Generated: {feature} ({entityCount} entities)
============================================================

Entities scaffolded (in dependency order):
  1. {Entity1} — {endpoint count} endpoints, {scenario count} scenarios
  2. {Entity2} — {endpoint count} endpoints, {scenario count} scenarios

Total files created: {count}

Next steps:
  1. Review generated code
  2. Run /backend-springboot-plugin:be-build to verify
  3. Run /backend-springboot-plugin:be-code {workDocDir}/{kebab-case-entity}.md for each entity
```

### Step 6: Initialize Pipeline State

Create `{workDocDir}/.progress/{kebab-case-entity}.json`:

1. Create `{workDocDir}/.progress/` directory if it does not exist
2. Write progress file:
   ```json
   {
     "feature": "{kebab-case-entity}",
     "workDocument": "{workDocDir}/{kebab-case-entity}.md",
     "createdAt": "{ISO 8601}",
     "updatedAt": "{ISO 8601}",
     "pipeline": {
       "status": "scaffolded",
       "scenarios": { "total": {count from work doc}, "completed": 0 }
     }
   }
   ```

3. **Spec-driven mode only**: Add `specSource` field to the progress file:
   ```json
   {
     "specSource": {
       "planFile": "docs/specs/{feature}/.implementation/backend/plan.json",
       "entity": "{EntityName}",
       "feature": "{feature}"
     }
   }
   ```

### Step 7: Release Lock

Delete `{workDocDir}/.progress/.lock`.

- **Single-entity mode**: release immediately after Step 6.
- **Spec-all mode**: release only after the last entity's Step 6 is complete. Do not release between entities.
