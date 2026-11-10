# v2-init: External skills, dependency commands and the app shell

Part of the `v2-init` skill. `{pluginRoot}` is the plugin root the skill states.

### Step 4: Install External Skills

Install the following external skills. For each skill, check if it already exists; install only if missing.

**React Router special handling**: the modes to install are the set of merged `routerMode` values across all apps (one app → one mode). If this is a reconfiguration and a previous mode is no longer in that set, remove its skill first; keep it while any app still uses it:
```bash
rm -rf .claude/skills/react-router-{previousMode}-mode
```
The Check Path/Install Command interpolate `{routerMode}` — for `framework` this resolves to
`react-router-framework-mode`, no special-casing needed.

| Skill | Check Path | Install Command | Install when |
|-------|-----------|-----------------|--------------|
| React Router (one per distinct `routerMode` across the apps; keep one another app still uses) | `.claude/skills/react-router-{routerMode}-mode/SKILL.md` | `npx skills add remix-run/agent-skills --skill react-router-{routerMode}-mode -a claude-code -y --copy` | always |
| Vitest | `.claude/skills/vitest/SKILL.md` | `npx skills add antfu/skills --skill vitest -a claude-code -y --copy` | always |
| React Best Practices | `.claude/skills/vercel-react-best-practices/SKILL.md` | `npx skills add vercel-labs/agent-skills --skill vercel-react-best-practices -a claude-code -y --copy` | always |
| Composition Patterns | `.claude/skills/vercel-composition-patterns/SKILL.md` | `npx skills add vercel-labs/agent-skills --skill vercel-composition-patterns -a claude-code -y --copy` | always |
| Web Design Guidelines | `.claude/skills/web-design-guidelines/SKILL.md` | `npx skills add vercel-labs/agent-skills --skill web-design-guidelines -a claude-code -y --copy` | always |
| Agent Browser | `.claude/skills/agent-browser/SKILL.md` | `npx skills add vercel-labs/agent-browser --skill agent-browser -a claude-code -y --copy` | `e2eTool == agent-browser` only |

For each row:
1. Check if the Check Path file exists
2. If missing (and the "Install when" condition holds), run the Install Command
3. Verify installation succeeded

Skip the Agent Browser row when `e2eTool == playwright` (Playwright ships no loadable skill — trace
analysis is built into the CLI).

### Step 4a: Print New-Stack Dependency Commands (never auto-install)

Print the `pnpm add` lines for the packages implied by the selected knobs, only for packages not already
in `package.json`. **Never install** — display and continue (same rule as ESLint). Skip the whole step for
an admin-default config (no new-stack packages).

| Enabled by | Command |
|---|---|
| `routerMode == framework` | `pnpm add @react-router/dev @react-router/node @react-router/serve isbot` |
| `serverState == tanstack-query` | `pnpm add @tanstack/react-query && pnpm add -D @tanstack/react-query-devtools` |
| `formStack == rhf-zod` | `pnpm add react-hook-form zod @hookform/resolvers` |
| `e2eTool == playwright` | `pnpm add -D @playwright/test` then one-time `npx playwright install` (browser binaries — print, never run) |
| `appProfile == ota` | `pnpm add dayjs` |
| `componentLibrary == external` | `pnpm add {externalComponents.package}` (+ `pnpm add {externalComponents.cssEntry}` when set) — or the project's `pnpm link` equivalent while the package is unpublished |

Under `clientStore == none` no `zustand` line is ever printed.

### Step 4b: App Shell Check (framework mode only)

When `routerMode == framework`, verify the RR framework app shell exists (glob):
`{appDir}/react-router.config.ts`, `{baseDir}/root.tsx`, `{baseDir}/routes.ts`, `{baseDir}/entry.server.tsx`,
`{baseDir}/entry.client.tsx`.
- If all present → nothing to do.
- If any absent → offer to scaffold them from `{pluginRoot}/templates/framework-app-shell.md`, or point the user to
  `npx create-react-router@latest`. Do not overwrite existing files.

`react-router.config.ts` and the generated `.react-router/` types dir live in `{appDir}` (path-base rule);
`routes.ts`/`root.tsx`/entry files live under `{baseDir}`.

### Step 4c: E2E Permission and CLI Check

**E2E permission setup** (after skill installation) — keyed on `e2eTool`:

The e2e-test-runner agent runs the E2E tool via Bash in a sub-agent session. Sub-agents may not inherit
session-level permissions, so a project-level permission rule is required. Add the rule for the selected
tool:
- `e2eTool == agent-browser` → `"Bash(agent-browser *)"`
- `e2eTool == playwright` → `"Bash(npx playwright *)"`

1. Read `.claude/settings.json` (create if absent)
2. Check if `permissions.allow` already contains the rule for the selected tool:
   - If present → skip
   - If absent → add it to the `permissions.allow` array
3. Write the updated `.claude/settings.json`

Example result (playwright):
```json
{
  "permissions": {
    "allow": [
      "Bash(npx playwright *)"
    ]
  }
}
```

> Merge rule: preserve all existing fields in settings.json — only add to the `permissions.allow` array.

**E2E CLI check** (after skill installation) — keyed on `e2eTool`:
- `agent-browser`:
  ```bash
  agent-browser --version 2>&1
  ```
  If not found, display (informational only — do not block):
  > "agent-browser CLI not installed. E2E testing requires it. Install with:"
  > "  npm i -g agent-browser | brew install agent-browser | cargo install agent-browser"
- `playwright`:
  ```bash
  npx playwright --version 2>&1
  ```
  If not found or browser binaries missing, display (informational only — do not block):
  > "Playwright not ready. Run: pnpm add -D @playwright/test && npx playwright install"
