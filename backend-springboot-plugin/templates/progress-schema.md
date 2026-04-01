# Pipeline Progress State

Lightweight state tracking for the feature implementation pipeline.

## File Location

`{workDocDir}/.progress/{feature}.json`

Created by `be-crud` (per entity). Updated by pipeline skills (be-crud, be-code, be-verify, be-review, be-fix, be-debug).

## Schema

```json
{
  "feature": "create-employee",
  "workDocument": "work/features/create-employee.md",
  "createdAt": "2026-03-30T10:00:00Z",
  "updatedAt": "2026-03-30T15:30:00Z",
  "specSource": {
    "planFile": "docs/specs/employee-management/.implementation/backend/plan.json",
    "entity": "Employee",
    "feature": "employee-management"
  },
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
      "previousStatus": "implementing",
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
| `planned` | Backend plan generated from spec, no scaffold yet | (tracked in spec progress file, not in backend pipeline) |
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

Note: `planned` status is tracked in the spec progress file (by `be-plan`), not in the backend pipeline. The backend pipeline starts at `scaffolded` when `be-crud` is used, or at `implementing` when `be-code` is run directly without `be-crud`.

```
scaffolded → implementing → implemented → verified ─→ reviewed ─→ be-commit
                                                   └→ done ────→ be-commit
                                    ↓            ↓          ↓
                              verify-failed  review-failed  fixing
                                    ↓            ↓          ↓
                                be-build     be-fix    be-review
                                    ↓            ↓     (re-review)
                                be-verify    fixing → reviewed/done
                                    ↓
                                verified

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

## Optional Fields

### `specSource` (spec-driven mode only)

Present when the feature was scaffolded from a planning-plugin spec via `be-plan` + `be-crud`.

```json
{
  "specSource": {
    "planFile": "docs/specs/{feature}/.implementation/backend/plan.json",
    "entity": "Employee",
    "feature": "employee-management"
  }
}
```

- `planFile`: path to the backend plan.json that drove scaffold generation
- `entity`: the specific entity name from the plan that this work document covers
- `feature`: the planning-plugin feature name (may differ from the work document feature name)

Set by: `be-crud` (spec-driven mode only)

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
