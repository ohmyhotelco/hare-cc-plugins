---
name: be-code
description: "TDD-implement a CQRS/WebFlux feature: RED-GREEN cycle through command executors, query processors, and router/handler code. Consumes a be-crud scaffold, plan.json, or an existing work document with test scenarios; drafts scenarios manually if none exist. Use be-crud first when no scaffold exists yet."
argument-hint: "<feature-name or work-doc-path>"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Implement Feature with TDD

Implement a feature using strict Test-Driven Development. This skill orchestrates the full TDD workflow: context gathering, scenario writing, and RED-GREEN cycle execution.

This skill holds an exclusive cross-skill lock (`{workDocDir}/.progress/.lock`) for the duration of the run and can demote a feature's pipeline status, discarding verification/review progress (see Step 3.5). Ground every claim in the Step 6 report in evidence — build output, `git status`/`git diff` — never narrate completion from memory, and never leave the lock file behind on failure or cancellation (see Error Handling).

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, tell the user to run `/backend-webflux-plugin:be-init` first and stop

### Step 1: Parse Argument

The argument can be:

- **File path**: If argument looks like a path (contains `/` or `.md`), treat it as a work document path. Extract `feature-name` from the filename by removing the `.md` extension and directory prefix (e.g., `work/features/employee.md` → `employee`). This `feature-name` is used for lock files and progress file lookups.
- **Feature name**: Otherwise, treat it as a feature description

