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
- **Pure transforms are pinned to the legacy output (golden test), not spot-checked.** When a phase
  ports a **pure transform** — a sanitizer, formatter, serializer, URL builder, any
  input→string/DOM function — the test target is the **full legacy output** over a **representative
  input set** (a golden / differential test), not a handful of behavior assertions. Behavior
  spot-checks (dangerous tag removed, `javascript:` stripped, script allowed) are a **supplement,
  never a substitute**: a port can pass all of its own spot-checks and still reshape the output —
  `<body>` wrapper dropped, `outerHTML`→`innerHTML`, array↔scalar, `null`↔`''`. "Passes its own
  tests" and "produces the legacy output" are **different claims**; only the golden test proves the
  second. Port the legacy call's options verbatim (`angular-to-react-mapping.md` → **pipes-directives**),
  and record any deliberately-agreed difference (e.g. an `iframeResizer` script replaced by a React
  binding) explicitly rather than letting it drift. Origin: OMH-708.
