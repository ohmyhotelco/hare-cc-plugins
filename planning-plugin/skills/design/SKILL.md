---
name: design
description: "Generate UI DSL, Stitch wireframes, React prototype, and Figma designs from a finalized functional specification through a 4-stage pipeline: DSL generation → Stitch wireframes → prototype scaffolding → Figma layer creation."
argument-hint: "[feature-name] [--stage=dsl|stitch|prototype|figma]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, mcp__figma__generate_figma_design, mcp__stitch__create_project, mcp__stitch__generate_screen_from_text, mcp__stitch__extract_design_context, mcp__stitch__fetch_screen_code, mcp__stitch__fetch_screen_image, mcp__stitch__list_projects, mcp__stitch__list_screens, mcp__stitch__get_project, mcp__stitch__get_screen
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

### Step 0b: Design System Integration

The design pipeline produces better results when a design system exists. Run `/planning-plugin:design-system` before `/planning-plugin:design` for best results.

**Agent-to-file reference map** (`design-system/pages/`):

| Design System File | dsl-generator | stitch-wireframe | prototype-generator | Purpose |
|--------------------|:---:|:---:|:---:|---------|
| `components.md` | O | - | - | Component inventory for type selection |
| `icons.md` | O | - | - | Domain-specific icon mappings |
| `patterns.md` | O | O | - | Layout validation via `page_layout` + `components_used` |
| `MASTER.md` | O | O | - | Design principles as DSL/wireframe constraints |
| `colors.md` | - | O | O | Color tokens for wireframe context + Tailwind theme |
| `typography.md` | - | O | O | Font families/sizes for wireframe context + Tailwind theme |
| `spacing-layout.md` | - | - | O | Layout density + spacing for Tailwind theme |

All references are optional — agents fall back to defaults when design-system files are absent.

**Stitch output cross-references** (`stitch-wireframes/`):

| Stitch Output File | prototype-generator | Purpose |
|--------------------|:---:|---------|
| `design-tokens.json` | O | Extracted color/font/spacing tokens for Tailwind theme |
| `DESIGN.md` | O | Natural-language design document for styling decisions |
| `shadcn-mapping.json` | O | Stitch HTML → shadcn/ui component mapping hints |
| `{screen-id}.html` | O | Visual layout reference (flex, grid, spacing) |

### Step 1: Parse Arguments & Validate

1. Parse the arguments to extract:
   - `feature` — kebab-case feature name (required)
   - `--stage` — optional stage filter: `dsl`, `stitch`, `prototype`, or `figma` (default: run all 4 stages sequentially)

2. Validate the spec exists:
   - Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`
   - If it does not exist, stop with:
     > "No specification found for '{feature}'. Run `/planning-plugin:spec "{feature}"` first."
   - Verify status is `reviewing` or `finalized`. If `drafting` or `analyzing`, stop with:
     > "The specification for '{feature}' is still in '{status}' status. Complete the spec review process first."

3. Validate `screens.md` exists at `docs/specs/{feature}/en/screens.md`:
   - If `docs/specs/{feature}/en/` directory does not exist, stop with:
     > "English spec not found. Run `/planning-plugin:translate {feature}` first to generate the English version."
   - If `screens.md` is missing inside the `en/` directory, stop with:
     > "No screen definitions found. The spec must include screens.md."

4. Stage-specific prerequisite checks:
   - If `--stage=stitch`: verify `docs/specs/{feature}/ui-dsl/manifest.json` exists. If not:
     > "UI DSL not found. Run `/planning-plugin:design {feature} --stage=dsl` first."
   - If `--stage=prototype`: verify `docs/specs/{feature}/ui-dsl/manifest.json` exists. If not:
     > "UI DSL not found. Run `/planning-plugin:design {feature} --stage=dsl` first."
   - If `--stage=figma`: verify `src/prototypes/{feature}/package.json` exists. If not:
     > "Prototype not found. Run `/planning-plugin:design {feature} --stage=prototype` first."

### Step 2: Determine Stages

Based on the `--stage` argument:
- No flag → run all 4 stages: `dsl` → `stitch` → `prototype` → `figma`
- `--stage=dsl` → run Stage 1 only
- `--stage=stitch` → run Stage 1.5 only
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
      "stitch": { "status": "pending" },
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
Task(subagent_type: "dsl-generator", prompt: "Generate UI DSL JSON files for the feature '{feature}'. specDir: docs/specs/{feature}/en/. feature: {feature}. Read screens.md (screen definitions, error handling) and {feature}-spec.md (functional requirements) from the spec directory. Read templates/ui-dsl-schema.json as the structural reference. Write output to docs/specs/{feature}/ui-dsl/.")
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

### Step 4.5: Stage 1.5 — Stitch Wireframe Generation

**Skip if not in the determined stages.**

1. Check if any Stitch MCP tool is available (e.g., `mcp__stitch__list_projects`)
   - If not available, update progress and inform the user:
     ```json
     { "design.stages.stitch": { "status": "skipped", "generatedAt": "ISO-8601" } }
     ```
     > "Stitch MCP is not configured. Skipping wireframe generation.
     >  Run: `claude mcp add stitch --transport http https://stitch.googleapis.com/mcp --header "X-Goog-Api-Key: <key>" -s user`"
   - Skip to Step 5

