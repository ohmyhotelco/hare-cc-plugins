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

1. Read `.claude/frontend-react-plugin.json` → extract `routerMode`, `appProfile`, `serverState`, `formStack`, `e2eTool`, `mockFirst`, `baseDir`, `appDir`, `prettierTemplate`, `i18n`, `devPort` (default `5173` when absent)
2. If `baseDir` is missing, use default value `"src"`
3. If `mockFirst` is missing, use default value `true`
4. If `appDir` is missing, use default value `"."` (project root)
5. New-stack keys fall back to admin defaults when absent: `appProfile="admin"`, `serverState="zustand-only"`, `formStack="native"`, `e2eTool="agent-browser"`, `prettierTemplate=true`. **`i18n` has no default** — pass it to foundation-generator when present, omit the parameter when absent, and never synthesize a language set from the locale directory (a language present as a folder but absent from `i18n.languages` would otherwise be silently claimed as covered). Pass `routerMode`/`serverState`/`formStack` (and each page's `rendering`) through to every phase agent (foundation-generator, tdd-cycle-runner, integration-generator) so they generate the right variant. `e2eTool` is used later by fe-e2e, not here — but foundation-generator scaffolds the Playwright harness once when `e2eTool="playwright"`.
6. If the file does not exist:
   > "Frontend React Plugin has not been initialized. Please run `/frontend-react-plugin:fe-init` first."
   - Stop here.
7. **Derive `srcPath`** — take the config `baseDir` **after its default is applied** and remove the leading `{appDir}/` (`app/src` + `appDir=app` → `src`; `appDir="."` → unchanged; `appDir == baseDir` → `.`). Every `npx …` path argument uses `srcPath`; the repo-relative source root stays available for file operations. See CLAUDE.md § Build Command Working Directory.

**Empty-store-phase skip.** When `serverState="tanstack-query"`, the planner may emit **no** `stores[]` entry for a feature whose server data lives entirely in the query cache. A phase with no files to generate is skipped: if the plan has no store for the feature (empty `stores[]`), mark `store-tdd` as **`"skipped"`** in generation-state with **`skipKind: "auto"`** and `reason: "no store planned"`, and log "Skipping store-tdd (no client-only store)". Use `"skipped"` — the status vocabulary is `completed` / `failed` / `skipped`, and a `"skip"` value matches no branch in the final-status logic, leaving a valid feature unable to reach `generated`. This is not an error — it is the expected shape under tanstack-query.

### Step 1: Validate Plan

1. Check if `docs/specs/{feature}/.implementation/frontend/plan.json` exists
   - If not found:
     > "Implementation plan not found."
     > "Please run `/frontend-react-plugin:fe-plan {feature}` first."
     - Stop here.

2. Read `plan.json` → extract `summary`, `buildOrder`, `feature`, `localesDir` (the i18n resource directory the generators write into), `baseDir` (as `planBaseDir` — the feature-level directory, e.g., `app/src/features/{feature}`)

3. Read `docs/specs/{feature}/.progress/{feature}.json` → extract `workingLanguage` (default: `"en"`)
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill must be in {workingLanguage_name}.

1. Check UI DSL and prototype availability:
   - `docs/specs/{feature}/ui-dsl/manifest.json` → `uiDslAvailable`
   - `prototypes/{feature}/` → `prototypeAvailable`

2. Check for existing generation state — **but a pending `delta-plan.json` outranks it**: if
   `delta-plan.json` exists, go straight to item 3 (**Delta detection**) regardless of what the
   state file says; handling old state first would route the run into resume/fresh-start and the
   delta would never be seen.
   - If `docs/specs/{feature}/.implementation/frontend/generation-state.json` exists (and no
     pending delta):
     - Read it and check `currentPhase` and phase statuses
     - If `deltaMode` is `true` in the state file: skip resume offer, proceed to item 3 (**Delta detection**), which handles resume
     - Otherwise: offer to resume from the last incomplete phase. A phase with `status: "skipped"`
       and `skipKind: "auto"` counts as **complete** here — it is a planned no-op, not unfinished
       work.

3. **Delta detection** — check if a delta plan exists:
   - If `docs/specs/{feature}/.implementation/frontend/delta-plan.json` exists:
     - Read delta-plan.json → extract `summary`
     > "A delta plan exists ({summary.specChanges.added} added, {summary.specChanges.modified} modified, {summary.specChanges.removed} removed spec changes)."
     > "Options:"
     > "1. Execute delta (regenerate only {summary.affectedFiles.create + summary.affectedFiles.modify + summary.affectedFiles.remove} affected files)"
     > "2. Execute full generation (ignore delta, regenerate everything)"
     > "3. View delta details"
     - If user chooses 1: `genMode = "delta"`, proceed to Lock Acquire — which runs Step 1.9 — then Step 2-D
     - If user chooses 2: `genMode = "full"`, proceed to item 4 (**Demotion warning**)
     - If user chooses 3: display full delta summary, then re-ask 1 or 2
   - If delta-plan.json does not exist: `genMode = "full"`, proceed to item 4 (**Demotion warning**)

4. **Demotion warning** (full mode only) — check `implementation.status` (already read in Step 1.3):
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

Acquire the feature lock `docs/specs/{feature}/.implementation/frontend/.lock` with `holder: "fe-gen"`, per CLAUDE.md § Lock file. **Check the holder's `pid` before treating any lock as stale** — the 30-minute rule sweeps ghost locks, it does not time out a live one. Held by a live holder → report `holder` and `acquiredAt`, then stop.

**Release on every exit below.** Any "stop here" from this point on — a user declining a
confirmation, a validation refusal, an agent that fails — releases this lock first. The lock is
taken before the confirmation prompts, so a refusal that just stops leaves the feature locked and
every later command refusing it (CLAUDE.md § Lock file).

**Then run Step 1.9 (Playwright Harness Preflight) immediately — every mode, before any branch.**
The preflight's own heading says "every mode", but a heading routes nothing: the delta branch jumps
Lock Acquire → Step 2-D and a fresh-start resume jumps to Step 3, and both would sail past it —
after an e2eTool switch, a delta run would then "succeed" with no harness and `fe-e2e` would refuse.
This sentence is the single routing point that makes the heading true.

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

### Step 1.9: Playwright Harness Preflight (every mode)

When `e2eTool == "playwright"`:

**Both files present → validate, don't skip blindly.** Read `playwright.config.ts`'s `webServer`
line and compare against the current config: port ≠ `devPort`, or command family ≠ `routerMode`
(Vite command in a framework project, or vice versa) → **stop** with:
> "playwright.config.ts serves port {baked} via {baked command}; config now says devPort {devPort} /
> routerMode {routerMode}. Align `.claude/frontend-react-plugin.json` or edit playwright.config.ts,
> then re-run."
Scaffolding writes only absent files, so a later config change can never propagate into an existing
config on its own — without this check the runner trusts a port the config stopped naming, and with
`reuseExistingServer` that can silently test an unrelated server. (Stopping, not rewriting: the
config may be user-owned, and clobbering it is worse than asking.)

**Either file absent** (check both — fe-e2e requires both, and the config alone is not proof of a
complete harness) → scaffold now, before any phases:

```
Agent(subagent_type: "foundation-generator", prompt: "
  Scaffold the Playwright harness only.

  Parameters:
  - mode: playwright-harness-only
  - e2eTool: playwright
  - routerMode: {routerMode — Step 5c picks the webServer dev command from the router-mode matrix; omitting this defaults to declarative and bakes a Vite command into a framework project's config}
  - appDir: {appDir}
  - devPort: {devPort — from config, default 5173}
  - projectRoot: {cwd}
  - baseDir: {baseDir}
  - srcPath: {srcPath}
  - localesDir: {localesDir}
")
```

`mode: playwright-harness-only` runs the agent's Step 5c and nothing else — launching it without
the mode would execute a full foundation phase (layouts, types, mocks) outside phase-state
tracking, which is exactly what a delta/resume preflight must not do.

**On return:** require `status: "completed"` and then **glob both files yourself** —
`{appDir}/playwright.config.ts` and `{appDir}/e2e/fixtures.ts`. Either missing (or a failed
status) → stop before any phases with the report's error; continuing would hand `fe-e2e` the exact
"harness not found" refusal this preflight exists to prevent. Nothing is recorded in
generation-state — the harness is app-level, and the files themselves are the state. This runs in
**full, delta, and resume modes alike**: delta delegates its foundation phase to `delta-modifier`
and resume skips completed phases, so without this preflight the fe-init reconfiguration message
("the next fe-gen run scaffolds it") is a promise those two modes silently break — the user follows
the remedy, it "succeeds", and `fe-e2e` still refuses.

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

**Resume, don't reset.** If `generation-state.json` already exists with `deltaMode: true`, this is
the resume of an interrupted delta — item 3 of Step 1 routes here for exactly that case. Preserve
every phase whose `status` is `"completed"` (and its `completedAt`), **and the top-level
`planPatched` flag** — dropping it makes 2-D.3 reapply the plan patch, which duplicates plan
entries, the exact defect the flag exists to prevent. Set only the not-yet-completed
active phases to `"pending"`. Recreating all phases as pending reruns work that already happened —
re-editing source files that were already delta-modified.

Otherwise (fresh delta), create `docs/specs/{feature}/.implementation/frontend/generation-state.json`:

```json
{
  "feature": "{feature}",
  "startedAt": "{ISO timestamp}",
  "deltaMode": true,
  "deltaFile": "docs/specs/{feature}/.implementation/frontend/delta-plan.json",
  "currentPhase": "{first non-skipped phase}",
  "phases": {
    "foundation": { "status": "pending | skipped", "skipKind": "auto", "deltaAction": "{action from phaseExecution}", "completedAt": null },
    "api-tdd": { "status": "pending | skipped", "skipKind": "auto", "deltaAction": "{action}", "completedAt": null },
    "store-tdd": { "status": "pending | skipped", "skipKind": "auto", "deltaAction": "{action}", "completedAt": null },
    "component-tdd": { "status": "pending | skipped", "skipKind": "auto", "deltaAction": "{action}", "completedAt": null },
    "page-tdd": { "status": "pending | skipped", "skipKind": "auto", "deltaAction": "{action}", "completedAt": null },
    "integration": { "status": "pending | skipped", "skipKind": "auto", "deltaAction": "{action}", "completedAt": null }
  }
}
```

Set `status = "skipped"` with `skipKind: "auto"` for phases with `deltaAction = "skip"`, `status = "pending"` for `deltaAction = "partial"`. Use `"skipped"`, not `"skip"` — the status vocabulary is `pending` / `completed` / `failed` / `skipped`, and the final-status logic has no branch for `"skip"`.

#### 2-D.3: Patch plan.json (before execution)

Apply the `planJsonPatch` from delta-plan.json to the existing plan.json **before** executing delta phases. This ensures tdd-cycle-runner and other agents can find plan entries for new files.

0. **Skip if already applied**: if `generation-state.json` has `planPatched: true`, this is a
   resume and the patch already ran — applying additions twice duplicates plan entries. Skip to
   2-D.4 (**Execute Delta Phases**).
1. Read current `plan.json`
2. Apply `planJsonPatch.additions` — add new entries to the respective arrays
3. Apply `planJsonPatch.modifications` — **merge into** the existing entry matched by its section's identity key (planner Phase 3.7: `name` for types/stores/components/**api**, `file` for pages/tests, `id` for e2eTests): overwrite only the fields the patch lists, keep every unlisted field, replace listed arrays wholesale, and do **not** persist the transient `change` field
4. Apply `planJsonPatch.removals` — remove entries from the respective arrays
5. Write the updated plan.json, then set `planPatched: true` in `generation-state.json`

> Note: If delta execution fails later, plan.json still reflects the intended state. This is safe because plan.json describes what *should* exist, not what *does* exist — generation-state.json tracks actual completion.

#### 2-D.4: Execute Delta Phases

For each phase in order (`foundation`, `api-tdd`, `store-tdd`, `component-tdd`, `page-tdd`, `integration`):

**If the phase's `generation-state.json` status is already `"completed"`** (a resume — 2-D.2 (**Initialize Delta Generation State**)
preserved it): log "Skipping {phase} (completed in the interrupted run)" and continue. Without this
check the loop keys on `deltaAction` alone and re-executes edits that already landed, duplicating
fixtures, routes, handlers, and locale entries.

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
  - sourceBaseDir: {baseDir}
  - projectRoot: {cwd}
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - routerMode: {routerMode}
  - mockFirst: {mockFirst}
  - appDir: {appDir}
  - srcPath: {srcPath}

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
  - sourceBaseDir: {baseDir}
  - projectRoot: {cwd}
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - routerMode: {routerMode}
  - mockFirst: {mockFirst}
  - appDir: {appDir}
  - srcPath: {srcPath}

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
  - appDir: {appDir}
  - srcPath: {srcPath}
  - skills: {skills list from buildOrder}
  - deltaMode: true
  - scopedFiles: {list of createFiles file paths}
  - serverState: {serverState}
  - formStack: {formStack}

  Follow the process defined in agents/tdd-cycle-runner.md.
  Read templates/tdd-rules.md for TDD rules.

  IMPORTANT: Only generate stubs, tests, and implementations for the files listed
  in scopedFiles. Do NOT generate files outside this list. Existing files in the
  feature directory are already implemented — import and reference them as-is.
