---
name: fo-visual
description: Visual gate for one generated screen — captures every planned state at each configured viewport × language through a Playwright spec, checks breakage (overflow, console errors, broken images, clipped text, DS responsive boundary), compares captures with their Figma frames where frames exist, and writes docs/gates/<app>/<screen>/visual.json. Use after fo-verify passes.
argument-hint: "--app <name> --screen <id> [--no-figma]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Workflow
---

# fo-visual — visual gate

The answer key is Figma for the states that have frames and a breakage check for everything else
(V3 plan decision 10). Design-system components are verified in the DS repo; this gate judges the
screen's composition. The workflow `frontend-ohmyhotel-plugin:fo-visual` captures once and compares
each frame in parallel; this skill prepares the frame list, waits, and writes the evidence.

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`.

## Step 0 — Preconditions

Config, `--app`/`--screen`, plan, `progress.json`: `gates.verify.result` must be `pass` with a
`treeHash` equal to `fo-screen-hash --app <app> --screen <screen>` now (a visual run on unverified or
changed code records nothing useful — say so and point at `fo-verify`). Harness present
(`<app.dir>/playwright.config.ts`). Lock `visual.lock`.

## Step 1 — Frames

Read `docs/figma-manifest.json` → `screens[<screen>].frames[]` (`state`, `viewport`, `nodeId`,
`export`). A frame without an `export` file is compared inline through the Figma MCP (no committed reference
image — say so); no frames at all → run `fo-figma` first, or `--no-figma` for the breakage check alone.

## Step 2 — Run and wait

`Workflow` with `name: "frontend-ohmyhotel-plugin:fo-visual"` and
`args: { app, screen, config, planFile, outDir: "<evidenceDir>/<app>/<screen>/visual", fileKey, lang: <plan spec.primaryLanguage>, figma: frames }`
(`lang` picks which language's capture is compared with each frame; the frames are language-neutral).
Wait for the task notification; do not end the turn after announcing the run.

## Step 3 — Evidence

From the result (`result`, `capture`, `comparisons`, `framesWithoutCapture`), write the gate record:

```bash
fo-evidence --app <app> --screen <screen> --gate visual --result <pass|fail|not-run> --from <result json> --spec-path <app.dir>/e2e/visual/<screen>.spec.ts
```

(`not-run` when the capture did not run, or when a frame could not be compared — the workflow's
`result` already says which; a render error or breakage is `fail`.) Set the `visual` row in block 5
of `<Screen>.spec.md`. Release the lock.

## Step 4 — Report and next

Capture table (states × viewports × languages, breakage per capture), the comparison table (scores and
findings per frame, critical first), frames without a capture, and the suggested commit
(`gate(<screen>): visual <result>`). Next:

- pass → `/frontend-ohmyhotel-plugin:fo-e2e --app <app> --screen <screen>`
- breakage or critical divergence → `/frontend-ohmyhotel-plugin:fo-review …` then `fo-fix`
  (the findings carry `fixHint`s), then `fo-verify` and `fo-visual` again
- designer review is the manual gate after this one; name the capture folder for the reviewer

Done when the evidence file and tracker are written, the lock is released and the next command is named.
