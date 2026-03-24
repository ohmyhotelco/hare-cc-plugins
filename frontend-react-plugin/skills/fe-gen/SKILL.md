---
name: fe-gen
description: "Generate production React code from an implementation plan using TDD. Run /frontend-react-plugin:fe-plan first."
argument-hint: "<feature-name>"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Code Generation Skill (TDD Coordinator)

Generates production React code based on the implementation plan (plan.json) using strict Test-Driven Development. Each phase runs in a separate agent session for context isolation.

> **Tool choice**: This skill uses `Agent` (not `Task`) to launch sub-agents. TDD phases are strictly sequential — each depends on the previous phase's output — so `Agent` is used for synchronous execution with immediate result inspection.

## Instructions

### Step 0: Read Configuration

1. Read `.claude/frontend-react-plugin.json` → extract `routerMode`, `mockFirst`, `baseDir`
2. If `baseDir` is missing, use default value `"src"`
3. If `mockFirst` is missing, use default value `true`
4. If the file does not exist:
   > "Frontend React Plugin has not been initialized. Please run `/frontend-react-plugin:fe-init` first."
   - Stop here.

### Step 1: Validate Plan

1. Check if `docs/specs/{feature}/.implementation/frontend/plan.json` exists
   - If not found:
     > "Implementation plan not found."
     > "Please run `/frontend-react-plugin:fe-plan {feature}` first."
     - Stop here.

2. Read `plan.json` → extract `summary`, `buildOrder`, `feature`, `baseDir` (as `planBaseDir` — the feature-level directory, e.g., `app/src/features/{feature}`)

3. Read `docs/specs/{feature}/.progress/{feature}.json` → extract `workingLanguage` (default: `"en"`)
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill must be in {workingLanguage_name}.

5. Check UI DSL and prototype availability:
   - `docs/specs/{feature}/ui-dsl/manifest.json` → `uiDslAvailable`
   - `prototypes/{feature}/` → `prototypeAvailable`

6. Check for existing generation state:
   - If `docs/specs/{feature}/.implementation/frontend/generation-state.json` exists:
     - Read it and check `currentPhase` and phase statuses
     - If `deltaMode` is `true` in the state file: skip resume offer, proceed to step 7 (delta detection will handle resume)
     - Otherwise: offer to resume from the last incomplete phase

7. **Delta detection** — check if a delta plan exists:
   - If `docs/specs/{feature}/.implementation/frontend/delta-plan.json` exists:
     - Read delta-plan.json → extract `summary`
     > "A delta plan exists ({summary.specChanges.added} added, {summary.specChanges.modified} modified, {summary.specChanges.removed} removed spec changes)."
     > "Options:"
     > "1. Execute delta (regenerate only {summary.affectedFiles.create + summary.affectedFiles.modify + summary.affectedFiles.remove} affected files)"
     > "2. Execute full generation (ignore delta, regenerate everything)"
     > "3. View delta details"
     - If user chooses 1: `genMode = "delta"`, proceed to Lock Acquire then Step 2-D
     - If user chooses 2: `genMode = "full"`, proceed to step 8 (demotion warning)
     - If user chooses 3: display full delta summary, then re-ask 1 or 2
   - If delta-plan.json does not exist: `genMode = "full"`, proceed to step 8

8. **Demotion warning** (full mode only) — check `implementation.status` (already read in Step 1.3):
   - Skip this step if `genMode = "delta"` (delta does not reset the full pipeline)
   - If status is `verified`, `reviewed`, or `done`:
     > "This feature is currently '{status}'. Re-generating will reset the pipeline status to 'generated', discarding verification/review progress."
     > "Continue with code generation?"
     - If the user declines, stop here.
   - If status is `fixing`:
     > "This feature is currently 'fixing' (fe-fix in progress or regen-required re-run)."
     > "Re-generating will overwrite any fe-fix changes in re-run phases."
     > "Continue with code generation?"
     - If the user declines, stop here.
   - All other statuses (`generated`, `gen-failed`, `planned`, `verify-failed`, `review-failed`, `resolved`, `escalated`) → no warning, proceed normally.

### Lock Acquire

