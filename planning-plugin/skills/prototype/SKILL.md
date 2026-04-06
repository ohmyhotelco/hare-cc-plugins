---
name: prototype
description: "Use when UI DSL is ready and a clickable prototype is needed for stakeholder review before production implementation."
argument-hint: "[feature-name]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Bash, Task
---

# Prototype Generation

Generate prototype for: **$ARGUMENTS**

## Instructions

Follow these steps in order.

### Step 1: Read Configuration

1. Read `.claude/planning-plugin.json` from the current project directory
2. If the file does not exist, stop with a guidance message:
   > "Planning Plugin is not configured for this project. Run `/planning-plugin:init` to set up."
3. Extract `workingLanguage` (default: `"en"` if field is absent)
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill (summaries, questions, feedback presentations, next-step guidance) must be in {workingLanguage_name}.

### Step 2: Parse Arguments & Validate

1. Parse `feature` from arguments (required, kebab-case)

2. Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`
   - If it does not exist, stop with:
     > "No specification found for '{feature}'. Run `/planning-plugin:spec "{feature}"` first."
   - Verify status is `reviewing` or `finalized`. If `drafting` or `analyzing`, stop with:
     > "The specification for '{feature}' is still in '{status}' status. Complete the spec review process first."

3. Verify `docs/specs/{feature}/ui-dsl/manifest.json` exists. If not, stop with:
   > "UI DSL not found for '{feature}'. Run `/planning-plugin:design {feature} --stage=dsl` first."

4. **Shared layout prerequisite check**: Read `docs/specs/{feature}/ui-dsl/manifest.json` and check if any screen or layout entry has `"source": "_shared"`:
   - If found, verify `docs/specs/_shared/ui-dsl/manifest.json` exists. If not, stop with:
     > "Shared layout DSL not found. Run `/planning-plugin:design _shared` first."
   - If found, also check if `docs/specs/_shared/stitch-wireframes/` has wireframe outputs (optional — only a suggestion if missing):
     > "Shared layout wireframes not found. Consider running `/planning-plugin:design _shared` to generate them for better visual consistency."

5. Check if Stitch wireframe outputs exist at `docs/specs/{feature}/stitch-wireframes/stitch-manifest.json`
   - If not present → skip (no Stitch integration)
   - If present → ask the user:
     ```
     Stitch wireframes detected for '{feature}'.
     If you edited wireframes on the Stitch website,
     run `/planning-plugin:sync-stitch {feature}` first.

     Proceed without syncing? (y/n)
     ```
   - If user answers **no** → stop with message: "Run `/planning-plugin:sync-stitch {feature}`, then re-run `/planning-plugin:prototype {feature}`."
   - If user answers **yes** → continue (record Stitch wireframes as available for Step 4 prompt branching)

### Step 3: Initialize Progress

Read the progress file and initialize the `design.stages.prototype` field if not present:

```json
{
  "design": {
    "stages": {
      "prototype": { "status": "pending" }
    }
  }
}
```

If `design.stages.prototype` already exists, preserve it (it will be overwritten in the next step).

### Step 4: Launch Prototype Generator Agent

1. Update progress: `design.stages.prototype.status = "in_progress"`
2. Build the prototype prompt. If `design.stages.stitch.status` is `"completed"`, append Stitch reference instructions:

```
Task(subagent_type: "prototype-generator", prompt: "Generate a React prototype for the feature '{feature}'. dslDir: docs/specs/{feature}/ui-dsl/. feature: {feature}. Read manifest.json and all screen-*.json files. Scaffold a Vite + React 19 + TypeScript + TailwindCSS + shadcn/ui project at prototypes/{feature}/ using React Router v7. Generate page components, mock data, and router setup with Lucide icons, then bundle into a single standalone HTML file using the bundle-artifact.sh script.{IF stitch completed: ' Also read Stitch wireframe outputs from docs/specs/{feature}/stitch-wireframes/ — use design-tokens.json for Tailwind theme, shadcn-mapping.json for component hints, HTML files for visual layout reference.'}")
```

### Step 5: Update Progress

**On success**, update the progress file:
```json
{
  "design.stages.prototype": {
    "status": "completed",
    "path": "prototypes/{feature}/",
    "artifact": "prototypes/{feature}/bundle.html",
    "bundleStatus": "current",
    "generatedAt": "ISO-8601"
  }
}
```

Set `design.status = "completed"` — prototype is the final stage of the design pipeline.

**On failure**, update `design.stages.prototype.status = "error"`, report the error, and ask the user whether to retry or skip.

### Step 6: Summary

Present a summary to the user:

```
Prototype Generation Results for '{feature}':

  Prototype: completed — prototypes/{feature}/bundle.html
```

**Next Steps:**
```
Next Steps:
  - Open `prototypes/{feature}/bundle.html` in a browser to preview the prototype
  - Run `cd prototypes/{feature} && npm run dev` for live development (Vite dev server)
  - Edit prototype files directly to refine the UI
  - Run `/planning-plugin:bundle {feature}` to rebuild bundle.html after edits
  - Run `/planning-plugin:design {feature} --stage=dsl` to regenerate DSL from updated screens.md
```

If `design-system/MASTER.md` does not exist, prepend this to the Next Steps:
```
  - Run `/planning-plugin:design-system --domain={domain}` to generate a design system — this enhances DSL icon accuracy, pattern validation, and prototype theming
```

## Error Handling

- If the agent fails, report the error and ask the user whether to retry
- If a prerequisite check fails, stop with a clear message and suggested fix
- Never leave the progress file in an inconsistent state — always update before stopping
- If the user interrupts mid-flow, save current state to the progress file
