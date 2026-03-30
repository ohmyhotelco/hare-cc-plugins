---
name: be-crud
description: "Generate CRUD scaffold for an entity using CQRS layered architecture."
argument-hint: "<EntityName> [field:Type field:Type ...]"
user-invocable: true
allowed-tools: Read, Write, Glob, Bash
---

# CQRS CRUD Scaffold Generator

Generate a complete CRUD scaffold for a new entity following the project's CQRS architecture.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, tell the user to run `/backend-springboot-plugin:be-init` first and stop
3. Read `config.architecture` — currently only `cqrs` is supported

### Step 1: Parse Arguments

Parse the argument:

- **EntityName**: PascalCase entity name (required). Example: `Employee`, `LeaveRequest`
- **Fields**: Optional field definitions in `name:Type` format. Example: `email:String displayName:String startDate:LocalDate`

If no fields are provided, ask the user:
> "What fields should `{EntityName}` have? (format: `name:Type`)"
> "Example: `email:String displayName:String status:String`"
> "Standard fields (`sequence`, `id`, `createdAt`, `updatedAt`) are added automatically."

### Step 2: Determine Domain

Ask the user which domain this entity belongs to:
> "Which domain does `{EntityName}` belong to? (e.g., `hr`, `leave`, `attendance`)"

This determines:
- Controller package: `{basePackage}.{domain}.api`
- Exception package: `{basePackage}.{domain}`
- API URL prefix: `/{domain}/{entities}` (pluralized, kebab-case)

### Step 3: Read Templates

Read these templates for code patterns:
- `templates/cqrs-module.md` — package layout and code templates
- `templates/entity-conventions.md` — entity and DTO conventions

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

#### 5. Query + QueryProcessor

File: `{sourceDir}/{basePackage}/query/Get{Entities}.java`
File: `{sourceDir}/{basePackage}/query/Find{EntityName}.java`
File: `{sourceDir}/{basePackage}/querymodel/Get{EntityName}PageQueryProcessor.java`
File: `{sourceDir}/{basePackage}/querymodel/Find{EntityName}QueryProcessor.java`

- GetEntities: pagination query (page, size with max 20)
- FindEntity: single lookup by UUID
- PageQueryProcessor: returns `PageCarrier<{EntityName}View>`
- FindQueryProcessor: returns `{EntityName}View`, throws 404 if not found

#### 6. View

File: `{sourceDir}/{basePackage}/view/{EntityName}View.java`

- Record with `id` (UUID) + displayable fields

#### 7. Controller

File: `{sourceDir}/{basePackage}/{domain}/api/{EntityName}Controller.java`

- Record class with DI (executors + processors)
- POST (201), GET list (200), GET single (200/404)
- Exception handlers for domain exceptions

#### 8. Exceptions

File: `{sourceDir}/{basePackage}/{domain}/Duplicate{UniqueField}Exception.java` (for each unique field)
File: `{sourceDir}/{basePackage}/{domain}/{EntityName}NotFoundException.java`

#### 9. Work Document

File: `{workDocDir}/{kebab-case-entity}.md`

- Generate from `templates/work-document-template.md`
- Pre-fill entity fields, commands, queries, API endpoints
- Generate test scenarios as `- [ ]` items

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

Next steps:
  1. Review generated code
  2. Run /backend-springboot-plugin:be-build to verify
  3. Run /backend-springboot-plugin:be-code {workDocDir}/{entity}.md for TDD implementation
```

### Step 5.5: Initialize Pipeline State

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