Validate `feature-name` (however derived above): reject and stop with an error if it contains `/`, `\`, `..`, or any character outside `[a-z0-9-]`. It is used directly to build progress-file and lock-file paths under `{workDocDir}/.progress/` in later steps — an unvalidated value could escape that directory.

### Step 1.5: Check Plan

If the argument is a feature name (not a file path):

1. Check if `docs/specs/{feature}/.implementation/backend/plan.json` exists
   - If exists: `planAvailable = true`, read plan.json
   - If not exists: `planAvailable = false`
2. If `planAvailable`:
   - List all entities from `plan.json.entities[]`
   - Validate each entity's `name`: reject and skip that entity if it contains `/`, `\`, `..`, or any character outside `[A-Za-z0-9]`. `plan.json` comes from another agent reading a spec file this skill does not control the provenance of, so it gets no more trust than direct user input — and the derived kebab-case form is used to build work-document and progress-file paths below.
   - For each remaining entity, check if `{workDocDir}/{kebab-case-entity}.md` exists
   - Build two lists: `entitiesWithWorkDoc` and `entitiesWithoutWorkDoc`
3. If `planAvailable` and multiple entities exist:
   > "Plan contains {count} entities: {entity names}"
   > "Options:"
   > "1. Process all entities sequentially (dependency order)"
   > "2. Select a specific entity to implement"
   - If user chooses 2: ask which entity, set `targetEntity = {chosen entity}`
   - If user chooses 1: `targetEntity = null` (process all in `entityDependencyOrder`)

### Step 2: Gather Context

1. Read `templates/core-conventions.md` for architecture and conventions (a trimmed,
   execution-facing subset of the plugin CLAUDE.md — see that file's own header for
   what it omits)
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
   - **Multi-entity iteration**: Steps 3 through 3.7 execute once (scenarios, lock, pipeline init for all entities). Steps 4 through 6 (the TDD cycle, build, and report) then execute once for the whole batch, not per entity — see Step 4's "Multi-entity batching" note. Step 7 (pipeline-state bookkeeping) still executes per entity in dependency order.
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

**Multi-entity mode**: Skip this step here. Demotion check is performed per-entity at the start of Step 4, before the single batched `implement` agent call.

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

**Multi-entity batching**: When processing multiple entities (plan-driven mode),
Steps 4-6 run **once for the whole batch**, not once per entity — launching a
separate `implement` agent per entity repeats that agent's own Phase 0 context load
(conventions, templates) for no benefit, since it never changes across entities in
the same run. Step 7 (pipeline-state bookkeeping) still runs per entity, since each
entity has its own progress file.

**Per-entity demotion check (multi-entity mode only)**: Before launching the
implement agent, loop over every entity in `entityDependencyOrder` and check
`{workDocDir}/.progress/{kebab-case-entity}.json`:
1. If it exists, read `pipeline.status`
2. If status is `"verified"`, `"reviewed"`, `"done"`, `"fixing"`, or `"escalated"`: warn the user (same messages as Step 3.5) and ask for confirmation for this entity
3. If the user declines for a specific entity: leave it out of the batch and proceed to the next entity's check

Build `confirmedEntities` from every entity that was not declined, in dependency
order. If `confirmedEntities` ends up empty, do not launch the implement agent and
do not run Step 5's build (there is nothing new to build) — go directly to Step 6
and produce its combined report with an empty "Entities implemented" list and the
full "Entities skipped" list (Step 6's own format already covers this; do not skip
Step 6 itself, since it is the only step that renders that report). Step 7 then
runs with an empty `confirmedEntities` loop — it has nothing to update, so it just
releases the lock.

**Subagent Isolation**: Pass only the specified parameters below. Do not include conversation history or user feedback from prior steps.

**Baseline for evidence**: Before launching the agent, run `git status --porcelain`
once for the whole batch. Record this output as the baseline — Step 6 diffs against
it to ground the Files created/modified lists in evidence instead of memory.

Launch the `implement` agent **once** with:

- **Single-entity mode** (file path argument, or plan-driven with exactly one
  entity): `workDocument`: path to the work document.
- **Multi-entity mode**: `workDocuments`: ordered array of work document paths, one
  per entity in `confirmedEntities` (dependency order), e.g.
  `["{workDocDir}/leave-type.md", "{workDocDir}/leave-request.md"]`.
- `config`: the parsed plugin config
- `projectRoot`: current project root

The implement agent loads its Phase 0 context once, then processes each document's
scenarios in order (all of document 1's scenarios, then document 2's, ...):
1. Select the next `- [ ]` scenario in the current document
2. Write test (RED)
3. Implement minimum code (GREEN)
4. Mark as `- [x]`
5. Repeat until the current document is complete, then move to the next document

### Step 5: Final Build

Skip this step when `confirmedEntities` was empty (nothing was implemented — see
Step 4) and report `Build: not run — no entities to build` in Step 6 instead.

Otherwise, after the implement agent returns (single document, or the whole batch,
complete — or stopped early per its own 3-consecutive-failure rule), run a full
build:

```bash
{config.buildCommand}
```

Set Bash tool timeout to 600000ms.

### Step 6: Report

Derive the "Files created" and "Files modified" lists from `git status --porcelain` (compared against the Step 4 baseline) and `git diff --stat` — never from memory or the implement agent's self-report. A `??` entry is a created file; an `M` entry is a modified file. If `git` is unavailable or the working tree is outside version control, state "not verified: file lists" instead of guessing.

Display implementation summary in the working language.

**Single-entity mode:**

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

**Multi-entity mode** — one combined report covering every entity in
`confirmedEntities`, plus any skipped in the demotion check:

```
Feature Implementation Complete: {feature} ({entityCount} entities)
=======================================

Entities implemented (in dependency order):
  1. {Entity1} — {completed}/{total} scenarios
  2. {Entity2} — {completed}/{total} scenarios

Entities skipped (demotion declined):
  {Entity} — existing status was '{status}', or "(none)"

Files created:
  {list of new files, across all entities}

Files modified:
  {list of modified files, across all entities}

