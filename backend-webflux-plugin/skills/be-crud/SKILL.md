---
name: be-crud
description: "Generate CRUD scaffold for an entity using CQRS layered architecture (R2DBC or MyBatis, functional or annotated web layer)."
argument-hint: "<EntityName> [field:Type ...] | --all <feature-name>"
user-invocable: true
allowed-tools: Read, Write, Glob, Bash
---

# CQRS CRUD Scaffold Generator

Generate a complete CRUD scaffold for a new entity following the project's CQRS architecture on the WebFlux stack. Supports two modes:

- **Manual mode** (default): `be-crud Employee email:String displayName:String`
- **Spec-driven mode**: `be-crud Employee` (when plan.json exists) or `be-crud --all employee-management`

This skill has two layers: **file generation** (Steps 0–5 — deterministic templating from `templates/`, no open-ended judgment) and **pipeline bookkeeping** (Steps 2.5, 2.6, 3.5, 6, 7 — lock/demotion/progress-file safety). The bookkeeping steps exist because this skill's output feeds `be-code` → `be-verify` → `be-review` later in the pipeline (see plugin `CLAUDE.md` § Pipeline); a corrupted or silently-overwritten progress file breaks that chain for every skill that runs after this one. They are file-system safety guards, not optional prompt scaffolding — do not skip any of them.

## Examples

### Example 1 — easy case: manual mode, R2DBC

Input: `be-crud Employee email:String displayName:String`

1. Step 0 reads config: `dataProfile: "both"`, `webLayer: "functional"` → Step 1 asks for the data profile; user accepts the default, `r2dbc`.
2. Step 2 asks for the domain; user answers `hr`.
3. Step 4 generates `Employee.java` (excerpt — full template in `templates/entity-conventions-r2dbc.md`):

   ```java
   @Table("employee")
   public class Employee {
       @Id
       @Column("sequence")
       private Long sequence;

       @Column("id")
       private UUID id;

       @Column("email")
       private String email;

       @Column("display_name")
       private String displayName;

       @Column("created_at")
       private LocalDateTime createdAt;

       @Column("updated_at")
       private LocalDateTime updatedAt;
   }
   ```

4. Step 4 also generates the router bean (excerpt — full template in `templates/web-layer-functional.md`):

   ```java
   @Bean
   public RouterFunction<ServerResponse> employeeRoutes(EmployeeHandler handler) {
       return RouterFunctions.route()
           .POST("/hr/employees", handler::create)
           .GET("/hr/employees", handler::list)
           .GET("/hr/employees/{id}", handler::find)
           .build();
   }
   ```

5. Step 5.1 Globs every path just written and confirms all files landed; Step 5.2 reports:

   ```
   CRUD Scaffold Generated: Employee (dataProfile: r2dbc, webLayer: functional)
   ======================================

   Files created (verified):
     src/main/resources/migration/V1__create_employee_table.sql
     src/main/java/com/example/data/Employee.java
     src/main/java/com/example/data/EmployeeRepository.java
     src/main/java/com/example/command/CreateEmployee.java
     src/main/java/com/example/commandmodel/CreateEmployeeCommandExecutor.java
     src/main/java/com/example/query/GetEmployeePage.java
     src/main/java/com/example/query/FindEmployee.java
     src/main/java/com/example/querymodel/GetEmployeePageQueryProcessor.java
     src/main/java/com/example/querymodel/FindEmployeeQueryProcessor.java
     src/main/java/com/example/view/EmployeeView.java
     src/main/java/com/example/hr/api/EmployeeRouter.java
     src/main/java/com/example/hr/api/EmployeeHandler.java
     src/main/java/com/example/hr/DuplicateEmailException.java
     src/main/java/com/example/hr/EmployeeNotFoundException.java
     work/features/employee.md

   Failed (not created — investigate before proceeding):
     (none)

   API Endpoints:
     POST   /hr/employees           -> 201 Created
     GET    /hr/employees?page&size -> 200 OK
     GET    /hr/employees/{id}      -> 200 OK / 404
   ```

### Example 2 — tricky case: `--all` with one entity already mid-pipeline

