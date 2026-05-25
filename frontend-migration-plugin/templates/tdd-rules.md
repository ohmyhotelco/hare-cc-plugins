# TDD Rules (Generation Phases)

The discipline `tdd-cycle-runner` follows. Adapted for migration: behavior comes from the legacy
Angular source (via `analysis.json` + `migration-plan.json`), not a greenfield spec.

## Iron law
No production code without a failing test first.

## Red → Green → Refactor
1. **Red** — write the test for one unit of planned behavior (ported from the legacy logic +
   its edge cases). Stub the module so it fails on the **assertion**, not on MODULE_NOT_FOUND.
   Run Vitest from `{appDir}`. **Read the output; confirm it fails.**
2. **Green** — minimal implementation to pass, applying `angular-to-react-mapping.md`. Run Vitest.
   **Read the output; confirm it passes.**
3. **Refactor** — clean up; keep green.

## Verify RED and GREEN are mandatory
Actually run Vitest and read the summary line. Never skip, never assume. This is the CLAUDE.md
"evidence before claims" 5-step gate applied to tests:
IDENTIFY → RUN → READ → VERIFY → CLAIM.

## Phase isolation
Each phase (`api → store → component → page → integration`) runs in its own agent session. The
coordinator passes only that phase's parameters — no conversation context leaks between phases
(subagent isolation).

## Stub-first for imports
Create minimal stubs so tests fail on assertions, not on missing modules.

## Anti-patterns (do not)
- Test mock behavior — assert on component output / return values instead.
- Add test-only methods to production code.
- Create incomplete mocks — MSW responses must match the full TypeScript interface.
- Mock anything but the network boundary — use real stores, real components.
- Claim a pass you did not run.

## Migration-specific
- Import extracted logic from `@omh/shared-*`; never re-implement what `fm-extract` produced.
- Preserve legacy behavior exactly (parity is gated later by `fm-e2e`/`fm-parity`) — including
  the AuthGuard login-modal UX and the API response envelope handling.
- Tag each test with a `// scenario` / `// analysis:file:line` comment for traceability.
