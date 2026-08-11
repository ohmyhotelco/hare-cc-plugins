---
name: fe-progress
description: "Show the current implementation status of all features or a specific feature."
argument-hint: "[feature-name]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash
---

# Implementation Progress

Show implementation pipeline status for features managed by the frontend-react-plugin.

## Instructions

### Step 0: Read Configuration

1. Read `.claude/frontend-react-plugin.json`
2. If the file does not exist:
   > "Frontend React Plugin has not been initialized. Please run `/frontend-react-plugin:fe-init` first."
   - Stop here.

### If a feature name is provided:

#### Step 1: Read Progress File

1. Read `docs/specs/{feature}/.progress/{feature}.json`
   - If not found:
     > "No progress file found for '{feature}'."
     > "Run `/frontend-react-plugin:fe-plan {feature}` to start."
     - Stop here.

2. Extract `workingLanguage` (default: `"en"`)
3. Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese

**Communication language**: All output must be in {workingLanguage_name}.

#### Step 2: Display Detailed Status

1. Check if the `implementation` field exists in the progress file
   - If absent:
     > "Feature '{feature}' has no implementation data yet."
     > "Run `/frontend-react-plugin:fe-plan {feature}` to start the implementation pipeline."
     - Stop here.

Read the `implementation` field and display:

```
Implementation Status for '{feature}':

  Status: {implementation.status} {status_emoji}
  Plan: {implementation.planFile or "—"}
  Generated: {implementation.generatedAt or "—"}

  TDD Phases:
    Foundation:     {tddPhases.foundation or "—"}
    API TDD:        {tddPhases.api-tdd or "—"}
    Store TDD:      {tddPhases.store-tdd or "—"}
    Component TDD:  {tddPhases.component-tdd or "—"}
    Page TDD:       {tddPhases.page-tdd or "—"}
    Integration:    {tddPhases.integration or "—"}

  Verification: {implementation.verification.status or "—"}
    {If verification exists: tsc: {tsc}, eslint: {eslint}, build: {build}, vitest: {vitest}}

  Review: {implementation.review.status or "—"}
    {If review exists:}
    Spec Review:    {review.specReview.score}/10 ({review.specReview.totalIssues} issues, {review.specReview.criticalIssues} critical)
    Quality Review: {review.qualityReview.score}/10 ({review.qualityReview.totalIssues} issues, {review.qualityReview.criticalIssues} critical)

  Fix: {implementation.fix.status or "—"}
    {If fix exists: Round {fix.round}, Fixed: {fix.fixed}, Escalated: {fix.escalated}, Tests added: {fix.testsAdded}}

  E2E: {implementation.e2e.status or "—"}
    {If e2e exists: {e2e.passed}/{e2e.total} scenarios passed}
    {If e2e.scenarios exists, list each: {id}: {name} — {status}}

  Delta: {implementation.lastDelta or "—"}
    {If lastDelta exists: {lastDelta.timestamp} — {lastDelta.specChanges.added} added, {lastDelta.specChanges.modified} modified, {lastDelta.specChanges.removed} removed}
```

**Status emoji mapping:**
- `planned` → (planned)
- `generated` → (generated)
- `gen-failed` → (FAILED)
- `verified` → (verified)
- `verify-failed` → (FAILED)
- `reviewed` → (reviewed)
- `review-failed` → (FAILED)
- `fixing` → (fixing)
- `resolved` → (resolved)
- `escalated` → (ESCALATED)
- `done` → (DONE)

#### Step 3: Spec Staleness Check

1. Read `implementation.generatedAt` from the progress file
2. If `generatedAt` exists:
   - Check if any spec file in `docs/specs/{feature}/{workingLanguage}/` was modified after `generatedAt` (use `stat` to get mtime)
   - If spec is newer:
     > "Warning: Spec modified after code generation ({generatedAt})."
     > "Run `/frontend-react-plugin:fe-plan {feature}` to detect changes (incremental mode)."

#### Step 4: Pending Delta Check

1. Check if `docs/specs/{feature}/.implementation/frontend/delta-plan.json` exists
   - If found:
     > "Pending delta plan detected. Run `/frontend-react-plugin:fe-gen {feature}` to apply incremental changes."

#### Step 5: Next Step Guidance

Based on `implementation.status`, display the recommended next action:

