---
name: be-crud
description: "Generate CRUD scaffold for an entity using CQRS layered architecture (R2DBC or MyBatis, functional or annotated web layer)."
argument-hint: "<EntityName> [field:Type[:unique][:nullable][:max=N][:pattern=email|phone|url] ...] [--domain <domain>] [--profile r2dbc|mybatis] [--yes] | --all <feature-name> [--yes]"
user-invocable: true
allowed-tools: Read, Write, Glob, Bash
---

# CQRS CRUD Scaffold Generator

Generate a complete CRUD scaffold for a new entity following the project's CQRS architecture on the WebFlux stack. Supports two modes:

- **Manual mode** (default): `be-crud Employee email:String:unique:pattern=email displayName:String:max=20`
- **Spec-driven mode**: `be-crud Employee` (when plan.json exists) or `be-crud --all employee-management`

This skill has two layers: **file generation** (Steps 0–5 — deterministic templating from `${CLAUDE_PLUGIN_ROOT}/templates/`, no open-ended judgment) and **pipeline bookkeeping** (Steps 2.5, 2.6, 3.5, 6, 7 — lock/demotion/progress-file safety). The bookkeeping steps exist because this skill's output feeds `be-code` → `be-verify` → `be-review` later in the pipeline (see ${CLAUDE_PLUGIN_ROOT}/CLAUDE.md § Pipeline); a corrupted or silently-overwritten progress file breaks that chain for every skill that runs after this one. They are file-system safety guards, not optional prompt scaffolding — do not skip any of them.

Files under `references/` write the plugin root as `{pluginRoot}`, which is `${CLAUDE_PLUGIN_ROOT}`.

## Examples

Worked examples, for when the shape of a run is unclear: `${CLAUDE_PLUGIN_ROOT}/skills/be-crud/references/examples.md`.

## Instructions

### Shared Derivation Rules (used throughout)

These mechanical transforms recur across the steps below — apply them exactly rather than re-deriving them ad hoc each time:

- **PascalCase → snake_case** (table/column names, Step 4 #1): insert `_` before each uppercase letter that follows a lowercase letter or digit, then lowercase the result. `LeaveRequest` → `leave_request`.
- **PascalCase → kebab-case** (progress file names, work document names — Steps 0.5, 2.5, 2.6, 6): same rule as snake_case, using `-` instead of `_`. `LeaveRequest` → `leave-request`.
- **Pluralization for URL paths** (Step 2, `/{domain}/{entities}`): append `s` to the kebab-case form's last word, `es` if that word ends in `s`/`x`/`ch`/`sh`, or replace a consonant+`y` ending with `ies` (`category` → `categories`, `policy` → `policies`; `key` → `keys`). `leave-request` → `leave-requests`; `expense` → `expenses`.
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
   - Read `${CLAUDE_PLUGIN_ROOT}/templates/plan-schema.md` for type mapping reference

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
- **Fields**: Optional field definitions, `name:Type[:flag…]`. Flags carry the facts Step 4 cannot
  otherwise know — `unique` (→ `existsBy{Field}` + `Duplicate{Field}Exception`, 409),
  `max=N` (→ `validate{Field}` length rule + `Invalid{Field}Exception`, 400),
  `pattern=email|phone|url` (→ the matching validator regex + `Invalid{Field}Exception`),
  `nullable` (default not null; with `max=`/`pattern=` the validator skips a `null` value and
  rejects only a present, bad one). `max=` and `pattern=` are String-only — the validator calls
  `.length()`/`matcher()`, so `amount:Integer:max=20` is rejected at parse time, not by javac. Example:
  `email:String:unique:pattern=email displayName:String:max=20 startDate:LocalDate`.
  Without flags a field is a plain not-null column with no validator and no exception — the
  templates' `email`/`displayName` are the worked case of the flags, not defaults every entity gets.

Validate `{EntityName}` before using it anywhere: it must match `^[A-Z][A-Za-z0-9]*$` (a PascalCase Java class name — `1Employee` is a path-safe string and an illegal class) and must not be a Java keyword or `Object`/`String`/`Record`. Reject and stop otherwise. Step 4 builds every output file path and every `class` line directly from this value (via the Shared Derivation Rules). Validate each field the same way: name `^[a-z][A-Za-z0-9]*$`, not a Java keyword (`class`, `default`, `int`, …), not one of the four standard fields every entity already has (`sequence`, `id`, `createdAt`, `updatedAt` — a second `id` is a duplicate member), **unique within the entity** (`email:String email:String` is a duplicate member), and — as its `snake_case` column, like the entity's `snake_case` table — not a MySQL reserved word (`order`, `group`, `key`, `rank`, `status` is fine, … the DDL is unquoted, so `Order` becomes `CREATE TABLE order`, a syntax error) and at most 64 characters (MySQL's identifier limit; `uk_{table}_{column}` must fit too) — it becomes a Java field and a column; type one of `String`, `Integer`, `Long`, `Boolean`, `BigDecimal`, `LocalDate`, `LocalDateTime`, `LocalTime`, `UUID` (the `${CLAUDE_PLUGIN_ROOT}/templates/plan-schema.md` mapping — anything else has no column type); `max=N` a positive integer; `pattern=` one of `email|phone|url`.

