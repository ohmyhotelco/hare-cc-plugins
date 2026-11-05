# fe-gen: Playwright harness preflight

Part of the `fe-gen` skill. `{pluginRoot}` is the plugin root the skill states.

### Step 1.9: Playwright Harness Preflight (every mode)

When `e2eTool == "playwright"`:

**Both files present → validate, don't skip blindly.** Read `playwright.config.ts`'s `webServer`
line and compare against the current config: port ≠ `devPort`, or command family ≠ `routerMode`
(Vite command in a framework project, or vice versa) → **stop** with:
> "playwright.config.ts serves port {baked} via {baked command}; config now says devPort {devPort} /
> routerMode {routerMode}. Align `.claude/frontend-react-plugin.json` or edit playwright.config.ts,
> then re-run."
Scaffolding writes only absent files, so a later config change can never propagate into an existing
config on its own — without this check the runner trusts a port the config stopped naming, and with
`reuseExistingServer` that can silently test an unrelated server. (Stopping, not rewriting: the
config may be user-owned, and clobbering it is worse than asking.)

**Either file absent** (check both — fe-e2e requires both, and the config alone is not proof of a
complete harness) → scaffold now, before any phases:

```
Agent(subagent_type: "frontend-react-plugin:foundation-generator", prompt: "
  Scaffold the Playwright harness only.

  Parameters:
  - mode: playwright-harness-only
  - e2eTool: playwright
  - routerMode: {routerMode — Step 5c picks the webServer dev command from the router-mode matrix; omitting this defaults to declarative and bakes a Vite command into a framework project's config}
  - appDir: {appDir}
  - devPort: {devPort — from config, default 5173}
  - projectRoot: {cwd}
  - baseDir: {baseDir}
  - srcPath: {srcPath}
  - localesDir: {localesDir}
")
```

`mode: playwright-harness-only` runs the agent's Step 5c and nothing else — launching it without
the mode would execute a full foundation phase (layouts, types, mocks) outside phase-state
tracking, which is exactly what a delta/resume preflight must not do.

**On return:** require `status: "completed"` and then **glob both files yourself** —
`{appDir}/playwright.config.ts` and `{appDir}/e2e/fixtures.ts`. Either missing (or a failed
status) → stop before any phases with the report's error; continuing would hand `fe-e2e` the exact
"harness not found" refusal this preflight exists to prevent. Nothing is recorded in
generation-state — the harness is app-level, and the files themselves are the state. This runs in
**full, delta, and resume modes alike**: delta delegates its foundation phase to `delta-modifier`
and resume skips completed phases, so without this preflight the fe-init reconfiguration message
("the next fe-gen run scaffolds it") is a promise those two modes silently break — the user follows
the remedy, it "succeeds", and `fe-e2e` still refuses.
