# Pipeline Progress State

Lightweight state tracking for the tool implementation pipeline.

## File Location

`{workDocDir}/.progress/{feature}.json` — `{feature}` is the kebab-case form of the tool name
(`get_hotel_bookings` → `get-hotel-bookings`).

Created by `mcp-code` (per tool). Updated by pipeline skills (mcp-code, mcp-verify, mcp-review,
mcp-fix, mcp-debug, mcp-commit).

## Schema

Every timestamp (`createdAt`, `updatedAt`, `*.timestamp`) is UTC, whole seconds, `Z`-suffixed —
`date -u +%Y-%m-%dT%H:%M:%SZ` — because `mcp-verify`/`mcp-progress` compare `updatedAt` textually
against a file mtime in the same shape; a local offset would compare as a different instant.

```json
{
  "feature": "get-hotel-bookings",
  "tool": "get_hotel_bookings",
  "toolClass": "com.example.mcp.tools.BookingTools",
  "workDocument": "work/features/get-hotel-bookings.md",
  "createdAt": "2026-03-30T10:00:00Z",
  "updatedAt": "2026-03-30T15:30:00Z",
  "specSource": {
    "planFile": "docs/specs/booking-reports/.implementation/mcp/plan.json",
    "tool": "get_hotel_bookings",
    "feature": "booking-reports"
  },
  "pipeline": {
    "status": "implementing",
    "scenarios": { "total": 9, "completed": 6 },
    "verification": {
      "status": "pass",
      "timestamp": "2026-03-30T14:00:00Z",
      "compilation": { "status": "pass", "errors": 0 },
      "checkstyle": { "status": "skip", "violations": 0 },
      "tests": { "status": "pass", "passed": 212, "total": 212 },
      "contract": { "status": "pass", "snapshotChanged": true, "changelogChanged": true },
      "build": { "status": "pass" },
      "coverage": { "status": "skip", "linePercent": null, "thresholdEnforced": false },
      "tree": "242239b9581f30c19dd8abf0f67d245102d75dbd",
      "committed": true
    },
    "review": {
      "status": "fail",
      "timestamp": "2026-03-30T14:30:00Z",
      "overallScore": 7.4,
      "criticalIssues": 1,
      "totalIssues": 5,
      "reportFile": "work/features/.progress/review-report-get-hotel-bookings.json",
      "scope": "full",
      "manifest": "work/features/.progress/review-manifest-get-hotel-bookings.txt"
    },
    "fix": {
      "status": "completed",
      "round": 1,
      "timestamp": "2026-03-30T15:00:00Z",
      "fixed": 4,
      "escalated": 1,
      "tddCount": 2,
      "directCount": 1,
      "contractCount": 1,
      "reportFile": "work/features/.progress/fix-report-get-hotel-bookings.json"
    },
    "build": {
      "timestamp": "2026-03-30T15:20:00Z",
      "previousStatus": "done",
      "by": "mcp-verify",
      "filesModified": ["src/main/java/.../BookingTools.java"]
    },
    "debug": {
      "status": "resolved",
      "previousStatus": "implementing",
      "timestamp": "2026-03-30T15:30:00Z",
      "classification": "test-failure",
      "rootCause": "Masking applied before sanitizing, so a zero-width character split the mask",
      "filesModified": ["src/main/java/.../BookingTools.java"]
    }
  }
}
```

`pipeline.review.scope` is `full` or `delta` (`skills/mcp-review` Step 2.8); `pipeline.review.manifest` is the `scripts/review-scope.sh` fingerprint of the files that review saw — the next review diffs against it. Absent `scope` or `manifest` (older records) → the next review is full.

## Status Values