Check `docs/specs/{feature}/.implementation/frontend/.lock`:
- If file exists:
  - Read `lockedAt` and `operation`
  - If more than 30 minutes have elapsed since `lockedAt` → stale lock, delete and proceed
  - Otherwise:
    > "Another operation is in progress: '{operation}' (started: {lockedAt})"
    - Stop here.
- Create lock file:
  ```json
  { "lockedAt": "{ISO timestamp}", "operation": "fe-gen" }
  ```

### Step 2: Confirm with User

Display the plan summary with TDD phase breakdown:

```
Code Generation for '{feature}' (TDD mode):

  Plan: docs/specs/{feature}/.implementation/frontend/plan.json
  Target: {baseDir}/

  TDD Phases:
    1. Foundation     — Types ({typeCount}), Mocks ({mockFileCount})
    2. API TDD        — {apiTestCount} tests → {apiFileCount} services
    3. Store TDD      — {storeTestCount} tests → {storeFileCount} stores
    4. Component TDD  — {componentTestCount} tests → {componentFileCount} components
    5. Page TDD       — {pageTestCount} tests → {pageFileCount} pages
    6. Integration    — Routes, i18n, MSW setup

  Total: {totalFiles} files, {totalTestCases} test cases
  shadcn/ui to install: {missing list or "none"}
```

Check for existing files that would be overwritten. Warn if any exist.

Ask:
> "Proceed with code generation?"

If the user declines, stop here.

### Step 2-D: Delta Execution (when `genMode = "delta"`)

Only executed when `genMode = "delta"`. This replaces Steps 2-8 for delta mode.

#### 2-D.1: Confirm Delta

Display the delta execution plan:

```
Delta Generation for '{feature}':

  Delta: docs/specs/{feature}/.implementation/frontend/delta-plan.json
  Target: {planBaseDir}/

  Phases:
    {For each phase in phaseExecution:}
    {phaseNum}. {phaseName} — {action} {if partial: "({fileCount} files: {create} create, {modify} modify, {remove} remove)"}
    {end for}

  Total: {createCount} files to create, {modifyCount} files to modify, {removeCount} removals
```

Ask:
> "Proceed with delta generation?"

If the user declines, stop here.

#### 2-D.2: Initialize Delta Generation State

Create or update `docs/specs/{feature}/.implementation/frontend/generation-state.json`:

```json
{
  "feature": "{feature}",
  "startedAt": "{ISO timestamp}",
  "deltaMode": true,
  "deltaFile": "docs/specs/{feature}/.implementation/frontend/delta-plan.json",
  "currentPhase": "{first non-skipped phase}",
  "phases": {
    "foundation": { "status": "pending | skip", "deltaAction": "{action from phaseExecution}", "completedAt": null },
    "api-tdd": { "status": "pending | skip", "deltaAction": "{action}", "completedAt": null },
    "store-tdd": { "status": "pending | skip", "deltaAction": "{action}", "completedAt": null },
    "component-tdd": { "status": "pending | skip", "deltaAction": "{action}", "completedAt": null },
    "page-tdd": { "status": "pending | skip", "deltaAction": "{action}", "completedAt": null },
    "integration": { "status": "pending | skip", "deltaAction": "{action}", "completedAt": null }
  }
}
```

Set `status = "skip"` for phases with `deltaAction = "skip"`, `status = "pending"` for `deltaAction = "partial"`.

#### 2-D.3: Patch plan.json (before execution)

Apply the `planJsonPatch` from delta-plan.json to the existing plan.json **before** executing delta phases. This ensures tdd-cycle-runner and other agents can find plan entries for new files.

1. Read current `plan.json`
2. Apply `planJsonPatch.additions` — add new entries to the respective arrays
3. Apply `planJsonPatch.modifications` — update existing entries
4. Apply `planJsonPatch.removals` — remove entries from the respective arrays
5. Write the updated plan.json

> Note: If delta execution fails later, plan.json still reflects the intended state. This is safe because plan.json describes what *should* exist, not what *does* exist — generation-state.json tracks actual completion.

#### 2-D.4: Execute Delta Phases

For each phase in order (`foundation`, `api-tdd`, `store-tdd`, `component-tdd`, `page-tdd`, `integration`):

**If `deltaAction = "skip"`**: Log "Skipping {phase} (no changes)" and continue to next phase.