If no fields are provided, ask the user:
> "What fields should `{EntityName}` have? (format: `name:Type[:unique][:max=N][:pattern=email|phone|url][:nullable]`)"
> "Example: `email:String:unique:pattern=email displayName:String:max=20 status:String`"
> "Standard fields (`sequence`, `id`, `createdAt`, `updatedAt`) are added automatically."

If `config.dataProfile == "both"` and this is a new entity (no existing module to match), use
`--profile` when given (an unattended caller such as `be-jira-auto` passes it); otherwise ask:
> "Data profile for `{EntityName}`? `r2dbc` (default, simplest reactive path) or `mybatis` (match an existing MyBatis-based module's conventions / complex queries)."
> Default to `r2dbc` if the user does not answer.

#### Spec-driven mode (`mode = "spec"` or `mode = "spec-all"`)

Extract from `plan.json.entities[]` where `name` matches the current entity:

- **EntityName**: from `entities[].name` — validate with the same rule as manual mode (PascalCase Java class name, not a keyword) before using it, and validate every `entities[].fields[]` name and every `domain` with the manual-mode rules too — `plan.json` is a generated artifact, not a trusted one. A spec field's `javaType` is validated against `${CLAUDE_PLUGIN_ROOT}/templates/plan-schema.md`'s mapping table, not the manual whitelist: that table also yields primitive `boolean` and a plan-defined enum type — a field with a non-empty `enumValues[]`, whose `javaType` is `{EntityName}{FieldName}` (`${CLAUDE_PLUGIN_ROOT}/templates/plan-schema.md` § Enum Handling; each value must be a legal Java constant name, `^[A-Z][A-Z0-9_]*$`) — which are valid here and unavailable in manual mode. `plan.json` is generated by another agent from a spec file this skill does not control the provenance of, so it gets no more trust than direct user input. In `mode = "spec-all"`, a failing entity is skipped (per Step 0.5 point 4's skip-and-continue rule) rather than aborting the whole run; in `mode = "spec"`, stop.
- **Fields**: from `entities[].fields[]` — map each field's `javaType` and `constraints`
- **Enums**: for each field with `enumValues[]`, Step 4 also writes `{sourceDir}/{basePackage}/data/{EntityName}{FieldName}.java` — a plain `enum` with those constants, column `VARCHAR(50)`; no converter or type handler: both profiles map an enum by name out of the box (`${CLAUDE_PLUGIN_ROOT}/templates/plan-schema.md` § Enum Handling)
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

Use `--domain` when given (an unattended caller such as `be-jira-auto` passes it); otherwise ask
the user which domain this entity belongs to:
> "Which domain does `{EntityName}` belong to? (e.g., `hr`, `leave`, `attendance`)"

#### Spec-driven mode

Read domain from `plan.json.entities[].domain`.
- If domain is present and non-null: use it directly, do not ask the user.
- If domain is null or missing: fall back to manual mode for this step — ask the user which domain this entity belongs to.

Validate `{domain}` (from either mode) before using it: it must match `^[a-z][a-z0-9]*$` and not be a Java keyword (`int`, `new`, `package`, … — `package com.example.int.api;` does not compile) — one Java package segment, so no hyphen (`employee-admin` becomes `package com.example.employee-admin.api;`) and no leading digit. Reject and stop (or, in `mode = "spec-all"`, skip this entity) otherwise. It is used directly to build the `{domain}/api/` package path and the API URL prefix below.

This determines:
- Router/Handler package (functional, default): `{basePackage}.{domain}.api`
- Controller package (annotated, only when `config.webLayer == "annotated"`): `{basePackage}.{domain}.api`
- Exception package: `{basePackage}.{domain}`
- API URL prefix: `/{domain}/{entities}` (pluralized, kebab-case)

### Step 2.5: Demotion Check

`--yes` answers this step's confirmation with yes — for an unattended caller (`be-jira-auto`) whose user asked to start the entity over; without it the prompt is asked.

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
4. If it exists and `lockedAt` is older than 30 minutes: remove the stale lock (first the directory its `snapshotDir` names, if any)
5. Write lock file: `{ "lockedAt": "{ISO 8601}", "operation": "be-crud", "feature": "{kebab-case-entity}", "runId": "{a fresh random id, kept in memory for the release}" }`

**Spec-all mode**: The lock is acquired once before the first entity and held for the entire multi-entity operation. It is released once in Step 7 after all entities are processed.

### Step 3: Read Templates

Read `${CLAUDE_PLUGIN_ROOT}/skills/be-crud/references/generate.md` and follow this section there.

### Step 3.5: Check Shared Classes

Read `${CLAUDE_PLUGIN_ROOT}/skills/be-crud/references/generate.md` and follow this section there.

### Step 4: Generate Files

Read `${CLAUDE_PLUGIN_ROOT}/skills/be-crud/references/generate.md` and follow this section there.

### Step 5: Verify and Report

Never state a file was created without having just confirmed it — the report in 5.2 is built entirely from the verification result in 5.1, not from the list of files Step 4 *attempted* to write.

#### 5.1 Verify Each File

For every file Step 3.5 or Step 4 was supposed to generate for this entity:

1. Glob its exact path and read its modification time (`date -u -r {path} +%Y-%m-%dT%H:%M:%S`, as be-verify Step 0.6 does).
2. If the file exists and its mtime (`YYYY-MM-DDTHH:MM:SS` UTC) is not before the lock's `lockedAt` (first 19 characters of its `Z` form): add it to a `verified` list — a Step 3.5 or #8 file that already existed and was left alone counts as verified too (it was not supposed to be written).
3. Otherwise — absent, or older than this run (a write that failed left a pre-existing file in place): add it, plus the step/sub-step that was supposed to generate it, to a `failed` list. Do not guess or assume it was written — existence alone is not evidence of this run's work.

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

Delete `{workDocDir}/.progress/.lock` — release per ${CLAUDE_PLUGIN_ROOT}/CLAUDE.md § State File Safety (only a lock whose `operation` is `be-crud`; a run that waited at a prompt past 30 minutes may find another skill's lock in its place).

- **Single-entity mode**: release immediately after Step 6, or immediately after Step 5.2's report if Step 6 was skipped because `failed` was non-empty. A failed generation still must not leave the lock held.
- **Spec-all mode**: release only after the last entity's Step 6 (or skipped-Step-6) is reached. Do not release between entities.
