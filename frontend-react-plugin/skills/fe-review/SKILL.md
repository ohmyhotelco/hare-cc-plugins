---
name: fe-review
description: "Run 2-stage code review (spec compliance → quality) on generated code for a feature."
argument-hint: "<feature-name>"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Task
---

# Code Review Skill

Run a 2-stage code review (spec review → quality review) on generated code.

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

3. Read `docs/specs/{feature}/.progress/{feature}.json` → extract `workingLanguage`
4. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All user-facing output in this skill (summaries, questions, feedback presentations, next-step guidance) must be in {workingLanguage_name}.

5. **Status check** — verify `implementation.status` indicates code has been generated:
   - Accepted statuses: `generated`, `verified`, `verify-failed`, `reviewed`, `review-failed`, `fixing`, `resolved`, `done`
   - If status is `"planned"` or absent:
     > "No generated code found (current status: '{status}')."
     > "Please run `/frontend-react-plugin:fe-gen {feature}` first."
     - Stop here.

6. **Generated files check** — verify the `baseDir` directory exists and contains files:
   - If the directory is empty or does not exist:
     > "Generated code not found."
     > "Please run `/frontend-react-plugin:fe-gen {feature}` first."
     - Stop here.

### Step 2: Spec Review

Run the spec-reviewer agent:

```
Task(subagent_type: "spec-reviewer", prompt: "
  Review generated code for '{feature}' against the functional specification.

  Parameters:
  - feature: {feature}
  - planFile: docs/specs/{feature}/.implementation/plan.json
  - specDir: docs/specs/{feature}/{workingLanguage}/
  - baseDir: {baseDir}/

  Follow the process defined in agents/spec-reviewer.md.
  Return the review result as JSON.
")
```

**Evaluate the result:**
- `status: "pass"` or `"pass_with_warnings"` → proceed to Step 3
- `status: "fail"` → display the report and stop (do not proceed to quality review):
  > "Spec Review FAILED (score: {overallScore}/10, critical issues: {criticalIssues})"

  Display issues using the enriched fields when available:
  ```
  Issues:
    [{severity}] {message} — {file} ({missingArtifact: "file" → "missing file", else → "existing file"})
      Refs: {refs joined by ", "} | Fix: {fixHint}
  ```
  If `refs` or `fixHint` are absent (legacy report), fall back to the basic format:
  ```
    [{severity}] {message} — {file}
  ```

  > "Fix with TDD discipline: `/frontend-react-plugin:fe-fix {feature}`"
  > "Then re-review: `/frontend-react-plugin:fe-review {feature}`"
  - Skip to Step 6 (save report and record progress)

### Step 3: Quality Review (only when spec review passes)

Run the quality-reviewer agent:

```
Task(subagent_type: "quality-reviewer", prompt: "
  Review code quality for '{feature}'.

  Parameters:
  - feature: {feature}
  - planFile: docs/specs/{feature}/.implementation/plan.json
  - baseDir: {baseDir}/
  - projectRoot: {cwd}

  Follow the process defined in agents/quality-reviewer.md.
  Return the review result as JSON.
")
```

### Step 4: Display Integrated Report

**Communication Guidelines:**
- Mention strengths first, 2-3 items (from summary.strengths)
- Each issue must include what to change (never just state what is wrong)
- No performative language ("Great job!", "Well done!" → state facts only)
- Sort by priority (critical → warning → suggestion)

Display the integrated results from both reviews:

```
Code Review Report for '{feature}':

  Stage 1 — Spec Review:
    Status: {pass/fail} (score: {overallScore}/10)
    Dimensions:
      Requirement Coverage: {score}/10
      UI Fidelity: {score}/10
      i18n Completeness: {score}/10
      Accessibility: {score}/10
      Route Coverage: {score}/10
    Issues: {totalIssues} ({criticalIssues} critical)

  Stage 2 — Quality Review:
    Status: {pass/fail} (score: {overallScore}/10)
    Dimensions:
      Single Responsibility: {score}/10
      Consistent Patterns: {score}/10
      No Hardcoded Strings: {score}/10
      Error Handling: {score}/10
      TypeScript Strictness: {score}/10
      Convention Compliance: {score}/10
      Architecture & Design: {score}/10
    Issues: {totalIssues} ({criticalIssues} critical)

  Overall: {PASS/FAIL}
```

**If there are issues**, organize and display them by category:

```
  Strengths:
    - {strength 1}
    - {strength 2}

  Issues:
    [{severity}] {message} — {file}:{line} ({missingArtifact description if available})
      Refs: {refs} | Fix: {fixHint}
    (fall back to "[{severity}] {message} — {file}:{line}" if enriched fields are absent)
    (omit :{line} when line number is absent)
```

### Step 5: Re-Review Guidance

If the result is `fail` or `pass_with_warnings`:
> "Fix with TDD discipline: `/frontend-react-plugin:fe-fix {feature}`"
> "Then re-review: `/frontend-react-plugin:fe-review {feature}`"
> "Do not skip the re-review after making fixes."

### Step 6: Save Review Report & Update Progress

Save the full review reports to `docs/specs/{feature}/.implementation/review-report.json`:

```json
{
  "timestamp": "{ISO timestamp}",
  "specReview": { /* full spec-reviewer output */ },
  "qualityReview": { /* full quality-reviewer output, or null if spec failed */ }
}
```

Then read `docs/specs/{feature}/.progress/{feature}.json` and add or update the `review` field:

```json
{
  "implementation": {
    "status": "reviewed | review-failed | done",
    "review": {
      "status": "pass",
      "timestamp": "{ISO timestamp}",
      "specReview": {
        "status": "pass",
        "score": 8.5,
        "criticalIssues": 0,
        "totalIssues": 1
      },
      "qualityReview": {
        "status": "pass",
        "score": 8.8,
        "criticalIssues": 0,
        "totalIssues": 1
      }
    }
  }
}
```

**Merge rule**: Read the existing progress file, merge changes into the existing `implementation` object preserving all other fields (e.g., `planFile`, `tddPhases`, `verification`, `fix`, `debug`), then write back the complete file.

Note: Set `implementation.status` as follows:
- Both pass (clean) → `"done"`
- Both pass but either has `pass_with_warnings` → `"reviewed"`
- Either one fails → `"review-failed"`
- Only spec-reviewer passes, quality-reviewer fails → `"review-failed"`
