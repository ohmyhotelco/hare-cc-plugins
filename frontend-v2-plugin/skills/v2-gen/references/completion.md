# v2-gen: Summary, next steps and mock-first guidance

Part of the `v2-gen` skill. `{pluginRoot}` is the plugin root the skill states.

### Step 5: Post-Generation Summary

Display comprehensive results:

```
Code Generation Complete for '{feature}' (TDD mode):

  TDD Results:
    Foundation:     {status} — {typeCount} types, {mockCount} mock files
    API TDD:        {status} — {testsPassed}/{testsTotal} tests
    Store TDD:      {status} — {testsPassed}/{testsTotal} tests
    Component TDD:  {status} — {testsPassed}/{testsTotal} tests
    Page TDD:       {status} — {testsPassed}/{testsTotal} tests
    Integration:    {status}

  Files created: {totalFiles}
    {file list grouped by category}

  Verification:
    TypeScript: {pass/fail}
    ESLint:     {pass/fail/skipped}
    Vitest:     {pass/fail} ({totalTestsPassed}/{totalTestsTotal})
    Build:      {pass/fail}

  Integration:
    Routes: {featureFile} → {centralFile} ({auto/manual})
    i18n:   {featureFile} → {centralFile} ({auto/manual})
```

### Step 6: Next Steps

> "Code generation complete. Recommended next steps:"
> "1. Verify: `/frontend-v2-plugin:v2-verify {feature}`"
> "2. Review: `/frontend-v2-plugin:v2-review {feature}`"
> "3. Fix issues (if any): `/frontend-v2-plugin:v2-fix {feature}`"

### Step 7: Mock-first Guidance (if `mockFirst` is `true`)

```
  Mock-first development:
    Start with mocks: VITE_ENABLE_MOCKS=true pnpm dev
    Start without mocks: pnpm dev
    Commit: public/mockServiceWorker.js (recommended)
```

### Step 8: Update Progress

Read `docs/specs/{feature}/.progress/{feature}.json` and update the `implementation` field:

```json
{
  "implementation": {
    "status": "generated | gen-failed",
    "mode": "tdd",
    "planFile": "docs/specs/{feature}/.implementation/frontend/plan.json",
    "generatedAt": "{ISO timestamp}",
    "filesCount": {totalFiles},
    "tddPhases": {
      "foundation": "completed",
      "api-tdd": "completed",
      "store-tdd": "completed",
      "component-tdd": "completed",
      "page-tdd": "completed",
      "integration": "completed"
    }
  }
}
```

**Status determination logic** — set `implementation.status` based on phase outcomes:
- All phases `"completed"` → `"generated"`
- Any phase `"failed"` AND user chose **Stop** → `"gen-failed"`
- Any phase `"skipped"` with **`skipKind: "auto"`** (a planned no-op — no-store-under-tanstack-query, or a delta phase with no changes) → does not block: treat it as completed for status purposes
- Any phase `"failed"`, or `"skipped"` with **`skipKind: "user"`** → `"gen-failed"` (incomplete generation must not enter review pipeline)
- `skipKind` is the discriminator, never the presence of free text: a missing `skipKind` on a `skipped` phase is treated as `"user"` (blocking), because a phase whose skip nobody classified is not a phase anyone confirmed was safe to omit
- Record each phase's actual status (`"completed"`, `"failed"`, `"skipped"`) in `tddPhases`

**Also remove `implementation.e2e`**: regeneration changed the code, so a prior E2E pass is stale
evidence — see 2-D.6 (**Update Progress (Delta)**) for the same rule on the delta path.

**Merge rule**: Read the existing progress file, merge changes into the existing `implementation` object preserving all other fields (e.g., `verification`, `review`, `fix`, `debug` — but not `e2e`, removed above), then write back the complete file.

Update generation-state.json with final status.
