---
name: fo-figma
description: Record a screen's Figma frames (state × viewport node ids) in docs/figma-manifest.json through the Figma MCP and export them to PNG with bin/fo-figma-export when FIGMA_TOKEN is set, so fo-plan can cite them and fo-visual can compare against them. Use before fo-plan on screens that have a design.
argument-hint: "--app <name> --screen <id> [--page <figma page>|--node <id>] [--file-key <key>]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# fo-figma — the view's answer key

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`.

## Step 0 — Preconditions

Config with `answerKeys.figma.manifest`; the manifest exists (`fo-init` creates `{ "fileKey": null, "screens": {} }`).
`fileKey`: from the manifest, `--file-key`, or ask once and store it in the manifest. The Figma
MCP must be connected in this session (a tool named `mcp__figma*__get_metadata` is available);
without it, say so and stop — there is no non-MCP discovery path. `FIGMA_TOKEN` in the environment
enables the PNG export; without it the frames are recorded without files (say so; the token is
never asked for in chat and never written to a file). Lock `figma.lock`.

`--page`/`--node`: the Figma page (e.g. `UI_Main`) or node the designer named for this screen; ask
when neither is given and the manifest has no `page` for the screen.

## Step 1 — Run and wait

Start one `Agent` with `subagent_type: frontend-ohmyhotel-plugin:figma-extractor` and its inputs
(`app`, `screen`, `config`, `planFile` when a plan exists, `manifest`, `fileKey`, `pageOrNode`,
`outDir: <evidenceDir>/<app>/<screen>/figma`, `mcpToolPrefix`). Wait for the completion notification.

## Step 2 — Record, report, next

`progress.json` under the screen: `figma: { recordedAt, frames, exported, missing }`. Release the
lock. Report the coverage table (states × viewports: frame / exported / missing), unmatched frames,
the naming rule inferred, and the suggested commit (`figma(<screen>): <n> frames`). Missing frames
are a request to the designer — list them in a form that can be pasted into the design ticket. Next:

- plan not yet written → `/frontend-ohmyhotel-plugin:fo-plan --app <app> --screen <screen>`
- plan exists → `fo-plan` again only if the frame set changed what the plan cites; otherwise
  `/frontend-ohmyhotel-plugin:fo-visual …` when the screen is generated

Done when the manifest is written, the tracker is updated, the lock is released and the next command
is named.
