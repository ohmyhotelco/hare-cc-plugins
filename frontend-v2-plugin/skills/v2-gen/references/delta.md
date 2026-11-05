# v2-gen: Delta execution

Part of the `v2-gen` skill. `{pluginRoot}` is the plugin root the skill states.

### Step 2-D: Delta Execution (when `genMode = "delta"`)

Only executed when `genMode = "delta"`. This replaces Steps 2-8 for delta mode.

#### 2-D.1: Confirm Delta

Display the delta execution plan:

```
Delta Generation for '{feature}':

  Delta: {runsDir}/{feature}/delta-plan.json
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

Otherwise (fresh delta), create `{runsDir}/{feature}/generation-state.json`:

```json
{
  "feature": "{feature}",
  "startedAt": "{ISO timestamp}",
  "deltaMode": true,
  "deltaFile": "{runsDir}/{feature}/delta-plan.json",
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
Agent(subagent_type: "frontend-v2-plugin:delta-modifier", prompt: "
  Apply delta modifications for '{feature}' phase 'foundation'.

  Parameters:
  - deltaFile: {runsDir}/{feature}/delta-plan.json
  - planFile: {runsDir}/{feature}/plan.json
  - feature: {feature}
  - phase: foundation
  - baseDir: {planBaseDir}/
  - sourceBaseDir: {baseDir}
  - projectRoot: {cwd}
  - specDir: {specRoot}/{workingLanguage}/
  - routerMode: {routerMode}
  - serverState: {serverState}
  - formStack: {formStack}
  - componentLibrary: {componentLibrary}
  - externalComponents: {the config object, or omit the line when absent}
  - apiLayer: {apiLayer}
  - apiPackage: {the config object, or omit the line when absent}
  - i18nBinding: {i18nBinding}
  - i18nHook: {the config object, or omit the line when absent}
  - clientStore: {clientStore}
  - mockFirst: {mockFirst}
  - appDir: {appDir}
  - srcPath: {srcPath}

  Follow the process defined in agents/delta-modifier.md.
  Read {pluginRoot}/templates/tdd-rules.md for TDD rules.
")
```

**On completion**: Record results from delta-modifier report.

**On failure**: Ask user whether to retry or stop. If stop → go to **Step 2-D.F** (failure path).

**For all other phases** — split into Part A (modify/remove) and Part B (create):

**Part A: Modifications and removals (delta-modifier agent)**

If `modifyRemoveFiles` is non-empty:

```
Agent(subagent_type: "frontend-v2-plugin:delta-modifier", prompt: "
  Apply delta modifications for '{feature}' phase '{phase}'.

  Parameters:
  - deltaFile: {runsDir}/{feature}/delta-plan.json
  - planFile: {runsDir}/{feature}/plan.json
  - feature: {feature}
  - phase: {phase}
  - baseDir: {planBaseDir}/
  - sourceBaseDir: {baseDir}
  - projectRoot: {cwd}
  - specDir: {specRoot}/{workingLanguage}/
  - routerMode: {routerMode}
  - serverState: {serverState}
  - formStack: {formStack}
  - componentLibrary: {componentLibrary}
  - externalComponents: {the config object, or omit the line when absent}
  - apiLayer: {apiLayer}
  - apiPackage: {the config object, or omit the line when absent}
  - i18nBinding: {i18nBinding}
  - i18nHook: {the config object, or omit the line when absent}
  - clientStore: {clientStore}
  - mockFirst: {mockFirst}
  - appDir: {appDir}
  - srcPath: {srcPath}

  Follow the process defined in agents/delta-modifier.md.
  Read {pluginRoot}/templates/tdd-rules.md for TDD rules.
")
```

> Note: `{planBaseDir}` is the feature-level directory from plan.json (e.g., `app/src/features/{feature}`), NOT the config-level `{baseDir}` (e.g., `app/src`).

**On completion**: Record results from delta-modifier report.

**On failure**: Ask user whether to retry or stop. If stop → go to **Step 2-D.F** (failure path).

**Part B: New file creation (TDD phases only)**

If `createFiles` is non-empty AND the phase is a TDD phase (`api-tdd`, `store-tdd`, `component-tdd`, `page-tdd`):

```
Agent(subagent_type: "frontend-v2-plugin:tdd-cycle-runner", prompt: "
  Execute TDD cycle for '{feature}' phase '{phase}'.

  Parameters:
  - planFile: {runsDir}/{feature}/plan.json
  - feature: {feature}
  - phase: {phase}
  - projectRoot: {cwd}
  - specDir: {specRoot}/{workingLanguage}/
  - uiDslDir: {specRoot}/ui-dsl/ (available: {uiDslAvailable})
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
  - componentLibrary: {componentLibrary}
  - externalComponents: {the config object, or omit the line when absent}
  - apiLayer: {apiLayer}
  - apiPackage: {the config object, or omit the line when absent}
  - i18nBinding: {i18nBinding}
  - i18nHook: {the config object, or omit the line when absent}
  - clientStore: {clientStore}

  Follow the process defined in agents/tdd-cycle-runner.md.
  Read {pluginRoot}/templates/tdd-rules.md for TDD rules.

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
3. Delete lock file (`{runsDir}/{feature}/.lock`)
4. Display:
   > "Delta generation failed at {phase}."
   > "Options:"
   > "1. Resume: `/frontend-v2-plugin:v2-gen {feature}` (will detect delta and resume)"
   > "2. Debug: `/frontend-v2-plugin:v2-debug {feature}`"
   > "3. Full regeneration: `/frontend-v2-plugin:v2-gen {feature}` (choose option 2 when prompted)"
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

Read `{runsDir}/{feature}/progress.json` and update:

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
> pre-delta state — the next `v2-gen` could only offer full generation. Interrupted in the new
> order, the delta is still active and simply re-runs its (now completed, skipped-on-resume)
> phases to reach this point again.

#### 2-D.8: Next Steps

> "Delta generation complete. Recommended next steps:"
> "1. Verify: `/frontend-v2-plugin:v2-verify {feature}`"
> "2. Review: `/frontend-v2-plugin:v2-review {feature}`"

Skip to Lock Release (do not execute Steps 3-8).