**If `deltaAction = "partial"`**:

Separate the phase's files into two groups:
- `createFiles` — entries from `affectedFiles.create` for this phase
- `modifyRemoveFiles` — entries from `affectedFiles.modify` and `affectedFiles.remove` for this phase

**Special case — foundation phase**: Do NOT split into Part A / Part B. Call delta-modifier once for the entire phase. The delta-modifier's Step 0.5 handles `create` operations alongside modify/remove, avoiding double processing.

**For `foundation` phase** (all operations in a single call):

```
Agent(subagent_type: "delta-modifier", prompt: "
  Apply delta modifications for '{feature}' phase 'foundation'.

  Parameters:
  - deltaFile: docs/specs/{feature}/.implementation/frontend/delta-plan.json
  - planFile: docs/specs/{feature}/.implementation/frontend/plan.json
  - feature: {feature}
  - phase: foundation
  - baseDir: {planBaseDir}/
  - projectRoot: {cwd}
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - routerMode: {routerMode}
  - mockFirst: {mockFirst}

  Follow the process defined in agents/delta-modifier.md.
  Read templates/tdd-rules.md for TDD rules.
")
```

**On completion**: Record results from delta-modifier report.

**On failure**: Ask user whether to retry or stop. If stop → go to **Step 2-D.F** (failure path).

**For all other phases** — split into Part A (modify/remove) and Part B (create):

**Part A: Modifications and removals (delta-modifier agent)**

If `modifyRemoveFiles` is non-empty:

```
Agent(subagent_type: "delta-modifier", prompt: "
  Apply delta modifications for '{feature}' phase '{phase}'.

  Parameters:
  - deltaFile: docs/specs/{feature}/.implementation/frontend/delta-plan.json
  - planFile: docs/specs/{feature}/.implementation/frontend/plan.json
  - feature: {feature}
  - phase: {phase}
  - baseDir: {planBaseDir}/
  - projectRoot: {cwd}
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - routerMode: {routerMode}
  - mockFirst: {mockFirst}

  Follow the process defined in agents/delta-modifier.md.
  Read templates/tdd-rules.md for TDD rules.
")
```

> Note: `{planBaseDir}` is the feature-level directory from plan.json (e.g., `app/src/features/{feature}`), NOT the config-level `{baseDir}` (e.g., `app/src`).

**On completion**: Record results from delta-modifier report.

**On failure**: Ask user whether to retry or stop. If stop → go to **Step 2-D.F** (failure path).

**Part B: New file creation (TDD phases only)**

If `createFiles` is non-empty AND the phase is a TDD phase (`api-tdd`, `store-tdd`, `component-tdd`, `page-tdd`):

```
Agent(subagent_type: "tdd-cycle-runner", prompt: "
  Execute TDD cycle for '{feature}' phase '{phase}'.

  Parameters:
  - planFile: docs/specs/{feature}/.implementation/frontend/plan.json
  - feature: {feature}
  - phase: {phase}
  - projectRoot: {cwd}
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - uiDslDir: docs/specs/{feature}/ui-dsl/ (available: {uiDslAvailable})
  - prototypeDir: prototypes/{feature}/ (available: {prototypeAvailable})
  - routerMode: {routerMode}
  - mockFirst: {mockFirst}
  - baseDir: {baseDir}
  - skills: {skills list from buildOrder}
  - deltaMode: true
  - scopedFiles: {list of createFiles file paths}

  Follow the process defined in agents/tdd-cycle-runner.md.
  Read templates/tdd-rules.md for TDD rules.

  IMPORTANT: Only generate stubs, tests, and implementations for the files listed
  in scopedFiles. Do NOT generate files outside this list. Existing files in the
  feature directory are already implemented — import and reference them as-is.
")
```

If `createFiles` is non-empty AND the phase is `integration`:
- Use the integration-generator agent (same as full generation). It already uses targeted Edit for existing aggregator files.

**On completion**: Update generation-state.json for this phase:
```json
{
  "{phase}": {
    "status": "completed",
    "deltaAction": "partial",
    "completedAt": "{ISO timestamp}",
    "filesCreated": {count},
    "filesModified": {count},
    "filesRemoved": {count}
  }
}
```

