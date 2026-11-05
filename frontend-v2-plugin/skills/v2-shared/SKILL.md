---
name: v2-shared
description: Shared conventions for every frontend-v2-plugin agent and skill — code conventions, state files and locks, accepted deviations, design principles, build working directory, router-mode command matrix, TypeScript check. Preloaded into agents through their `skills:` frontmatter; not meant to be invoked by hand.
user-invocable: false
---

# Shared conventions (frontend-v2-plugin)

Agents receive this skill through `skills: [v2-shared]`. The plugin-root `CLAUDE.md` is maintainer notes and reaches no agent.

## Conventions
- Use only the configured component library (shadcn/ui by default; the external package + `ui-kit` under `componentLibrary: external`) — never install a second one
- 2-space indentation
- functional component + hooks
- Define TypeScript interface for all props/data
- icon-only button: aria-label required, decorative icon: aria-hidden="true"
- form control: must associate with <label> (htmlFor or wrapping)
- variable-length text: apply truncate / line-clamp-*
- full-page layout: set full height chain from html → body → #root → layout

### Mock-First Development
- `mockFirst: true` (default) — develop with MSW v2 without a backend
- Feature-level mock: `{baseDir}/features/{feature}/mocks/` (factories + fixtures + handlers)
- Factory + Fixture separation: factory generates data for tests, fixture provides fixed data for MSW handlers
- Hardcoded mock data — do not use external libraries like faker
- Environment variable toggle: activate only in dev mode with `VITE_ENABLE_MOCKS=true`
- Global MSW: `{baseDir}/mocks/` (browser.ts, server.ts, handlers.ts aggregator)

### Performance & Composition
- React performance patterns: see `.claude/skills/vercel-react-best-practices` (waterfall elimination, bundle optimization, re-render minimization)
  - **Router-mode conditional**: in `declarative`/`data` (Vite SPA) the server-side (RSC/SSR) rules do not apply — agent auto-skips. In `framework` mode the app is **not** a Vite SPA (per-route SSR/SSG), so the SSR/rendering-strategy rules **do apply** — do not skip them.
- Component composition patterns: see `.claude/skills/vercel-composition-patterns` (no boolean props, compound component, React 19 API)
- Web UI accessibility/design audit: see `.claude/skills/web-design-guidelines` (WebFetch latest guidelines during review)

### Lint & Format Gate

Specs live in `${CLAUDE_PLUGIN_ROOT}/templates/eslint-config.md` and `${CLAUDE_PLUGIN_ROOT}/templates/prettier-config.md`. This is the shared contract every agent and skill that scaffolds or checks them follows.

**Roles.** ESLint is a **hard** check (code quality) — exit ≠ 0 fails `v2-verify`. Prettier is **advisory** (formatting only) — reported, never blocking. `eslint-config-prettier` keeps the two from conflicting.

- The ESLint template is an ESLint v9 flat config with `strictTypeChecked` + `stylisticTypeChecked`, native flat config for react-hooks and react-refresh, and test-file overrides.
- **Detection / scaffold / skip** (uniform across `foundation-generator`, `integration-generator`, `v2-verify`):
  1. Glob for an existing config (`eslint.config.*` / `.eslintrc*`; `prettier.config.*` / `.prettierrc*`). Present → use as-is, never overwrite.
  2. Absent and the flag (`eslintTemplate` / `prettierTemplate`) is `true` or unset → generate from the template.
  3. Absent and the flag is `false` → skip silently.
  4. **Never auto-install deps.** Missing packages → print the `pnpm add -D …` line, skip the run, record `skipped` (not a failure).
- Commands, run from `{appDir}`: `npx eslint . 2>&1` (hard) and `npx prettier --check . 2>&1` (advisory). Never run `prettier --write` on the user's tree unasked.

### i18n Key Coverage

i18next resolves `language → fallback → the key itself` and never throws, so a missing or wrong key is invisible to `tsc`, ESLint, and unit tests alike. `foundation-generator` scaffolds an app-wide key-coverage spec (`{baseDir}/__tests__/i18n-key-coverage.test.ts`) that asserts every literal key resolves in **all** `i18n.languages`, that `{{param}}` values receive params, and that markup/entity-bearing values are not on the plain-text render path. Statically unresolvable (dynamic) keys are tallied as `uncheckable` with `file:line` and reported — never failed on, never dropped.

`v2-verify`'s existing `npx vitest run` makes it a hard gate; `v2-verify` asserts the spec's results **appear in that run** — file existence is not the test. No `i18n` config block → no spec, and the axis reports `skipped`. Contract: `${CLAUDE_PLUGIN_ROOT}/templates/i18n-key-coverage.md`.