Input: `be-crud --all leave-management`, where `plan.json` lists `LeaveType` then `LeaveRequest` in `entityDependencyOrder`, and `{workDocDir}/.progress/leave-request.json` already has `pipeline.status: "implementing"` from a prior run.

1. Step 2.6 acquires the lock once, before `LeaveType`.
2. `LeaveType` has no existing progress file — Steps 1–6 run normally for it.
3. For `LeaveRequest`, Step 2.5 finds the existing progress file and warns: "Entity 'LeaveRequest' already has pipeline progress (status: 'implementing'). Re-running scaffold will reset the status to 'scaffolded', discarding all pipeline history. Continue?"
4. The user declines. Per Step 2.5's spec-all rule, `LeaveRequest` is skipped — not the whole `--all` run — and the lock stays held.
5. Step 7 releases the lock once, after both entities have been attempted. The combined report separates what was generated from what was skipped:

   ```
   CRUD Scaffold Generated: leave-management (2 entities in plan)
   ============================================================

   Entities scaffolded (in dependency order):
     1. LeaveType (r2dbc) — 3 endpoints, 5 scenarios

   Entities skipped (demotion declined):
     2. LeaveRequest — existing status was 'implementing'; no files touched

   Total files created: 15
   ```

## Instructions

### Shared Derivation Rules (used throughout)

These mechanical transforms recur across the steps below — apply them exactly rather than re-deriving them ad hoc each time:

