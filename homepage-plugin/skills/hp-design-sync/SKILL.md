---
name: hp-design-sync
description: "Sync design tokens and component definitions from Figma into local JSON files. Requires Figma MCP."
argument-hint: "[figma-file-url]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Sync Design Tokens from Figma

Extract design tokens and component definitions from a Figma file via the official Figma MCP server, saving them as local JSON files for use by `hp-gen`.

Supports both **design system library files** and **page-based design files** (where each Figma page represents a website page with sections as child frames).

## Instructions

### Step 0: Read Configuration

Read `.claude/homepage-plugin.json`. Extract `defaultLocale` for communication language.

Language mapping:
- `ko` → Korean
- `en` → English
- `vi` → Vietnamese

### Step 1: Resolve Figma File Key

Determine the Figma file key from one of these sources (in priority order):

1. **Skill argument** — if `[figma-file-url]` was provided, extract the file key using regex: `figma\.com/(file|design)/([a-zA-Z0-9]+)`
2. **Configuration** — read `figmaFileKey` from `.claude/homepage-plugin.json`
3. **User prompt** — if neither is available, ask the user for a Figma file URL

Also extract nodeId from URL if present (query param `node-id`). This allows targeting a specific page or frame.

Once resolved, if `figmaFileKey` is not already in `.claude/homepage-plugin.json`, update the config file to add `figmaFileKey` and `figmaFileUrl` fields.

### Step 2: Verify Figma MCP Connection

#### 2.1 Tool Discovery

Check that Figma MCP tools are available. Look for tools matching any of these patterns:
- `mcp__figma__*`
- `mcp__figma_desktop__*`
- `mcp__Figma__*`

If no Figma MCP tools are found, display an error message with setup instructions:

> **Figma MCP not connected.**
>
> To set up the Figma MCP server:
> 1. Remote (recommended): Add `https://mcp.figma.com/mcp` as an MCP server
> 2. Or install the Figma desktop MCP plugin
>
> See: https://developers.figma.com/docs/figma-mcp-server/

Then exit.

Identify the exact tool name prefix (e.g., `mcp__figma__` or `mcp__figma_desktop__`) for passing to the agent.

#### 2.2 Connectivity Test

After identifying the tool prefix, perform an actual MCP call to verify the connection works:

Call `{mcpToolPrefix}get_metadata` with the `fileKey` from Step 1.

- **Success**: The tool returns file metadata (page names, node structure). Proceed to Step 3 using this response (avoids a redundant call).
- **Failure / Error / Timeout**: Display an error:

> **Figma MCP connection failed.**
>
> Tools with prefix `{mcpToolPrefix}` were found but the connection test failed.
> Error: {error message}
>
> Possible causes:
> 1. The MCP server is not running or unreachable
> 2. The Figma file key is invalid: `{fileKey}`
> 3. You don't have access to this Figma file
> 4. The MCP server needs re-authentication
>
> Try restarting the MCP server or re-adding it.

Then exit. **Do NOT proceed to the agent if the connectivity test fails.**

### Step 3: Discover File Structure and Classify Pages

Use the `get_metadata` response from Step 2.2 (do not call again — reuse the connectivity test result).

#### 3.1 Determine File Structure

Analyze the result to determine the file structure:

- **Page-based**: The file contains pages with names like "Home", "About", "Services", etc. Each page has child frames representing sections (hero, features, etc.). This is the common case for website design files.
- **Library-based**: The file contains pages with names like "Components", "Styles", "Tokens", "Primitives". This is a design system library.

#### 3.2 Classify Pages

For page-based files, classify each page into one of four categories using name pattern matching:

| Category | Name Patterns (case-insensitive) | Purpose |
|---|---|---|
| `website` | "Home", "About", "Services", "Pricing", "Contact", "Blog", "FAQ", "Landing", "Portfolio" and other website page names | Website pages with sections |
| `layout` | "Layout", "Shared", "Common", "Global", "Navigation" | Header/Footer/Nav definitions |
| `icons` | "Icons", "Iconography", "Icon Set", "Icon Library" | Icon component library |
| `components` | "Components", "Design System", "Library", "UI Kit", "Atoms", "Molecules" | Additional UI components |

Pages that do not match any non-website pattern default to `website`.

**Viewport detection**: For website pages, detect if multiple viewport variants exist. Common patterns:
- Same page name with viewport suffix: "Home - Desktop", "Home - Mobile", "Home - Tablet"
- Same page name with size suffix: "Home 1440", "Home 375", "Home 768"
- Separate pages named "Mobile", "Tablet", "Responsive"
- Frames within a page with different widths (check via `get_metadata` child frame dimensions)

