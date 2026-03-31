# Pipeline Progress State

Lightweight state tracking for the feature implementation pipeline.

## File Location

`{workDocDir}/.progress/{feature}.json`

Created by `be-code` or `be-crud`. Updated by pipeline skills (be-verify, be-review, be-fix, be-debug).

## Schema

```json
{
  "feature": "create-employee",
  "workDocument": "work/features/create-employee.md",
  "createdAt": "2026-03-30T10:00:00Z",
  "updatedAt": "2026-03-30T15:30:00Z",
  "pipeline": {
    "status": "implementing",
    "scenarios": {
      "total": 5,
      "completed": 3
    },
    "verification": {
      "status": "pass",
      "timestamp": "2026-03-30T14:00:00Z",
      "compilation": { "status": "pass", "errors": 0 },
      "checkstyle": { "status": "pass", "violations": 0 },
      "tests": { "status": "pass", "passed": 25, "total": 25 },
      "build": { "status": "pass" }
    },
    "review": {
      "status": "fail",
      "timestamp": "2026-03-30T14:30:00Z",
      "overallScore": 7.5,
      "criticalIssues": 1,
      "totalIssues": 5,
      "reportFile": "work/features/.progress/review-report-create-employee.json"
    },
    "fix": {
      "status": "completed",
      "round": 1,
      "timestamp": "2026-03-30T15:00:00Z",
      "fixed": 4,
      "escalated": 1,
      "tddCount": 2,
      "directCount": 2,
      "reportFile": "work/features/.progress/fix-report-create-employee.json"
    },
    "debug": {
      "status": "resolved",
      "timestamp": "2026-03-30T15:30:00Z",
      "classification": "test-failure",
      "rootCause": "Missing @Transactional on executor",
      "filesModified": ["src/main/java/.../CreateEmployeeCommandExecutor.java"]
    }
  }
}
```

## Status Values

| Status | Meaning | Set By |
|--------|---------|--------|
| `scaffolded` | CRUD scaffold generated, no tests yet | be-crud |
| `implementing` | TDD in progress (some `- [ ]` remain) | be-code |
| `implemented` | All scenarios complete (`- [x]`) | be-code |
| `verified` | Build + checkstyle + tests all pass | be-verify |
| `verify-failed` | One or more verification steps failed | be-verify |
| `reviewed` | Code review passed (with warnings) | be-review |
| `review-failed` | Code review has critical issues | be-review |
| `fixing` | Review fixes being applied | be-fix |
| `done` | Review passed clean, ready to commit | be-review |
| `resolved` | Debug issue fixed | be-debug |
| `escalated` | Manual intervention required | be-fix, be-debug |

## State Transitions

```
scaffolded → implementing → implemented → verified → reviewed → done
                                  ↓            ↓          ↓
                            verify-failed  review-failed  fixing
                                  ↓            ↓          ↓
                              be-build     be-fix    be-review
                                  ↓            ↓     (re-review)
                              verified     fixing → reviewed/done

At any point:
  be-debug → resolved | escalated
  resolved → (re-enter pipeline at appropriate stage)
  escalated → (manual intervention, then re-enter)
```

## Read-Modify-Write Rule

When updating the progress file:
1. Read the latest file content immediately before writing
2. Merge only the fields being changed — preserve all existing fields
3. Write the complete merged object

This prevents race conditions and data loss when multiple skills update the file.

## Directory Structure

```
{workDocDir}/
├── create-employee.md          <- Work document with scenarios
├── query-employee.md
├── .progress/                  <- Pipeline state (gitignored optional)
│   ├── create-employee.json    <- Progress for create-employee
│   ├── review-report-create-employee.json  <- Review report (per feature)
│   └── fix-report-create-employee.json     <- Fix report (per feature)
```