- **PascalCase → snake_case** (table/column names, Step 4 #1): insert `_` before each uppercase letter that follows a lowercase letter or digit, then lowercase the result. `LeaveRequest` → `leave_request`.
- **PascalCase → kebab-case** (progress file names, work document names — Steps 0.5, 2.5, 2.6, 6): same rule as snake_case, using `-` instead of `_`. `LeaveRequest` → `leave-request`.
- **Pluralization for URL paths** (Step 2, `/{domain}/{entities}`): append `s` to the kebab-case form's last word, or `es` if that word ends in `s`/`x`/`ch`/`sh`. `leave-request` → `leave-requests`; `expense` → `expenses`.
- **Next migration version number** (Step 4 #1): Glob `src/main/resources/migration/V*__*.sql`, extract the integer between `V` and the first `__` from each matched filename, take the max (0 if no files exist), and use `max + 1`. Plain integers, no zero-padding: `V1`, `V2`, … `V10`.

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, tell the user to run `/backend-webflux-plugin:be-init` first and stop
3. Read `config.architecture` — currently only `cqrs` is supported
4. Read `config.dataProfile` (`"r2dbc" | "mybatis" | "both"`) and `config.webLayer` (`"functional" | "annotated"`) — these gate which templates are used in Step 4. See `docs/decisions.md` Decision 1 and Decision 2.

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
     > "No backend plan found. Run `/backend-webflux-plugin:be-plan {feature}` first."
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

Validate `{EntityName}` before using it anywhere: reject and stop with an error if it contains `/`, `\`, `..`, or any character outside `[A-Za-z0-9]`. Step 4 builds every output file path directly from this value (via the Shared Derivation Rules) — an unvalidated name could escape the intended source/output directories.

If no fields are provided, ask the user:
> "What fields should `{EntityName}` have? (format: `name:Type`)"
> "Example: `email:String displayName:String status:String`"
> "Standard fields (`sequence`, `id`, `createdAt`, `updatedAt`) are added automatically."

If `config.dataProfile == "both"` and this is a new entity (no existing module to match), ask:
> "Data profile for `{EntityName}`? `r2dbc` (default, simplest reactive path) or `mybatis` (match an existing MyBatis-based module's conventions / complex queries)."
> Default to `r2dbc` if the user does not answer.

#### Spec-driven mode (`mode = "spec"` or `mode = "spec-all"`)

Extract from `plan.json.entities[]` where `name` matches the current entity:

- **EntityName**: from `entities[].name` — validate with the same rule as manual mode (reject `/`, `\`, `..`, or any character outside `[A-Za-z0-9]`) before using it. `plan.json` is generated by another agent from a spec file this skill does not control the provenance of, so it gets no more trust than direct user input. In `mode = "spec-all"`, a failing entity is skipped (per Step 0.5 point 4's skip-and-continue rule) rather than aborting the whole run; in `mode = "spec"`, stop.
- **Fields**: from `entities[].fields[]` — map each field's `javaType` and `constraints`
- **Indexes**: from `entities[].indexes[]`
- **Commands**: from `plan.json.commands[]` where `entity` matches
- **Queries**: from `plan.json.queries[]` where `entity` matches
- **Endpoints**: from `plan.json.endpoints[]` that reference matching commands/queries
- **Exceptions**: from `plan.json.exceptions[]` where `entity` matches
- **Validation Rules**: from `plan.json.validationRules[]` where `entity` matches
- **Test Scenarios**: from `plan.json.testScenarios[]` where `entity` matches
- **Data profile**: use `config.dataProfile` if it is `"r2dbc"` or `"mybatis"`; if `"both"`, default this entity to `r2dbc` unless the plan/work document says otherwise — do not ask the user in spec-driven mode

Do not ask the user for fields — they are already defined in the plan.

### Step 2: Determine Domain

#### Manual mode

Ask the user which domain this entity belongs to:
> "Which domain does `{EntityName}` belong to? (e.g., `hr`, `leave`, `attendance`)"

#### Spec-driven mode

Read domain from `plan.json.entities[].domain`.
- If domain is present and non-null: use it directly, do not ask the user.
- If domain is null or missing: fall back to manual mode for this step — ask the user which domain this entity belongs to.

Validate `{domain}` (from either mode) before using it: reject and stop (or, in `mode = "spec-all"`, skip this entity) if it contains `/`, `\`, `..`, or any character outside `[a-z0-9-]`. It is used directly to build the `{domain}/api/` package path and the API URL prefix below.

This determines:
- Router/Handler package (functional, default): `{basePackage}.{domain}.api`
- Controller package (annotated, only when `config.webLayer == "annotated"`): `{basePackage}.{domain}.api`
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

1. Run `mkdir -p {workDocDir}/.progress` (Bash) — idempotent, safe to run even if the directory already exists. This is the directory both the lock file and the progress files (Step 6) live in.
2. Check if `{workDocDir}/.progress/.lock` exists
3. If it exists and `lockedAt` is less than 30 minutes ago: warn the user that another operation (`{operation}`) is in progress and stop
4. If it exists and `lockedAt` is older than 30 minutes: remove the stale lock
5. Write lock file: `{ "lockedAt": "{ISO 8601}", "operation": "be-crud", "feature": "{kebab-case-entity}" }`

**Spec-all mode**: The lock is acquired once before the first entity and held for the entire multi-entity operation. It is released once in Step 7 after all entities are processed.

### Step 3: Read Templates

Read these templates for code patterns:
- `templates/cqrs-module.md` — package layout, and pointers to the profile/web-layer files below
- `templates/entity-conventions.md` — shared DTO/exception/validator conventions
- `templates/entity-conventions-r2dbc.md` or `templates/entity-conventions-mybatis.md` — matching this entity's resolved `dataProfile` (never read both for one entity)
- `templates/web-layer-functional.md` or `templates/web-layer-annotated.md` — matching `config.webLayer`
- `templates/checkstyle-config.md` — checkstyle rules (only when `config.checkstyle == true`)
- `templates/coverage-gate.md` — JaCoco Gradle block (only when generating a new project's `build.gradle`, not per-entity)

### Step 3.5: Check Shared Classes

Check if the following shared classes exist and generate them if missing:

1. `{sourceDir}/{basePackage}/view/PageCarrier.java`
   - If it does not exist: generate from the Generic Pagination Wrapper template in `templates/entity-conventions.md`

There is no `BaseEntity` shared class in this plugin (no auditing-listener equivalent — see `templates/entity-conventions.md`). Do not generate one.

### Step 4: Generate Files

Generate the following files in order. Use the entity's resolved `dataProfile` (`r2dbc` or `mybatis`, never `"both"` for a single entity) and `config.webLayer` to select which template variant applies.

#### 1. Manual SQL Migration

File: `src/main/resources/migration/V{next}__create_{snake_case_entity}_table.sql`

- Determine `{next}` and `{snake_case_entity}` using the Shared Derivation Rules above
- Generate `CREATE TABLE` with MySQL syntax: `sequence BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY`, `id CHAR(36) NOT NULL UNIQUE`, custom fields, `created_at DATETIME(6) NOT NULL`, `updated_at DATETIME(6) NOT NULL`, `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`
- Add indexes for unique fields
- This file is generated only — never executed by this skill (see `docs/decisions.md` Decision 3)

#### 2. Entity / POJO

**R2DBC**: File: `{sourceDir}/{basePackage}/data/{EntityName}.java` — `@Table`/`@Column`-annotated class per `templates/entity-conventions-r2dbc.md` Entity Template.

**MyBatis**: File: `{sourceDir}/{basePackage}/data/{EntityName}.java` — plain POJO, no annotations, per `templates/entity-conventions-mybatis.md` Entity (POJO) Template. Also generate `{sourceDir}/{basePackage}/data/{EntityName}Mapper.java` (interface) and `src/main/resources/mapper/{EntityName}Mapper.xml`.

Both: Lombok `@Getter`, `@Setter` when `config.lombokEnabled == true`.

#### 3. Repository (R2DBC only)

File: `{sourceDir}/{basePackage}/data/{EntityName}Repository.java`

- Extends `ReactiveCrudRepository<{EntityName}, Long>`
- `findById(UUID id)` returning `Mono<{EntityName}>`
- `existsBy{UniqueField}` returning `Mono<Boolean>` for unique fields

MyBatis entities skip this file (the mapper interface + XML generated in Step 2 covers persistence).

#### 4. Command + CommandExecutor

File: `{sourceDir}/{basePackage}/command/Create{EntityName}.java`
File: `{sourceDir}/{basePackage}/commandmodel/Create{EntityName}CommandExecutor.java`

- Command: record with fields from user input
- Executor: `@Component` record returning `Mono<Void>` — R2DBC uses `flatMap`-chained repository calls (see `templates/entity-conventions-r2dbc.md` § Command Executor); MyBatis wraps mapper calls in `Mono.fromCallable(...).subscribeOn(Schedulers.boundedElastic())` (see `templates/entity-conventions-mybatis.md` § Command Executor). Includes validation, duplicate check, UUID v7 generation, explicit `createdAt`/`updatedAt` assignment, save/insert.

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
- PageQueryProcessor: returns `Mono<PageCarrier<{EntityName}View>>`
- FindQueryProcessor: returns `Mono<{EntityName}View>`, empty `Mono` (mapped to 404 at the web layer) if not found

**Spec-driven enhancements**: When `mode = "spec"` or `mode = "spec-all"`:
- Generate all queries from `plan.json.queries[]` for this entity (may include search/filter queries)
- Use `plan.json.queries[].maxPageSize` if specified (override default 20)
- Include filter fields from `plan.json.queries[].filters[]`

#### 6. View

File: `{sourceDir}/{basePackage}/view/{EntityName}View.java`

- Record with `id` (UUID) + displayable fields

#### 7. Web Layer

**Functional (default, `config.webLayer == "functional"`)**:
File: `{sourceDir}/{basePackage}/{domain}/api/{EntityName}Router.java` — `@Configuration` class with a `RouterFunction<ServerResponse>` `@Bean`.
File: `{sourceDir}/{basePackage}/{domain}/api/{EntityName}Handler.java` — `@Component` record with DI (executors + processors), one method per route, `onErrorResume` chain mapping domain exceptions to HTTP status.

**Annotated (only when `config.webLayer == "annotated"`)**:
File: `{sourceDir}/{basePackage}/{domain}/api/{EntityName}Controller.java` — record class with DI, `@RestController`, methods returning `Mono`/`Flux`, `@ExceptionHandler` methods for domain exceptions.

Both styles: POST (201), GET list (200), GET single (200/404).

**Spec-driven enhancements**: When `mode = "spec"` or `mode = "spec-all"`:
- Generate all endpoints from `plan.json.endpoints[]` that reference this entity's commands/queries
- Include PUT, PATCH, DELETE routes/endpoints if defined in the plan
- Map all exceptions from `plan.json.exceptions[]` for this entity to the router's error chain or `@ExceptionHandler` methods

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
- Record the resolved `dataProfile` for this entity at the top of the document
- Generate test scenarios as `- [ ]` items

**Spec-driven enhancements**: When `mode = "spec"` or `mode = "spec-all"`:
- Include all test scenarios from `plan.json.testScenarios[]` for this entity
- Add spec source references as comments (e.g., `<!-- FR-001, TS-001 -->`)
- Include validation rules section from `plan.json.validationRules[]`
- Include exception table from `plan.json.exceptions[]`

### Step 5: Verify and Report

Never state a file was created without having just confirmed it — the report in 5.2 is built entirely from the verification result in 5.1, not from the list of files Step 4 *attempted* to write.

#### 5.1 Verify Each File

For every file Step 3.5 or Step 4 was supposed to generate for this entity:

1. Glob its exact path.
2. If the glob matches: add it to a `verified` list.
3. If the glob does not match: add it, plus the step/sub-step that was supposed to generate it, to a `failed` list. Do not guess or assume it exists — an un-globbed file is a failed file, not an omission.

#### 5.2 Report

Display the result in the working language, built only from the `verified`/`failed` lists from 5.1 — never from the pre-verification generation list:

```
CRUD Scaffold Generated: {EntityName} (dataProfile: {r2dbc|mybatis}, webLayer: {functional|annotated})
======================================

Files created (verified):
  {verified list from 5.1}

Failed (not created — investigate before proceeding):
  {failed list from 5.1, or "(none)"}

API Endpoints:
  POST   /{domain}/{entities}           -> 201 Created
  GET    /{domain}/{entities}?page&size  -> 200 OK
  GET    /{domain}/{entities}/{id}       -> 200 OK / 404
  {additional endpoints if spec-driven}

Next steps:
  1. Review generated code
  2. Run /backend-webflux-plugin:be-build to verify
  3. Run /backend-webflux-plugin:be-code {workDocDir}/{kebab-case-entity}.md for TDD implementation
```

If `failed` is non-empty, do not claim the scaffold is complete — state plainly that generation partially failed for this entity. Step 6's progress record must not be written for it: an incomplete file set should not receive a `"scaffolded"` status.

For `mode = "spec-all"`, display a combined report after all entities are attempted, applying 5.1's verification per entity before assembling it:

```
CRUD Scaffold Generated: {feature} ({entityCount} entities in plan)
============================================================

Entities scaffolded (in dependency order):
  1. {Entity1} ({dataProfile}) — {endpoint count} endpoints, {scenario count} scenarios, all files verified
  2. {Entity2} ({dataProfile}) — {endpoint count} endpoints, {scenario count} scenarios, all files verified

Entities with failed files (see per-entity detail above):
  {Entity} — {count} file(s) failed, or "(none)"

Entities skipped (demotion declined):
  {Entity} — existing status was '{status}', or "(none)"

Total files created: {count}

Next steps:
  1. Review generated code
  2. Run /backend-webflux-plugin:be-build to verify
  3. Run /backend-webflux-plugin:be-code {workDocDir}/{kebab-case-entity}.md for each entity
```

### Step 6: Initialize Pipeline State

Skip this step entirely for an entity whose Step 5.1 `failed` list is non-empty — do not write a `"scaffolded"` progress record for a file set that is not actually complete. In spec-all mode, proceed to the next entity instead.

Otherwise, create `{workDocDir}/.progress/{kebab-case-entity}.json` (the directory already exists from Step 2.6's `mkdir -p`):

1. Write progress file:
   ```json
   {
     "feature": "{kebab-case-entity}",
     "workDocument": "{workDocDir}/{kebab-case-entity}.md",
     "createdAt": "{ISO 8601}",
     "updatedAt": "{ISO 8601}",
     "dataProfile": "{r2dbc|mybatis}",
     "pipeline": {
       "status": "scaffolded",
       "scenarios": { "total": {count from work doc}, "completed": 0 }
     }
   }
   ```

2. **Spec-driven mode only**: Add `specSource` field to the progress file:
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

- **Single-entity mode**: release immediately after Step 6, or immediately after Step 5.2's report if Step 6 was skipped because `failed` was non-empty. A failed generation still must not leave the lock held.
- **Spec-all mode**: release only after the last entity's Step 6 (or skipped-Step-6) is reached. Do not release between entities.
