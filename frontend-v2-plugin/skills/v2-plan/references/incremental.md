# v2-plan: incremental mode (Steps 3-I to 5-I)

Part of the `v2-plan` skill. `{pluginRoot}` is the plugin root the skill states.

### Step 3-I: Launch Planner Agent (Incremental Mode)

Only executed when `planMode = "incremental"`.

Launch the implementation-planner agent in incremental mode:

```
Agent(subagent_type: "frontend-v2-plugin:implementation-planner", prompt: "
  Analyze spec changes for '{feature}' and produce a delta plan.

  Parameters:
  - feature: {feature}
  - specDir: {specRoot}/{workingLanguage}/
  - uiDslDir: {specRoot}/ui-dsl/ (available: {uiDslAvailable})
  - prototypeDir: prototypes/{feature}/ (available: {prototypeAvailable})
  - routerMode: {routerMode}
  - appProfile: {appProfile}
  - serverState: {serverState}
  - formStack: {formStack}
  - componentLibrary: {componentLibrary}
  - externalComponents: {the config object, or omit the line when absent}
  - apiLayer: {apiLayer}
  - apiPackage: {the config object, or omit the line when absent}
  - i18nBinding: {i18nBinding}
  - i18nHook: {the config object, or omit the line when absent}
  - clientStore: {clientStore}
  - renderingDefault: {renderingDefault}
  - mockFirst: {mockFirst}
  - projectRoot: {cwd}
  - baseDir: {baseDir}
  - appDir: {appDir}
  - srcPath: {srcPath}
  - incrementalMode: true
  - existingPlanFile: {runsDir}/{feature}/plan.json
  - deltaOutputFile: {runsDir}/{feature}/delta-plan.json
  - outputFile: {runsDir}/{feature}/plan.json
  - i18n: {the config i18n block, or omit when absent}

  Follow the process defined in agents/implementation-planner.md.
  Execute Phase 3 (Incremental Mode) instead of Phase 2.
  Write the delta plan to the deltaOutputFile path.
")
```

### Step 4-I: Display Delta Summary & Confirm

Only executed when `planMode = "incremental"`.

1. Read the generated `{runsDir}/{feature}/delta-plan.json`
2. Display the delta summary (as defined in the agent's Delta User Summary Template)

3. If `largeDeltaWarning` is `true`:
   > "Warning: This delta affects more than 60% of implementation files."
   > "Full regeneration may be more reliable and produce more consistent code."
   > "Options:"
   > "1. Proceed with delta (incremental update)"
   > "2. Switch to full regeneration"
   - If user chooses 2: discard delta-plan.json, set `planMode = "full"`, go to Step 3

4. If no spec changes detected (`specChanges.added`, `modified`, and `removed` are all empty)
   **and `contentComparisonUnavailable` is empty**:
   > "No spec changes detected. The current plan is up to date."
   When `contentComparisonUnavailable` is **non-empty**, this branch is forbidden — the honest
   statement is "no *detectable* changes", which is not the same thing. Display the listed objects
   and their source IDs with:
   > "Content comparison unavailable for {N} object(s) (plan predates sourceHash). If any of these
   > requirements changed, run full generation; incremental cannot see their edits."
   and keep the delta only if other changes exist; otherwise delete it and stop as below.
   - **Delete the `delta-plan.json` the planner just wrote** and leave the progress file untouched.
     Left in place, the session hook and `v2-progress` report a pending delta, and following their
     `v2-gen` advice executes a zero-change delta that resets the status to `generated` and clears
     valid E2E evidence — a full pipeline demotion with no code change behind it.
   - Stop here (release the lock).

5. Confirm:
   > "Proceed with incremental plan? Run `/frontend-v2-plugin:v2-gen {feature}` to apply the delta."

6. Skip to Step 5-I.

### Step 5-I: Update Progress (Incremental Mode)

Only executed when `planMode = "incremental"`.

1. Read `{runsDir}/{feature}/progress.json`
2. Add or update the `implementation` field — preserve the existing status (do NOT reset to `"planned"`):

```json
{
  "implementation": {
    "deltaFile": "{runsDir}/{feature}/delta-plan.json",
    "deltaDetectedAt": "{ISO timestamp}"
  }
}
```

3. Write the updated progress file back. **Merge rule**: preserve ALL existing fields in the progress file (including `status`, `planFile`, `tddPhases`, `generatedAt`, `verification`, `review`, `fix`, `debug`) — only add the `deltaFile` and `deltaDetectedAt` fields.
