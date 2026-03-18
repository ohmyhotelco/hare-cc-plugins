---
name: fe-init
description: Initialize Frontend React Plugin configuration for the current project. Sets React Router mode.
argument-hint: ""
user-invocable: true
allowed-tools: Read, Write, Glob, Bash
---

# Initialize Frontend React Plugin

Set up the Frontend React Plugin configuration for this project.

## Instructions

### Step 1: Check Existing Configuration

1. Check if `.claude/frontend-react-plugin.json` already exists in the current project directory
2. If it exists, read the current configuration and show it to the user:
   > "Frontend React Plugin is already configured:"
   > ```json
   > { current config contents }
   > ```
   > "Do you want to reconfigure? This will overwrite the existing settings."
3. If the user declines, stop here
4. If reconfiguring, remember the current `routerMode` as `previousMode` for Step 4

### Step 2: Ask for Router Mode

Ask the user which React Router v7 mode to use.

Present options:
- **declarative** (default) — `<BrowserRouter>`, `<Routes>`, `<Route>`, `<Outlet>` pattern
- **data** — `createBrowserRouter`, `RouterProvider`, loader/action pattern

Default: `declarative`

Note: The router mode determines which React Router patterns and constraints the plugin enforces.

### Step 2b: Ask for Mock-First Development

Ask the user whether to enable mock-first development with MSW v2.

Present:
- **yes** (default) — Enable network-level mocking with MSW v2. Develop without a backend. Toggle with `VITE_ENABLE_MOCKS=true`.
- **no** — Use only real APIs without a mock layer

Default: `yes` (mock-first enabled)

Note: Mock-first does not modify production code (Axios services). MSW intercepts requests at the network level, so once the backend is ready, you only need to remove the environment variable.

### Step 2c: Ask for Source Directory Path

Ask the user for the base source directory path.

Present:
- **app/src** (default) — Monorepo-friendly structure (app/src/features/, app/src/layouts/, etc.)
- Custom path — e.g., `src`, `packages/web/src`

Default: `app/src`

Note: This sets the root directory for all generated source code (features, layouts, mocks, locales, etc.). The `@/` path alias in tsconfig should map to this directory.

### Step 3: Write Configuration

1. Ensure the `.claude/` directory exists in the project root
2. Write the configuration file to `.claude/frontend-react-plugin.json`:

```json
{
  "routerMode": "{selected mode}",
  "mockFirst": {true or false based on Step 2b},
  "baseDir": "{selected path from Step 2c}"
}
```

### Step 4: Install External Skills

Install the following external skills. For each skill, check if it already exists; install only if missing.

**React Router special handling**: If this is a reconfiguration and the mode changed (previousMode exists and differs from selected mode), remove the previous mode's skill first:
```bash
rm -rf .claude/skills/react-router-{previousMode}-mode
```

| Skill | Check Path | Install Command |
|-------|-----------|-----------------|
| React Router | `.claude/skills/react-router-{routerMode}-mode/SKILL.md` | `npx skills add remix-run/agent-skills --skill react-router-{routerMode}-mode -a claude-code -y --copy` |
| Vitest | `.claude/skills/vitest/SKILL.md` | `npx skills add antfu/skills --skill vitest -a claude-code -y --copy` |
| React Best Practices | `.claude/skills/vercel-react-best-practices/SKILL.md` | `npx skills add vercel-labs/agent-skills --skill vercel-react-best-practices -a claude-code -y --copy` |
| Composition Patterns | `.claude/skills/vercel-composition-patterns/SKILL.md` | `npx skills add vercel-labs/agent-skills --skill vercel-composition-patterns -a claude-code -y --copy` |
| Web Design Guidelines | `.claude/skills/web-design-guidelines/SKILL.md` | `npx skills add vercel-labs/agent-skills --skill web-design-guidelines -a claude-code -y --copy` |

For each row:
1. Check if the Check Path file exists
2. If missing, run the Install Command
3. Verify installation succeeded

### Step 5: Confirm

Display:

```
Frontend React Plugin configured successfully!

  Router mode: {routerMode}
  Mock-first: {enabled or disabled}
  Base dir: {baseDir}

  External skills installed:
    - .claude/skills/react-router-{routerMode}-mode (React Router v7)
    - .claude/skills/vitest (Vitest testing)
    - .claude/skills/vercel-react-best-practices (React performance)
    - .claude/skills/vercel-composition-patterns (Composition patterns)
    - .claude/skills/web-design-guidelines (Web UI audit)

  Config file: .claude/frontend-react-plugin.json
```

### Step 6: Next Steps

> "Setup complete. To generate your first feature:"
> "1. Initialize planning plugin (if not done): `/planning-plugin:init`"
> "2. Create a functional spec: `/planning-plugin:spec {feature}`"
> "3. Create an implementation plan: `/frontend-react-plugin:fe-plan {feature}`"
> "4. Generate code (TDD): `/frontend-react-plugin:fe-gen {feature}`"
