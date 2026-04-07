---
name: sync-stitch
description: "Use when wireframes were manually edited on the Stitch website and need to be re-fetched to the local project."
argument-hint: "[feature-name] [--screen=screen-id]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash,
  mcp__stitch__list_screens, mcp__stitch__get_screen, mcp__stitch__get_project,
  mcp__stitch__list_projects
---

# Sync Stitch Wireframes

Re-fetch wireframe content from Stitch for: **$ARGUMENTS**

## Instructions

### Step 0: Read Configuration

1. Read `.claude/planning-plugin.json` from the current project directory
2. If the file does not exist, stop with:
   > "Planning Plugin is not configured for this project. Run `/planning-plugin:init` to set up."
3. Extract `workingLanguage` (default: `"en"` if field is absent)
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill (summaries, questions, feedback presentations, next-step guidance) must be in {workingLanguage_name}.

### Step 1: Parse Arguments & Validate

1. Parse `feature` from arguments (required, kebab-case)
2. Parse optional `--screen=<screen-id>` flag — if provided, only sync that single screen
3. Verify `docs/specs/{feature}/stitch-wireframes/stitch-manifest.json` exists. If not, stop with:
   > "No Stitch wireframes found for '{feature}'. Run `/planning-plugin:design {feature} --stage=stitch` to generate wireframes first."
4. Read and parse `stitch-manifest.json` — extract `stitchProject.projectId`, `screens` array, and `stitchProject.designTheme`

### Step 2: Verify Stitch MCP Connectivity

1. Call `get_project` with `name: "projects/{projectId}"` (using the project ID from the manifest)
2. If the tool is unavailable or returns an error, stop with:
   > "Stitch MCP is not available. Run: `claude mcp add stitch --transport http https://stitch.googleapis.com/mcp --header \"X-Goog-Api-Key: <key>\" -s user`"
3. Store the updated `designTheme` from the project response (it may have changed on the website)

### Step 3: Compare Screens

1. Call `list_screens` with `projectId` from the manifest
2. Build a Stitch screen map: `{ stitchScreenId → screenTitle }` from the API response
3. Compare against the manifest's `screens` array:
   - **Matched**: screens present in both manifest and Stitch (by `stitchScreenId`)
   - **New**: screens in Stitch but not in the manifest
   - **Deleted**: screens in the manifest but not in Stitch
4. **Variant pattern detection**: If there are both deleted AND new screens,
   check if it's a variant scenario:
   a. Group new screens by title: `{ normalizedTitle → [screenEntries] }`
   b. For each deleted manifest screen, find new screen group(s) whose title
      contains (or closely matches) the manifest screen's `title`
   c. If >= 50% of deleted screens have at least one matching new screen group,
      this is a variant pattern
5. If variant pattern is detected:
   a. If `--screen=<screen-id>` was provided, narrow scope: only consider the
      deleted screen matching that ID and its variant group. If the specified
      screen is not in the deleted list, skip variant adoption and proceed to
      item 7 (normal --screen sync of matched screens)
   b. Log: "Detected variant pattern: {n} original screens → {m} variant screens."
   c. Proceed to **Step 3b: Variant Adoption**
6. If NOT a variant pattern (normal new/deleted only), keep existing behavior:
   > "Found {n} new screen(s) and {m} deleted screen(s) in Stitch. New: [{titles}]. Deleted: [{titles}]. These will be noted but not auto-synced. Run `/planning-plugin:design {feature} --stage=stitch` for a full regeneration."
7. If `--screen=<screen-id>` was provided:
   - Find the matching screen in the manifest by `dslScreenId` or `stitchScreenId`
   - If not found, stop with: "Screen '{screen-id}' not found in the manifest."
   - Limit the sync to only this screen
8. Otherwise, sync all **matched** screens

### Step 3b: Variant Adoption

For each deleted manifest screen, process its matching variant group:

1. **Single variant (auto-adopt)**:
   If only 1 matching new screen exists:
   a. Auto-adopt: update the manifest screen entry in-memory
      - `stitchScreenId` → variant's screen ID
      - `sourceScreen` → `projects/{projectId}/screens/{newScreenId}`
   b. Call `get_screen` to retrieve `width`, `height`
   c. Log: "Auto-adopted single variant for '{dslScreenId}': {variantTitle}"

