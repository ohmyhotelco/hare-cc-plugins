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

2. Read `plan.json` → extract `summary`, `buildOrder`, `feature`

3. Read `docs/specs/{feature}/.progress/{feature}.json` → extract `workingLanguage` (default: `"en"`)
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill must be in {workingLanguage_name}.

5. Check UI DSL and prototype availability:
   - `docs/specs/{feature}/ui-dsl/manifest.json` → `uiDslAvailable`
   - `prototypes/{feature}/` → `prototypeAvailable`

6. Check for existing generation state:
   - If `docs/specs/{feature}/.implementation/frontend/generation-state.json` exists:
     - Read it and check `currentPhase` and phase statuses
     - Offer to resume from the last incomplete phase

7. **Demotion warning** — check `implementation.status` (already read in Step 1.3):
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

### Step 3: Initialize Generation State

Create `docs/specs/{feature}/.implementation/frontend/generation-state.json`:

```json
{
  "feature": "{feature}",
  "startedAt": "{ISO timestamp}",
  "currentPhase": "foundation",
  "phases": {
    "foundation": { "status": "pending" },
    "api-tdd": { "status": "pending" },
    "store-tdd": { "status": "pending" },
    "component-tdd": { "status": "pending" },
    "page-tdd": { "status": "pending" },
    "integration": { "status": "pending" }
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
- Update generation-state.json: `foundation.status = "completed"`
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
- Update generation-state.json: `integration.status = "completed"`
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

### Resume Support

When Step 1.6 detects an existing `.implementation/frontend/generation-state.json`:

1. Read the state file
2. **All-completed check** — if every phase in the state file has `status: "completed"`:
   > "Previous generation completed successfully. Re-running will start fresh."
   - Delete generation-state.json and proceed to Step 3 (fresh start).
3. **Plan freshness check** — compare `.implementation/frontend/plan.json` modification time against `.implementation/frontend/generation-state.json` `startedAt`:
   - Read `startedAt` from generation-state.json
   - Check if `.implementation/frontend/plan.json` was modified after `startedAt` (use `stat` or file system check)
   - If plan.json is newer than startedAt:
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