**On failure**: Ask user whether to retry or stop. If stop → go to **Step 2-D.F** (failure path).

#### 2-D.F: Failure Path (delta execution stopped)

When a phase fails and the user chooses to stop:

1. Update generation-state.json: set failed phase `status = "failed"`, remaining phases stay `"pending"`
2. Update progress file:
   ```json
   {
     "implementation": {
       "status": "gen-failed",
       "lastDelta": {
         "timestamp": "{ISO timestamp}",
         "status": "failed",
         "failedPhase": "{phase}",
         "specChanges": { "added": N, "modified": N, "removed": N }
       }
     }
   }
   ```
   **Merge rule**: preserve all existing fields. Only update `status` and add/update `lastDelta`.
3. Delete lock file (`docs/specs/{feature}/.implementation/frontend/.lock`)
4. Display:
   > "Delta generation failed at {phase}."
   > "Options:"
   > "1. Resume: `/frontend-react-plugin:fe-gen {feature}` (will detect delta and resume)"
   > "2. Debug: `/frontend-react-plugin:fe-debug {feature}`"
   > "3. Full regeneration: `/frontend-react-plugin:fe-gen {feature}` (choose option 2 when prompted)"
5. Stop here.

#### 2-D.5: Post-Delta Summary

Display comprehensive results:

```
Delta Generation Complete for '{feature}':

  Delta Results:
    {For each phase:}
    {phaseName}: {status} — {filesCreated} created, {filesModified} modified, {filesRemoved} removed
    {end for}

  Verification:
    TypeScript: {pass/fail}
    Vitest:     {pass/fail} ({testsPassed}/{testsTotal})
    Build:      {pass/fail}

  Files changed: {totalChanged}
    Created: {list of created files}
    Modified: {list of modified files}
    Removed: {list of removed code blocks}
```

#### 2-D.6: Archive Delta

1. Rename `delta-plan.json` → `delta-plan.{timestamp}.json` (keep for audit)
2. Remove `implementation.deltaFile` and `implementation.deltaDetectedAt` from the progress file

#### 2-D.7: Update Progress (Delta)

Read `docs/specs/{feature}/.progress/{feature}.json` and update:

```json
{
  "implementation": {
    "status": "generated",
    "generatedAt": "{ISO timestamp}",
    "lastDelta": {
      "timestamp": "{ISO timestamp}",
      "specChanges": { "added": 1, "modified": 1, "removed": 1 },
      "filesChanged": { "created": 2, "modified": 6, "removed": 2 }
    }
  }
}
```

**Merge rule**: preserve all existing fields. Only update `status`, `generatedAt`, and add `lastDelta`.

#### 2-D.8: Next Steps

> "Delta generation complete. Recommended next steps:"
> "1. Verify: `/frontend-react-plugin:fe-verify {feature}`"
> "2. Review: `/frontend-react-plugin:fe-review {feature}`"

Skip to Lock Release (do not execute Steps 3-8).

### Step 3: Initialize Generation State

Create `docs/specs/{feature}/.implementation/frontend/generation-state.json`:

```json
{
  "feature": "{feature}",
  "startedAt": "{ISO timestamp}",
  "currentPhase": "foundation",
  "phases": {
    "foundation": { "status": "pending", "completedAt": null },
    "api-tdd": { "status": "pending", "completedAt": null },
    "store-tdd": { "status": "pending", "completedAt": null },
    "component-tdd": { "status": "pending", "completedAt": null },
    "page-tdd": { "status": "pending", "completedAt": null },
    "integration": { "status": "pending", "completedAt": null }
  }
}
```

### Step 4: Execute TDD Phases

Execute each phase sequentially. After each phase, update generation-state.json and display progress.

#### Phase 1: Foundation

Launch the foundation-generator agent:

```
Agent(subagent_type: "foundation-generator", prompt: "
  Generate test infrastructure for '{feature}'.

  Parameters:
  - planFile: docs/specs/{feature}/.implementation/frontend/plan.json
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - uiDslDir: docs/specs/{feature}/ui-dsl/ (available: {uiDslAvailable})
  - prototypeDir: prototypes/{feature}/ (available: {prototypeAvailable})
  - mockFirst: {mockFirst}
  - baseDir: {baseDir}
  - projectRoot: {cwd}
  - feature: {feature}

  Follow the process defined in agents/foundation-generator.md.
")
```