### Routing Conventions
- Routes requiring authentication: wrap with `<ProtectedRoute>` → redirect to /login when unauthenticated (pass return destination via location.state.from)
- Routes requiring permissions: `<RoleRoute permissions={[...]}>` → redirect to /forbidden when unauthorized
- NavLink active state: use shadcn/ui `cn()` + `isActive` callback
- Axios 401 interceptor → /login redirect: use navigate ref pattern (do not directly import useNavigate)
- URL searchParams ↔ Zustand: bidirectional sync via useEffect + store subscription
- Internal navigation: use react-router `<Link>`, `<NavLink>`, `useNavigate` (do not use `<a>`, `window.location`)

## Communication Language

- Feature-level skills (v2-plan, v2-gen, v2-verify, v2-review, v2-fix, v2-e2e, v2-debug, v2-progress) read `workingLanguage` from `docs/specs/{feature}/.progress/{feature}.json`
- All user-facing output (summaries, questions, feedback, next-step guidance) must be in the working language
- Language name mapping: `en` = English, `ko` = Korean, `vi` = Vietnamese
- Keep that output to the length the result needs: lead with the outcome (pass/fail, what changed, what is blocked), then the evidence it rests on, then the next step. The JSON report is the complete record — the final message is a readout of it, not a second copy.

## Pipeline Rules

### State File Safety

State files (progress, generation-state, review-report, fix-report, debug-report) are critical for pipeline continuity.

**Read-Modify-Write rule**: When updating state JSON files:
1. Read the **latest** file content immediately before writing (do not use data cached earlier in the session)
2. Merge only the fields being changed — preserve all existing fields
3. Write the complete merged object

**Lock file**: A skill that mutates state acquires the lock before work and releases it on **every** exit — completion, refusal, a failed verification, or an agent that stops early. A *failed* acquire does not release that lock (it belongs to someone else), but the run still releases every lock it did take.

Two scopes, acquired in this order — **feature lock → app lock**, never the reverse:

| Lock | Scope | Held by |
| --- | --- | --- |
| `docs/specs/{feature}/.implementation/frontend/.lock` | one feature's state and code | `v2-gen`, `v2-verify`, `v2-review`, `v2-fix`, `v2-e2e` |
| `docs/specs/.app.lock` | every Read-Modify-Write of an **app-wide** file — the central route file (`App.tsx` / `router.tsx` / `{sourceBaseDir}/routes.ts`), `{sourceBaseDir}/i18n/config.ts`, `{sourceBaseDir}/mocks/handlers.ts` / `browser.ts` / `node.ts`, the shared layouts + their locale files under `{sourceBaseDir}/layouts/`, and the Phase 2 targets: `{apiPackage.entry}`, each `{i18nHook.resourcesDir}/{resourceFile}`, and `{externalComponents.uiKitDir}/**` (gap components, form adapters) | `foundation-generator`, `tdd-cycle-runner`, `integration-generator`, `delta-modifier`, `review-fixer` |

The feature lock does not protect app-wide files — two features in flight is a supported state, so two concurrent RMWs of one central file is too. Hold the app lock across the read-modify-write itself only: take it, re-read the file, edit, release. Never across an agent launch or a build.

**`baseDir` names two different directories, and the app-lock targets are under the wrong one if you confuse them.** Config `baseDir` is the **source root** (`app/src`); `plan.json` `baseDir` is the **feature directory** (`app/src/features/{feature}`). Agents receiving the feature directory (`delta-modifier`, `review-fixer`) resolve every app-wide path above against **`sourceBaseDir`**, passed separately — `{featureDir}/routes.ts` matches nothing, so an agent testing that path silently never takes the lock. Skills that read both must keep them in distinct variables; `v2-gen` already does this (`planBaseDir`), `v2-verify` must not overwrite one with the other.

Lock contents:

```json
{ "holder": "v2-verify", "pid": 49402, "pidStartedAt": "2026-08-11T14:58:12+09:00",
  "acquiredAt": "2026-08-11T15:21:04+09:00" }
```

- **Check `pid` first, and never break a lock whose process is still alive, however old it is.** `v2-gen` runs six TDD phases and legitimately exceeds 30 minutes.
- **The 30-minute rule is a ghost-lock sweep, not a timeout.** It applies only once the holder is gone: `pid` is absent, or no live process carries that id.
- **Never compare a running process's command against `holder`.** `holder` is a skill name (`v2-verify`); the process that owns the lock is the enclosing session (`claude`/`node`), whose command never matches it. Treating a mismatch as pid reuse would classify *every* legitimate lock as holder-less and sweep it at 30 minutes — the exact failure the `pid` check exists to prevent. Detect reuse with `pidStartedAt` instead: record the holder process's start time at acquire, and treat the lock as holder-less only when a live process with that id reports a **different** start time. When `pidStartedAt` is absent, liveness alone decides.
- `acquiredAt` — ISO-8601 **with time**. Date-only or unparseable makes a holder-less lock immediately sweepable; it never makes a live holder's lock removable.
- `pid` — a process that outlives the work, recorded with its `pidStartedAt`. `$$` from a one-shot Bash call is already dead and soon recycled, so record the enclosing session process or omit `pid` entirely, which is honest. When absent, `acquiredAt` alone decides.

