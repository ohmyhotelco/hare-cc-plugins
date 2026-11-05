# fe-gen: Summary, next steps and mock-first guidance

Part of the `fe-gen` skill. `{pluginRoot}` is the plugin root the skill states.

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
> "1. Verify: `/frontend-react-plugin:fe-verify {feature}`"
> "2. Review: `/frontend-react-plugin:fe-review {feature}`"
> "3. Fix issues (if any): `/frontend-react-plugin:fe-fix {feature}`"

### Step 7: Mock-first Guidance (if `mockFirst` is `true`)

```
  Mock-first development:
    Start with mocks: VITE_ENABLE_MOCKS=true pnpm dev
    Start without mocks: pnpm dev
    Commit: public/mockServiceWorker.js (recommended)
```
