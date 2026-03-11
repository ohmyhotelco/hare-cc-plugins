---
name: gen
description: "Generate production React code from an implementation plan. Run /frontend-react-plugin:plan first."
argument-hint: "<feature-name>"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# Code Generation Skill

Generate production React code based on the implementation plan (plan.json).

## Instructions

### Step 0: Read Configuration

1. Read `.claude/frontend-react-plugin.json` → extract `routerMode`, `mockFirst`
2. If `mockFirst` is missing, use default value `true`
3. If the file does not exist:
   > "Frontend React Plugin has not been initialized. Please run `/frontend-react-plugin:init` first."
   - Stop here.

### Step 1: Validate Plan

1. Check if `docs/specs/{feature}/.implementation/plan.json` exists
   - If not found:
     > "Implementation plan not found."
     > "Please run `/frontend-react-plugin:plan {feature}` first."
     - Stop here.

2. Read `plan.json` → extract `summary`, `buildOrder`, `feature`

3. Read `docs/specs/{feature}/.progress/{feature}.json` → extract `workingLanguage`

4. Check UI DSL and prototype availability:
   - `docs/specs/{feature}/ui-dsl/manifest.json` → `uiDslAvailable`
   - `src/prototypes/{feature}/` → `prototypeAvailable`

### Step 2: Confirm with User

Display the plan summary and ask for confirmation:

```
Code Generation for '{feature}':

  Plan: docs/specs/{feature}/.implementation/plan.json
  Target: {baseDir}/

  Files to create ({totalFiles}):
    {file list grouped by category}
    Tests: {test file count} test files ({test case count} test cases)

  shadcn/ui to install: {missing list or "none"}

  Build order: types → api/stores → mocks → components → pages → routes/i18n/msw-setup
```

Check for existing files that would be overwritten:
- For each file in plan, check if it already exists
- If any exist, warn the user:
  > "Warning: The following files already exist and will be overwritten:"
  > {list of existing files}

Ask:
> "Proceed with code generation?"

If the user declines, stop here.

### Step 3: Launch Generator Agent

Launch the code-generator agent:

```
Task(subagent_type: "code-generator", prompt: "
  Generate production React code for '{feature}'.

  Parameters:
  - feature: {feature}
  - planFile: docs/specs/{feature}/.implementation/plan.json
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - uiDslDir: docs/specs/{feature}/ui-dsl/ (available: {uiDslAvailable})
  - prototypeDir: src/prototypes/{feature}/ (available: {prototypeAvailable})
  - routerMode: {routerMode}
  - mockFirst: {mockFirst}
  - projectRoot: {cwd}

  Follow the process defined in agents/code-generator.md.
  Generate all files according to the plan's buildOrder.
")
```

### Step 4: Post-Generation

1. **Display results** — including test files:

```
Code Generation Complete for '{feature}':

  Files created: {totalFiles}
    {file list}
    Test files: {test file list or "no tests planned"}

  shadcn/ui installed: {installed list or "none needed"}
```

2. **Step 4a: Verification Gate** — automatically run tsc, ESLint, and build:

   a. TypeScript verification:
   ```bash
   npx tsc --noEmit 2>&1
   ```

   b. ESLint verification (if config exists):
   - Use Glob to check for `.eslintrc*`, `eslint.config.*`
   - If found: `npx eslint {baseDir} --ext .ts,.tsx 2>&1`

   c. Build verification:
   ```bash
   npx vite build 2>&1
   ```

   d. Test run (when plan has `tests[]`):
   ```bash
   npx vitest run {baseDir} 2>&1
   ```
   - exit code 0 → pass, else fail
   - If no tests, skipped

   Display results:
   ```
   Verification:
     TypeScript: {pass/fail} ({error count} errors)
     ESLint:     {pass/fail/skipped}
     Build:      {pass/fail}
     Tests:      {pass/fail/skipped}
   ```

   **On FAIL:**
   > "Verification failed. Fix the errors and re-verify with `/frontend-react-plugin:verify {feature}`."

3. **Step 4b: Code Review (optional)** — confirm with user:

   > "Would you like to run a code review? (spec compliance + quality check)"

   If the user says yes:
   - Run the spec-reviewer agent → display results
   - If spec-reviewer passes, run the quality-reviewer agent → display results
   - Display combined report:
     ```
     Code Review:
       Spec Review:    {pass/fail} (score: {score}/10)
       Quality Review: {pass/fail} (score: {score}/10)
     ```

   If review result is `fail` or `pass_with_warnings`:
   > "Fix the issues and re-review with `/frontend-react-plugin:review-code {feature}`."
   > "Do not skip re-review after making fixes."

   If the user says no, skip this step.
   Standalone execution: `/frontend-react-plugin:review-code {feature}`

4. **Manual integration steps** — display the steps the user needs to do manually:

```
  Manual integration steps:
    1. Route registration:
       Add to {insertLocation}:
       {route snippet}

    2. i18n namespace:
       Register '{namespace}' namespace in i18n config

    {additional steps if any}
```

5. **Mock-first guidance** (if `mockFirst` is `true`):

```
  Mock-first development:
    Start with mocks: VITE_ENABLE_MOCKS=true pnpm dev
    Start without mocks: pnpm dev
    Commit: public/mockServiceWorker.js (recommended)
```

6. **Step 4c: Test run guidance** — if test files were generated but tests were fail or skipped in Step 4a:

   > "Re-run tests: `pnpm vitest run src/features/{feature}/`"
   > "Auto-debug: `/frontend-react-plugin:debug {feature}`"

7. **Update progress** — Read `docs/specs/{feature}/.progress/{feature}.json` and add or update the `implementation` field (including verification and review results):

```json
{
  "implementation": {
    "status": "generated | gen-failed",
    "planFile": "docs/specs/{feature}/.implementation/plan.json",
    "generatedAt": "{ISO timestamp}",
    "filesCount": {totalFiles},
    "verification": {
      "status": "pass|fail",
      "timestamp": "{ISO timestamp}"
    },
    "review": {
      "status": "pass|fail|skipped",
      "timestamp": "{ISO timestamp}"
    }
  }
}
```

Write the updated progress file back.
