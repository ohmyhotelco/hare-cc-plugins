# Review Reception Discipline

Reference document for presenting and applying review feedback. Adapted from [obra/superpowers receiving-code-review](https://github.com/obra/superpowers) for specification review workflows.

## Core Principle

Review feedback requires technical evaluation, not performative agreement. Verify before applying. Flag conflicts before presenting. Technical correctness over social comfort.

## Evaluation Criteria

When presenting planner/tester review issues to the user, evaluate each issue against these 4 criteria before presenting:

### 1. Consistency with Prior Decisions

- Check if this issue contradicts a decision made in a previous round
- Read the progress file's `rounds` array for previous decisions (Accept, Reject, Defer)
- If the issue targets a section that was explicitly addressed by a previous "Accept" decision: flag as conflict
- If the issue re-raises something the user previously "Reject"ed: flag as conflict
- Flag format: `⚠ Conflicts with Round N decision: {decision summary}`

### 2. Context Accuracy

- Verify the reviewer correctly understood the spec section they reference
- Read the cited section and confirm the issue description matches what is actually written
- If the reviewer misquoted, misinterpreted, or referenced a non-existent section: flag as inaccurate
- Flag format: `⚠ Reviewer may have misread: {explanation}`

### 3. Impact Assessment

Classify each suggestion's effect on the spec:

- **Improves spec**: Addresses a genuine gap, ambiguity, or inconsistency
- **Neutral**: Valid observation but optional; spec works without it
- **Risk of scope creep**: Suggestion adds requirements beyond the defined scope or MVP boundary
- **May harm clarity**: Suggestion would make the spec more complex without proportional benefit

### 4. Redundancy Check

- Is this issue already covered by another issue in the same review round?
- Was this issue already addressed in a previous round (check progress file)?
- If redundant: flag as `⚠ Overlaps with {issue_id}` or `⚠ Already addressed in Round N`

## Presentation Format

Present each issue with the technical assessment appended:

```
### PL-001 [critical] — Missing password reset flow
**Section**: {feature}-spec.md > FR-001
**Issue**: The spec defines login but doesn't address password reset.
**Suggestion**: Add FR for password reset including email verification.

**Assessment**: Improves spec — genuine gap in authentication flow. No conflicts with prior decisions.
```

For issues with flags:

```
### TS-003 [major] — Missing rate limiting
**Section**: {feature}-spec.md > FR-002
**Issue**: No rate limiting on login attempts.
**Suggestion**: Add rate limiting rule: max 5 attempts per 15 minutes.

**Assessment**: ⚠ Conflicts with Round 1 decision — user explicitly deferred rate limiting to Phase 2 (see OQ-003). Recommend: Reject or Defer.
```

For issues with context problems:

```
### PL-004 [major] — Missing error state for edit form
**Section**: screens.md > Screen: Entity Edit
**Issue**: No error handling defined for form submission failure.
**Suggestion**: Add error state with retry option.

**Assessment**: ⚠ Reviewer may have misread — error handling is defined in screens.md > Error Handling section (row 3: "Form submission failure"). Recommend: Reject.
```

## Response Discipline

### Forbidden Responses

Never use these when presenting review feedback:
- "Great point!"
- "Excellent observation!"
- "You're absolutely right!"
- "The reviewer makes a good case for..."
- Any expression of enthusiasm before technical evaluation

### Correct Responses

State the technical assessment directly:
- "This addresses a genuine gap in the authentication flow."
- "This conflicts with the Round 1 decision to defer rate limiting."
- "The reviewer misread section X — the spec already covers this."
- "Valid observation but optional for MVP scope."

## Application Discipline

When applying accepted changes to spec files:

1. **Re-read the target section** before applying — the section may have changed since the review was run
2. **Check for cross-section inconsistency** — if the suggestion affects one section, verify it doesn't create contradictions in related sections
3. **Multi-suggestion coherence** — if multiple accepted suggestions target the same section, apply them as a coherent edit rather than sequential independent patches
4. **Preserve existing structure** — maintain the spec's established formatting, heading hierarchy, and ID conventions when inserting new content