**On completion:**
- Update generation-state.json: `foundation.status = "completed"`, `foundation.completedAt = "{ISO timestamp}"`
- Display: files created, tsc verification result

**On failure:**
- Update generation-state.json:
  ```json
  {
    "foundation": {
      "status": "failed",
      "error": "{error message or summary}",
      "failedAt": "{ISO timestamp}"
    }
  }
  ```
- Ask user whether to retry or stop

#### Phase 2-5: TDD Cycles

For each TDD phase in order (`api-tdd`, `store-tdd`, `component-tdd`, `page-tdd`):

**Skip if** plan has no matching tests or implementation entries for this phase.

Get the `skills` list from the corresponding `buildOrder` entry.

Launch the tdd-cycle-runner agent:

```
Agent(subagent_type: "tdd-cycle-runner", prompt: "
  Execute TDD cycle for '{feature}' phase '{phase}'.

  Parameters:
  - planFile: docs/specs/{feature}/.implementation/frontend/plan.json
  - feature: {feature}
  - phase: {phase}
  - projectRoot: {cwd}
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - uiDslDir: docs/specs/{feature}/ui-dsl/ (available: {uiDslAvailable})
  - prototypeDir: prototypes/{feature}/ (available: {prototypeAvailable})
  - routerMode: {routerMode}
  - mockFirst: {mockFirst}
  - baseDir: {baseDir}
  - skills: {skills list from buildOrder}

  Follow the process defined in agents/tdd-cycle-runner.md.
  Read templates/tdd-rules.md for TDD rules.
")
```

**On completion:**
- Update generation-state.json:
  ```json
  {
    "{phase}": {
      "status": "completed",
      "completedAt": "{ISO timestamp}",
      "red": { "verifyResult": "fail", "failureCount": N },
      "green": { "verifyResult": "pass", "testsPassed": N, "testsTotal": N }
    }
  }
  ```
- Display phase summary:
  ```
  Phase {N}: {phase} — Complete
    RED:   {failureCount} tests failed (expected)
    GREEN: {testsPassed}/{testsTotal} tests passed
    Files: {file list}
  ```

**On failure:**
- Update generation-state.json:
  ```json
  {
    "{phase}": {
      "status": "failed",
      "error": "{error message or summary}",
      "failedAt": "{ISO timestamp}"
    }
  }
  ```
- Display error details
- Ask user:
  > "Phase {phase} failed. Options:"
  > "1. Retry this phase"
  > "2. Skip and continue to next phase"
  > "3. Stop generation (resume later with /frontend-react-plugin:fe-gen {feature})"
- If user chooses Skip: update generation-state.json `{phase}.status = "skipped"`, continue to next phase

#### Phase 6: Integration

Launch the integration-generator agent:

```
Agent(subagent_type: "integration-generator", prompt: "
  Generate integration layer for '{feature}'.

  Parameters:
  - planFile: docs/specs/{feature}/.implementation/frontend/plan.json
  - feature: {feature}
  - projectRoot: {cwd}
  - routerMode: {routerMode}
  - mockFirst: {mockFirst}
  - baseDir: {baseDir}
  - workingLanguage: {workingLanguage}
  - skills: {skills list from buildOrder}

  Follow the process defined in agents/integration-generator.md.
")
```

**On completion:**
- Update generation-state.json: `integration.status = "completed"`, `integration.completedAt = "{ISO timestamp}"`
- Record verification results

**On failure:**
- Update: `integration.status = "failed"`

### Step 5: Post-Generation Summary

Display comprehensive results:

```
Code Generation Complete for '{feature}' (TDD mode):

  TDD Results:
    Foundation:     {status} — {typeCount} types, {mockCount} mock files
    API TDD:        {status} — {testsPassed}/{testsTotal} tests
    Store TDD:      {status} — {testsPassed}/{testsTotal} tests
    Component TDD:  {status} — {testsPassed}/{testsTotal} tests
    Page TDD:       {status} — {testsPassed}/{testsTotal} tests
    Integration:    {status}

  Files created: {totalFiles}
    {file list grouped by category}

  Verification:
    TypeScript: {pass/fail}
    ESLint:     {pass/fail/skipped}
    Vitest:     {pass/fail} ({totalTestsPassed}/{totalTestsTotal})
    Build:      {pass/fail}

  Integration:
    Routes: {featureFile} → {centralFile} ({auto/manual})
    i18n:   {featureFile} → {centralFile} ({auto/manual})
```

