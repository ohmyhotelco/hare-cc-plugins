---
name: v2-plan
description: "Use when a feature needs an implementation plan before code generation, either from an existing spec or through interactive requirements gathering."
argument-hint: "<ticket-key|feature-name> [--change|--new-screen|--standalone] [--app <app>[,<app>...]]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# Implementation Plan Skill

Analyzes a functional specification (planning-plugin output) or gathers requirements interactively (standalone mode) and produces an implementation plan for production React code.

Conventions (`v2-shared`): `${CLAUDE_PLUGIN_ROOT}/skills/v2-shared/SKILL.md`.

Files under `references/` write the plugin root as `{pluginRoot}`, which is `${CLAUDE_PLUGIN_ROOT}`.

## Instructions

### Step 0: Read Configuration

**Monorepo (v2-shared § Monorepo Rules).** Read the config file first (missing → the stop below). In change mode (Step 0.5) the apps are chosen in change.md C.1 — do not ask for an app here; read the shared keys only. Otherwise, before extracting any key, resolve the app (`--app <app>`, else the plan's `apps`, else `defaultApp`, else ask) and overlay `apps[{app}]`; every key below comes from that merged view. Once `appDir` is known, where this skill runs `npx`, derive `nodeBin` and pass it to every agent that receives `appDir`. Mention the resolved app in the first line of output. `runsDir` (default `docs/plugin-runs`), `rulesDir` (default `docs/rules`) and `{specRoot}` resolve as v2-shared § Monorepo Rules says.

1. Read `.claude/frontend-v2-plugin.json` → extract `routerMode`, `appProfile`, `serverState`, `formStack`, `renderingDefault`, `mockFirst`, `baseDir`, `appDir`, `i18n`, and the Phase 2 knobs `componentLibrary`, `apiLayer`, `i18nBinding`, `clientStore` with their companion objects `externalComponents`, `apiPackage`, `i18nHook`
2. If `baseDir` is missing, use default value `"src"`
3. If `mockFirst` is missing, use default value `true`
4. If `appDir` is missing, use default value `"."` (project root)
5. New-stack keys fall back to admin defaults when absent: `appProfile="admin"`, `serverState="zustand-only"`, `formStack="native"`; `renderingDefault` applies only when `routerMode="framework"` (default `"ssr"`). Phase 2 knobs fall back to `componentLibrary="shadcn"`, `apiLayer="feature-local"`, `i18nBinding="react-i18next"`, `clientStore="zustand"`; pass a companion object only when present. Pass all of these through to the planner so it can plan rendering / queries / form schemas / component inventory / API reuse / i18n resources.
6. If the file does not exist:
   > "Frontend V2 Plugin has not been initialized. Please run `/frontend-v2-plugin:v2-init` first."
   - Stop here.
7. **Derive `srcPath`** — take the config `baseDir` **after its default is applied** and remove the leading `{appDir}/` (`app/src` + `appDir=app` → `src`; `appDir="."` → unchanged; `appDir == baseDir` → `.`). Every `npx …` path argument uses `srcPath`; the repo-relative source root stays available for file operations. See v2-shared § Build Command Working Directory.

### Lock Acquire

`v2-plan` writes `plan.json`, `delta-plan.json`, and the progress file, so it is a state-mutating
skill and takes the feature lock like the others — a plan written while `v2-gen` is generating from
the previous plan leaves the two disagreeing about what exists.

**Create the lock's parent first.** `{runsDir}/{feature}/` does not exist
for a feature being planned standalone for the first time, and lock creation fails there before the
steps that would create it ever run. Note whether the directory already existed, `mkdir -p` it, then
acquire.

Do **not** try to reject a mistyped feature name here — at this point the mode is unknown (`Step 0.5`
decides it), and a "spec must exist" check either kills the legitimate first-ever standalone run or,
if evaluated after the `mkdir -p`, always passes because the mkdir just created the directory being
checked. The existing nets downstream are the right ones: Step 0.5 auto-detection asks the user when
no spec exists, and Step 1 stops on a missing spec in spec mode. The one residue a typo can leave is
the directory this section created — so on any exit before the first artifact write, if this run
created the directory (it did not exist before the `mkdir -p`): **delete this run's own lock file,
then remove the now-empty directories with non-recursive `rmdir`, innermost first.** Never
`rm -rf`: between deleting our lock and removing the directory, another session may legitimately
acquire a new lock in it, and a recursive delete would destroy that live lock. `rmdir` on a
non-empty directory fails harmlessly, which is exactly the right outcome — someone else is using
it now. A pre-existing directory is never removed.

Acquire `{runsDir}/{feature}/.lock` with `holder: "v2-plan"`, per
v2-shared § Lock file. **Check the holder's `pid` before treating any lock as stale.** Held by a live
holder → report `holder` and `acquiredAt`, then stop.

Everything from here to Step 5 runs under the lock — it is taken before Step 0.5 so that no branch (standalone, incremental, or full) can reach a write by jumping to Step 1, 1-S, 3, or 3-I. Release it on **every** exit below, including a
user declining at Step 4-I or Step 4.

### Step 0.5: Detect Mode

1. Flags win: `--standalone` → `mode = "standalone"`, skip to Step 1-S. `--change` → `mode = "change"`.
   `--new-screen` → the spec/standalone flow below (item 2b onward), never change mode.
2. Otherwise decide in this order:
   a. `{runsDir}/{feature}/plan.json` exists with `changeKind: "change"` → `mode = "change"` (re-plan).
   a2. `{runsDir}/{feature}/progress.json` has `standalone: true` → `mode = "spec"`: a standalone feature
      being re-planned. Step 1 reads that file (not a planning-plugin one) and Step 2.5 skips.
   b. A planning-plugin spec exists — `docs/specs/{feature}/.progress/{feature}.json` → `mode = "spec"`,
      Step 1.
   c. `{feature}` looks like a ticket key (`^[A-Z][A-Z0-9]+-[0-9]+$`, e.g. `ABC-123`) → `mode = "change"`.
   d. None of these → ask:
      > "How should '{feature}' be planned?"
      > "1. Change to existing code, from a ticket (recommended for fixes and small features)"
      > "2. New screen, requirements gathered interactively (standalone)"
      > "3. New screen from a planning-plugin spec: create it first with `/planning-plugin:pp-spec {feature}`"
      - 1 → `mode = "change"`; 2 → `mode = "standalone"`, Step 1-S; 3 → stop.
3. `mode = "change"` → read `${CLAUDE_PLUGIN_ROOT}/skills/v2-plan/references/change.md` and follow it
   instead of Steps 1–5.

### Step 1: Validate Spec

1. Check if the progress file exists: the planning-plugin one, `docs/specs/{feature}/.progress/{feature}.json`
   (`{specRoot}` is then `docs/specs/{feature}`), or — for a standalone re-plan (Step 0.5 rule a2) —
   `{runsDir}/{feature}/progress.json` (`{specRoot}` is then `{runsDir}/{feature}/spec`)
   - If not found:
     > "Functional specification not found: `{specRoot}/`"
     > "Please create the functional specification using planning-plugin first."
     - Stop here.

2. Read the progress file and check `status`:
   - `"reviewing"` or `"finalized"` → proceed
   - If status is `"reviewing"`:
     > "The specification is in 'reviewing' status — unresolved review issues may exist."
     > "For the most accurate plan, finalize first: `/planning-plugin:pp-review {feature}`"
     > "Continue with current spec?"
     - If the user declines, stop here.
   - `"drafting"` or `"analyzing"` →
     > "The functional specification is not yet complete (status: {status})."
     > "Please finish writing the specification, then try again."
     - Stop here.

3. Extract `workingLanguage` from the progress file (default: `"en"`), and create or update
   `{runsDir}/{feature}/progress.json` with `feature`, `status` and `workingLanguage` copied from it
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill (summaries, questions, feedback presentations, next-step guidance) must be in {workingLanguage_name}.

### Step 1-S: Standalone Requirements Gathering (standalone mode only)

Read `${CLAUDE_PLUGIN_ROOT}/skills/v2-plan/references/standalone.md` and follow this section there.

### Step 2: Check UI DSL

1. Check if `{specRoot}/ui-dsl/manifest.json` exists
   - exists → `uiDslAvailable = true`
   - not exists → `uiDslAvailable = false`

2. If `uiDslAvailable` is false, display recommendation:
   > "UI DSL is not available. The plan will be generated by inferring from the spec markdown."
   > "For a more accurate plan, running `/planning-plugin:pp-design {feature}` is recommended."

3. Check if `prototypes/{feature}/` exists → `prototypeAvailable`

### Step 2.5: Detect Shared Layout

**Standalone features skip this step entirely** (read the progress file's `standalone` flag): the
standalone planner rule is "shared layout detection: skip", and item 2 below reads `screens.md`,
which standalone never creates — without this branch an existing standalone feature (spec mode by
Step 0.5 rule a2) dies here and **never reaches Step 2.7's
incremental detection**, making standalone replanning unreachable through this skill. Set
`sharedLayoutIds = "none"` and continue to Step 2.7.

1. If `uiDslAvailable` is true:
   - Read `{specRoot}/ui-dsl/manifest.json`
   - Check `layouts` array for entries with `"source": "_shared"`
   - If found: `sharedLayoutIds` = list of layout IDs
2. If `uiDslAvailable` is false:
   - Read `{specRoot}/{workingLanguage}/screens.md`
   - Check for `<!-- @layout: _shared/` directive
   - If found: extract layout IDs
3. If no shared layout references found: `sharedLayoutIds` = `"none"`

### Step 2.7: Incremental Detection

Check if incremental mode is applicable:

1. Check if `{runsDir}/{feature}/plan.json` exists → `existingPlanExists`
2. If `existingPlanExists`:
   - Read `{runsDir}/{feature}/progress.json` → extract `implementation.status`
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

Read `${CLAUDE_PLUGIN_ROOT}/skills/v2-plan/references/incremental.md` and follow this section there.

### Step 4-I: Display Delta Summary & Confirm

Read `${CLAUDE_PLUGIN_ROOT}/skills/v2-plan/references/incremental.md` and follow this section there.

### Step 3: Launch Planner Agent

Create the output directory if it doesn't exist:

Create `{runsDir}/{feature}/` if it does not exist. If `{runsDir}/README.md` does not exist, create it and `{runsDir}/.gitignore` as v2-shared § Monorepo Rules says.

```
{runsDir}/{feature}/
```

Launch the implementation-planner agent:

```
Agent(subagent_type: "frontend-v2-plugin:implementation-planner", prompt: "
  Analyze the functional specification for '{feature}' and produce an implementation plan.

  Parameters:
  - feature: {feature}
  - specDir: {specRoot}/{workingLanguage}/
  - uiDslDir: {specRoot}/ui-dsl/ (available: {uiDslAvailable})
  - prototypeDir: prototypes/{feature}/ (available: {prototypeAvailable})
  - routerMode: {routerMode}
  - appProfile: {appProfile}
  - serverState: {serverState}
  - formStack: {formStack}
  - componentLibrary: {componentLibrary}
  - externalComponents: {the config object, or omit the line when absent}
  - apiLayer: {apiLayer}
  - apiPackage: {the config object, or omit the line when absent}
  - i18nBinding: {i18nBinding}
  - i18nHook: {the config object, or omit the line when absent}
  - clientStore: {clientStore}
  - renderingDefault: {renderingDefault}
  - mockFirst: {mockFirst}
  - projectRoot: {cwd}
  - baseDir: {baseDir}
  - appDir: {appDir}
  - srcPath: {srcPath}
  - outputFile: {runsDir}/{feature}/plan.json
  - i18n: {the config i18n block, or omit when absent}

  Follow the process defined in agents/implementation-planner.md.
  Write the implementation plan to the outputFile path.
")
```

### Step 4: Display Summary

1. Read the generated `{runsDir}/{feature}/plan.json`
2. Display the summary:

```
Implementation Plan for '{feature}':

  Source: {specRoot}/ (status: {specStatus}, UI DSL: {available/not available})
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
    Tests:       {testFiles} test files, {testCases} test cases
    E2E:         {e2eScenarios} scenarios

  Components: {shadcn: "{missing count} shadcn/ui components need installation ({missing list})" | external: "{used count} from {package}, {gap count} ui-kit gaps ({gap list})"}

  TDD Phases:
    1. Foundation     — shared-layouts + types + mocks (infra)
    2. API TDD        — RED: api tests → GREEN: api services
    3. Store TDD      — RED: store tests → GREEN: stores
    4. Component TDD  — RED: component tests → GREEN: components
    5. Page TDD       — RED: page tests → GREEN: pages
    6. Integration    — routes + i18n + MSW setup + barrel

  Plan saved to: {runsDir}/{feature}/plan.json
  Review and edit the plan, then run /frontend-v2-plugin:v2-gen {feature}
```

### Step 5: Update Progress

1. Read `{runsDir}/{feature}/progress.json`
2. Add or update the `implementation` field:

```json
{
  "implementation": {
    "status": "planned",
    "planFile": "{runsDir}/{feature}/plan.json"
  }
}
```

3. Write the updated progress file back. **Merge rule**: preserve all existing fields in the progress file — only add or update the `implementation` fields shown above.

### Step 5-I: Update Progress (Incremental Mode)

Read `${CLAUDE_PLUGIN_ROOT}/skills/v2-plan/references/incremental.md` and follow this section there.

### Lock Release

Delete `{runsDir}/{feature}/.lock`.

Both Step 5 and Step 5-I end here — whichever branch ran, this is the last action. Release also on
every early exit after Lock Acquire (a declined confirmation at Step 4 or 4-I, a planner failure),
per v2-shared § Lock file: the lock is taken before those prompts, so a refusal that just stops
leaves the feature locked and `v2-gen` refusing it.
