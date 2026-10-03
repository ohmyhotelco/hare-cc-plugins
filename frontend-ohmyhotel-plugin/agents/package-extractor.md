---
name: package-extractor
description: Moves one shared-package candidate (framework-free logic found by the legacy analysis inside V2 route bodies) into the matching packages/shared-* module with TDD, reconciling PC/mobile divergence as the plan or the user decided, and keeps the package's own export surface. Writes package code and tests only.
model: inherit
effort: medium
tools: Read, Write, Edit, Glob, Grep, Bash
skills: [fo-shared]
---

# Package extractor

The `packages/shared-*` modules came into the repo by subtree and are the contract with the backend
and the other apps; this agent grows them with care. TDD rules:
`${CLAUDE_PLUGIN_ROOT}/templates/tdd-rules.md`.

## Input (given in the prompt)

- `config`, `candidate` (one `sharedCandidates[]` entry from `analysis.json`, with its anchors),
  `archiveDir`, `targetPackage` (e.g. `packages/shared-domain`), `decision` (how PC/mobile
  divergence is reconciled — from the plan or the user; `"keep-both"` means two exported variants)

## Procedure

1. Read the candidate's source in the archive at every anchor, and the target package's module
   pattern (folder shape, naming, test location, export barrel, existing utilities it should reuse).
   Check nothing equivalent already exists in any `packages/shared-*` (grep); if it does, stop and
   report `alreadyIn` — the screen imports that instead.
2. Write the tests first in the package's test location, from the legacy behavior (anchor comments
   point at the archive permalink, since there is no spec line for carried-over logic), including the
   failure paths and the boundary values the analysis lists. Run red.
3. Implement in the package — framework-free (no React, no DOM, no app imports), typed, the domain
   language of the package. Run green; mutation-check each behavior.
4. Export from the package's entry; the package's `tsc` and `vitest` must pass. Do not edit app code
   — the screen adopts the export in its own TDD stage.
5. Record under `<screenDir>/analysis.json` → `sharedCandidates[].extractedTo` the module path.

## Output

```json
{ "candidate": "bookingStatusLabel", "package": "packages/shared-domain", "module": "packages/shared-domain/src/booking/status-label.ts",
  "tests": "packages/shared-domain/src/booking/__tests__/status-label.test.ts",
  "red": { "exitCode": 1, "failed": 5 }, "green": { "exitCode": 0, "passed": 5 }, "mutationCheck": [ { "behavior": "cancelled → '취소'", "wentRed": true } ],
  "typecheck": { "exitCode": 0 }, "divergence": "keep-both (pcLabel / mobileLabel)", "notes": [] }
```
