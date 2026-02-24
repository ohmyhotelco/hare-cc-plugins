---
name: plan
description: "Analyze a functional specification and produce an implementation plan for production React code generation."
argument-hint: "<feature-name>"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Task
---

# Implementation Plan Skill

기능 명세(planning-plugin 산출물)를 분석하여 프로덕션 React 코드의 구현 계획서를 생성한다.

## Instructions

### Step 0: Read Configuration

1. Read `.claude/frontend-react-plugin.json` → `routerMode` 추출
2. 파일이 없으면:
   > "Frontend React Plugin이 초기화되지 않았습니다. `/frontend-react-plugin:init`을 먼저 실행하세요."
   - Stop here.

### Step 1: Validate Spec

1. Check if `docs/specs/{feature}/.progress/{feature}.json` exists
   - 없으면:
     > "기능 명세를 찾을 수 없습니다: `docs/specs/{feature}/`"
     > "planning-plugin으로 기능 명세를 먼저 작성하세요."
     - Stop here.

2. Read the progress file and check `status`:
   - `"reviewing"` or `"finalized"` → proceed
   - `"drafting"` or `"analyzing"` →
     > "기능 명세가 아직 완성되지 않았습니다 (status: {status})."
     > "명세 작성을 완료한 후 다시 실행하세요."
     - Stop here.

3. Extract `workingLanguage` from the progress file (default: `"ko"`)

### Step 2: Check UI DSL

1. Check if `docs/specs/{feature}/ui-dsl/manifest.json` exists
   - exists → `uiDslAvailable = true`
   - not exists → `uiDslAvailable = false`

2. If `uiDslAvailable` is false, display recommendation:
   > "UI DSL이 없습니다. spec markdown에서 추론하여 계획을 생성합니다."
   > "더 정확한 계획을 위해 `/planning-plugin:design {feature}` 실행을 권장합니다."

3. Check if `src/prototypes/{feature}/` exists → `prototypeAvailable`

### Step 3: Launch Planner Agent

Create the output directory if it doesn't exist:
```
docs/specs/{feature}/.implementation/
```

Launch the implementation-planner agent:

```
Task(subagent_type: "implementation-planner", prompt: "
  Analyze the functional specification for '{feature}' and produce an implementation plan.

  Parameters:
  - feature: {feature}
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - uiDslDir: docs/specs/{feature}/ui-dsl/ (available: {uiDslAvailable})
  - prototypeDir: src/prototypes/{feature}/ (available: {prototypeAvailable})
  - routerMode: {routerMode}
  - projectRoot: {cwd}
  - outputFile: docs/specs/{feature}/.implementation/plan.json

  Follow the process defined in agents/implementation-planner.md.
  Write the implementation plan to the outputFile path.
")
```

### Step 4: Display Summary

1. Read the generated `docs/specs/{feature}/.implementation/plan.json`
2. Display the summary:

```
Implementation Plan for '{feature}':

  Source: docs/specs/{feature}/ (status: {specStatus}, UI DSL: {available/not available})
  Target: {baseDir}/ ({projectStructure} layout)
  Router: {routerMode} mode

  Files to create ({totalFiles}):
    Types:       {type names} ({count} files)
    API:         {api names} — {endpoint count} endpoints ({count} files)
    Stores:      {store names} ({count} files)
    Components:  {component names} ({count} files)
    Pages:       {page descriptions} ({count} files)
    Routes:      {entry count} entries under {parentRoute}
    i18n:        {namespace} namespace ({language count} languages)

  shadcn/ui: {missing count} components need installation ({missing list})

  Build order: types → api/stores → components → pages → routes/i18n

  Plan saved to: docs/specs/{feature}/.implementation/plan.json
  Review and edit the plan, then run /frontend-react-plugin:gen {feature}
```
