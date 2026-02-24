---
name: gen
description: "Generate production React code from an implementation plan. Run /frontend-react-plugin:plan first."
argument-hint: "<feature-name>"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# Code Generation Skill

구현 계획서(plan.json) 기반으로 프로덕션 React 코드를 생성한다.

## Instructions

### Step 0: Read Configuration

1. Read `.claude/frontend-react-plugin.json` → `routerMode` 추출
2. 파일이 없으면:
   > "Frontend React Plugin이 초기화되지 않았습니다. `/frontend-react-plugin:init`을 먼저 실행하세요."
   - Stop here.

### Step 1: Validate Plan

1. Check if `docs/specs/{feature}/.implementation/plan.json` exists
   - 없으면:
     > "구현 계획서를 찾을 수 없습니다."
     > "`/frontend-react-plugin:plan {feature}`을 먼저 실행하세요."
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

  shadcn/ui to install: {missing list or "none"}

  Build order: types → api/stores → components → pages → routes/i18n
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
  - projectRoot: {cwd}

  Follow the process defined in agents/code-generator.md.
  Generate all files according to the plan's buildOrder.
")
```

### Step 4: Post-Generation

1. **Display results**:

```
Code Generation Complete for '{feature}':

  Files created: {totalFiles}
    {file list}

  shadcn/ui installed: {installed list or "none needed"}
```

2. **Manual integration steps** — display the steps the user needs to do manually:

```
  Manual integration steps:
    1. Route registration:
       Add to {insertLocation}:
       {route snippet}

    2. i18n namespace:
       Register '{namespace}' namespace in i18n config

    {additional steps if any}
```

3. **Update progress** — Read `docs/specs/{feature}/.progress/{feature}.json` and add or update the `implementation` field:

```json
{
  "implementation": {
    "status": "generated",
    "planFile": "docs/specs/{feature}/.implementation/plan.json",
    "generatedAt": "{ISO timestamp}",
    "filesCount": {totalFiles}
  }
}
```

Write the updated progress file back.
