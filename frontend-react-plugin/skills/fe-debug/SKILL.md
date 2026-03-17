---
name: fe-debug
description: "Systematic debugging of generated code using 4-phase methodology with escalation."
argument-hint: "<feature-name>"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# Debug Skill

Resolves issues in generated code using a systematic 4-phase debugging methodology.

## Instructions

### Step 0: Read Configuration

1. Read `.claude/frontend-react-plugin.json` → extract `routerMode`, `mockFirst`
2. If the file does not exist:
   > "Frontend React Plugin has not been initialized. Please run `/frontend-react-plugin:fe-init` first."
   - Stop here.

### Step 1: Validate Files

1. Check if `docs/specs/{feature}/.implementation/plan.json` exists
   - If not found:
     > "Implementation plan not found."
     > "Please run `/frontend-react-plugin:fe-plan {feature}` first."
     - Stop here.

2. Read `plan.json` → extract `baseDir`, `feature`

3. Read `docs/specs/{feature}/.progress/{feature}.json` → extract `workingLanguage` and `implementation.status` (save as `previousStatus` for use in Step 5 guidance)
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill (summaries, questions, feedback presentations, next-step guidance) must be in {workingLanguage_name}.

5. **Generated files check** — verify that the `baseDir` directory exists:
   - If the directory does not exist:
     > "Generated code not found."
     > "Please run `/frontend-react-plugin:fe-gen {feature}` first."
     - Stop here.

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
Task(subagent_type: "debugger", prompt: "
  Debug the following issue in '{feature}'.

  Parameters:
  - feature: {feature}
  - planFile: docs/specs/{feature}/.implementation/plan.json
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - baseDir: {baseDir}/
  - projectRoot: {cwd}
  - problemDescription: {problemDescription}

  Follow the 4-phase methodology defined in agents/debugger.md.
  Write the debug report to docs/specs/{feature}/.implementation/debug-report.json.
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

  Report saved to: docs/specs/{feature}/.implementation/debug-report.json
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

  Report saved to: docs/specs/{feature}/.implementation/debug-report.json
```

Additional guidance on escalation:
> "All 3 hypotheses failed — this may be a structural issue rather than a simple bug."
> "Recommended: Consider re-reviewing the plan (`/frontend-react-plugin:fe-plan {feature}`) or revising the spec."
> "Refer to the evidence and structural analysis in the report."

### Step 5: Next-Step Guidance

After resolution, read the **previous** `implementation.status` (before this debug session) and provide context-aware guidance:

| Previous Status | Guidance |
|----------------|----------|
| `verify-failed` | > "Issue resolved. Re-verify: `/frontend-react-plugin:fe-verify {feature}`" |
| `review-failed` | > "Issue resolved. Re-review: `/frontend-react-plugin:fe-review {feature}`, or fix remaining issues: `/frontend-react-plugin:fe-fix {feature}`" |
| `generated` | > "Issue resolved. Continue pipeline: `/frontend-react-plugin:fe-verify {feature}`" |
| Other / unknown | > "Issue resolved. Consider re-verifying (`/frontend-react-plugin:fe-verify {feature}`) or re-reviewing (`/frontend-react-plugin:fe-review {feature}`)." |

If escalated:
> "Manual intervention required. After resolving, re-enter the pipeline with `/frontend-react-plugin:fe-verify {feature}` or `/frontend-react-plugin:fe-review {feature}`."

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
      "reportFile": "docs/specs/{feature}/.implementation/debug-report.json"
    }
  }
}
```

**Merge rule**: Read the existing progress file, merge changes into the existing `implementation` object preserving all other fields (e.g., `planFile`, `tddPhases`, `verification`, `review`, `fix`), then write back the complete file.