| Status | Meaning | Set By |
|--------|---------|--------|
| `planned` | Tool plan generated from spec, no work yet | (tracked in the spec progress file, not in this pipeline) |
| `implementing` | TDD in progress (some `- [ ]` remain) | mcp-code |
| `implemented` | All scenarios complete (`- [x]`) and the final build passed | mcp-code |
| `verified` | Compilation + tests + contract + build pass, checkstyle/coverage PASS or SKIP (`Overall: PASS`); `verification.tree` is the `scripts/source-tree-hash.sh` value of the tree it ran on — mcp-review and mcp-commit recompute it and refuse (or question) the status on a changed tree until `verification.committed` says the record has been consumed | mcp-verify |
| `verify-failed` | One or more verification rows failed | mcp-verify |
| `reviewed` | Review passed with warnings/suggestions, or a **delta** review passed (`review.scope: delta` — only the files changed since the previous review were re-judged; a `--full` review is the way to `done`) | mcp-review |
| `review-failed` | Review failed (a dimension < 7 or a critical issue) | mcp-review |
| `fixing` | Review fixes applied, awaiting re-verification | mcp-fix |
| `done` | A **full** review passed clean, ready to commit | mcp-review |
| `resolved` | The code changed outside the review loop, or the committed code is not the code that earned the status (mcp-debug resolved an issue; `mcp-verify --fix` kept an edit on a `verified`/`reviewed`/`done` tool; `mcp-commit` committed a staged tree the user confirmed despite a mismatch) — re-verify. `previousStatus` sits in `pipeline.debug` or `pipeline.build`, whichever has the newer `timestamp` | mcp-debug, mcp-verify, mcp-commit |
| `escalated` | Manual intervention required; `mcp-verify` re-admits the tool once it is resolved | mcp-fix, mcp-debug |

## State Transitions

Note: `planned` is tracked in the spec progress file (by `mcp-plan`), not in this pipeline, which
starts at `implementing` when `mcp-code` runs.

```
implementing → implemented → verified ─→ reviewed ─→ mcp-commit
                                     └→ done ────→ mcp-commit
                  ↓            ↓          ↓
            verify-failed  review-failed  fixing
                  ↓            ↓          ↓
       mcp-verify --fix     mcp-fix    mcp-verify (the fix changed code)
                  ↓            ↓          ↓
              verified       fixing    verified → mcp-review → reviewed/done
                               ↓
                           escalated (all issues escalated, or the build fails after fixes)

At any point:
  mcp-debug → resolved | escalated | (status unchanged: not reproduced, or no file modified)
  mcp-verify --fix, edit kept → other verified/reviewed/done tools → resolved
  mcp-commit, confirmed staged-tree mismatch → that reviewed/done tool → resolved
  resolved → mcp-verify → verified | verify-failed
  escalated → (manual intervention) → mcp-verify → verified | verify-failed
```

`pipeline.build` records a status change made outside the review loop: `by` is `mcp-verify` (a
`--fix` edit kept) or `mcp-commit` (a confirmed mismatch), `previousStatus` the status it replaced,
`filesModified` the edited (or staged) paths.

## Read-Modify-Write Rule

When updating the progress file:
1. Read the latest file content immediately before writing
2. Merge only the fields being changed — preserve all existing fields
3. Write the complete merged object

This prevents race conditions and data loss when multiple skills update the file.

## Optional Fields

### `specSource` (spec-driven mode only)

Present when the tool was planned by `mcp-plan` and implemented by `mcp-code` in spec-driven mode.

- `planFile`: path to the plan.json that drove the work document
- `tool`: the tool name from the plan that this work document covers
- `feature`: the planning feature name (may differ from the tool's own feature name)

## Directory Structure

```
{workDocDir}/
├── get-hotel-bookings.md          <- Work document (tool spec + scenarios)
├── list-channels.md
├── .progress/                     <- Pipeline state (gitignore it, or commit it — team choice)
│   ├── get-hotel-bookings.json    <- Progress for get_hotel_bookings
│   ├── review-report-get-hotel-bookings.json
│   ├── fix-report-get-hotel-bookings.json
│   ├── audit-security-project.json          <- Focused audit (mcp-review --dimension)
│   └── fix-report-audit-security-project.json   <- mcp-fix --report on that audit
```

Every skill that scans `.progress/*.json` for progress files excludes the report files:
`review-report-*`, `fix-report-*` and `audit-*`.
