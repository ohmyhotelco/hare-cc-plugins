# v2-plan: change mode

Part of the `v2-plan` skill. `{pluginRoot}` is the plugin root the skill states. Runs under the lock
taken in § Lock Acquire; release it on every exit (§ Lock Release). Contract:
`{pluginRoot}/templates/change-plan.md`.

### C.0: Re-plan guard

`{runsDir}/{feature}/plan.json` already exists and `implementation.status` in `progress.json` is past
`planned` (generated, verified, reviewed, done, …) → warn:
> "{feature} already has generated code ({status}). Re-planning replaces the plan and resets the status
> to `planned`; the earlier reports and gate records stay in the folder but no longer describe the plan."
Ask to continue; declined → stop.

### C.1: Apps in scope

`--app a,b` → those apps. Otherwise ask which apps the ticket touches (multi-select, `defaultApp`
pre-selected). For each, take its merged `baseDir`/`appDir` (v2-shared § Monorepo Rules).
`packageDirs` — the workspace packages those apps depend on, minus `excludePaths`.

### C.2: Ticket content

If this session has a tool that reads the issue tracker (e.g. a Jira issue lookup), read `{feature}`:
summary, description, acceptance criteria, and comments that change scope. Otherwise ask the user to
paste the ticket text or a summary. Never fill a gap yourself — ask.

### C.3: Brief

`workingLanguage` = the language the user writes in (default `en`). Write
`{runsDir}/{feature}/spec/{workingLanguage}/brief.md` (create `{runsDir}/README.md` and
`{runsDir}/.gitignore` first if absent — v2-shared § Monorepo Rules, Run records):

```markdown
# {feature}: {one-line goal}

Source: {feature}

## Goal
{2–3 sentences}

## Acceptance criteria
- AC-1: {testable statement}

## Out of scope
- {…}

## Apps and packages
- {app or package}: {why}
```

Summarize in your own words; do not paste the ticket. Show the brief and ask the user to confirm or
edit it. Declined → delete what this run wrote and stop.

### C.4: Launch the planner

Record `baseCommit` = `git rev-parse HEAD` now; pass it to the planner, which writes it into `plan.json`. Reviews and gate records use it to tell what this change wrote.

```
Agent(subagent_type: "frontend-v2-plugin:implementation-planner", prompt: "
  Plan a change to existing code for '{feature}'.

  Parameters:
  - changeMode: true
  - feature: {feature}
  - baseCommit: {baseCommit}
  - briefFile: {runsDir}/{feature}/spec/{workingLanguage}/brief.md
  - apps: {the C.1 list as JSON: [{ app, baseDir, appDir }]}
  - packageDirs: {list}
  - excludePaths: {list or []}
  - rulesDir: {rulesDir}
  - routerMode: {routerMode}
  - serverState: {serverState}
  - formStack: {formStack}
  - componentLibrary: {componentLibrary}
  - apiLayer: {apiLayer}
  - i18nBinding: {i18nBinding}
  - clientStore: {clientStore}
  - mockFirst: {mockFirst}
  - projectRoot: {cwd}
  - baseDir: .  (file paths are repo-relative in change mode)
  - appDir: .  (each app's own appDir is in `apps`)
  - outputFile: {runsDir}/{feature}/plan.json
  - deltaOutputFile: {runsDir}/{feature}/delta-plan.json

  Follow the process defined in agents/implementation-planner.md (Change Mode).
")
```

### C.5: Summary and confirmation

Show, per app and per package: files to modify / create / remove with the AC each serves, the tests,
the rules read, `questions[]`, and `largeDeltaWarning` with its reason. Ask:
> "Proceed with this change plan?"

Open questions → ask them first and re-run C.4 with the answers added to the brief. Declined → delete
`plan.json` and `delta-plan.json` written in this run, keep the brief, stop.

### C.6: Progress

Create or update `{runsDir}/{feature}/progress.json`: `feature`, `status: "finalized"`,
`workingLanguage`, `changeKind: "change"`, `ticket`, `apps` (keys), and `implementation`:
`{ "status": "planned", "planFile": "…/plan.json", "deltaPlanFile": "…/delta-plan.json", "plannedAt": "{ISO}" }`.

### C.7: Next

> "Next: `/frontend-v2-plugin:v2-gen {feature}` (applies the change app by app), then
> `/frontend-v2-plugin:v2-verify {feature}` and `/frontend-v2-plugin:v2-review {feature}`; for the PR,
> `/frontend-v2-plugin:v2-progress {feature} --pr-body`."
