---
name: v2-debug
description: "Use when generated code has runtime errors, test failures, or build issues that need systematic diagnosis."
argument-hint: "<feature-name>"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Debug Skill

Resolves issues in generated code using a systematic 4-phase debugging methodology.

The debug session runs autonomously with its own hypothesis-test-fix cycle.

Conventions (`v2-shared`): `${CLAUDE_PLUGIN_ROOT}/skills/v2-shared/SKILL.md`.

## Instructions

### Step 0: Read Configuration

1. Read `.claude/frontend-v2-plugin.json` → extract `routerMode`, `mockFirst`, `appDir`, `baseDir`
2. If `baseDir` is missing, use default value `"src"`; if `appDir` is missing, use default value `"."` (project root)
3. If the file does not exist:
   > "Frontend V2 Plugin has not been initialized. Please run `/frontend-v2-plugin:v2-init` first."
   - Stop here.
4. **Derive `srcPath`** — take the config `baseDir` **after its default is applied** and remove the leading `{appDir}/` (`app/src` + `appDir=app` → `src`; `appDir="."` → unchanged; `appDir == baseDir` → `.`). Every `npx …` path argument uses `srcPath`; the repo-relative source root stays available for file operations. See v2-shared § Build Command Working Directory.

### Step 1: Validate Files

1. Check if `docs/specs/{feature}/.implementation/frontend/plan.json` exists
   - If not found:
     > "Implementation plan not found."
     > "Please run `/frontend-v2-plugin:v2-plan {feature}` first."
     - Stop here.

2. Read `plan.json` → extract `baseDir`, `feature`

3. Read `docs/specs/{feature}/.progress/{feature}.json` → extract `workingLanguage` (default: `"en"`) and `implementation.status` (save as `previousStatus` for use in Step 5 guidance)
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill (summaries, questions, feedback presentations, next-step guidance) must be in {workingLanguage_name}.

1. **Generated files check** — verify that the `baseDir` directory exists:
   - If the directory does not exist:
     > "Generated code not found."
     > "Please run `/frontend-v2-plugin:v2-gen {feature}` first."
     - Stop here.

   Note: v2-debug intentionally does not check `implementation.status` — it serves as an interrupt tool usable at any pipeline stage. The previous status is saved for context-aware guidance in Step 5.

### Step 2: Collect Problem Description

Ask the user to describe the problem:

> "Please describe the issue to debug:"
> "- Error message or stack trace"
> "- Related file path (if known)"
> "- Expected behavior vs actual behavior"

Collect the user's response as `problemDescription`.

### Step 3: Launch Debugger Agent

Run the debugger agent:

```
Agent(subagent_type: "frontend-v2-plugin:debugger", prompt: "
  Debug the following issue in '{feature}'.

  Parameters:
  - feature: {feature}
  - planFile: docs/specs/{feature}/.implementation/frontend/plan.json
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - baseDir: {baseDir}/
  - projectRoot: {cwd}
  - appDir: {appDir}
  - srcPath: {srcPath}
  - problemDescription: {problemDescription}
  - routerMode: {routerMode}

  Follow the 4-phase methodology defined in agents/debugger.md.
  Write the debug report to docs/specs/{feature}/.implementation/frontend/debug-report.json.
")
```

### Step 4: Display Debug Report

Display the agent execution results.

**Resolved:**
```
Debug Report for '{feature}':

  Status: RESOLVED
  Classification: {issueClassification}

  Root Cause:
    File: {rootCause.file}:{rootCause.line}
    Description: {rootCause.description}

  Fix Applied:
    {hypothesis description and fix}

  Files Modified:
    {list of modified files}

  Verification:
    TypeScript: {tsc result}
    Build: {build result}
    Tests: {test result}

  Report saved to: docs/specs/{feature}/.implementation/frontend/debug-report.json
```

**Escalated:**
```
Debug Report for '{feature}':

  Status: ESCALATED (3 hypotheses failed)

  Problem: {problemDescription}

  Hypotheses Tested:
    1. {hypothesis 1} → {result}
    2. {hypothesis 2} → {result}
    3. {hypothesis 3} → {result}

  Evidence Collected:
    {evidence list}

  Recommendation: {recommendation}

  Report saved to: docs/specs/{feature}/.implementation/frontend/debug-report.json
```

Additional guidance on escalation:
> "All 3 hypotheses failed — this may be a structural issue rather than a simple bug."

If previousStatus is `review-failed` or `fixing`:
> "- Fix remaining review issues: `/frontend-v2-plugin:v2-fix {feature}`"
> "- Or re-plan if the issue is structural: `/frontend-v2-plugin:v2-plan {feature}`"

Otherwise:
> "- Consider re-reviewing the plan (`/frontend-v2-plugin:v2-plan {feature}`) or revising the spec."

> "Refer to the evidence and structural analysis in the report."

### Step 5: Next-Step Guidance

After resolution, read the **previous** `implementation.status` (before this debug session) and provide context-aware guidance:

| Previous Status | Guidance |
|----------------|----------|
| `gen-failed` | > "Issue resolved. Re-run code generation: `/frontend-v2-plugin:v2-gen {feature}`" |
| `generated` | > "Issue resolved. Continue pipeline: `/frontend-v2-plugin:v2-verify {feature}`" |
| `verify-failed` | > "Issue resolved. Re-verify: `/frontend-v2-plugin:v2-verify {feature}`" |
| `review-failed` | > "Issue resolved. Re-review: `/frontend-v2-plugin:v2-review {feature}`, or fix remaining issues: `/frontend-v2-plugin:v2-fix {feature}`" |
| `fixing` | > "Issue resolved. Re-review to verify fixes: `/frontend-v2-plugin:v2-review {feature}`" |
| `escalated` | > "Issue resolved. Re-enter pipeline: `/frontend-v2-plugin:v2-fix {feature}`, `/frontend-v2-plugin:v2-verify {feature}`, or `/frontend-v2-plugin:v2-review {feature}`" |
| Other / unknown | > "Issue resolved. Consider re-verifying (`/frontend-v2-plugin:v2-verify {feature}`) or re-reviewing (`/frontend-v2-plugin:v2-review {feature}`)." |

If escalated:
> "Manual intervention required. After resolving, re-enter the pipeline with `/frontend-v2-plugin:v2-fix {feature}`, `/frontend-v2-plugin:v2-verify {feature}`, or `/frontend-v2-plugin:v2-review {feature}`."

### Step 6: Update Progress

Read `docs/specs/{feature}/.progress/{feature}.json` and update `implementation.status`:

- resolved → `"resolved"` (set status to `"resolved"`)
- escalated → `"escalated"` (set status to `"escalated"`)

```json
{
  "implementation": {
    "status": "resolved | escalated",
    "debug": {
      "status": "resolved | escalated",
      "timestamp": "{ISO timestamp}",
      "reportFile": "docs/specs/{feature}/.implementation/frontend/debug-report.json"
    }
  }
}
```

**Merge rule**: Read the existing progress file, merge changes into the existing `implementation` object preserving all other fields (e.g., `planFile`, `tddPhases`, `verification`, `review`, `fix`), then write back the complete file.