If multiple viewports are detected, group them by page and record the viewport info in `selectedPages`:
```json
{ "name": "Home", "nodeId": "0:1", "pageType": "website", "viewport": "desktop", "viewportWidth": 1440 }
{ "name": "Home - Mobile", "nodeId": "0:4", "pageType": "website-mobile", "viewport": "mobile", "viewportWidth": 375, "desktopPageName": "Home" }
```

If no mobile/tablet variants are found, this is normal — the section generator will apply responsive breakpoint inference rules.

For library-based files, all pages default to `components` category.

#### 3.3 User Confirmation

Display the classified pages with their detected categories to the user:

```
Detected pages:
  [website]     Home (5 sections)
  [website]     About (3 sections)
  [layout]      Layout (Header, Footer)
  [icons]       Icons (24 components)
  [components]  Components (Card, Badge, Avatar, ...)
```

Ask:

> "Which pages should we extract? You can also change page categories if the auto-detection is wrong. (Enter page names or 'all')"

The user can:
- Select which pages to extract
- Override a page's category (e.g., reclassify a page auto-detected as `components` to `website`)

If a `nodeId` was extracted from the URL in Step 1, pre-select the corresponding page.

### Step 4: Check Existing Design System

Read `docs/design-system/design-tokens.json` if it exists.

- If it exists, show the last sync time (`extractedAt` field) and ask: **"Update existing tokens or replace entirely?"**
  - **Update** — agent merges new values with existing ones
  - **Replace** — agent overwrites completely
- If it does not exist, proceed with fresh extraction.

### Step 5: Launch Design Token Extractor Agent

Launch the `design-token-extractor` agent with the following parameters:

- `fileKey` — the Figma file key from Step 1
- `mcpToolPrefix` — the MCP tool name prefix identified in Step 2
- `selectedPages` — list of `{ name, nodeId, pageType }` objects selected by the user in Step 3. `pageType` is one of `"website"`, `"website-mobile"`, `"website-tablet"`, `"layout"`, `"icons"`, `"components"`
- `fileStructure` — `"page-based"` or `"library-based"` (from Step 3)
- `projectRoot` — current working directory
- `outputDir` — `docs/design-system/`
- `mode` — `"update"` or `"replace"` (from Step 4, default `"replace"` for fresh extraction)

### Step 6: Validate Output

After the agent completes, first check for extraction failure:

**6.0 Check for total failure:**
- If `docs/design-system/extraction-error.json` exists, read it and display the error:
  > **Design token extraction failed.**
  > {error message from the file}
  >
  > No design tokens were extracted. Check your Figma MCP connection and try again.
  Then exit without proceeding to Step 7.

**6.1 Structural validation** — verify the output files exist and are well-formed:

1. **`docs/design-system/design-tokens.json`** must exist and contain:
   - `$schema` field equal to `"design-tokens-v1"`
   - `colors` object with at least `primary`, `background`, `foreground`
   - `cssVariables` object with `:root` containing at least 10 CSS variable entries
   - `typography` object with `fontFamily`
   - `extractionStats` object

2. **`docs/design-system/component-map.json`** must exist and contain:
   - `$schema` field equal to `"component-map-v1"`
   - `pages` object with at least one page entry (for page-based files) OR `globalComponents` object (for library-based files)
   - `extractionStats` object

If structural validation fails, report which fields are missing and suggest re-running.

**6.2 Extraction coverage validation** — verify that meaningful data was extracted from Figma:

Read `extractionStats.overallCoverage` from `design-tokens.json`.

- **Coverage >= 0.5** (50%+) → proceed normally
- **Coverage < 0.5 but > 0** → display a warning:
  > **Low extraction coverage ({coverage*100}%).**
  > Most design tokens are using default values, not values from your Figma file.
  > This may indicate that the Figma file has non-standard variable naming,
  > or that some MCP tool calls failed during extraction.
  >
  > You can:
  > 1. Proceed with the current tokens (defaults will be used for missing values)
  > 2. Re-run `/homepage-plugin:hp-design-sync` to retry extraction
  >
  Ask the user whether to proceed or retry.
- **Coverage == 0** → display an error:
  > **No tokens were extracted from Figma.**
  > All values in the output are defaults. This likely means the Figma MCP
  > connection failed silently during extraction.
  >
  > Please verify your Figma MCP connection and re-run `/homepage-plugin:hp-design-sync`.
  Then exit.