**Exception**: `v2-debug` intentionally does NOT acquire a lock — it serves as an interrupt tool usable at any pipeline stage, even when another operation holds the lock. The debugger writes `debug-report.json` and updates `implementation.status` without locking.

### Deliberate Deviations (`openApprovals`)

A reviewer that re-raises a known, accepted deviation every round trains people to skim reviews. `plan.json` carries `openApprovals[]` as the one place a deviation is recorded:

```json
{ "id": "OA-1", "what": "phone validation accepts KR formats only",
  "why": "international formats are out of scope for v1 (spec §4.2 defers)",
  "status": "approved", "owner": "jieun.park", "at": "2026-08-11" }
```

- `spec-reviewer` and `quality-reviewer` **do not re-raise** an issue matching an `approved` entry; they list it once under "accepted deviations" so it stays visible.
- **`status: "pending"` is not approval, and neither is a free-text note.** Approval requires `status: "approved"` **and** a named `owner` — not `TBD`, not the agent. An agent may *propose* a `pending` entry; it may never approve one, or the pipeline would be approving its own shortcuts.
- Scope reduction without an approved entry is a review failure, not a smaller review. See § Design Principles, "Scope moves in both directions".

### Design Principles

Applied by every agent and skill in this plugin.

- **Subagent isolation.** Subagents never inherit session history. A coordinator constructs only the parameters each agent needs — no conversation context leaks between phases. Fresh judgement per task, no context pollution.
- **Delegation is named, not improvised.** Every phase that delegates names its agent explicitly; launch it with the `Agent` tool and only its declared params. Do not spawn an agent the skill did not name — in particular, never add a reviewer to double-check work a gate already covers. Verification belongs to the gate that owns it; `v2-clean-code` and `v2-test-review` are standalone audits a human invokes, not steps a phase adds for itself. When a skill names several independent agents, send them in one message so they run concurrently — but agents sharing a lock or a write target are **not** independent, whatever the fan-out looks like. The skill's own text wins over this paragraph.
- **Scope moves in both directions.** Silently narrowing what the plan asks for is the familiar failure; unrequested widening is the same failure mirrored. Do not add features, files, gates, or behavior the plan does not call for, and do not substitute your own judgement about what the task should have been. If the plan looks wrong, say so in a sentence and execute it as written — amending it belongs to whoever owns the decision, not the executor.
- **Evidence before claims, always** — see below.

### Verification Philosophy

A principle applied across all agents and skills: **"Evidence before claims, always"**

A statement about the *state of the evidence* is itself a claim: "all four languages are covered", "the spec ran", "M of N scenarios passed" each need the same treatment as a tool result — enumerate the artifacts and quote their values. Inferring coverage from configuration is not observation, and a file existing does not show a check ran: read the run output for its results.

#### Build Command Working Directory

All build/test tool commands (`npx vite`, `npx react-router`, `npx vitest`, `npx tsc`, `npx eslint`, `npx playwright`) must run from `{appDir}` — the directory containing `vite.config.*` / `react-router.config.ts` and `package.json`.

- Read `appDir` from `.claude/frontend-v2-plugin.json`
- If `appDir` is `"."` or absent → run from project root (no prefix needed)
- Otherwise → prefix commands with `cd {projectRoot}/{appDir} &&`

Example: `baseDir: "app/src"`, `appDir: "app"` → `cd {projectRoot}/app && npx vite build 2>&1`

This applies to all agents and skills. Skills pass `appDir` to agents as a parameter.

**Path arguments must be relative to `appDir`, not to the repo — use `{srcPath}`.** `baseDir` is
repo-relative, so passing it to a command that already ran `cd {appDir}` doubles the prefix:
`cd app && npx vitest run app/src/...` resolves to `app/app/src/...`, which does not exist. The
command finds nothing and exits non-zero, and a gate reads that as a failure it cannot explain.

`srcPath` is the source root **relative to `appDir`**: take `baseDir` and remove the leading
`{appDir}/`. Skills derive it in Step 0 and pass it to every agent alongside `baseDir`.

| `baseDir` | `appDir` | `srcPath` |
| --- | --- | --- |
| `app/src` | `app` | `src` |
| `app/app` | `app` | `app` |
| `src` | `.` | `src` |
| `packages/web/src` | `packages/web` | `src` |
| `custom` (no `/src` or `/app` suffix) | `custom` | `.` |