| Status | Guidance |
|---|---|
| `planned` | "Run `/frontend-react-plugin:fe-gen {feature}` to generate code." |
| `generated` | "Run `/frontend-react-plugin:fe-verify {feature}` or `/frontend-react-plugin:fe-review {feature}`." |
| `gen-failed` | "Run `/frontend-react-plugin:fe-gen {feature}` to retry generation." |
| `verified` | "Run `/frontend-react-plugin:fe-review {feature}`." |
| `verify-failed` | "Run `/frontend-react-plugin:fe-debug {feature}` or review errors." |
| `reviewed` | Check `implementation.e2e.status`: if absent -> "Run `/frontend-react-plugin:fe-fix {feature}` to address warnings, or `/frontend-react-plugin:fe-e2e {feature}` for E2E."; if `pass` -> "Reviewed with warnings, E2E passed. Run `/frontend-react-plugin:fe-fix {feature}` to address warnings."; if `partial` or `fail` -> "Run `/frontend-react-plugin:fe-fix {feature}` then `/frontend-react-plugin:fe-e2e {feature}`." |
| `review-failed` | "Run `/frontend-react-plugin:fe-fix {feature}`, then `/frontend-react-plugin:fe-review {feature}`." |
| `fixing` | Check report file timestamps: if `e2e-report.json` exists and is newer than `review-report.json` -> "Run `/frontend-react-plugin:fe-e2e {feature}` to re-run E2E after fixes."; if fix-report.json has regen-required entries -> "Run `/frontend-react-plugin:fe-gen {feature}` then `/frontend-react-plugin:fe-review {feature}`."; otherwise -> "Run `/frontend-react-plugin:fe-review {feature}` to re-review after fixes." |
| `resolved` | "Run `/frontend-react-plugin:fe-verify {feature}` or `/frontend-react-plugin:fe-review {feature}`." |
| `escalated` | "Manual intervention needed. See fix-report.json or debug-report.json." |
| `done` | Check `implementation.e2e.status`: if absent -> "Review passed. Run `/frontend-react-plugin:fe-e2e {feature}` for E2E testing."; if `pass` -> "Pipeline complete."; if `partial` or `fail` -> "Review passed but E2E has failures. Run `/frontend-react-plugin:fe-fix {feature}` then `/frontend-react-plugin:fe-e2e {feature}`." |

### If no feature name is provided:

#### Step 1: Scan All Features

1. Glob `docs/specs/*/.progress/*.json` to find all progress files
2. If no files found:
   > "No features found. Run `/frontend-react-plugin:fe-plan {feature}` to start."
   - Stop here.

#### Step 2: Read Configuration Language

1. Read `.claude/frontend-react-plugin.json` for display language context
2. Default to English if no specific language preference

#### Step 3: Build Summary Table

For each progress file:
1. Read `implementation` field
   - If `implementation` is absent → skip this feature (only show features with implementation data)
2. Extract:
   - `status`
   - TDD phase completion: count completed phases out of 6 total
   - Review score: `review.specReview.score` (or "—")
   - Fix round: `fix.round` (or "—")
   - E2E: `e2e.passed`/`e2e.total` (or "—")
   - Delta: "pending" if `delta-plan.json` exists, "applied" if `lastDelta` exists, "—" otherwise

3. If no features have `implementation` data after filtering:
   > "No features with implementation data found. Run `/frontend-react-plugin:fe-plan {feature}` to start."
   - Stop here.

4. Display:

```
Implementation Progress:

┌──────────────────┬───────────────┬─────────┬──────────┬───────┬─────────┬──────────┐
│ Feature          │ Status        │ Gen     │ Review   │ Fix   │ E2E     │ Delta    │
├──────────────────┼───────────────┼─────────┼──────────┼───────┼─────────┼──────────┤
│ {feature}        │ {status}      │ {n}/6   │ {score}  │ {Rn}  │ {p}/{t} │ {delta}  │
└──────────────────┴───────────────┴─────────┴──────────┴───────┴─────────┴──────────┘

{totalFeatures} features: {doneCount} done, {inProgressCount} in progress, {failedCount} failed
```

**Column formatting:**
- **Gen**: `{completed}/6` + `✓` if all 6 completed, or "—" if no tddPhases
- **Review**: `{specReview.score}/10` or "—"
- **Fix**: `R{round}` or "—"
- **E2E**: `{passed}/{total}` + `✓` if all passed, or "—"
- **Delta**: `pending` if delta-plan.json exists, `✓` if lastDelta exists with no pending, "—" otherwise
