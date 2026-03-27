---
name: fe-plan
description: "Use when a feature needs an implementation plan before code generation, either from an existing spec or through interactive requirements gathering."
argument-hint: "<feature-name> [--standalone]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Task
---

# Implementation Plan Skill

Analyzes a functional specification (planning-plugin output) or gathers requirements interactively (standalone mode) and produces an implementation plan for production React code.

## Instructions

### Step 0: Read Configuration

1. Read `.claude/frontend-react-plugin.json` → extract `routerMode`, `mockFirst`, `baseDir`, `appDir`
2. If `baseDir` is missing, use default value `"src"`
3. If `mockFirst` is missing, use default value `true`
4. If `appDir` is missing, use default value `"."` (project root)
5. If the file does not exist:
   > "Frontend React Plugin has not been initialized. Please run `/frontend-react-plugin:fe-init` first."
   - Stop here.

### Step 0.5: Detect Mode

1. Check if `--standalone` flag is present in the argument
   - If `--standalone` is present: `mode = "standalone"`, skip to Step 1-S
   - If absent: `mode = "spec"`, proceed to Step 1

2. **Auto-detection** — if `--standalone` is not specified, check if `docs/specs/{feature}/.progress/{feature}.json` exists:
   - If not found:
     > "No planning-plugin specification found for '{feature}'."
     > "Options:"
     > "1. Standalone mode (gather requirements interactively)"
     > "2. Create specification first: `/planning-plugin:spec {feature}`"
     - If user chooses 1: `mode = "standalone"`, skip to Step 1-S
     - If user chooses 2: stop here.
   - If found: `mode = "spec"`, proceed to Step 1

### Step 1: Validate Spec

1. Check if `docs/specs/{feature}/.progress/{feature}.json` exists
   - If not found:
     > "Functional specification not found: `docs/specs/{feature}/`"
     > "Please create the functional specification using planning-plugin first."
     - Stop here.

2. Read the progress file and check `status`:
   - `"reviewing"` or `"finalized"` → proceed
   - If status is `"reviewing"`:
     > "The specification is in 'reviewing' status — unresolved review issues may exist."
     > "For the most accurate plan, finalize first: `/planning-plugin:review {feature}`"
     > "Continue with current spec?"
     - If the user declines, stop here.
   - `"drafting"` or `"analyzing"` →
     > "The functional specification is not yet complete (status: {status})."
     > "Please finish writing the specification, then try again."
     - Stop here.

3. Extract `workingLanguage` from the progress file (default: `"en"`)
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill (summaries, questions, feedback presentations, next-step guidance) must be in {workingLanguage_name}.

### Step 1-S: Standalone Requirements Gathering (standalone mode only)

Gather minimal requirements interactively from the user.

#### 1-S.1: Feature Description
> "Describe '{feature}' in 2-3 sentences. What does this feature do?"

#### 1-S.2: Working Language
> "Working language? (en/ko/vi, default: en)"

#### 1-S.3: Entities
> "List the main data entities (e.g., Hotel, Room, Booking)."
> "For each entity, list key fields (e.g., Hotel: id, name, rating, location)."

#### 1-S.4: Screens
> "List the screens/pages for this feature."
> "Briefly describe what each screen does and which entities it uses."

#### 1-S.5: Confirm & Proceed

Display collected requirements summary and confirm:

```
Standalone Plan for '{feature}':
  Description: {description}
  Entities: {count} ({names})
  Screens: {count} ({names})
  Language: {workingLanguage}

  Note: Standalone mode generates a simplified plan.
  For a complete spec-based plan with validation rules,
  error codes, and test scenarios, use planning-plugin.
```

> "Proceed with standalone plan generation?"
- If the user declines, stop here.

#### 1-S.6: Generate Minimal Spec Files

Create the following directory structure:

```
docs/specs/{feature}/
├── .progress/{feature}.json  ← status: "finalized", standalone: true
├── {workingLanguage}/
│   └── {feature}-spec.md     ← auto-generated from user input
└── .implementation/
    └── frontend/
```

**Progress file**: Include `"standalone": true` flag:
```json
{
  "feature": "{feature}",
  "status": "finalized",
  "standalone": true,
  "workingLanguage": "{workingLanguage}",
  "createdAt": "{ISO timestamp}"
}
```

