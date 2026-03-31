---
name: be-code
description: "Implement a feature using TDD. Gathers context, writes scenarios, runs TDD cycle."
argument-hint: "<feature-name or work-doc-path>"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Implement Feature with TDD

Implement a feature using strict Test-Driven Development. This skill orchestrates the full TDD workflow: context gathering, scenario writing, and RED-GREEN cycle execution.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, tell the user to run `/backend-springboot-plugin:be-init` first and stop

### Step 1: Parse Argument

The argument can be:

- **File path**: If argument looks like a path (contains `/` or `.md`), treat it as a work document path
- **Feature name**: Otherwise, treat it as a feature description

### Step 2: Gather Context

1. Read the plugin CLAUDE.md for architecture and conventions
2. If the argument is a work document:
   - Read the document
   - Extract `- [ ]` scenarios
   - Skip to Step 4
3. If the argument is a feature name:
   - Explore existing code: scan `{sourceDir}/{basePackage}/` for related entities, controllers, commands, queries
   - Read existing work documents in `{workDocDir}/` for patterns
   - Check for any related PRD/TSD documents

### Step 3: Write Test Scenarios

If no work document was provided:

1. Read `templates/test-scenario-template.md` for the scenario format
2. Draft test scenarios following CLAUDE.md scenario writing rules:
   - Single sentence, English, present tense
   - Start with lowercase (usable as snake_case method name)
   - Use `- [ ]` checkbox format
   - Most important scenario first
3. Mark uncertain scenarios with `?`:
   ```
   - [ ] valid request returns 201 Created
   - [ ] duplicate email returns 409 Conflict
   - [ ] ? empty display name returns 400 Bad Request
   ```
4. Present the scenario list to the user for approval:
   > "Here are the test scenarios for {feature}:"
   > {scenario list}
   > "Please review. I'll remove scenarios marked with `?` unless you confirm them."
5. Wait for user approval before proceeding
6. Save approved scenarios to `{workDocDir}/{feature-name}.md`

### Step 3.5: Demotion Check

If `{workDocDir}/.progress/{feature-name}.json` exists:

1. Read `pipeline.status`
2. If status is `"verified"`, `"reviewed"`, or `"done"`:
   > "This feature is currently '{status}'. Re-running TDD implementation will reset the pipeline status to 'implementing', discarding verification/review progress."
   > "Continue?"
   If the user declines, stop here.
3. If status is `"fixing"`:
   > "This feature is currently 'fixing' (be-fix in progress). Re-running implementation will overwrite fix changes."
   > "Continue?"
   If the user declines, stop here.

### Step 3.6: Acquire Lock

1. Check if `{workDocDir}/.progress/.lock` exists
2. If it exists and `lockedAt` is less than 30 minutes ago: warn the user that another operation (`{operation}`) is in progress and stop
3. If it exists and `lockedAt` is older than 30 minutes: remove the stale lock
4. Write lock file: `{ "lockedAt": "{ISO 8601}", "operation": "be-code", "feature": "{feature-name}" }`

### Step 3.7: Initialize Pipeline State

Create or update `{workDocDir}/.progress/{feature-name}.json`:

1. Create `{workDocDir}/.progress/` directory if it does not exist
2. If progress file does not exist, create it:
   ```json
   {
     "feature": "{feature-name}",
     "workDocument": "{workDocDir}/{feature-name}.md",
     "createdAt": "{ISO 8601}",
     "updatedAt": "{ISO 8601}",
     "pipeline": {
       "status": "implementing",
       "scenarios": { "total": {count}, "completed": 0 }
     }
   }
   ```
3. If progress file exists, update `pipeline.status` to `"implementing"` and refresh scenario counts

### Step 4: TDD Cycle

**Subagent Isolation**: Pass only the specified parameters below. Do not include conversation history or user feedback from prior steps.

Launch the `implement` agent once with:

- `workDocument`: path to the work document
- `config`: the parsed plugin config
- `projectRoot`: current project root

The implement agent processes all scenarios internally:
1. Select the next `- [ ]` scenario
2. Write test (RED)
3. Implement minimum code (GREEN)
4. Mark as `- [x]`
5. Repeat until all scenarios are complete

### Step 5: Final Build

After all scenarios are complete, run a full build:

```bash
{config.buildCommand}
```

Set Bash tool timeout to 600000ms.

### Step 6: Report

Display implementation summary in the working language:

```
Feature Implementation Complete: {feature-name}
=======================================

Scenarios: {completed}/{total}
  {list each scenario with status}

Files created:
  {list of new files}

Files modified:
  {list of modified files}

Build: {PASS / FAIL}
```

If the build failed, suggest running `/backend-springboot-plugin:be-build` for auto-diagnosis.

### Step 7: Update Pipeline State

Update `{workDocDir}/.progress/{feature-name}.json`:

1. Read progress file
2. Update `pipeline.scenarios.completed` with final count of `- [x]` items
3. Update `pipeline.status`:
   - All scenarios complete + build passes → `"implemented"`
   - All scenarios complete + build fails → `"implemented"` (build issue is separate)
   - Some scenarios remain → `"implementing"`
4. Update `updatedAt` timestamp
5. Write back (read-modify-write)

6. Release lock: delete `{workDocDir}/.progress/.lock`

Suggest next step:
- **implemented + build passes**: `/backend-springboot-plugin:be-verify {feature}`
- **implemented + build fails**: `/backend-springboot-plugin:be-build`
- **implementing**: resume with `/backend-springboot-plugin:be-code {workDoc}`

### Error Handling

- **3 consecutive test failures**: The implement agent will stop. Present the issue to the user with context and ask for guidance.
- **Compilation errors during TDD**: The implement agent will fix stubs, not tests.
- **User cancellation**: Save progress (completed scenarios remain `- [x]`). The user can re-run `be-code` with the same work document to resume.
