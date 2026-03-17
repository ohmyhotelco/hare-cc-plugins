---
name: fe-verify
description: "Run verification gate (tsc, ESLint, build) on generated code for a feature."
argument-hint: "<feature-name>"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash
---

# Verification Gate Skill

Run TypeScript, ESLint, and Vite build verification on generated code.

## Instructions

### Step 0: Read Configuration

1. Read `.claude/frontend-react-plugin.json` → extract `routerMode`, `mockFirst`
2. If the file does not exist:
   > "Frontend React Plugin has not been initialized. Please run `/frontend-react-plugin:fe-init` first."
   - Stop here.

### Step 1: Validate Files

1. Check if `docs/specs/{feature}/.implementation/plan.json` exists
   - If not found:
     > "Implementation plan not found."
     > "Please run `/frontend-react-plugin:fe-plan {feature}` first."
     - Stop here.

2. Read `plan.json` → extract `baseDir`, file list from all sections (types, api, stores, components, pages, tests)

3. Read `docs/specs/{feature}/.progress/{feature}.json` → extract `workingLanguage`, `implementation.status`
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill must be in {workingLanguage_name}.

5. **Status check** — verify `implementation.status` indicates code has been generated:
   - If status is `"planned"`, `"gen-failed"`, or absent:
     > "No generated code found (current status: '{status}')."
     > "Please run `/frontend-react-plugin:fe-gen {feature}` first."
     - Stop here.

6. **File existence check** — Verify that all files specified in the plan actually exist:
   - Use Glob to check existence of each file path
   - If missing files are found, display a warning:
     > "Warning: {count} planned files not found:"
     > {list of missing files}

### Step 2: Run Verification

Run the following 3 verifications sequentially.

#### 2.1 TypeScript Check

```bash
npx tsc --noEmit 2>&1
```

- exit code 0 → pass
- exit code != 0 → fail (collect error list)
- Record error/warning counts

#### 2.2 ESLint Check (if config exists)

Check for ESLint config file existence:
- Glob: `.eslintrc*`, `eslint.config.*`
- If no config found, skip this step

If config exists, detect config type and use appropriate command:
```bash
# If eslint.config.* exists (flat config, ESLint v9+):
npx eslint {baseDir} 2>&1

# If .eslintrc* exists (legacy config, ESLint v8):
npx eslint {baseDir} --ext .ts,.tsx 2>&1
```

- exit code 0 → pass
- exit code != 0 → fail (record error/warning counts)

#### 2.3 Build Check

```bash
npx vite build 2>&1
```

- exit code 0 → pass
- exit code != 0 → fail (collect error messages)

#### 2.4 Test Check

Check `tests[]` in plan.json:
- If `tests[]` is not empty:
  ```bash
  npx vitest run {baseDir} 2>&1
  ```
  - exit code 0 → pass
  - exit code != 0 → fail (collect list of failed tests)
- If `tests[]` does not exist or is empty: skipped ("no tests planned")

### Step 3: Display Report

Display the verification results:

```
Verification Report for '{feature}':

  TypeScript:  {pass/fail} ({error count} errors, {warning count} warnings)
  ESLint:      {pass/fail/skipped} ({error count} errors, {warning count} warnings)
  Build:       {pass/fail}
  Tests:       {pass/fail/skipped} ({passed}/{total})

  Overall: {PASS/FAIL}
```

**If FAIL:**
- Display up to 10 error messages for each failed item
- Suggest fixes:
  > "After fixing the errors, re-verify with `/frontend-react-plugin:fe-verify {feature}`."
  > "Auto-debug: `/frontend-react-plugin:fe-debug {feature}`"

### Step 4: Update Progress

Read `docs/specs/{feature}/.progress/{feature}.json` and add or update the `verification` field:

```json
{
  "implementation": {
    "status": "verified",
    "verification": {
      "status": "pass",
      "timestamp": "{ISO timestamp}",
      "tsc": { "status": "pass", "errors": 0, "warnings": 0 },
      "eslint": { "status": "pass", "errors": 0, "warnings": 0 },
      "build": { "status": "pass" },
      "tests": { "status": "pass", "passed": 10, "total": 10 }
    }
  }
}

Note: Set `implementation.status` to `"verified"` (all pass) or `"verify-failed"` (any fail).
```

**Merge rule**: Read the existing progress file, merge changes into the existing `implementation` object preserving all other fields (e.g., `planFile`, `tddPhases`, `review`, `fix`, `debug`), then write back the complete file.
