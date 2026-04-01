---
name: be-code
description: "Implement a feature using TDD. Gathers context, writes scenarios, runs TDD cycle."
argument-hint: "<feature-name or work-doc-path>"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Implement Feature with TDD

Implement a feature using strict Test-Driven Development. This skill orchestrates the full TDD workflow: context gathering, scenario writing, and RED-GREEN cycle execution.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, tell the user to run `/backend-springboot-plugin:be-init` first and stop

### Step 1: Parse Argument

The argument can be:

- **File path**: If argument looks like a path (contains `/` or `.md`), treat it as a work document path. Extract `feature-name` from the filename by removing the `.md` extension and directory prefix (e.g., `work/features/employee.md` → `employee`). This `feature-name` is used for lock files and progress file lookups.
- **Feature name**: Otherwise, treat it as a feature description

### Step 1.5: Check Plan

If the argument is a feature name (not a file path):

1. Check if `docs/specs/{feature}/.implementation/backend/plan.json` exists
   - If exists: `planAvailable = true`, read plan.json
   - If not exists: `planAvailable = false`
2. If `planAvailable`:
   - List all entities from `plan.json.entities[]`
   - For each entity, check if `{workDocDir}/{kebab-case-entity}.md` exists
   - Build two lists: `entitiesWithWorkDoc` and `entitiesWithoutWorkDoc`
3. If `planAvailable` and multiple entities exist:
   > "Plan contains {count} entities: {entity names}"
   > "Options:"
   > "1. Process all entities sequentially (dependency order)"
   > "2. Select a specific entity to implement"
   - If user chooses 2: ask which entity, set `targetEntity = {chosen entity}`
   - If user chooses 1: `targetEntity = null` (process all in `entityDependencyOrder`)

### Step 2: Gather Context

1. Read the plugin CLAUDE.md for architecture and conventions
2. If the argument is a work document path:
   - Read the document
   - Extract `- [ ]` scenarios
   - Skip to Step 3.5 (single work document mode)
3. If the argument is a feature name and `planAvailable`:
   - Determine entity list to process:
     - If `targetEntity` is set: process only that entity
     - If `targetEntity` is null: process all entities in `plan.json.entityDependencyOrder`
   - For each entity to process:
     - Check if `{workDocDir}/{kebab-case-entity}.md` exists
     - If exists: extract `- [ ]` scenarios
     - If not exists: mark for auto-generation in Step 3
   - **Multi-entity iteration**: Steps 3 through 3.7 execute once (scenarios, lock, pipeline init for all entities). Then Steps 4 through 7 execute per entity in dependency order.
4. If the argument is a feature name and not `planAvailable`:
   - First, check if `{workDocDir}/{feature-name}.md` exists
     - If found: treat it as the work document — read it, extract `- [ ]` scenarios, and skip to Step 3.5 (same as file path mode)
   - If no matching work document:
     - Explore existing code: scan `{sourceDir}/{basePackage}/` for related entities, controllers, commands, queries
     - Read existing work documents in `{workDocDir}/` for patterns
     - Check for any related PRD/TSD documents

### Step 3: Write Test Scenarios

#### When `planAvailable` and work document does not exist

Auto-generate an enriched work document from plan.json for each entity that lacks one:

1. Read `templates/work-document-template.md` for the document format
2. For each entity in plan.json that has no existing work document, generate `{workDocDir}/{kebab-case-entity}.md` with:
   - **Entity section**: fields table from `plan.json.entities[].fields[]` with types, constraints, and source references
   - **Commands section**: from `plan.json.commands[]` for this entity, including validation steps from BR-nnn
   - **Queries section**: from `plan.json.queries[]` with filter/sort/pagination details
   - **API Endpoints section**: from `plan.json.endpoints[]` with HTTP methods, paths, status codes
   - **Validation Rules section**: from `plan.json.validationRules[]` with regex patterns and source references
   - **Exceptions section**: from `plan.json.exceptions[]` with E-nnn codes, HTTP status, and conditions
   - **Test Scenarios section**: from `plan.json.testScenarios[]` as `- [ ]` items with source references in comments
     ```
     ### POST /{domain}/{entities}

     - [ ] valid request returns 201 Created  <!-- TS-001, AC-001 -->
     - [ ] invalid email format returns 400 Bad Request  <!-- TS-002, BR-001 -->
     - [ ] duplicate email returns 409 Conflict  <!-- TS-003, BR-002 -->
     ```
   - **Test Data section**: auto-generate generator class stubs based on entity fields
3. Present the generated work document to the user for confirmation:
   > "Work document generated from plan.json for {EntityName}:"
   > "{scenario count} test scenarios from spec (TS-nnn references preserved)"
   > "Review and confirm to proceed with TDD implementation."
4. Wait for user approval before proceeding
5. If user requests changes, apply them to the work document

#### When not `planAvailable` and no work document

Follow the original manual flow:

1. Read `templates/test-scenario-template.md` for the scenario format
2. Draft test scenarios following CLAUDE.md scenario writing rules:
   - Single sentence, English, present tense
   - Start with lowercase (usable as snake_case method name)
   - Use `- [ ]` checkbox format
   - Most important scenario first
3. Mark uncertain scenarios with `?`:
   ```
   - [ ] valid request returns 201 Created
   - [ ] duplicate email returns 409 Conflict
   - [ ] ? empty display name returns 400 Bad Request
   ```
4. Present the scenario list to the user for approval:
   > "Here are the test scenarios for {feature}:"
   > {scenario list}
   > "Please review. I'll remove scenarios marked with `?` unless you confirm them."
5. Wait for user approval before proceeding
6. Save approved scenarios to `{workDocDir}/{feature-name}.md`

