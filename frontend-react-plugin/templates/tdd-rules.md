# TDD Rules for React Feature Generation

Reference document loaded by TDD cycle agents. Adapted from [obra/superpowers TDD skill](https://github.com/obra/superpowers) for React feature code generation with MSW, Vitest, and Testing Library.

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Write code before the test? Delete it. Start over. No exceptions.

## Red-Green-Refactor Cycle

### RED — Write Failing Test

One minimal test showing what should happen.

- One behavior per test — if the name contains "and", split it
- A name that describes the behavior, not the implementation
- Real code paths (mocks only at the network boundary, via MSW)
- An anchor to the spec — see "Anchors" below

**Stub-first for import resolution.** The implementation does not exist yet, so the import would raise MODULE_NOT_FOUND and the test would *error* rather than *fail*. Create a minimal stub:

```typescript
// Stub: {baseDir}/features/{feature}/api/entityApi.ts
export const entityApi = {} as Record<string, never>;
```

Now the import resolves and the test fails on its assertion — the correct RED state.

### VERIFY RED — Watch It Fail (MANDATORY)

> Run from `{appDir}` — see CLAUDE.md § Build Command Working Directory.

```bash
npx vitest run {testFile} --reporter=verbose
```

The test must **fail**, not error, and the message must be the assertion you expected — not a typo or a wrong path.

- **Passes immediately?** The assertion is vacuous, or it tests behavior that already exists. Fix the test.
- **Errors instead of failing?** Fix the error, re-run until it fails correctly.

### GREEN — Minimal Implementation

The simplest code that passes. Replace the stub.

- Implement only what the test demands
- Follow plan.json exactly — no additions, no "improvements"
- Do not refactor other code during GREEN

### VERIFY GREEN — Watch It Pass (MANDATORY)

Same command. Every test in the file passes and the output is pristine — no warnings, no unhandled errors. **Test fails? Fix the implementation, not the test.**

### VERIFY THE TEST — Survive a Mutation (MANDATORY)

Green proves the test and the code agree. It does not prove the test would notice if the code were wrong — and here they share an author, written from one reading of the spec in one session. A misreading produces a test and an implementation that agree with each other, and the phase goes green anyway.

So break the **one behavior you just made pass** in the production code: delete the guard, invert the condition, return the other branch, or stop passing the prop. Re-run. Confirm it goes **red**. Restore the code and re-run once to confirm green.

- Stays green → the test asserts nothing about that behavior. Strengthen the assertion and repeat.
- Scope is the behavior just written — one mutation, seconds. Not the file, not the suite.

### REFACTOR — Clean Up (Optional)

After GREEN only: remove duplication, improve names, extract helpers. Keep tests green. Do not add behavior.

## Anchors — cite the spec, not a derived artifact

Every test carries a source comment naming where its expected behavior came from:

```typescript
// TS-014 — docs/specs/{feature}/{lang}/test-scenarios.md:88
```

The anchor points at the **spec**: the scenario (`TS-nnn`), requirement (`FR-nnn`), or validation rule, with `file:line`. It must **not** point at `plan.json` or any other generated artifact — those were written from the same reading the test was, so citing one proves nothing and a reviewer following it learns nothing the test did not already assume.

This is what makes the reading checkable: `test-reviewer` follows the anchor and confirms the cited line says what the test assumes. Behavior with no spec line to cite — a rendering detail, a defensive branch — carries no anchor. Do not invent one.

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

**Rule:** Assert on component output (what renders) or on return values, never on whether a mock was called.

### Anti-Pattern 2: Test-Only Methods in Production

```typescript
// BAD: Adding a method only used in tests
class EntityStore {
  _resetForTest() { /* ... */ }
}

// GOOD: Use the store's public API
beforeEach(() => {
  useEntityStore.setState(initialState);
});
```

**Rule:** Never add production methods that only tests call. Test helpers belong in test files or test-utils.

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

**Rule:** Before mocking, ask what side effects the real code has and whether the test depends on them. Mock at the lowest level necessary — for API calls, that is MSW.

### Anti-Pattern 4: Incomplete Mocks

```typescript
// BAD: Partial response missing fields downstream code uses
server.use(
  http.get('/api/v1/entities', () =>
    HttpResponse.json({ items: [] }) // Missing: total, page, pageSize
  ),
);
```

**Rule:** An MSW handler response must include **every** field in the TypeScript interface. Partial responses fail silently downstream.

## Mock Strategy

| Mock this (unavoidable boundary) | With | Why |
|---|---|---|
| HTTP API calls | MSW (`server.use`) | Network boundary — cannot hit a real backend |
| Browser APIs (localStorage, …) | Vitest mocks | Environment boundary |
| i18n `t()` | i18n test wrapper | Avoids loading the full i18n config |
| React Router context | `MemoryRouter` wrapper | Router hooks need a context |

| Never mock this | Why |
|---|---|
| Zustand stores | Test real state management |
| Components a page imports | Test real composition, not stubs |
| Utility functions (`cn`, `formatDate`) | Pure — test them directly |
| Factories / fixtures | Test infrastructure — always real |
| Validation logic | Business logic — must be tested for real |

## Phase Completion Checklist

- [ ] Every function/component has at least one test
- [ ] Watched each test fail before implementing, for the expected reason (RED verified)
- [ ] Wrote minimal code to pass each test — no extras
- [ ] All tests pass, output pristine (GREEN verified)
- [ ] Each new behavior survived a mutation (broke it, saw red, reverted, re-confirmed green)
- [ ] Each test carries a spec anchor (`TS-nnn` / `FR-nnn` + `file:line`), never a `plan.json` reference
- [ ] Tests use real code — MSW only at the network boundary
- [ ] No test-only methods in production code
- [ ] Mock responses complete (all interface fields)

## Rationalizations — the thought IS the warning

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. The test takes 30 seconds. |
| "I'll write tests after" | A test that passes immediately proves nothing. RED is mandatory. |
| "Already manually verified" | Ad-hoc ≠ systematic. No record, no re-run, no regression catch. |
| "Deleting the implementation and restarting is wasteful" | Sunk cost. Unverified code is debt, not progress. |
| "Keep it as reference, then write tests" | You will adapt the test to it. That is testing-after. Delete means delete. |
| "Test is hard to write, skip it" | Hard to test = hard to use. Simplify the design instead. |
| "TDD will slow me down" | TDD is faster than debugging. |
| "plan.json is too complex for one-test-at-a-time" | Complex plans need more discipline, not less. |
| "MSW setup is too heavy for this test" | MSW is the only acceptable mock boundary. Set it up. |
| "It went green, so the test works" | Green means they agree. Mutate it and find out. |
| "This is different because…" | No. That thought IS the rationalization. |

**Violating the letter of the rules is violating the spirit of the rules.**

Stop and start over on any of: implementation written before its test; a test that passes on the first run; assertions on mock call counts instead of rendered output; mock setup longer than the test; production methods added "for testing"; a failure you cannot explain.
