---
name: progress
description: Show the current status of all functional specifications including review scores, open issues, and translation sync state.
argument-hint: "[feature-name]"
user-invocable: true
allowed-tools: Read, Glob, Grep
---

# Specification Status

Show status for: **$ARGUMENTS**

## Instructions

### If a feature name is provided:

1. Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`
2. Display:

```
Feature: {feature}
Status: {status}
Current Round: {currentRound}

Review History:
┌───────┬─────────────────┬──────────────────┬──────────────────┐
│ Round │ Planner Score   │ Tester Score     │ Key Decisions    │
├───────┼─────────────────┼──────────────────┼──────────────────┤
│   1   │ {score}/10      │ {score}/10       │ {decisions}      │
└───────┴─────────────────┴──────────────────┴──────────────────┘

Translation Status:
  Korean (ko):      {synced ? "Synced" : "Out of sync"} — Last synced: {timestamp}
  Vietnamese (vi):  {synced ? "Synced" : "Out of sync"} — Last synced: {timestamp}

Open Questions: {count from spec's Open Questions section}
```

3. If there are unresolved issues from the latest review round, list them

### If no feature name is provided:

1. Scan `docs/specs/*/` for all feature directories
2. Read each progress file
3. Display a summary table:

```
Specifications Overview:
┌──────────────────┬────────────┬───────┬─────────┬─────────┬────────────┐
│ Feature          │ Status     │ Round │ Planner │ Tester  │ Translated │
├──────────────────┼────────────┼───────┼─────────┼─────────┼────────────┤
│ social-login     │ reviewing  │   2   │  7/10   │  6/10   │ ko✓ vi✓    │
│ user-profile     │ finalized  │   3   │  9/10   │  8/10   │ ko✓ vi✓    │
│ notifications    │ drafting   │   0   │   —     │   —     │ ko✗ vi✗    │
└──────────────────┴────────────┴───────┴─────────┴─────────┴────────────┘
```

4. If no specs exist yet, display:
   > No specifications found. Run `/planning-plugin:spec "feature description"` to create one.