**6.3 Content image validation** (page-based files only):

Read `component-map.json` and check sections that have `contentImages`:

1. For each section with `contentImages.status !== "none"`:
   - Verify that files referenced in `contentImages.images[].path` actually exist at `{projectRoot}/src/assets/{path}`
   - Count total extracted vs failed

2. If any images have `extracted: false`, display a warning:

   > **Some content images could not be extracted from Figma.**
   >
   > The following images failed to extract:
   > - {sectionType}: {role}-{index} ({nodeName}) — {error}
   > - ...
   >
   > These sections will use placeholder values during code generation. You can:
   > 1. Manually add images to `src/assets/images/{pageName}/{sectionType}/`
   > 2. Re-run `/homepage-plugin:hp-design-sync` to retry extraction
   > 3. Proceed without images — optional image props will be omitted, required ones will get a TODO comment

3. If `contentImages.extractionSummary` shows `total: 0` across all sections but image-bearing section types exist (HeroSection, TeamSection, etc.), display a note:

   > **No content images were found in the Figma sections.**
   >
   > The sections exist but no image nodes were identified. This may mean the Figma file uses placeholder shapes instead of actual images, or images are embedded differently.
   > You can add images manually to `src/assets/images/` after running `/homepage-plugin:hp-plan`.

**6.4 Layout validation** (if any selected page had `pageType: "layout"`, or `component-map.json` contains `sharedComponents`):

1. If `component-map.json` has `sharedComponents.Header` or `sharedComponents.Footer`:
   - Verify `docs/pages/_shared/layout-plan.json` exists
   - Verify screenshot files referenced in `sharedComponents[].screenshotRef` exist under `docs/design-system/`
2. If layout pages were selected but `sharedComponents` is empty or missing, display a warning:
   > **No layout components were detected in the layout page(s).**
   >
   > The page was classified as a layout page but no Header or Footer frames were found.
   > You can define the layout manually during `/homepage-plugin:hp-plan`.

**6.5 Icon map validation** (if any selected page had `pageType: "icons"`):

1. Verify `iconMap` exists in `component-map.json`
2. If `iconMap.unmappedCount > 0`, display a warning:
   > **{unmappedCount} icon(s) could not be mapped to Lucide icons.**
   >
   > Unmapped icons:
   > - {figmaName} — no Lucide match (custom SVG path saved)
   > - ...
   >
   > These will use inline SVG rendering during code generation.

3. If `iconMap.totalCount === 0`, display a note:
   > **No icon components were found in the icon page(s).**

**6.6 Additional components validation** (if any selected page had `pageType: "components"`):

1. Verify `additionalComponents` exists in `component-map.json`
2. Display the list of discovered additional components:
   > **Additional components extracted: {count}**
   > {ComponentName1}, {ComponentName2}, ...
3. If `additionalComponents` is empty, display a note:
   > **No additional components found beyond the standard 7 UI components.**

### Step 7: Display Summary

Show extraction results:

- File structure detected (page-based / library-based)
- Pages extracted by category:
  - Website pages (with section counts per page)
  - Layout pages (Header/Footer extracted: Y/N)
  - Icon pages (mapped/total icons)
  - Component pages (additional component count)
- Number of color tokens extracted
- Number of typography scales
- Number of sections discovered and mapped
- Number of UI components identified (Button, Input, etc.)
- Content images extracted: {extracted} / {total} across {sectionsWithImages} sections
- If any images failed: list failed images by section type
- Layout components: Header (Y/N), Footer (Y/N) — if extracted
- Layout plan pre-populated: `layout-plan.json` (Y/N) — if layout extracted
- Icons: {mapped}/{total} mapped to Lucide, {unmapped} custom — if icons extracted
- Additional components: {count} discovered — if component pages extracted

Show next step guidance:
- If layout was extracted: "Layout pre-populated from Figma. Run `/homepage-plugin:hp-plan` to review and customize header/footer definitions."
- If layout was NOT extracted: "Run `/homepage-plugin:hp-plan` to define pages, sections, and layout."
- If icons were extracted: "Icon mappings saved. Section generator will use matched Lucide icons during `/homepage-plugin:hp-gen`."
- "Run `/homepage-plugin:hp-design-sync` again to re-sync after Figma updates."

## Communication Language

Use the `defaultLocale` from the configuration for all user-facing output:
- `ko` → Korean
- `en` → English
- `vi` → Vietnamese