Build: {PASS / FAIL}
```

If the build failed, suggest running `/backend-webflux-plugin:be-build` for auto-diagnosis.

### Step 7: Update Pipeline State

For each entity in `confirmedEntities` (or the single entity in single-entity mode),
update `{workDocDir}/.progress/{kebab-case-entity}.json`:

1. Read progress file
2. Update `pipeline.scenarios.completed` with final count of `- [x]` items in that entity's own work document
3. Update `pipeline.status`:
   - All scenarios complete + build passes → `"implemented"`
   - All scenarios complete + build fails → `"implemented"` (build issue is separate)
   - Some scenarios remain → `"implementing"`
4. Update `updatedAt` timestamp
5. Write back (read-modify-write — preserve all existing fields including `specSource`)

After every entity's (or the single entity's) progress file is updated, release the
lock: delete `{workDocDir}/.progress/.lock`.

Suggest next step:
- **All entities implemented + build passes**: `/backend-webflux-plugin:be-verify {entity}` for each entity
- **implemented + build fails**: `/backend-webflux-plugin:be-build`
- **implementing**: resume with `/backend-webflux-plugin:be-code {workDoc}`

### Error Handling

- **3 consecutive test failures**: The implement agent will stop. Present the issue to the user with context and ask for guidance. This is a pause within the same run, not an abandoned operation — keep the lock held; it releases normally in Step 7 once the run resumes and completes.
- **Compilation errors during TDD**: The implement agent will fix stubs, not tests.
- **User cancellation**: Save progress (completed scenarios remain `- [x]`). Release `{workDocDir}/.progress/.lock` before stopping, since Step 7 — which normally releases it — will not run. The user can re-run `be-code` with the same work document to resume.
- **Implement agent fails unexpectedly, or Step 5's build command errors out entirely** (crashes or times out, as opposed to running and reporting `FAIL`): Release `{workDocDir}/.progress/.lock` immediately. In multi-entity mode, the single batched agent call stops wherever it was — any document later in the `workDocuments` list than the one it was on when it failed is untouched. Leave `pipeline.status` as `"implementing"` for every affected entity, preserve any `- [x]` scenarios already completed (read from each entity's own work document), and report which entities (if any) finished successfully before the failure. Do not report Step 6 as complete.
- **`plan.json` or the work document is malformed/unreadable**: Stop before Step 3.6 (before the lock is ever acquired) and report the parse error with the file path and reason. Never guess field values to keep going.

## Example: Single-Entity, Non-Plan-Driven Run

Invocation: `/backend-webflux-plugin:be-code employee`

1. **Step 0-1**: Config found. Argument `employee` is a feature name, not a path.
2. **Step 1.5**: No `docs/specs/employee/.implementation/backend/plan.json` exists — `planAvailable = false`.
3. **Step 2**: No `work/features/employee.md` yet. Scan of `src/main/java/com/example/hr/` finds no existing `Employee` entity.
4. **Step 3** (manual flow): Draft scenarios and present for approval:
   ```
   Here are the test scenarios for employee:
   - [ ] valid request returns 201 Created
   - [ ] duplicate email returns 409 Conflict
   - [ ] ? empty display name returns 400 Bad Request

   Please review. I'll remove scenarios marked with `?` unless you confirm them.
   ```
   User confirms all three, including the `?` one. Saved to `work/features/employee.md`.
5. **Step 3.5**: No existing progress file for `employee` — demotion check does not apply.
6. **Step 3.6**: No `.lock` present. Lock acquired: `{"lockedAt": "2026-08-20T09:00:00Z", "operation": "be-code", "feature": "employee"}`.
7. **Step 3.7**: `work/features/.progress/employee.json` created with `pipeline.status = "implementing"`, `scenarios.total = 3`.
8. **Step 4**: Baseline captured (`git status --porcelain` → clean). `implement` agent launched with the work document. One RED-GREEN iteration, summarized:
   - RED: `PostTests.duplicate_email_returns_409_Conflict` written, fails — `DuplicateEmailException` does not exist yet.
   - GREEN: `CreateEmployeeCommandExecutor` checks `EmployeeRepository.existsByEmail`, throws `DuplicateEmailException`; the router's `onErrorResume` maps it to 409. Test passes.
   - Scenario marked `- [x]`. The remaining two scenarios follow the same RED-GREEN pattern.
9. **Step 5**: `./gradlew build` runs, exits 0.
10. **Step 6**: Report, grounded in evidence (`git status --porcelain` against the Step 4 baseline, `git diff --stat`):
    ```
    Feature Implementation Complete: employee
    =======================================

    Scenarios: 3/3
      [x] valid request returns 201 Created
      [x] duplicate email returns 409 Conflict
      [x] empty display name returns 400 Bad Request

    Files created:
      src/main/java/com/example/hr/command/CreateEmployee.java
      src/main/java/com/example/hr/commandmodel/CreateEmployeeCommandExecutor.java
      src/main/java/com/example/hr/hr/DuplicateEmailException.java
      src/test/java/com/example/hr/PostTests.java

    Files modified:
      src/main/java/com/example/hr/config/EmployeeRouterConfig.java

    Build: PASS
    ```
11. **Step 7**: Progress file updated to `pipeline.status = "implemented"`. Lock released. Next step suggested: `/backend-webflux-plugin:be-verify employee`.
