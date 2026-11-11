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

Whenever `plan.json` already exists, whatever the status, ask which re-plan this is: the same unmerged
change (keep the plan's `baseCommit`) or a later PR for the ticket after an earlier one merged (new
`baseCommit`).

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

Summarize in your own words; do not paste the ticket. When the ticket names an app (by name, path or
platform) that C.1 did not select, say so with the ticket's words and offer to add it — the C.1
pre-selection is only `defaultApp`. Accepted → resolve the added app as C.1 does (merged `baseDir`/`appDir`
and config), add it to the C.1 list, recompute `packageDirs`, and rewrite the brief's "Apps and
packages" before showing it again. Show the brief and ask the user to confirm or edit it. Declined →
delete what this run wrote and stop.

### C.4: Launch the planner

When `plan.json` or `delta-plan.json` already exists and no `plan.prev.json` / `delta-plan.prev.json` is
there yet, copy each to that name first — once per re-plan, so a C.5 question re-run does not overwrite
the accepted copy. Any exit before acceptance (decline, planner failure, stop) restores them. Record `baseCommit` = `git rev-parse HEAD` now — or the kept one when C.0 found a re-plan of the same unmerged change, so its earlier commits still count; pass it to the planner, which writes it into `plan.json`. Reviews and gate records use it to tell what this change wrote.

```
Agent(subagent_type: "frontend-v2-plugin:implementation-planner", prompt: "
  Plan a change to existing code for '{feature}'.

  Parameters:
  - changeMode: true
  - feature: {feature}
  - baseCommit: {baseCommit}
  - briefFile: {runsDir}/{feature}/spec/{workingLanguage}/brief.md
  - apps: {the C.1 list as JSON: [{ app, baseDir, appDir, config }], config = that app's merged values of routerMode, serverState, formStack, componentLibrary, apiLayer, i18nBinding, clientStore, mockFirst, appProfile and their companion objects (externalComponents, apiPackage, i18nHook, i18n, layout)}
  - packageDirs: {list}
  - excludePaths: {list or []}
  - rulesDir: {rulesDir}
  - routerMode: {routerMode}  (this and the stack keys below are the default app's; each app's own are in apps[].config)
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

Open questions → ask them first and re-run C.4 with the answers added to the brief. A question the user says cannot be answered in this ticket (a decision held elsewhere) is marked `"status": "deferred"` with `heldBy` (who decides; `answer` stays null), and the plan may proceed; an `appsReadOnly[]` entry naming it shows as "decision pending". Declined → delete
`plan.json` and `delta-plan.json` written in this run, restore the `.prev.json` copies when C.4 made
them, keep the brief, stop. Accepted → delete the `.prev.json` copies.

### C.6: Progress

Create or update `{runsDir}/{feature}/progress.json`: `feature`, `status: "finalized"`,
`workingLanguage`, `changeKind: "change"`, `ticket`, `apps` (keys), and `implementation`:
`{ "status": "planned", "planFile": "…/plan.json", "deltaFile": "…/delta-plan.json", "plannedAt": "{ISO}" }`.

### C.7: Next

> "Next: `/frontend-v2-plugin:v2-gen {feature}` (applies the change app by app), then
> `/frontend-v2-plugin:v2-verify {feature}`, then `/frontend-v2-plugin:v2-review {feature}` (with
> `v2-fix` until it passes), then `/frontend-v2-plugin:v2-e2e {feature}` once the review has nothing
> left; for the PR, `/frontend-v2-plugin:v2-progress {feature} --pr-body`.
> You may also run `v2-e2e` right after `v2-verify` as an early check — it is cheap in change mode —
> but a review fix makes that pass stale, so the e2e run that counts is the one after the review."
