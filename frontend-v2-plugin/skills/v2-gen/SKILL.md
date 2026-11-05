---
name: v2-gen
description: "Generate production React code from an implementation plan using TDD. Run /frontend-v2-plugin:v2-plan first."
argument-hint: "<feature-name> [--app <app>]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Code Generation Skill (TDD Coordinator)

Generates production React code based on the implementation plan (plan.json) using strict Test-Driven Development. Each phase runs in a separate agent session for context isolation.

TDD phases run in order, because each depends on the previous phase's output: start a phase only after the previous agent has reported.

Conventions (`v2-shared`): `${CLAUDE_PLUGIN_ROOT}/skills/v2-shared/SKILL.md`.

Files under `references/` write the plugin root as `{pluginRoot}`, which is `${CLAUDE_PLUGIN_ROOT}`.

## Instructions

### Step 0: Read Configuration

**Monorepo (v2-shared § Monorepo Rules).** Read the config file first (missing → the stop below). Then, before extracting any key, resolve the app (`--app <app>`, else `defaultApp`, else ask) and overlay `apps[{app}]`; every key below comes from that merged view. Once `appDir` is known, where this skill runs `npx`, derive `nodeBin` and pass it to every agent that receives `appDir`. Mention the resolved app in the first line of output.

1. Read `.claude/frontend-v2-plugin.json` → extract `routerMode`, `appProfile`, `serverState`, `formStack`, `e2eTool`, `mockFirst`, `baseDir`, `appDir`, `prettierTemplate`, `i18n`, `devPort` (default `5173` when absent), and the Phase 2 knobs `componentLibrary`, `apiLayer`, `i18nBinding`, `clientStore` with their companion objects `externalComponents`, `apiPackage`, `i18nHook`
2. If `baseDir` is missing, use default value `"src"`
3. If `mockFirst` is missing, use default value `true`
4. If `appDir` is missing, use default value `"."` (project root)
5. New-stack keys fall back to admin defaults when absent: `appProfile="admin"`, `serverState="zustand-only"`, `formStack="native"`, `e2eTool="agent-browser"`, `prettierTemplate=true`. **`i18n` has no default** — pass it to foundation-generator when present, omit the parameter when absent, and never synthesize a language set from the locale directory (a language present as a folder but absent from `i18n.languages` would otherwise be silently claimed as covered). Phase 2 knobs fall back to `componentLibrary="shadcn"`, `apiLayer="feature-local"`, `i18nBinding="react-i18next"`, `clientStore="zustand"`; pass a companion object only when present. Pass `routerMode`/`serverState`/`formStack`/`componentLibrary`/`apiLayer`/`i18nBinding`/`clientStore` (and each page's `rendering`) through to every phase agent (foundation-generator, tdd-cycle-runner, integration-generator) so they generate the right variant. `e2eTool` is used later by v2-e2e, not here — but foundation-generator scaffolds the Playwright harness once when `e2eTool="playwright"`.
6. If the file does not exist:
   > "Frontend V2 Plugin has not been initialized. Please run `/frontend-v2-plugin:v2-init` first."
   - Stop here.
7. **Derive `srcPath`** — take the config `baseDir` **after its default is applied** and remove the leading `{appDir}/` (`app/src` + `appDir=app` → `src`; `appDir="."` → unchanged; `appDir == baseDir` → `.`). Every `npx …` path argument uses `srcPath`; the repo-relative source root stays available for file operations. See v2-shared § Build Command Working Directory.

**Empty-phase skip.** When `serverState="tanstack-query"`, the planner may emit **no** `stores[]` entry for a feature whose server data lives entirely in the query cache; under `clientStore="none"` it never emits one; under `apiLayer="workspace-package"` a feature fully covered by `api[].reuse[]` has no `additions[]`. A phase with no files to generate is skipped: if the plan has no store for the feature (empty `stores[]`), mark `store-tdd` as **`"skipped"`** in generation-state with **`skipKind: "auto"`** and `reason: "no store planned"`, and log "Skipping store-tdd (no client-only store)"; likewise mark `api-tdd` `skipped` / `skipKind: "auto"` / `reason: "no package additions"` when every `api[]` entry has `reuse[]` and no `additions[]`. Any other phase skipped for having no matching entries (Phase 2-5 "Skip if") records the same `skipKind: "auto"` and a reason — a skip without `skipKind` blocks the feature (Step 8). Use `"skipped"` — the status vocabulary is `completed` / `failed` / `skipped`, and a `"skip"` value matches no branch in the final-status logic, leaving a valid feature unable to reach `generated`. This is not an error — it is the expected shape under tanstack-query.

### Step 1: Validate Plan

1. Check if `docs/specs/{feature}/.implementation/frontend/plan.json` exists
   - If not found:
     > "Implementation plan not found."
     > "Please run `/frontend-v2-plugin:v2-plan {feature}` first."
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
     > "This feature is currently 'fixing' (v2-fix in progress or regen-required re-run)."
     > "Re-generating will overwrite any v2-fix changes in re-run phases."
     > "Continue with code generation?"
     - If the user declines, stop here.
   - All other statuses (`generated`, `gen-failed`, `planned`, `verify-failed`, `review-failed`, `resolved`, `escalated`) → no warning, proceed normally.

### Lock Acquire

Acquire the feature lock `docs/specs/{feature}/.implementation/frontend/.lock` with `holder: "v2-gen"`, per v2-shared § Lock file. **Check the holder's `pid` before treating any lock as stale** — the 30-minute rule sweeps ghost locks, it does not time out a live one. Held by a live holder → report `holder` and `acquiredAt`, then stop.

**Release on every exit below.** Any "stop here" from this point on — a user declining a
confirmation, a validation refusal, an agent that fails — releases this lock first. The lock is
taken before the confirmation prompts, so a refusal that just stops leaves the feature locked and
every later command refusing it (v2-shared § Lock file).

**Then run Step 1.9 (Playwright Harness Preflight) immediately — every mode, before any branch.**
The preflight's own heading says "every mode", but a heading routes nothing: the delta branch jumps
Lock Acquire → Step 2-D and a fresh-start resume jumps to Step 3, and both would sail past it —
after an e2eTool switch, a delta run would then "succeed" with no harness and `v2-e2e` would refuse.
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
  Components: {shadcn: "shadcn/ui to install: {missing list or none}" | external: "{package} reused, ui-kit gaps: {gap list or none}"}
```

Check for existing files that would be overwritten. Warn if any exist.

Ask:
> "Proceed with code generation?"

If the user declines, stop here.

### Step 1.9: Playwright Harness Preflight (every mode)

Read `${CLAUDE_PLUGIN_ROOT}/skills/v2-gen/references/playwright-preflight.md` and follow this section there.

### Step 2-D: Delta Execution (when `genMode = "delta"`)

Read `${CLAUDE_PLUGIN_ROOT}/skills/v2-gen/references/delta.md` and follow this section there.

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
Agent(subagent_type: "frontend-v2-plugin:foundation-generator", prompt: "
  Generate test infrastructure for '{feature}'.

  Parameters:
  - planFile: docs/specs/{feature}/.implementation/frontend/plan.json
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - uiDslDir: docs/specs/{feature}/ui-dsl/ (available: {uiDslAvailable})
  - prototypeDir: prototypes/{feature}/ (available: {prototypeAvailable})
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

**Skip if** plan has no matching tests or implementation entries for this phase — record it as `skipped` with `skipKind: "auto"` and a reason (Step 0, Empty-phase skip); never launch the runner for an empty phase.

Get the `skills` list from the corresponding `buildOrder` entry.

Launch the tdd-cycle-runner agent:

```
Agent(subagent_type: "frontend-v2-plugin:tdd-cycle-runner", prompt: "
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
  - componentLibrary: {componentLibrary}
  - externalComponents: {the config object, or omit the line when absent}
  - apiLayer: {apiLayer}
  - apiPackage: {the config object, or omit the line when absent}
  - i18nBinding: {i18nBinding}
  - i18nHook: {the config object, or omit the line when absent}
  - clientStore: {clientStore}
  - mockFirst: {mockFirst}
  - baseDir: {baseDir}
  - appDir: {appDir}
  - srcPath: {srcPath}
  - skills: {skills list from buildOrder}

  Follow the process defined in agents/tdd-cycle-runner.md.
  Read ${CLAUDE_PLUGIN_ROOT}/templates/tdd-rules.md for TDD rules.
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
  > "3. Stop generation (resume later with /frontend-v2-plugin:v2-gen {feature})"
- If user chooses Skip: update generation-state.json `{phase}.status = "skipped"` with **`skipKind: "user"`**, continue to next phase

#### Phase 6: Integration

Launch the integration-generator agent:

```
Agent(subagent_type: "frontend-v2-plugin:integration-generator", prompt: "
  Generate integration layer for '{feature}'.

  Parameters:
  - planFile: docs/specs/{feature}/.implementation/frontend/plan.json
  - feature: {feature}
  - projectRoot: {cwd}
  - routerMode: {routerMode}
  - serverState: {serverState}
  - apiLayer: {apiLayer}
  - apiPackage: {the config object, or omit the line when absent}
  - i18nBinding: {i18nBinding}
  - i18nHook: {the config object, or omit the line when absent}
  - i18n: {the config's i18n block, or omit the line entirely when absent}
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

Read `${CLAUDE_PLUGIN_ROOT}/skills/v2-gen/references/completion.md` and follow this section there.

### Step 6: Next Steps

Read `${CLAUDE_PLUGIN_ROOT}/skills/v2-gen/references/completion.md` and follow this section there.

### Step 7: Mock-first Guidance (if `mockFirst` is `true`)

Read `${CLAUDE_PLUGIN_ROOT}/skills/v2-gen/references/completion.md` and follow this section there.

### Step 8: Update Progress

Read `${CLAUDE_PLUGIN_ROOT}/skills/v2-gen/references/completion.md` and follow this section there.

### Lock Release

Delete `docs/specs/{feature}/.implementation/frontend/.lock`.

### Resume Support

When Step 1.6 detects an existing `.implementation/frontend/generation-state.json`, read `${CLAUDE_PLUGIN_ROOT}/skills/v2-gen/references/resume.md` and follow it.

