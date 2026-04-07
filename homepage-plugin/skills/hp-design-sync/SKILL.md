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

### Step 3: Discover File Structure

Call `{mcpToolPrefix}get_metadata` with the `fileKey` to get a high-level node map of the entire file.

Analyze the result to determine the file structure:

- **Page-based**: The file contains pages with names like "Home", "About", "Services", etc. Each page has child frames representing sections (hero, features, etc.). This is the common case for website design files.
- **Library-based**: The file contains pages with names like "Components", "Styles", "Tokens", "Primitives". This is a design system library.

Display the discovered pages and their child frames to the user. Ask:

> "Which pages should we extract designs from? (Enter page names or 'all')"

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
- `selectedPages` — list of page names and their node IDs selected by the user in Step 3
- `fileStructure` — `"page-based"` or `"library-based"` (from Step 3)
- `projectRoot` — current working directory
- `outputDir` — `docs/design-system/`
- `mode` — `"update"` or `"replace"` (from Step 4, default `"replace"` for fresh extraction)

### Step 6: Validate Output

After the agent completes, verify the output files:

1. **`docs/design-system/design-tokens.json`** must exist and contain:
   - `$schema` field equal to `"design-tokens-v1"`
   - `colors` object with at least `primary`, `background`, `foreground`
   - `cssVariables` object with `:root` containing at least 10 CSS variable entries
   - `typography` object with `fontFamily`

2. **`docs/design-system/component-map.json`** must exist and contain:
   - `$schema` field equal to `"component-map-v1"`
   - `pages` object with at least one page entry (for page-based files) OR `globalComponents` object (for library-based files)

If validation fails, report which fields are missing and suggest re-running.

### Step 7: Display Summary

Show extraction results:

- File structure detected (page-based / library-based)
- Pages extracted (with section counts per page)
- Number of color tokens extracted
- Number of typography scales
- Number of sections discovered and mapped
- Number of UI components identified (Button, Input, etc.)

Show next step guidance:
- "Run `/homepage-plugin:hp-plan` to define pages and sections. The planner will use extracted Figma data to pre-populate section definitions."
- "Run `/homepage-plugin:hp-design-sync` again to re-sync after Figma updates."

## Communication Language

Use the `defaultLocale` from the configuration for all user-facing output:
- `ko` → Korean
- `en` → English
- `vi` → Vietnamese
