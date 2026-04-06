# Pre-Finalization Verification Gate

Reference document for the spec finalization process. Adapted from [obra/superpowers verification-before-completion](https://github.com/obra/superpowers) for specification review workflows.

## The Iron Law

```
NO FINALIZATION WITHOUT VERIFICATION EVIDENCE
```

Convergence scores confirm that reviewers are satisfied with the current state. But scores alone do not guarantee that accepted changes were actually applied. Before marking a spec as FINALIZED, verify that every "Accept"ed and "Modify"ed issue from ALL review rounds is reflected in the spec text. Evidence before claims, always.

## When to Run

- After convergence check passes (scores >= 8, or 3 rounds with caveats)
- Before the user confirms finalization
- This gate supplements (does not replace) the convergence check

## Verification Procedure

### Step 1: Collect Accepted Issues

Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`.

For each round in the `rounds` array, collect every issue where the user's decision was **Accept** or **Modify**. Record:
- Issue ID (e.g., PL-001, TS-003)
- Issue title
- The suggestion text (or the user's modified version for "Modify" decisions)
- The target section/file (derived from the issue's `section` field)

Skip issues with "Reject" or "Defer" decisions — these are intentionally excluded.

### Step 2: Search for Evidence

For each collected issue:

1. Identify the target spec file from the issue's `section` field:
   - FR / user story / overview issues → `{feature}-spec.md`
   - Screen / error handling / layout issues → `screens.md`
   - Test scenario / NFR issues → `test-scenarios.md`
2. Read the relevant section of the spec file
3. Determine whether the suggestion was applied by checking for:
   - New content that addresses the issue description
   - Modified text matching the suggestion intent
   - For "Modify" decisions: content matching the user's modified version, not the original suggestion
4. Mark as **VERIFIED** or **UNVERIFIED**

### Step 3: Present Results

Show the verification summary:

```
Verification Gate — {verified_count}/{total_count} accepted issues confirmed

✓ PL-001: Missing password reset flow — Found in {feature}-spec.md > FR-005
✓ TS-002: Input validation limits — Found in {feature}-spec.md > FR-003 > Validation Rules
✗ PL-003: Empty state for list view — NOT FOUND in screens.md > Screen: List View
✗ TS-005: Concurrent edit handling — NOT FOUND in screens.md > Error Handling
```

### Step 4: Resolution

**If all items are verified**: Proceed directly to finalization.

**If unverified items exist**: Present each unverified item with its original suggestion. For each, ask the user:

- **Resolve now**: Apply the missing change to the spec file immediately
- **Defer**: Move to Open Questions section in `{feature}-spec.md` with a note that it was accepted but not applied
- **Dismiss**: The issue was addressed differently than the original suggestion — the user explains how (record the explanation in the progress file)

After all items are resolved, deferred, or dismissed, proceed with finalization.

## Important Rules

- This is evidence-based: READ the actual spec text, do not assume changes were applied
- "Modify" decisions must be checked against the user's modified version, not the original suggestion
- Issues from ALL rounds must be checked, not just the latest round
- Dismissed items must be recorded in the progress file with the user's explanation
- If the same section was targeted by multiple issues across rounds, verify each one independently

## Common Failures

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| "Issue was applied" | Text evidence in spec file | Round score improved |
| "Spec is complete" | All accepted issues verified | Convergence scores >= 8 |
| "Ready to finalize" | Verification gate passed | User said "finalize" |
| "Deferred properly" | Entry in Open Questions | Issue just dismissed verbally |

## Red Flags — STOP

- About to finalize without running this verification
- Assuming changes were applied because the user said "Accept"
- Skipping verification because scores are high
- Checking only the latest round's issues
- Treating "Dismiss" as a way to skip verification (require explanation)