2. Update progress: `design.stages.stitch.status = "in_progress"`
3. Launch the **stitch-wireframe** agent:

```
Task(subagent_type: "stitch-wireframe", prompt: "Generate Stitch wireframes for the feature '{feature}'. dslDir: docs/specs/{feature}/ui-dsl/. feature: {feature}. Read manifest.json and all screen-*.json files. Generate visual wireframes using Google Stitch MCP, extract design tokens and shadcn/ui mapping hints. Write outputs to docs/specs/{feature}/stitch-wireframes/.")
```

4. On success, update progress:
   ```json
   {
     "design.stages.stitch": {
       "status": "completed",
       "projectId": "{stitch project ID from agent result}",
       "screenCount": "{count from agent result}",
       "outputDir": "docs/specs/{feature}/stitch-wireframes/",
       "designDoc": "docs/specs/{feature}/stitch-wireframes/DESIGN.md",
       "generatedAt": "ISO-8601"
     }
   }
   ```
   Stage 1.5 outputs now include `DESIGN.md` — a natural-language design document with 5 dimensions (Visual Theme, Color Palette, Typography, Component Styling, Layout Principles). This document is consumed by the prototype generator in Step 1c for Tailwind theming and component styling decisions.
5. On failure or if agent returns `stitch_mcp_unavailable`, update `status: "skipped"` and continue to the next stage

### Step 5: Stage 2 — Prototype Generation

**Skip if not in the determined stages.**

1. Update progress: `design.stages.prototype.status = "in_progress"`
2. Build the prototype prompt. If `design.stages.stitch.status` is `"completed"`, append Stitch reference instructions:

```
Task(subagent_type: "prototype-generator", prompt: "Generate a React prototype for the feature '{feature}'. dslDir: docs/specs/{feature}/ui-dsl/. feature: {feature}. Read manifest.json and all screen-*.json files. Scaffold a Vite + React 19 + TypeScript + TailwindCSS + shadcn/ui project at src/prototypes/{feature}/ using React Router v7. Generate page components, mock data, and router setup with Lucide icons, then bundle into a single standalone HTML file using the bundle-artifact.sh script.{IF stitch completed: ' Also read Stitch wireframe outputs from docs/specs/{feature}/stitch-wireframes/ — use design-tokens.json for Tailwind theme, shadcn-mapping.json for component hints, HTML files for visual layout reference.'}")
```

3. On success, update progress:
   ```json
   {
     "design.stages.prototype": {
       "status": "completed",
       "path": "src/prototypes/{feature}/",
       "artifact": "src/prototypes/{feature}/bundle.html",
       "bundleStatus": "current",
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

  Stage 1   — DSL Generation:      {status} — {screenCount} screens
  Stage 1.5 — Stitch Wireframes:   {status} — {screenCount} screens / {reason for skip}
  Stage 2   — Prototype:           {status} — {path}
  Stage 3   — Figma:               {status} — {url or reason for skip}

Next Steps:
  - Open `src/prototypes/{feature}/bundle.html` in a browser to preview the prototype
  - Run `cd src/prototypes/{feature} && npm run dev` for live development (Vite dev server)
  - Run `/planning-plugin:design {feature} --stage=stitch` to generate Stitch wireframes (requires Stitch MCP)
  - Run `/planning-plugin:design {feature} --stage=figma` to generate Figma designs (requires Figma MCP)
  - Edit prototype files directly to refine the UI before Figma generation
  - Run `/planning-plugin:design {feature} --stage=dsl` to regenerate DSL from updated screens.md
```

If `design-system/MASTER.md` does not exist, prepend this to the Next Steps:
```
  - Run `/planning-plugin:design-system --domain={domain}` to generate a design system — this enhances DSL icon accuracy, pattern validation, and prototype theming
```

Adjust the "Next Steps" based on which stages were completed or skipped.

## Error Handling

- If an agent fails, report the error and ask the user whether to retry or skip that stage
- If a prerequisite check fails, stop with a clear message and suggested fix
- Never leave the progress file in an inconsistent state — always update before stopping
- If the user interrupts mid-flow, save current state to the progress file
