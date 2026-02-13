---
name: design
description: "(Phase 2) Generate Figma screen designs from a finalized functional specification using Figma MCP."
argument-hint: "[feature-name]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Task
---

# Figma Screen Design Generator (Phase 2)

> **This skill is not yet implemented.** It will be available after Phase 2 (Figma MCP integration) is complete.

Generate Figma designs for: **$ARGUMENTS**

## Planned Workflow

1. Read the finalized spec at `docs/specs/{feature}/{workingLanguage}/{feature}-spec.md`
2. Extract the Screen Definitions section
3. Generate a screen design brief using `templates/screen-design-brief.md`
4. Launch the `figma-designer` agent to create screens in Figma via MCP

## Prerequisites (Not Yet Configured)

- [ ] Figma MCP server selected and configured in `.mcp.json`
- [ ] Figma desktop app running with MCP plugin
- [ ] Screen design brief template created
- [ ] `figma-designer` agent fully implemented

## Current Status

Run `/planning-plugin:spec` to create functional specifications first. Figma design generation will be added in Phase 2.
