# TDD rules for screen generation

Read by `tdd-cycle-runner`, `delta-modifier` and `review-fixer`. Adapted from the obra/superpowers TDD
skill for React code generated with Vitest, Testing Library and MSW.

## The cycle, and why each step records something

Every behavior goes through one cycle; every step leaves evidence in the stage result so a reviewer
can tell what was actually run.

1. **Red — write the test first.** One behavior per test (a name with "and" is two tests); the name
   describes the behavior, not the implementation; real code paths, with MSW as the only network mock;
   a spec anchor (below). Create a minimal stub for the implementation first so the import resolves
   and the test fails on its assertion, not on `MODULE_NOT_FOUND`.
2. **Run it and record the failure.** `npx vitest run <testFile> --reporter=verbose` from the app
   directory (the package directory for API additions). The expected outcome is a failing assertion
   with the message you anticipated. A test that errors has a wrong path or syntax — fix it and run
   again. A test that passes against a stub asserts nothing — fix the test. Record the failure count
   and reason.
3. **Green — the minimum implementation.** Replace the stub with the simplest code the test demands,
   following the plan entry; do not add behavior the plan does not list and do not refactor other
   code in this step. Before writing new logic, walk the reuse ladder: something already in the repo →
   a platform built-in (`Intl`, `URLSearchParams`, CSS) → the design system or an existing ui-kit
   primitive → an installed dependency → new code, in that order.
4. **Run it and record the pass.** Same command; every test in the file passes and the output has no
   warnings or unhandled rejections. A failure is fixed in the implementation, not in the test; after
   three fix-and-run rounds, stop and report the failure as the stage result.
5. **Mutation check — prove the test can fail.** Green shows the test and the code agree, and both
   were written by the same agent from one reading of the spec; a misreading makes them agree for the
   wrong reason. For each behavior just written: break exactly it in the production code (delete the
   guard, invert the condition, return the other branch), run the file, confirm red, restore, run once
   more, confirm green. A mutation that stays green means the assertion is vacuous — strengthen it and
   repeat. Record each mutation (what was broken, went red or not, assertion strengthened or not) in
   `mutationCheck[]`. One mutation per behavior, seconds each; never a whole file, never left in place.
6. **Refactor, if useful.** Remove duplication, improve names, extract helpers within the screen; run
   the file again; revert the refactor if it goes red.

## Anchors — cite the spec, not a derived artifact

Each test carries a comment naming where its expected behavior comes from, with file and line:

```typescript
// TS-014 — specs/01-main-page/ko/main-page-test-scenarios_ko.md:88
```

Cite the spec snapshot (`TS-nnn`, `FR-nnn`, `FR-nnn BR-nnn`, a validation rule), never
`implementation-plan.json`: the plan was written from the same reading the test was, so citing it
proves nothing, and `test-reviewer` follows anchors to confirm the cited line says what the test
assumes. Behavior with no spec line (a rendering detail, a defensive branch) carries no anchor.

## Request bodies

A body builder that spreads shared params (`{ ...commonParams(), ...payload }`) can re-add a field the
endpoint's schema deliberately omits, and TypeScript does not catch it (excess-property checks fire on
literals only). Return the body parsed through the endpoint's zod schema (non-strict, so it strips
what the schema omits) and pin it with a key-set test:

```typescript
expect(Object.keys(buildCreateBookingBody(input)).sort()).toEqual(['checkIn', 'checkOut', 'guestCount', 'roomTypeId']);
```

`toEqual` on the sorted keys is the point; `toMatchObject` passes with an extra field present.

## What to mock

| Mock | With | Because |
|---|---|---|
| HTTP calls | MSW (`server.use`) | the network is the one boundary a unit test cannot cross |
| Browser APIs (storage, matchMedia) | Vitest mocks | environment boundary |
| `useT` | the app's i18n test wrapper | avoids loading the resource bundle |
| Router context | plain render for page bodies; `createRoutesStub` only when the body uses router hooks | route modules are checked by typegen, tsc, build and E2E, not unit tests |
| Query context | a fresh `QueryClient` per test with `retry: false` | assertions run against MSW responses |

Do not mock components the screen composes, utility functions, factories, fixtures or validation
logic: a test that mocks them checks the mock, not the behavior.

## Anti-patterns the reviewers look for

- Asserting on mock call counts instead of rendered output or returned data.
- A mock response missing fields of the interface (the test passes, the real response breaks).
- Methods added to production code only so a test can reach in.
- Mock setup longer than the test.
- A test whose failure you cannot explain — stop and find out before continuing.

## Stage result

The stage reports, per test file: the red run (failures, reasons), the green run (pass count,
duration), the mutation checks, the TypeScript check, and the files written. "Looks complete" is not a
result; a run that did not happen is reported as not run, with the reason.
