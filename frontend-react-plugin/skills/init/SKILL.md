---
name: init
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

### Step 3: Write Configuration

1. Ensure the `.claude/` directory exists in the project root
2. Write the configuration file to `.claude/frontend-react-plugin.json`:

```json
{
  "routerMode": "{selected mode}"
}
```

### Step 4: Install React Router Skill

1. If this is a reconfiguration and the mode changed (previousMode exists and differs from selected mode), remove the previous mode's skill:
   ```bash
   rm -rf .claude/skills/react-router-{previousMode}-mode
   ```
2. Check if `.claude/skills/react-router-{selected_mode}-mode/SKILL.md` already exists
3. If it does not exist, install the external skill:
   ```bash
   npx skills add remix-run/agent-skills --skill react-router-{selected_mode}-mode -a claude-code -y --copy
   ```
4. Verify installation by checking that `.claude/skills/react-router-{selected_mode}-mode/SKILL.md` now exists

### Step 5: Install Vitest Skill

1. Check if `.claude/skills/vitest/SKILL.md` already exists
2. If it does not exist, install the external skill:
   ```bash
   npx playbooks add skill supabase/supabase --skill vitest -y
   ```
3. Verify installation by checking that `.claude/skills/vitest/SKILL.md` now exists

### Step 6: Confirm

Display:

```
Frontend React Plugin configured successfully!

  Router mode: {routerMode}
  React Router skill: .claude/skills/react-router-{routerMode}-mode (installed)
  Vitest skill: .claude/skills/vitest (installed)

  Config file: .claude/frontend-react-plugin.json

Next steps:
  - The plugin will enforce conventions based on this setting
  - Edit .claude/frontend-react-plugin.json anytime to change settings
  - Run /frontend-react-plugin:init to reconfigure interactively
```
