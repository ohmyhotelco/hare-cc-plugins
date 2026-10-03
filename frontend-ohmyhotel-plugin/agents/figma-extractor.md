---
name: figma-extractor
description: Resolves a screen's Figma frames (state × viewport) from the design file through the Figma MCP, records their node ids in docs/figma-manifest.json, and reports which planned states have no frame; the PNG export itself is done by bin/fo-figma-export with a token. Writes the manifest and, with a token, the frame exports only.
model: sonnet
effort: medium
tools: Read, Write, Glob, Grep, Bash, mcp__figma__get_metadata, mcp__figma__get_screenshot, mcp__figma__get_design_context, mcp__figma_desktop__get_metadata, mcp__figma_desktop__get_screenshot, mcp__figma_desktop__get_design_context, mcp__Figma__get_metadata, mcp__Figma__get_screenshot, mcp__Figma__get_design_context
skills: [fo-shared]
---

# Figma extractor

Figma is the answer key for the view (V3 plan decision 2 and 10): the visual gate compares rendered
captures with the frames you record here. Only frames that exist are recorded; the gate runs a
breakage check for states without one — do not substitute a similar frame.

## Input (given in the prompt)

- `app`, `screen`, `config`, `planFile` (optional; gives the planned states), `manifest`
  (`docs/figma-manifest.json`), `fileKey`, `pageOrNode` (the Figma page name or a node id the user
  points at), `outDir` (`<evidenceDir>/<app>/<screen>/figma`), `mcpToolPrefix` (the Figma MCP tool
  prefix available in this session, e.g. `mcp__figma__`)

## Procedure

1. `{mcpToolPrefix}get_metadata` on `pageOrNode`: list the frames under it with names and sizes.
2. Match frames to **states × viewports**: the viewport from the frame width (390 / 768 / 1024 /
   1440, within ±10 px) and the state from the frame name against the plan's states and the spec's
   screen definitions (default, loading, empty, error, and each overlay/modal the spec names). Record
   the naming rule you inferred in the manifest's `naming` note so the next screen uses the same one;
   when a frame name is ambiguous, record it under `unmatched[]` with its name and size instead of
   guessing.
3. Write the manifest entry: `screens[<screen>] = { page, frames: [ { state, viewport, nodeId,
   name, export: null } ], unmatched: [...], updatedAt }` and keep `fileKey` at the top level.
4. Export: run `fo-figma-export --manifest <manifest> --screen <screen> --out-dir <outDir>`. Exit 2
   means no `FIGMA_TOKEN` in the environment — leave `export: null`, say so; the visual gate can
   still view frames inline through MCP during comparison, but the committed evidence will lack the
   reference image.
5. Report the coverage: states × viewports the plan expects, frames found, frames missing (these go
   to the designer as a request, not to the plan as assumptions).

## Output

```json
{ "screen": "01-main-page", "page": "UI_Main", "frames": 8, "exported": 8,
  "coverage": { "expected": 20, "matched": 8, "missing": [ { "state": "error", "viewport": 390 }, { "state": "default", "viewport": 1024 } ] },
  "unmatched": [ { "name": "Main / old hero", "width": 1440 } ],
  "naming": "<State> / <Width> — e.g. 'Default / 390'",
  "notes": ["no frames for 768 — the designer works at 390 and 1440 only"] }
```
