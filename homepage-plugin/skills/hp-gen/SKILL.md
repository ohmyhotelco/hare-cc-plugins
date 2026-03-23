---
name: hp-gen
description: "Generate Astro pages and sections from page plans. Run /homepage-plugin:hp-plan first."
argument-hint: "[page-name]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Code Generation Skill (3-Phase Pipeline)

Generates Astro pages, sections, and shared infrastructure from page plans (`page-plan.json`). Each phase runs in a separate agent session for context isolation.

> **Tool choice**: This skill uses `Agent` (not `Task`) to launch sub-agents. Phases are strictly sequential — each depends on the previous phase's output.

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
1. Read `docs/pages/{page-name}/.implementation/homepage/generation-state.json`
2. If `phases.infrastructure.status === "completed"` → skip Phase 1
3. For Phase 2, check each page's status — skip pages already marked as `completed`, resume from first `pending` or `failed` page
4. Ask user: "Resume from {phase/page}? Or restart from scratch?"

### Step 3: Acquire Lock

Lock file path: `docs/pages/{page-name}/.implementation/homepage/.lock`

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
   - If age < 30 minutes → exit with "Another homepage-plugin operation is in progress"
   - If age >= 30 minutes → delete stale lock, log warning, proceed to step 3
3. Write new `.lock` file with `lockedBy: "hp-gen"`, `lockedAt: new Date().toISOString()`, `pageName`

**Release**: Always delete `.lock` file on completion or failure (in Step 8 and Error Handling).

### Step 4: Confirm with User

Display the generation plan:
- Pages to generate
- Sections per page (static vs island)
- Shared infrastructure to create (if first page)
- Estimated components to generate

Ask user to confirm before proceeding.

### Step 5: Phase 1 — Infrastructure

Determine if this is the first page being generated (no existing layout/shared components).

Launch `page-assembler` agent with the following parameters:
- `pageName` — `"_infrastructure"` (special value for infrastructure phase)
- `planFile` — path to the first page's `page-plan.json`
- `layoutPlanFile` — `docs/pages/_shared/layout-plan.json`
- `projectRoot` — project root path
- `config` — homepage-plugin configuration object
- `isFirstPage` — `true`

The agent generates:
- MarketingLayout.astro
- Header.astro + Footer.astro + MobileNav.tsx
- SEO utilities (structured-data.ts)
- i18n setup (utils.ts + translation files)
- Global styles (globals.css)
- Content Collection config (if MDX enabled)
- ESLint config (if eslintTemplate enabled and no config exists)

Update `generation-state.json`:
```json
{
  "phases": {
    "infrastructure": { "status": "completed", "completedAt": "..." }
  }
}
```

### Step 6: Phase 2 — Sections & Pages

For each page (sequential):

1. Launch `section-generator` agent with:
   - `pageName` — page identifier
   - `planFile` — path to `docs/pages/{page-name}/page-plan.json`
   - `projectRoot` — project root path
   - `config` — homepage-plugin configuration object

   The agent will:
   - Generate all sections for this page
   - Skip sections marked as `reuse: true`
   - Generate React islands for interactive sections

2. Launch `page-assembler` agent with:
   - `pageName` — page identifier
   - `planFile` — path to `docs/pages/{page-name}/page-plan.json`
   - `layoutPlanFile` — `docs/pages/_shared/layout-plan.json`
   - `projectRoot` — project root path
   - `config` — homepage-plugin configuration object
   - `isFirstPage` — `false`

   The agent will:
   - Assemble page from generated sections
   - Add SEO metadata + JSON-LD
   - Wire i18n translations

Update `generation-state.json` after each page:
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
     1. Read the plugin's `templates/eslint-config.md`
     2. Extract the JavaScript code block from the "Canonical Config" section
     3. Write it to `{projectRoot}/eslint.config.js` using the Write tool
     4. Check dependencies: `pnpm ls eslint @eslint/js typescript-eslint eslint-plugin-astro eslint-plugin-react-hooks globals 2>&1`
     5. If any dependency missing: display `pnpm add -D eslint @eslint/js typescript-eslint eslint-plugin-astro eslint-plugin-react-hooks globals` and **skip ESLint** (do not run)
     6. If all present: run `npx eslint . 2>&1`
   - If `eslintTemplate` is false and no config exists: skip ESLint entirely
3. **Astro build** — `npx astro build`

### Step 8: Update Progress

For each page, update `docs/pages/{page-name}/.progress/{page-name}.json`:

- All verifications pass → status: `generated`
- Any verification fails → status: `gen-failed`

Record verification results and timestamps.

Release the lock file.

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

## Error Handling

- If an agent fails, record the failure in `generation-state.json` and continue to the next page
- If infrastructure generation fails, abort all subsequent pages (infrastructure is a prerequisite)
- Always release the lock file, even on failure
