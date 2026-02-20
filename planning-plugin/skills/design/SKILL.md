---
name: design
description: "Generate UI DSL, React prototype, and Figma designs from a finalized functional specification through a 3-stage pipeline: DSL generation → prototype scaffolding → Figma layer creation."
argument-hint: "[feature-name] [--stage=dsl|prototype|figma]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, mcp__figma__generate_figma_design
---

# Design Pipeline

Generate designs for: **$ARGUMENTS**

## Instructions

Follow these steps in order.

### Step 0: Read Configuration

1. Read `.claude/planning-plugin.json` from the current project directory
2. If the file does not exist, stop with a guidance message:
   > "Planning Plugin is not configured for this project. Run `/planning-plugin:init` to set up."
3. Extract `workingLanguage` (default: `"en"` if field is absent)
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

### Step 1: Parse Arguments & Validate

1. Parse the arguments to extract:
   - `feature` — kebab-case feature name (required)
   - `--stage` — optional stage filter: `dsl`, `prototype`, or `figma` (default: run all 3 stages sequentially)

2. Validate the spec exists:
   - Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`
   - If it does not exist, stop with:
     > "No specification found for '{feature}'. Run `/planning-plugin:spec "{feature}"` first."
   - Verify status is `reviewing` or `finalized`. If `drafting` or `analyzing`, stop with:
     > "The specification for '{feature}' is still in '{status}' status. Complete the spec review process first."

3. Validate `screens.md` exists at `docs/specs/{feature}/{workingLanguage}/screens.md`:
   - If not found, stop with:
     > "No screen definitions found. The spec must include screens.md."

4. Stage-specific prerequisite checks:
   - If `--stage=prototype`: verify `docs/specs/{feature}/ui-dsl/manifest.json` exists. If not:
     > "UI DSL not found. Run `/planning-plugin:design {feature} --stage=dsl` first."
   - If `--stage=figma`: verify `src/prototypes/{feature}/package.json` exists. If not:
     > "Prototype not found. Run `/planning-plugin:design {feature} --stage=prototype` first."

### Step 2: Determine Stages

Based on the `--stage` argument:
- No flag → run all 3 stages: `dsl` → `prototype` → `figma`
- `--stage=dsl` → run Stage 1 only
- `--stage=prototype` → run Stage 2 only
- `--stage=figma` → run Stage 3 only

### Step 3: Initialize Progress

Read the progress file and initialize the `design` field if not present:

```json
{
  "design": {
    "status": "pending",
    "stages": {
      "dsl": { "status": "pending" },
      "prototype": { "status": "pending" },
      "figma": { "status": "pending" }
    }
  }
}
```

If the `design` field already exists, preserve existing stage statuses for stages not being re-run.

### Step 4: Stage 1 — DSL Generation

**Skip if not in the determined stages.**

1. Update progress: `design.stages.dsl.status = "in_progress"`
2. Launch the **dsl-generator** agent:

```
Task(subagent_type: "dsl-generator", prompt: "Generate UI DSL JSON files for the feature '{feature}'. specDir: docs/specs/{feature}/{workingLanguage}/. feature: {feature}. Read screens.md (screen definitions, error handling) and {feature}-spec.md (functional requirements) from the spec directory. Read templates/ui-dsl-schema.json as the structural reference. Write output to docs/specs/{feature}/ui-dsl/.")
```

3. On success, update progress:
   ```json
   {
     "design.stages.dsl": {
       "status": "completed",
       "screenCount": {count from agent result},
       "generatedAt": "ISO-8601"
     }
   }
   ```
4. On failure, update `status: "error"`, report error, and ask user whether to retry or skip

### Step 5: Stage 2 — Prototype Generation

**Skip if not in the determined stages.**

1. Update progress: `design.stages.prototype.status = "in_progress"`
2. Launch the **prototype-generator** agent:

```
Task(subagent_type: "prototype-generator", prompt: "Generate a React prototype for the feature '{feature}'. dslDir: docs/specs/{feature}/ui-dsl/. feature: {feature}. Read manifest.json and all screen-*.json files. Scaffold a Vite + React + TypeScript + TailwindCSS + shadcn/ui project at src/prototypes/{feature}/. Generate page components, mock data, and router setup.")
```

3. On success, update progress:
   ```json
   {
     "design.stages.prototype": {
       "status": "completed",
       "path": "src/prototypes/{feature}/",
       "generatedAt": "ISO-8601"
     }
   }
   ```
4. On failure, update `status: "error"`, report error, and ask user whether to retry or skip

### Step 6: Stage 3 — Figma Generation (Optional)

**Skip if not in the determined stages.**

1. Check if the Figma MCP `generate_figma_design` tool is available
   - If not available, update progress and inform the user:
     ```json
     { "design.stages.figma": { "status": "skipped", "generatedAt": "ISO-8601" } }
     ```
     > "Figma MCP is not configured. Skipping Figma layer generation. Configure the Figma MCP server to enable this stage."
   - Skip to Step 7

2. Update progress: `design.stages.figma.status = "in_progress"`
3. Build the screen list from `docs/specs/{feature}/ui-dsl/manifest.json`
4. Launch the **figma-designer** agent:

```
Task(subagent_type: "figma-designer", prompt: "Generate Figma designs from the React prototype for feature '{feature}'. prototypeDir: src/prototypes/{feature}/. feature: {feature}. screens: {screen list with IDs and page file paths}. Read each page component and use generate_figma_design to convert them to Figma layers.")
```

5. On success, update progress:
   ```json
   {
     "design.stages.figma": {
       "status": "completed",
       "figmaFileUrl": "{url from agent result}",
       "generatedAt": "ISO-8601"
     }
   }
   ```
6. On failure or if agent returns `figma_mcp_unavailable`, update `status: "skipped"` and continue

### Step 7: Finalize & Summary

1. Determine overall design status:
   - All completed stages succeeded → `design.status = "completed"`
   - Some stages completed, some skipped → `design.status = "partial"`
   - Only pending stages remain → `design.status = "pending"`

2. Write the updated progress file

3. Present a summary to the user:

```
Design Pipeline Results for '{feature}':

  Stage 1 — DSL Generation:      {status} — {screenCount} screens
  Stage 2 — Prototype:           {status} — {path}
  Stage 3 — Figma:               {status} — {url or reason for skip}

Next Steps:
  - Run `cd src/prototypes/{feature} && npm run dev` to preview the prototype
  - Run `/planning-plugin:design {feature} --stage=figma` to generate Figma designs (requires Figma MCP)
  - Edit prototype files directly to refine the UI before Figma generation
  - Run `/planning-plugin:design {feature} --stage=dsl` to regenerate DSL from updated screens.md
```

Adjust the "Next Steps" based on which stages were completed or skipped.

## Error Handling

- If an agent fails, report the error and ask the user whether to retry or skip that stage
- If a prerequisite check fails, stop with a clear message and suggested fix
- Never leave the progress file in an inconsistent state — always update before stopping
- If the user interrupts mid-flow, save current state to the progress file