**Minimal spec**: Auto-generate from user input — include overview section, entity definitions with fields, screen descriptions, and basic CRUD functional requirements per entity.

#### 1-S.7: Continue to Plan Generation

Set `uiDslAvailable = false`, `prototypeAvailable = false`.
Proceed to Step 3 (Launch Planner Agent) — the implementation-planner already handles `uiDslAvailable = false` and `standalone: true` in the progress file.

### Step 2: Check UI DSL

1. Check if `docs/specs/{feature}/ui-dsl/manifest.json` exists
   - exists → `uiDslAvailable = true`
   - not exists → `uiDslAvailable = false`

2. If `uiDslAvailable` is false, display recommendation:
   > "UI DSL is not available. The plan will be generated by inferring from the spec markdown."
   > "For a more accurate plan, running `/planning-plugin:design {feature}` is recommended."

3. Check if `prototypes/{feature}/` exists → `prototypeAvailable`

### Step 2.5: Detect Shared Layout

1. If `uiDslAvailable` is true:
   - Read `docs/specs/{feature}/ui-dsl/manifest.json`
   - Check `layouts` array for entries with `"source": "_shared"`
   - If found: `sharedLayoutIds` = list of layout IDs
2. If `uiDslAvailable` is false:
   - Read `docs/specs/{feature}/{workingLanguage}/screens.md`
   - Check for `<!-- @layout: _shared/` directive
   - If found: extract layout IDs
3. If no shared layout references found: `sharedLayoutIds` = `"none"`

### Step 2.7: Incremental Detection

Check if incremental mode is applicable:

1. Check if `docs/specs/{feature}/.implementation/frontend/plan.json` exists → `existingPlanExists`
2. If `existingPlanExists`:
   - Read `docs/specs/{feature}/.progress/{feature}.json` → extract `implementation.status`
   - If `implementation.status` is one of `generated`, `verified`, `verify-failed`, `reviewed`, `review-failed`, `fixing`, `resolved`, `done`:
     > "An existing implementation plan and generated code exist (status: {status})."
     > "Options:"
     > "1. Incremental update — detect spec changes, regenerate only affected files"
     > "2. Full regeneration — discard all changes, create new plan from scratch"
     - If user chooses 1: `planMode = "incremental"`, proceed to Step 3-I
     - If user chooses 2: `planMode = "full"`, proceed to Step 3
   - If `implementation.status` is `planned`, `gen-failed`, or absent:
     - No generated code to preserve → `planMode = "full"`, proceed to Step 3
3. If not `existingPlanExists`: `planMode = "full"`, proceed to Step 3

### Step 3-I: Launch Planner Agent (Incremental Mode)

Only executed when `planMode = "incremental"`.

Launch the implementation-planner agent in incremental mode:

```
Task(subagent_type: "implementation-planner", prompt: "
  Analyze spec changes for '{feature}' and produce a delta plan.

  Parameters:
  - feature: {feature}
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - uiDslDir: docs/specs/{feature}/ui-dsl/ (available: {uiDslAvailable})
  - prototypeDir: prototypes/{feature}/ (available: {prototypeAvailable})
  - routerMode: {routerMode}
  - mockFirst: {mockFirst}
  - sharedLayoutIds: [{sharedLayoutIds or "none"}]
  - projectRoot: {cwd}
  - baseDir: {baseDir}
  - incrementalMode: true
  - existingPlanFile: docs/specs/{feature}/.implementation/frontend/plan.json
  - deltaOutputFile: docs/specs/{feature}/.implementation/frontend/delta-plan.json
  - outputFile: docs/specs/{feature}/.implementation/frontend/plan.json

  Follow the process defined in agents/implementation-planner.md.
  Execute Phase 3 (Incremental Mode) instead of Phase 2.
  Write the delta plan to the deltaOutputFile path.
")
```

### Step 4-I: Display Delta Summary & Confirm

Only executed when `planMode = "incremental"`.

