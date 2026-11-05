---
name: hp-gen
description: "Generate Astro pages and sections from page plans. Run /homepage-plugin:hp-plan first."
argument-hint: "[page-name]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Workflow
---

# Code Generation Skill (3-Phase Pipeline)

Generates Astro pages, sections, and shared infrastructure from page plans (`page-plan.json`). The `homepage-plugin:hp-gen-run` workflow runs the agents and owns their order and stop rules; this skill owns what surrounds it: preconditions, locks, the user's confirmation, verification, progress and the summary.

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/hp-shared/SKILL.md`.

## Instructions

### Step 0: Read Configuration

Read `.claude/homepage-plugin.json`. If not found, exit with instruction to run `/homepage-plugin:hp-init`.

Read `defaultLocale` — all user-facing output in this language.

### Step 1: Validate Plans

If `[page-name]` argument provided:
- Validate `docs/pages/{page-name}/page-plan.json` exists
- Generate only this page

If no argument:
- Scan `docs/pages/*/page-plan.json` for all planned pages
- If none found, exit with instruction to run `/homepage-plugin:hp-plan`

### Step 2: Check Generation State

For each page, check `docs/pages/{page-name}/.progress/{page-name}.json`:

- Status `planned` → proceed with generation
- Status `generated` or later → warn about demotion and ask to confirm re-generation
- Status `gen-failed` → check `generation-state.json` for resume opportunity

**Resume support**: If `generation-state.json` exists with incomplete phases, offer to resume from the last incomplete phase instead of starting over:
1. Read `docs/pages/_shared/generation-state.json`
2. If `phases.infrastructure.status === "completed"` and the layout still exists → skip Phase 1
3. For Phase 2, check each page's status — skip pages already marked as `completed`, resume from first `pending` or `failed` page
4. Ask user: "Resume from {phase/page}? Or restart from scratch?"

### Step 3: Acquire Lock

Take a lock for every page in the run, and one for `_shared`, because every run writes `docs/pages/_shared/generation-state.json`. Lock file path: `docs/pages/{page-name}/.implementation/homepage/.lock`

**Lock file format** (JSON):
```json
{
  "lockedBy": "hp-gen",
  "lockedAt": "2026-03-23T14:30:00.000Z",
  "pageName": "home"
}
```

**Acquisition protocol**:
1. Check if `.lock` file exists
2. If exists → read `lockedAt` field → parse as ISO-8601 → compare with current time
   - If age < 30 minutes → release any lock this run took and exit with "Another homepage-plugin operation is in progress"
   - If age >= 30 minutes → delete stale lock, log warning, proceed to step 3
3. Write new `.lock` file with `lockedBy: "hp-gen"`, `lockedAt: new Date().toISOString()`, `pageName`

**Release**: Always delete every `.lock` file this run took on completion or failure (in Step 8 and on any early exit).

### Step 4: Confirm with User

Display the generation plan:
- Pages to generate
- Sections per page (static vs island)
- Shared infrastructure to create (if first page)
- Estimated components to generate

Ask user to confirm before proceeding.

### Step 5: Run the Workflow

Make sure `docs/pages/_shared/generation-state.json` exists and lists every page in the run under `phases.pages` with status `pending`, keeping entries already there. When this run passes `infrastructure`, set `phases.infrastructure` to `pending`, so a session that dies inside that stage runs it again. `page-assembler` records each finished entry in this file, so progress survives a session that dies mid-run.

Call the `Workflow` tool with `name: "homepage-plugin:hp-gen-run"` and `args`:

- `projectRoot` — project root path
- `config` — homepage-plugin configuration object
- `stateFile` — `docs/pages/_shared/generation-state.json`
- `layoutPlanFile` — `docs/pages/_shared/layout-plan.json`
- `infrastructure` — `{ planFile }` with the first page's `page-plan.json` when no layout or shared components exist, or when `phases.infrastructure` is recorded and not `completed`; otherwise `null`
- `pages` — `[{ pageName, planFile }]` in order, leaving out pages a resume skips
- `fileKey` — Figma file key from `.claude/homepage-plugin.json` (if available)
- `mcpToolPrefix` — MCP tool prefix (auto-detect from available tools: `mcp__figma__*`, `mcp__figma_desktop__*`, or `mcp__Figma__*`)

The workflow runs `page-assembler` for the infrastructure, then `section-generator` and `page-assembler` for each page in turn. Failed infrastructure stops the run. A failed page does not stop the next one.

Tell the user what will run. The result arrives as a task notification; continue at Step 6 when it does. If the call is refused or fails, release the locks and report it.

### Step 6: Record Failures

From the workflow result, update `generation-state.json`:

- `stoppedAt: "infrastructure"` — set `phases.infrastructure` to `{ "status": "failed", "error": ... }`, skip Step 7, and treat every page in the run as failed
- each entry in `pages` with `status: "failed"` — set `phases.pages.{page}` to `{ "status": "failed", "error": ... }` from its `failedAgent` and `failure`

```json
{
  "phases": {
    "infrastructure": { "status": "completed", "completedAt": "2026-03-23T14:30:00Z" },
    "pages": {
      "home": { "status": "completed", "completedAt": "2026-03-23T14:32:00Z" },
      "about": { "status": "completed", "completedAt": "2026-03-23T14:35:00Z" },
      "contact": { "status": "failed", "error": "section-generator failed on ContactSection" }
    }
  }
}
```
Valid `status` values per phase: `"pending"`, `"completed"`, `"failed"`.

### Step 7: Phase 3 — Verification

Run verification checks:

1. **TypeScript** — `npx tsc --noEmit`
2. **ESLint** — `npx eslint .` (skip if no config and eslintTemplate is false)
   - If `eslintTemplate` is true and no ESLint config exists (no `.eslintrc*` or `eslint.config.*`):
     1. Read `${CLAUDE_PLUGIN_ROOT}/templates/eslint-config.md`
     2. Extract the JavaScript code block from the "Canonical Config" section
     3. Write it to `{projectRoot}/eslint.config.js` using the Write tool
     4. Check dependencies: `pnpm ls eslint @eslint/js typescript-eslint eslint-plugin-astro eslint-plugin-react-hooks globals 2>&1`
     5. If any dependency missing: display `pnpm add -D eslint @eslint/js typescript-eslint eslint-plugin-astro eslint-plugin-react-hooks globals` and **skip ESLint** (do not run)
     6. If all present: run `npx eslint . 2>&1`
   - If `eslintTemplate` is false and no config exists: skip ESLint entirely
3. **Astro build** — `npx astro build`

### Step 8: Update Progress

For each page, update `docs/pages/{page-name}/.progress/{page-name}.json`:

- The page failed in the workflow, or any verification fails → status: `gen-failed`
- Otherwise → status: `generated`

Record verification results and timestamps.

Release the locks.

### Step 9: Display Results

Show:
- Pages generated
- Sections created (new vs reused)
- Islands created
- Verification results (pass/fail per check)
- Next step guidance:
  - If all passed: "Run `/homepage-plugin:hp-verify` for full quality check, or `/homepage-plugin:hp-review` for code review."
  - If failures: "Fix the errors above, then re-run `/homepage-plugin:hp-gen`."

## Communication Language

Read `defaultLocale` from `.claude/homepage-plugin.json` for all user-facing output.