2. **Multiple variants (batch interactive selection)**:
   If any deleted manifest screens have 2+ matching new screen groups,
   present a single batch selection prompt covering all multi-variant screens:

   **Phase A — Text summary table** (no image downloads):
   a. For each multi-variant screen, call `get_screen` for each candidate
      to retrieve `width`, `height`, and `screenshot.downloadUrl`
   b. Display a batch selection table:
      ```
      Variant Selection Required ({count} screens with multiple variants)

      Screen 1: '{dslScreenId}' ({original title})
        [1a] {variant-1-title} ({width}x{height})
        [1b] {variant-2-title} ({width}x{height})
        [1c] {variant-3-title} ({width}x{height})

      Screen 2: '{dslScreenId}' ({original title})
        [2a] {variant-1-title} ({width}x{height})
        [2b] {variant-2-title} ({width}x{height})

      Enter selections (e.g., "1a 2b") or:
        'all-first' — adopt first variant for all
        'preview 1' — show thumbnails for Screen 1
        'preview all' — show thumbnails for all
        'skip' — leave all unresolved
      ```

   **Phase B — User response handling**:
   c. Parse user response:
      - **Direct selection** (e.g., `"1a 2b"`): adopt selected variants.
        Any screens not mentioned adopt their first variant automatically
      - **`preview N`**: download `=w400` thumbnails for the specified
        screen's variants, display using Read tool, then re-show the
        selection prompt (allow up to 2 preview rounds total):
        ```bash
        curl -sL "{screenshot.downloadUrl}=w400" \
          -o /tmp/stitch-variant-{stitchScreenId}.png
        ```
        (Note: `=w400` is for lightweight preview only.
        Step 4 uses `=w{width}` for full-resolution final download.)
      - **`preview all`**: download `=w400` thumbnails for all
        multi-variant screens, display using Read tool, then re-show
        the selection prompt (allow up to 2 preview rounds total)
      - **`all-first`**: adopt the first variant for every multi-variant
        screen
      - **`skip`**: leave all multi-variant screens unresolved (manifest
        entries unchanged with old, now-hidden stitchScreenIds)
   d. For each adopted variant, update the manifest screen entry in-memory:
      - `stitchScreenId` → variant's screen ID
      - `sourceScreen` → `projects/{projectId}/screens/{newScreenId}`

3. **Unmatched new screens**:
   Report any new screens that don't match any deleted manifest screen:
   > "New screen '{title}' has no matching manifest entry. Skipping."
   > "To add new screens, run `/planning-plugin:design {feature} --stage=stitch`"

4. **Unmatched deleted screens**:
   Report any deleted manifest screens that have no matching variants:
   > "No variants found for '{dslScreenId}'. This screen will remain
   > unsynced with a stale reference."

5. Build the final sync list by combining:
   - Adopted variants (auto + manually selected) from this step
   - Matched screens from Step 3 (screens still present in both manifest and Stitch)
   - If `--screen` was provided, filter this combined list to only that screen
   → continue to Step 4 (Re-fetch Screen Content)

6. **Cleanup**: After Step 4 completes, remove temp files:
   ```bash
   rm -f /tmp/stitch-variant-*.png
   ```
   (Safe no-op if no previews were requested.)

### Step 4: Re-fetch Screen Content

For each screen to sync:

1. Call `get_screen` with `name: "projects/{projectId}/screens/{stitchScreenId}"`, `projectId`, and `screenId` to retrieve full metadata
   - Update `width` and `height` from the response
   - Update `sourceScreen` resource path

2. Download HTML code from `get_screen` response's `htmlCode.downloadUrl`:
   ```bash
   curl -sL "{htmlCode.downloadUrl}" -o docs/specs/{feature}/stitch-wireframes/{dslScreenId}.html
   ```
   - If the download fails (empty file or curl error), log a warning and skip this screen:
     > "Warning: Failed to fetch code for screen '{dslScreenId}'. Skipping."

3. Download PNG screenshot from `get_screen` response's `screenshot.downloadUrl`:
   - Append `=w{width}` using the screen's width from `get_screen` for high-resolution download:
     ```bash
     curl -sL "{screenshot.downloadUrl}=w{width}" -o docs/specs/{feature}/stitch-wireframes/{dslScreenId}.png
     ```
   - Do NOT use the Write tool for PNG files — it handles text only and will corrupt binary data
   - **File size validation**: After writing each PNG, check file size:
     ```bash
     stat -f%z docs/specs/{feature}/stitch-wireframes/{dslScreenId}.png
     ```
     If a desktop-width screen (width >= 1440) produces a PNG under 100KB, log a warning: the image may be a low-resolution thumbnail. Consider re-downloading with an explicit `=w{width}` suffix.
   - If the download fails, log a warning and continue:
     > "Warning: Failed to fetch screenshot for screen '{dslScreenId}'. HTML was updated but PNG is stale."

4. Track which screens were successfully synced

### Step 5: Regenerate Design Tokens

1. Pick a representative screen (first layout screen if available, otherwise first synced screen)
2. Parse all updated HTML files directly to extract design tokens:
   - Scan CSS for color declarations → map to semantic roles (`primary`, `secondary`, `accent`, `background`, `foreground`, `muted`, `border`, `destructive`)
   - Extract font-family, font-size, font-weight values
   - Extract spacing (margin, padding, gap) and border-radius values