### Step 6: Next Steps

> "Code generation complete. Recommended next steps:"
> "1. Verify: `/frontend-react-plugin:fe-verify {feature}`"
> "2. Review: `/frontend-react-plugin:fe-review {feature}`"
> "3. Fix issues (if any): `/frontend-react-plugin:fe-fix {feature}`"

### Step 7: Mock-first Guidance (if `mockFirst` is `true`)

```
  Mock-first development:
    Start with mocks: VITE_ENABLE_MOCKS=true pnpm dev
    Start without mocks: pnpm dev
    Commit: public/mockServiceWorker.js (recommended)
```

### Step 8: Update Progress

Read `docs/specs/{feature}/.progress/{feature}.json` and update the `implementation` field:

```json
{
  "implementation": {
    "status": "generated | gen-failed",
    "mode": "tdd",
    "planFile": "docs/specs/{feature}/.implementation/frontend/plan.json",
    "generatedAt": "{ISO timestamp}",
    "filesCount": {totalFiles},
    "tddPhases": {
      "foundation": "completed",
      "api-tdd": "completed",
      "store-tdd": "completed",
      "component-tdd": "completed",
      "page-tdd": "completed",
      "integration": "completed"
    }
  }
}
```

**Status determination logic** — set `implementation.status` based on phase outcomes:
- All phases `"completed"` → `"generated"`
- Any phase `"failed"` AND user chose **Stop** → `"gen-failed"`
- Any phase `"failed"` or `"skipped"` AND user chose **Skip** to continue → `"gen-failed"` (incomplete generation must not enter review pipeline)
- Record each phase's actual status (`"completed"`, `"failed"`, `"skipped"`) in `tddPhases`

**Merge rule**: Read the existing progress file, merge changes into the existing `implementation` object preserving all other fields (e.g., `verification`, `review`, `fix`, `debug`), then write back the complete file.

Update generation-state.json with final status.

### Lock Release

Delete `docs/specs/{feature}/.implementation/frontend/.lock`.

### Resume Support

When Step 1.6 detects an existing `.implementation/frontend/generation-state.json`:

1. Read the state file
2. **All-completed check** — if every phase in the state file has `status: "completed"`:
   > "Previous generation completed successfully. Re-running will start fresh."
   - Delete generation-state.json and proceed to Step 3 (fresh start).
3. **Plan freshness check** — compare `.implementation/frontend/plan.json` modification time against phase-level `completedAt` timestamps:
   - Get plan.json mtime (use `stat` or file system check)
   - For each completed phase (in order), compare plan.json mtime against `completedAt`:
     - If plan.json was modified after a specific phase's `completedAt`:
       > "plan.json has been modified after '{phase}' was completed."
       > "Options:"
       > "1. Continue from the next incomplete phase"
       > "2. Re-run from '{phase}' onward"
       > "3. Restart generation from scratch"
       - Option 1: continue from next incomplete phase as-is
       - Option 2: reset the affected phase and all subsequent phases to `"pending"` (clear `completedAt`), resume from that phase
       - Option 3: delete generation-state.json and proceed to Step 3 (fresh start)
   - If plan.json mtime is older than all completed phases' `completedAt` (or no `completedAt` recorded — legacy state):
     - Fall back to `startedAt` comparison: if plan.json is newer than `startedAt`:
       > "Warning: plan.json has been modified since generation started ({startedAt})."
       > "Resuming may create inconsistencies between already-generated and new code."
       > "Options: 1. Continue anyway  2. Restart generation from scratch"
       - If user chooses restart: delete generation-state.json and proceed to Step 3 (fresh start)
4. Find the first phase with `status` not `"completed"`
5. Display:
   ```
   Resuming code generation for '{feature}':
     Completed: {list of completed phases}
     Resuming from: {phase name}
   ```
6. Ask user to confirm resume
7. Continue from the incomplete phase (skip completed phases)
