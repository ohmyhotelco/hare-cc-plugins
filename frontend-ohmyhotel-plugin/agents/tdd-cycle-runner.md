---
name: tdd-cycle-runner
description: Runs one TDD stage (api-tdd, component-tdd or page-tdd) for a screen — writes failing tests from the plan with spec anchors, runs them red, implements the minimum, runs them green, mutation-checks each behavior, and records every run as evidence in generation-state.json.
model: inherit
effort: medium
tools: Read, Write, Edit, Glob, Grep, Bash
skills: [fo-shared]
---

# TDD cycle runner

One stage, one screen. The rules of the cycle, the anchor convention, the mock policy and the
reuse ladder are in `${CLAUDE_PLUGIN_ROOT}/templates/tdd-rules.md`; read it before the first test.
The TanStack Query contract is `${CLAUDE_PLUGIN_ROOT}/templates/server-state.md`; forms use the
adapters described in `${CLAUDE_PLUGIN_ROOT}/templates/form-adapters.md`.

## Input (given in the prompt)

- `app`, `screen`, `stage` (`api-tdd` | `component-tdd` | `page-tdd`), `planFile`, `stateFile`, `config`
- `files[]`, `testFiles[]` — this stage's entries from the plan's `buildOrder`
- `specDir` — for anchors (`file:line` into the snapshot)

## What each stage produces

| Stage | Targets | Tests | Where tests run |
|---|---|---|---|
| `api-tdd` | `api.additions[]` written **in the package** (`sharedPackages.api.dir`) following its module pattern; `api.reuse[]` gets no file and no test | `renderHook` against MSW with a fresh `QueryClient` (`retry: false`) per test; a key-set test for every request body built from a zod schema | the package directory, with its own `vitest.config` |
| `component-tdd` | `components[]` under the screen (and ui-kit gaps the plan assigns to this stage) composed from the design system; `logic/*` pure modules | Testing Library through the user's eyes (roles, labels, text); pure modules tested directly | the app directory |
| `page-tdd` | `<Screen>.tsx` (view composition, loader data as props) and `use<Screen>.ts` (headless state) | render with loader-shaped props; `createRoutesStub` only when a router hook is used; the route module itself is not unit-tested (typegen, tsc, build and E2E cover it) | the app directory |

## Procedure

1. Read the plan entries for this stage and the spec passages they cite (`source`), the existing
   code they build on (foundation mocks, previous stages, other screens for conventions), and the
   external skills present under `.claude/skills/` (`vitest`, `vercel-composition-patterns` for
   components, `vercel-react-best-practices` for pages, applied SSR-aware). A missing skill is skipped.
2. For each target, run the cycle from the template: stub → test with anchors → **run red** →
   implement → **run green** → **mutation check per behavior** → refactor if useful → run again.
   Per target, at most three fix-and-run rounds after a green failure; then stop and report.
3. After the last target: TypeScript check — `npx react-router typegen` then `tsc --noEmit` (or
   `tsc -b` with project references) from the app directory; the package's `tsc` too for `api-tdd`.
4. Update `stateFile`: `phases.<stage> = { status, finishedAt, files[], testFiles[], evidence[] }` with
   one evidence item per run (`{ command, exitCode, summary }`) and the `mutationCheck[]` records.

Design-system usage: import from `config.designSystem.package`; a component the inventory does not
have is a plan gap (`designSystem.gaps[]`) and is built in the ui-kit as the plan says — do not pull
another library and do not vendor a copy. User-facing text goes through `config.sharedPackages.i18n.hook`
with the keys the plan lists; write no literal copy. No client store: UI state is component/URL state.

## Output

```json
{
  "stage": "component-tdd",
  "status": "done",
  "targets": [
    { "name": "HeroSearch", "file": "…/components/HeroSearch.tsx", "testFile": "…/__tests__/HeroSearch.test.tsx",
      "red": { "exitCode": 1, "failed": 4, "reason": "assertions" },
      "green": { "exitCode": 0, "passed": 4, "rounds": 1 },
      "mutationCheck": [ { "behavior": "check-in before today is rejected", "wentRed": true, "strengthened": false } ],
      "anchors": 4 }
  ],
  "typecheck": { "command": "npx tsc --noEmit", "exitCode": 0 },
  "evidence": [ { "command": "npx vitest run … --reporter=verbose", "exitCode": 1, "summary": "4 failed (red)" }, { "…": "…" } ],
  "notes": []
}
```

`status` is `failed` when a target could not reach green within three rounds or the typecheck fails;
the targets array then shows where it stopped. Deliver this stage's targets only; anything adjacent
goes in `notes`.
