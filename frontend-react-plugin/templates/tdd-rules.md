# TDD Rules for React Feature Generation

Reference document loaded by TDD cycle agents. Adapted from [obra/superpowers TDD skill](https://github.com/obra/superpowers) for React feature code generation with MSW, Vitest, and Testing Library.

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Write code before the test? Delete it. Start over. No exceptions.

## Red-Green-Refactor Cycle

### RED — Write Failing Test

Write one minimal test showing what should happen.

**Requirements:**
- One behavior per test — if the name contains "and", split it
- Clear name describing the behavior being tested
- Real code paths (mocks only for network boundary via MSW)
- Source comment linking to spec scenario (`// TS-nnn`)

**Stub-first for import resolution:**

Since tests are written before implementation, imports will fail. Create minimal stubs so the test FAILS on assertions, not on import errors:

```typescript
// Stub: src/features/{feature}/api/entityApi.ts
// Minimal stub — just enough for import resolution
export const entityApi = {} as Record<string, never>;
```

The stub ensures:
- Import resolves (no MODULE_NOT_FOUND error)
- Test fails on assertion (correct RED state)
- Failure message is clear: "entityApi.getList is not a function" or assertion mismatch

### VERIFY RED — Watch It Fail (MANDATORY)

```bash
npx vitest run {testFile} --reporter=verbose
```

Confirm:
- Test **fails** (not errors from missing modules or syntax)
- Failure message is the expected assertion failure
- Fails because feature is not implemented (not because of typos)

**Test passes immediately?** Something is wrong — you're testing existing behavior or the assertion is vacuous. Fix the test.

**Test errors (not fails)?** Fix the error (missing import, wrong path), re-run until it fails correctly.

### GREEN — Minimal Implementation

Write the simplest code to make the test pass. Replace the stub with real implementation.

**Rules:**
- Only implement what the test demands — no extra features
- Follow plan.json spec exactly — no additions, no "improvements"
- Do not refactor other code during GREEN

### VERIFY GREEN — Watch It Pass (MANDATORY)

```bash
npx vitest run {testFile} --reporter=verbose
```

Confirm:
- All tests in the file pass
- Output is pristine (no warnings, no unhandled errors)

**Test fails?** Fix the implementation, not the test.

### REFACTOR — Clean Up (Optional)

After GREEN only:
- Remove duplication
- Improve names
- Extract helpers

Keep tests green throughout. Do not add behavior.

## Testing Anti-Patterns (MUST AVOID)

### Anti-Pattern 1: Testing Mock Behavior

```typescript
// BAD: Testing that the mock exists
test('calls API', async () => {
  const spy = vi.spyOn(entityApi, 'getList');
  render(<EntityListPage />);
  expect(spy).toHaveBeenCalled(); // Tests mock mechanics, not behavior
});

// GOOD: Test what the component renders
test('shows entity list on success', async () => {
  render(<EntityListPage />);
  await waitFor(() => {
    expect(screen.getAllByRole('row')).toHaveLength(4);
  });
});
```

**Rule:** Assert on component output (what renders) or function return values, not on whether a mock was called.

### Anti-Pattern 2: Test-Only Methods in Production

```typescript
// BAD: Adding a method only used in tests
class EntityStore {
  _resetForTest() { /* ... */ }
}

// GOOD: Use the store's public API or test utilities
beforeEach(() => {
  useEntityStore.setState(initialState);
});
```

**Rule:** Never add methods to production code that are only called by tests. Put test helpers in test files or test-utils.

### Anti-Pattern 3: Mocking Without Understanding

```typescript
// BAD: Over-mocking that breaks test logic
vi.mock('../stores/entityStore', () => ({
  useEntityStore: vi.fn(() => ({ list: [] })),
}));
// Now the test can't verify store interactions

// GOOD: Mock at the network boundary only (MSW)
server.use(
  http.get('/api/v1/entities', () =>
    HttpResponse.json({ items: [], total: 0, page: 1, pageSize: 20 })
  ),
);
```

**Rule:** Before mocking, ask: "What side effects does the real code have? Does my test depend on them?" Mock at the lowest level necessary — prefer MSW for API calls.

### Anti-Pattern 4: Incomplete Mocks

```typescript
// BAD: Partial response missing fields downstream code uses
server.use(
  http.get('/api/v1/entities', () =>
    HttpResponse.json({ items: [] }) // Missing: total, page, pageSize
  ),
);

// GOOD: Mirror the complete API response shape
server.use(
  http.get('/api/v1/entities', () =>
    HttpResponse.json({ items: [], total: 0, page: 1, pageSize: 20 })
  ),
);
```

**Rule:** MSW handler responses MUST include ALL fields defined in the TypeScript interface. Partial responses create silent failures.

### Anti-Pattern 5: Tests as Afterthought

Tests written after implementation pass immediately. Passing immediately proves nothing:
- Might test the wrong thing
- Might test implementation, not behavior
- Might miss edge cases

**Rule:** This is why the RED step exists. Seeing the test fail proves it tests something real.

## Mock Strategy for React Features

### What to mock (unavoidable boundaries)

| Boundary | Mock Tool | Reason |
|----------|-----------|--------|
| HTTP API calls | MSW (`server.use`) | Network boundary — cannot hit real backend |
| Browser APIs (localStorage, etc.) | Vitest mocks | Environment boundary |
| i18n `t()` function | i18n test wrapper | Avoid loading full i18n config |
| React Router context | `MemoryRouter` wrapper | Routing context required for hooks |

### What NOT to mock

| Real Code | Why Not Mock |
|-----------|-------------|
| Zustand stores | Test real state management behavior |
| Components imported by pages | Test real composition, not mock stubs |
| Utility functions (cn, formatDate) | Pure functions — test directly |
| Factories/fixtures | Test infrastructure — always use real |
| Validation logic | Business logic — must be tested for real |

## Gate Functions (Check Before Acting)

### Before adding a mock:

```
1. What side effects does the real code have?
2. Does this test depend on any of those side effects?
3. Can I test this without mocking? (prefer real code)
4. If I must mock, am I mocking at the lowest level?
5. Is my mock response complete (all interface fields)?
```

### Before asserting:

```
1. Am I testing real behavior or mock existence?
2. Does this assertion prove the feature works?
3. Would this assertion catch a regression?
```

### Before claiming RED verified:

```
1. Did the test fail (not error)?
2. Is the failure message the expected assertion failure?
3. Does it fail because the feature is missing (not a typo)?
```

### Before claiming GREEN verified:

```
1. Do ALL tests in the file pass?
2. Is the output pristine (no warnings)?
3. Did I only implement what the test demanded?
```

## Verification Checklist

Before marking a TDD phase complete:

- [ ] Every function/component has at least one test
- [ ] Watched each test fail before implementing (RED verified)
- [ ] Each test failed for the expected reason (feature missing, not typo)
- [ ] Wrote minimal code to pass each test (no extras)
- [ ] All tests pass (GREEN verified)
- [ ] Output pristine (no errors, no warnings)
- [ ] Tests use real code (MSW only for network boundary)
- [ ] No test-only methods added to production code
- [ ] Mock responses are complete (all interface fields)
- [ ] Each test has a `// TS-nnn` source comment

## Red Flags — STOP and Reassess

- Writing implementation before test
- Test passes immediately on first run
- Asserting on mock call counts instead of rendered output
- Mock setup is longer than the test logic
- Adding methods to production code "for testing"
- "This is too simple to test" — simple code breaks; test takes 30 seconds
- "I'll add tests after" — tests-after prove nothing; RED is mandatory