3. If a single screen lacks certain tokens (e.g., `destructive`), scan additional screens' HTML for red-toned colors
4. Merge and deduplicate across all parsed HTML files
5. Write `docs/specs/{feature}/stitch-wireframes/design-tokens.json` in this format:
```json
{
  "colors": {
    "primary": "#...",
    "secondary": "#...",
    "accent": "#...",
    "background": "#...",
    "foreground": "#...",
    "muted": "#...",
    "border": "#...",
    "destructive": "#..."
  },
  "typography": {
    "fontFamily": { "sans": "...", "mono": "..." },
    "fontSize": { "xs": "...", "sm": "...", "base": "...", "lg": "...", "xl": "...", "2xl": "...", "3xl": "..." },
    "fontWeight": { "normal": "...", "medium": "...", "semibold": "...", "bold": "..." }
  },
  "spacing": ["4px", "8px", "12px", "16px", "24px", "32px", "48px"],
  "borderRadius": { "sm": "...", "md": "...", "lg": "..." }
}
```

### Step 6: Regenerate DESIGN.md

Generate a natural-language design document from the updated wireframes. Synthesize from HTML/CSS analysis of the representative and other synced screens.

Write to `docs/specs/{feature}/stitch-wireframes/DESIGN.md`:

```markdown
# {Feature} Design Language

## Visual Theme & Atmosphere
{2-3 sentences describing the overall mood, visual style, and design philosophy.
Use design language, not technical terms.}

## Color Palette
{List each color with descriptive name, hex code, and functional role.}

## Typography
{Describe font choices in design terms — headings, body text, monospace, scale.}

## Component Styling
{Describe the visual character of UI elements in natural language — cards, buttons, inputs, tables, badges.}

## Layout Principles
{Describe spatial organization in design terms — spacing, alignment, rhythm, navigation placement.}
```

**Rules**:
- Use descriptive design language, not CSS values (`"subtly rounded corners"` not `"border-radius: 8px"`)
- Every color entry must include descriptive name + hex + functional role
- Base content on actual HTML/CSS analysis — do not fabricate values
- If design system files exist at `design-system/pages/`, reference them for consistent terminology

### Step 7: Regenerate shadcn/ui Mapping

Analyze the updated Stitch-generated HTML elements and map them to shadcn/ui components:

1. For each distinct UI element in the HTML, identify the closest shadcn/ui equivalent
2. Note visual properties (sizing, spacing, variants) that should carry over
3. Map CSS class patterns to Tailwind utility classes

Write `docs/specs/{feature}/stitch-wireframes/shadcn-mapping.json`:
```json
{
  "mappings": [
    {
      "stitchElement": "div.card-container",
      "shadcnComponent": "Card",
      "notes": "rounded-lg shadow-sm border, use CardHeader + CardContent",
      "tailwindClasses": "rounded-lg shadow-sm border p-6"
    }
  ],
  "layoutPatterns": [
    {
      "screen": "screen-id",
      "pattern": "flex flex-col gap-6",
      "sections": ["header with search + action button", "data table", "pagination"]
    }
  ]
}
```

### Step 8: Update Manifest

Read and update `docs/specs/{feature}/stitch-wireframes/stitch-manifest.json`:

1. Update `generatedAt` to current ISO-8601 UTC timestamp
2. Update `stitchProject.designTheme` from the `get_project` response (Step 2)
3. For each synced screen, update:
   - `width` and `height` from `get_screen` response
   - `sourceScreen` resource path
4. Keep `designTokensFile`, `designDocFile`, and `shadcnMappingFile` references unchanged
5. Write the updated manifest

### Step 9: Update Progress File

1. Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`
2. Set `design.stages.stitch.status` to `"completed"`
3. Set `design.stages.stitch.screenCount` to the number of successfully synced screens
4. Set `design.stages.stitch.generatedAt` to current ISO-8601 UTC timestamp
5. If a prototype stage exists (`design.stages.prototype`):
   - Set `design.stages.prototype.bundleStatus` to `"stale"` (prototype needs rebuild with updated wireframes)
6. Write the updated progress file

### Step 10: Report Summary

Display a summary:

```
Stitch Sync Complete for '{feature}'

Screens synced: {count}/{total}
  {list of synced screen IDs}

{If any screens failed:}
Screens skipped (fetch errors):
  {list of failed screen IDs with reasons}

{If variant adoption was performed:}
Variant adoption:
  Auto-adopted (single variant): {count}
    {list of dslScreenIds}
  Manually selected: {count}
    {list of dslScreenIds with selected variant title}
  Skipped: {count}
    {list of skipped dslScreenIds}
  Unmatched new screens: {count}
    {list of titles}

{If new/deleted screens detected (non-variant):}
Note: {n} new and {m} deleted screens detected in Stitch.
  Run /planning-plugin:design {feature} --stage=stitch for full regeneration.

Updated artifacts:
  - HTML/PNG wireframes: docs/specs/{feature}/stitch-wireframes/
  - Design tokens: design-tokens.json
  - Design language: DESIGN.md
  - shadcn mapping: shadcn-mapping.json
  - Manifest: stitch-manifest.json

{If prototype exists and bundleStatus was set to stale:}
Prototype bundle is now STALE. Next steps:
  /planning-plugin:prototype {feature}                  (regenerate prototype with updated wireframes)
  /planning-plugin:bundle {feature}                    (rebuild bundle only, without regenerating prototype)

{If no prototype:}
Next steps:
  /planning-plugin:prototype {feature}                  (generate prototype from updated wireframes)
```