1. Read the generated `docs/specs/{feature}/.implementation/frontend/delta-plan.json`
2. Display the delta summary (as defined in the agent's Delta User Summary Template)

3. If `largeDeltaWarning` is `true`:
   > "Warning: This delta affects more than 60% of implementation files."
   > "Full regeneration may be more reliable and produce more consistent code."
   > "Options:"
   > "1. Proceed with delta (incremental update)"
   > "2. Switch to full regeneration"
   - If user chooses 2: discard delta-plan.json, set `planMode = "full"`, go to Step 3

4. If no spec changes detected (`specChanges.added`, `modified`, and `removed` are all empty):
   > "No spec changes detected. The current plan is up to date."
   - Stop here.

5. Confirm:
   > "Proceed with incremental plan? Run `/frontend-react-plugin:fe-gen {feature}` to apply the delta."

6. Skip to Step 5-I.

### Step 3: Launch Planner Agent

Create the output directory if it doesn't exist:

**Migration check** (backward compatibility):
1. If `docs/specs/{feature}/.implementation/plan.json` exists (old path) AND `docs/specs/{feature}/.implementation/frontend/` does NOT exist:
   - Move all files from `.implementation/` to `.implementation/frontend/` (excluding subdirectories that are already namespaces)
   - Update embedded paths in progress file if present
   - Display: "Migrated .implementation/ → .implementation/frontend/"
2. Otherwise: create `docs/specs/{feature}/.implementation/frontend/` if it doesn't exist

```
docs/specs/{feature}/.implementation/frontend/
```

Launch the implementation-planner agent:

```
Task(subagent_type: "implementation-planner", prompt: "
  Analyze the functional specification for '{feature}' and produce an implementation plan.

  Parameters:
  - feature: {feature}
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - uiDslDir: docs/specs/{feature}/ui-dsl/ (available: {uiDslAvailable})
  - prototypeDir: prototypes/{feature}/ (available: {prototypeAvailable})
  - routerMode: {routerMode}
  - mockFirst: {mockFirst}
  - sharedLayoutIds: [{sharedLayoutIds or "none"}]
  - projectRoot: {cwd}
  - baseDir: {baseDir}
  - appDir: {appDir}
  - outputFile: docs/specs/{feature}/.implementation/frontend/plan.json

  Follow the process defined in agents/implementation-planner.md.
  Write the implementation plan to the outputFile path.
")
```

### Step 4: Display Summary

1. Read the generated `docs/specs/{feature}/.implementation/frontend/plan.json`
2. Display the summary:

```
Implementation Plan for '{feature}':

  Source: docs/specs/{feature}/ (status: {specStatus}, UI DSL: {available/not available})
  Target: {baseDir}/ ({projectStructure} layout)
  Router: {routerMode} mode

  Files to create ({totalFiles}):
    Shared layouts: {layout names} ({new/existing})
    Types:       {type names} ({count} files)
    API:         {api names} — {endpoint count} endpoints ({count} files)
    Stores:      {store names} ({count} files)
    Components:  {component names} ({count} files)
    Pages:       {page descriptions} ({count} files)
    Routes:      {entry count} entries under {parentRoute}
    i18n:        {namespace} namespace ({language count} languages)
    Mocks:       {fixture count} fixtures, {handler count} handler sets (MSW v2)

  shadcn/ui: {missing count} components need installation ({missing list})

  Build order: shared-layouts → types → api/stores → mocks → components → pages → routes/i18n/msw-setup

  Plan saved to: docs/specs/{feature}/.implementation/frontend/plan.json
  Review and edit the plan, then run /frontend-react-plugin:fe-gen {feature}
```

### Step 5: Update Progress

1. Read `docs/specs/{feature}/.progress/{feature}.json`
2. Add or update the `implementation` field:

```json
{
  "implementation": {
    "status": "planned",
    "planFile": "docs/specs/{feature}/.implementation/frontend/plan.json"
  }
}
```

3. Write the updated progress file back. **Merge rule**: preserve all existing fields in the progress file — only add or update the `implementation` fields shown above.

### Step 5-I: Update Progress (Incremental Mode)

Only executed when `planMode = "incremental"`.

1. Read `docs/specs/{feature}/.progress/{feature}.json`
2. Add or update the `implementation` field — preserve the existing status (do NOT reset to `"planned"`):

```json
{
  "implementation": {
    "deltaFile": "docs/specs/{feature}/.implementation/frontend/delta-plan.json",
    "deltaDetectedAt": "{ISO timestamp}"
  }
}
```

3. Write the updated progress file back. **Merge rule**: preserve ALL existing fields in the progress file (including `status`, `planFile`, `tddPhases`, `generatedAt`, `verification`, `review`, `fix`, `debug`) — only add the `deltaFile` and `deltaDetectedAt` fields.