### Step 3.5: Demotion Check

**Single-entity mode** (file path or single entity): If `{workDocDir}/.progress/{feature-name}.json` exists:

1. Read `pipeline.status`
2. If status is `"verified"`, `"reviewed"`, or `"done"`:
   > "This feature is currently '{status}'. Re-running TDD implementation will reset the pipeline status to 'implementing', discarding verification/review progress."
   > "Continue?"
   If the user declines, stop here.
3. If status is `"fixing"`:
   > "This feature is currently 'fixing' (be-fix in progress). Re-running implementation will overwrite fix changes."
   > "Continue?"
   If the user declines, stop here.
4. If status is `"escalated"`:
   > "This feature was escalated (manual intervention required). Running TDD implementation may build on unresolved issues."
   > "Continue?"
   If the user declines, stop here.

**Multi-entity mode**: Skip this step here. Demotion check is performed per-entity at the start of Step 4 (before launching the implement agent for each entity).

### Step 3.6: Acquire Lock

1. Check if `{workDocDir}/.progress/.lock` exists
2. If it exists and `lockedAt` is less than 30 minutes ago: warn the user that another operation (`{operation}`) is in progress and stop
3. If it exists and `lockedAt` is older than 30 minutes: remove the stale lock
4. Write lock file: `{ "lockedAt": "{ISO 8601}", "operation": "be-code", "feature": "{feature-name}" }`

**Multi-entity mode**: The lock is acquired once here and held for the entire multi-entity operation. It is released once in Step 7 after all entities are processed.

### Step 3.7: Initialize Pipeline State

For each entity being processed, create or update `{workDocDir}/.progress/{kebab-case-entity}.json`:

1. Create `{workDocDir}/.progress/` directory if it does not exist
2. If progress file does not exist, create it:
   ```json
   {
     "feature": "{kebab-case-entity}",
     "workDocument": "{workDocDir}/{kebab-case-entity}.md",
     "createdAt": "{ISO 8601}",
     "updatedAt": "{ISO 8601}",
     "pipeline": {
       "status": "implementing",
       "scenarios": { "total": {count}, "completed": 0 }
     }
   }
   ```
3. If progress file exists: **read-modify-write** — update only `pipeline.status` to `"implementing"` and refresh scenario counts. **Preserve all existing fields** including `specSource`, `pipeline.verification`, `pipeline.review`, etc.

### Step 4: TDD Cycle

**Per-entity execution**: When processing multiple entities (plan-driven mode), Steps 4-7 execute once per entity. The current entity's work document is passed to the implement agent.

**Per-entity demotion check (multi-entity mode only)**: Before launching the implement agent for each entity, check `{workDocDir}/.progress/{kebab-case-entity}.json`:
1. If it exists, read `pipeline.status`
2. If status is `"verified"`, `"reviewed"`, `"done"`, `"fixing"`, or `"escalated"`: warn the user (same messages as Step 3.5) and ask for confirmation per entity
3. If the user declines for a specific entity: skip that entity and proceed to the next

**Subagent Isolation**: Pass only the specified parameters below. Do not include conversation history or user feedback from prior steps.

Launch the `implement` agent once per entity with:

- `workDocument`: path to the current entity's work document (`{workDocDir}/{kebab-case-entity}.md`)
- `config`: the parsed plugin config
- `projectRoot`: current project root

The implement agent processes all scenarios internally:
1. Select the next `- [ ]` scenario
2. Write test (RED)
3. Implement minimum code (GREEN)
4. Mark as `- [x]`
5. Repeat until all scenarios are complete

### Step 5: Final Build

After all scenarios are complete, run a full build:

```bash
{config.buildCommand}
```

Set Bash tool timeout to 600000ms.

### Step 6: Report

Display implementation summary in the working language:

```
Feature Implementation Complete: {feature-name}
=======================================

Scenarios: {completed}/{total}
  {list each scenario with status}

Files created:
  {list of new files}

Files modified:
  {list of modified files}

Build: {PASS / FAIL}
```

If the build failed, suggest running `/backend-springboot-plugin:be-build` for auto-diagnosis.

### Step 7: Update Pipeline State

Update `{workDocDir}/.progress/{kebab-case-entity}.json` for the current entity:

1. Read progress file
2. Update `pipeline.scenarios.completed` with final count of `- [x]` items
3. Update `pipeline.status`:
   - All scenarios complete + build passes → `"implemented"`
   - All scenarios complete + build fails → `"implemented"` (build issue is separate)
   - Some scenarios remain → `"implementing"`
4. Update `updatedAt` timestamp
5. Write back (read-modify-write — preserve all existing fields including `specSource`)

6. Release lock: delete `{workDocDir}/.progress/.lock` **only in single-entity mode or after the last entity in multi-entity mode**. Do not release the lock between entities.

**Multi-entity mode**: After completing one entity, display a brief per-entity status and proceed to the next entity (return to Step 4 for the next entity in `entityDependencyOrder` — scenario writing and lock acquisition do not re-run per entity). After the last entity's Step 7 completes, release the lock. Then display a combined summary report (using the Step 6 format but covering all entities).

Suggest next step:
- **All entities implemented + build passes**: `/backend-springboot-plugin:be-verify {entity}` for each entity
- **implemented + build fails**: `/backend-springboot-plugin:be-build`
- **implementing**: resume with `/backend-springboot-plugin:be-code {workDoc}`

### Error Handling

- **3 consecutive test failures**: The implement agent will stop. Present the issue to the user with context and ask for guidance.
- **Compilation errors during TDD**: The implement agent will fix stubs, not tests.
- **User cancellation**: Save progress (completed scenarios remain `- [x]`). The user can re-run `be-code` with the same work document to resume.