**Commands take `{srcPath}`; file operations keep `{baseDir}`.** Read, Write, Edit, and Glob resolve
against the repo root and must stay repo-relative — only the arguments of the tool commands above are
rewritten. A test file is *written* to `{baseDir}/features/{f}/__tests__/x.test.ts` and *run* as
`npx vitest run {srcPath}/features/{f}/__tests__/x.test.ts` from `{appDir}`.

**Framework-mode path-base rule.** `react-router.config.ts` and the generated `.react-router/` types
directory live in `{appDir}` (siblings of `vite.config.*`/`package.json`) — every scaffold, glob, check,
and edit of them resolves against `{appDir}`, never the repo root. `routes.ts`, `root.tsx`, and the
`entry.*.tsx` files live under `{baseDir}`.

#### Router-mode command matrix (single source of truth)

All agents/skills read this table instead of hard-coding a command; branch on `routerMode`.

| Concern | `declarative` / `data` (Vite SPA) | `framework` (SSR/SSG) |
| --- | --- | --- |
| Dev server | `npx vite --port {port}` | `npx react-router dev --port {port}` |
| Build | `npx vite build` | `npx react-router build` |
| Typecheck | composite-aware `tsc -b` \| `tsc --noEmit` | `npx react-router typegen` **then** the composite-aware tsc |
| Route integration target | `App.tsx` / `router.tsx` (JSX / `RouteObject[]`) | `{baseDir}/routes.ts` (+ `{appDir}/react-router.config.ts` `prerender` array) |
| Loading state | in-page `loading` state | `HydrateFallback` + `useNavigation` pending UI |
| Error state | in-page `error` state | route module `ErrorBoundary` |
| Page unit-test target | page component (`MemoryRouter`) | page-body component via Testing Library; `createRoutesStub` only for router-hook components; route module via typegen/build + E2E |
| SSR rules (vercel skill) | skip | apply |

**Runtime assumptions (framework mode, Phase 1).** Node ≥ 22; the built app runs locally via
`npx react-router-serve ./build/server/index.js`; server-only config comes from non-`VITE_`
`process.env`. The plugin verifies up to a green build + a local serve smoke and configures **no**
deployment target.

#### TypeScript Check — Composite Config Detection

Vite projects commonly use composite tsconfig with `references`. Agents must detect this and use the correct command:

1. Read `tsconfig.json` in `{appDir}` (not project root)
2. If it contains a `references` array → `npx tsc -b 2>&1`
3. Otherwise → `npx tsc --noEmit 2>&1`

> `tsc -b` checks all referenced tsconfig projects (e.g., tsconfig.app.json + tsconfig.node.json).
> `tsc --noEmit` only checks the root config scope, missing errors in build tool configs.

## Monorepo Rules

The target is an existing monorepo with several apps and shared workspace packages. These rules
override anything above that disagrees.

**Excluded paths.** `excludePaths` (config, absent → none) lists paths no skill or agent reads, globs
into, lints, audits, searches or runs — for example retired apps kept for reference. Never edit, move
or delete them and never propose a cleanup; that decision belongs to the project's owners. A path you
were given inside one is reported as `excluded` and skipped.

**Several apps, one config.** Shared keys sit at the top level; per-app keys (`baseDir`, `appDir`,
`devPort`, `i18nHook`, and any stack key whose value differs) sit under `apps.{app}`, plus
`defaultApp`. Resolve the app first — the `--app <app>` argument, else the `app` recorded in the
feature's `plan.json`, else `defaultApp`, else ask — then overlay `apps[{app}]` on the top-level keys
(per-app values win) and read every other key from that merged view. A config with no `apps` object is
a single-app config and is read as it is.

**Node version.** Never assume the `node` on PATH. From the project root,
`nodeBin = $(${CLAUDE_PLUGIN_ROOT}/scripts/node-env.sh {appDir})` returns the bin directory of the Node
version `{appDir}/.nvmrc` pins; every build or test command runs as
`cd {projectRoot}/{appDir} && PATH="{nodeBin}:$PATH" npx …`. Skills derive `nodeBin` in Step 0 and pass
it to agents; an agent that must run `npx` without one derives it the same way. A non-zero exit stops
the run — never fall back to PATH or to a `.nvmrc` above `{appDir}`.

**Product rules.** Domain knowledge (payment flow, native-app bridge, shared-package boundaries,
user-facing copy, PR body format) lives in the product repo, not in this plugin: `rulesDir` (config,
default `docs/rules`). Before planning, generating or reviewing code in one of those areas, list
`{rulesDir}/` and read the files whose names match the area. Absent folder or no matching file →
proceed on general rules and say so in the output. Cite a rule by file and heading; never copy its
text into a report.

**Codex.** The Codex audit runs the `codex` binary (`codex exec --sandbox read-only -C <dir> -o
<out.md> "<prompt>"`); `CODEX_BIN` overrides the path when the shell's `codex` is a wrapper. Absent
binary → the audit records `skipped` with the reason, never a faked verdict.