")
```

If `createFiles` is non-empty AND the phase is `integration`:
- Use the integration-generator agent (same as full generation). It already uses targeted Edit for existing aggregator files.

**On completion** — branch on the agent's reported `status` first:
- `"partial"` (some operations escalated) or `"failed"` → this phase is **not** complete. Record it
  as `"failed"` with the escalated operations listed, keep `delta-plan.json` active (do **not**
  archive in 2-D.7 (**Archive Delta**)), skip 2-D.6 (**Update Progress**)'s `generated` write, follow the failure path (2-D.F) instead —
  final status `gen-failed`. Recording a partial phase as completed archives the delta and promotes
  code with unapplied changes into review as `generated`.
- `"completed"` → update generation-state.json for this phase:
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

#### 2-D.6: Update Progress (Delta)

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

**Also remove `implementation.e2e`** in this same write: the delta changed code, so a prior E2E
pass describes an app that no longer exists — preserving it lets a later `done` read as "Pipeline
complete" on stale evidence.

**Merge rule**: preserve all existing fields except `implementation.e2e` (removed above). Only update `status`, `generatedAt`, and add `lastDelta`.

#### 2-D.7: Archive Delta (last)

1. Rename `delta-plan.json` → `delta-plan.{timestamp}.json` (keep for audit)
2. Remove `implementation.deltaFile` and `implementation.deltaDetectedAt` from the progress file

> Archiving runs **after** the progress write on purpose: interrupted between the two, the old
> order left changed code with no active delta to resume and a progress file still claiming the
> pre-delta state — the next `fe-gen` could only offer full generation. Interrupted in the new
> order, the delta is still active and simply re-runs its (now completed, skipped-on-resume)
> phases to reach this point again.

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
    // a phase that is skipped also carries skipKind: "auto" (a planned no-op, does not block)
    // or "user" (the user chose Skip at a failure prompt, blocks -> gen-failed)
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
  - routerMode: {routerMode}
  - serverState: {serverState}
  - formStack: {formStack}
  - e2eTool: {e2eTool}
  - mockFirst: {mockFirst}
  - baseDir: {baseDir}
  - appDir: {appDir}
  - srcPath: {srcPath}
  - projectRoot: {cwd}
  - feature: {feature}
  - prettierTemplate: {prettierTemplate}
  - i18n: {the config's i18n block, or omit the line entirely when absent}
  - localesDir: {localesDir}
  - devPort: {devPort}

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
  - serverState: {serverState}
  - formStack: {formStack}
  - mockFirst: {mockFirst}
  - baseDir: {baseDir}
  - appDir: {appDir}
  - srcPath: {srcPath}
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
  > "2. Skip and continue to next phase (status will be gen-failed — cannot enter review pipeline)"
  > "3. Stop generation (resume later with /frontend-react-plugin:fe-gen {feature})"
- If user chooses Skip: update generation-state.json `{phase}.status = "skipped"` with **`skipKind: "user"`**, continue to next phase

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
  - serverState: {serverState}
  - mockFirst: {mockFirst}
  - baseDir: {baseDir}
  - appDir: {appDir}
  - srcPath: {srcPath}
  - workingLanguage: {workingLanguage}
  - skills: {skills list from buildOrder}
  - localesDir: {localesDir}

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
- Any phase `"skipped"` with **`skipKind: "auto"`** (a planned no-op — no-store-under-tanstack-query, or a delta phase with no changes) → does not block: treat it as completed for status purposes
- Any phase `"failed"`, or `"skipped"` with **`skipKind: "user"`** → `"gen-failed"` (incomplete generation must not enter review pipeline)
- `skipKind` is the discriminator, never the presence of free text: a missing `skipKind` on a `skipped` phase is treated as `"user"` (blocking), because a phase whose skip nobody classified is not a phase anyone confirmed was safe to omit
- Record each phase's actual status (`"completed"`, `"failed"`, `"skipped"`) in `tddPhases`

**Also remove `implementation.e2e`**: regeneration changed the code, so a prior E2E pass is stale
evidence — see 2-D.6 (**Update Progress (Delta)**) for the same rule on the delta path.

**Merge rule**: Read the existing progress file, merge changes into the existing `implementation` object preserving all other fields (e.g., `verification`, `review`, `fix`, `debug` — but not `e2e`, removed above), then write back the complete file.

Update generation-state.json with final status.

### Lock Release

Delete `docs/specs/{feature}/.implementation/frontend/.lock`.

### Resume Support

When Step 1.6 detects an existing `.implementation/frontend/generation-state.json`:

1. Read the state file
2. **All-completed check** — if every phase has `status: "completed"` or `"skipped"` with
   `skipKind: "auto"`:
   - **If `delta-plan.json` exists**: do not start fresh — proceed to Step 1 item 3 (**Delta
     detection**); the pending delta is the reason this run exists.
   - Otherwise:
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
