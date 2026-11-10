# Design: Multi-module extension (0.3.0)

> Status: **draft — for owner review, no code in this PR** · target version **0.3.0** (from 0.2.4)
> Fit decision: **B. Extend** (`docs/decisions.md` Decision 9)
> Scope: module-scoped config and gates (Decisions 10, 11, 13); a verification gate run and recorded
> by a script (Decision 12)
> Out of scope: a Spring Boot 3 branch of `be-crud` (Decision 14); `be-plan` reading ticket text
> (Decision 15); moving the be- layout to the current generation (`<xx>-shared`, `workflows/`, `bin/`,
> `docs/gates/`); the R2DBC profile and blocking-MVC modules (unchanged); any change to the coverage
> rule (Decision 6 stands)
> Date: 2026-11-06 · revised 2026-11-10 after owner review

## 1. Goal

Make the be- pipeline produce a verification record that a CI gate can trust on a **multi-module
Gradle repository**, without hand edits to the config and without override fields.

| Axis | 0.2.4 | Multi-module target | 0.3.0 |
|---|---|---|---|
| Where the code is | repository root `src/` | one subproject among many | `module` (project path) → `moduleDir` → `sourceDir`/`testDir`, resources, Step 2 checks |
| Java / Boot version | module build file `plugins {}` | root `buildscript.ext` / `subprojects {}` | module file, then root file |
| Gradle commands | `./gradlew build`, `./gradlew test` (every subproject) | one subproject | `{gradleCommand} {taskPrefix}<task>` |
| Test results counted | every `TEST-*.xml` in the project | the module's | `{moduleDir}/build/test-results/test/` only, from this run |
| Tree hash | all subprojects | module + project dependencies | module closure when it can be established, else all (Decision 13) |
| Verification record | values written by the skill's prose | — | `scripts/verify-run.sh` runs the rows and derives every value; `writer`, `testsRun`, `treeScope`, `module` |
| Committed mark | `be-commit` Step 6.5 writes `committed` | — | `verify-run.sh mark-committed`, which recomputes the staged hash |
| Coverage | `coverage: true` + no report ⇒ `fail`; `skip` = not configured | — | unchanged |
| Web layer | `be-init` warns and asks when both styles are present | module already mixes styles | `functional` for new domains, existing domain keeps its style, no extra question (Decision 11) |

## 2. Key decisions

| # | Decision | Rationale |
|---|---|---|
| D9 | Extend, minor version 0.3.0 | Fit-test stops are config gaps; ELS-3869 showed the method works once config is right |
| D10 | Optional `module` (Gradle project path) + derived `moduleDir`, `taskPrefix`; one module per config; root-literal paths move under `moduleDir` | Gates must build and count only the module under change; project path and directory differ |
| D11 | Mixed web layer: new domain functional, existing domain keeps its style; no new value | Decision 2 already has both rules |
| D12 | `verify-run.sh` runs the gate and is the only writer of `pipeline.verification`; `partial` only in a separate block; `committed` through the script; coverage unchanged; no override | A CI gate can only count what a script derived from what it ran |
| D13 | Hash = module + transitive `project(':x')` + root set incl. `buildSrc/` and wrapper; full hash when the closure is uncertain | Fail toward hashing too much |
| D14 | No Boot 3 branch in `be-crud`; clear stop | A dependency branch needs a per-branch sample; no ticket needs it yet |
| D15 | Entry on an existing module = work document → `be-code` | Matches how real tickets entered |

Orchestration model, instruction style and evidence placement do not change: skills stay entry points,
agents keep their current roster, evidence stays under `{workDocDir}/.progress/`.

## 3. Configuration

```jsonc
{
  // existing keys unchanged
  "module": ":orders-api",       // NEW, optional — Gradle project path; absent = single-module behaviour of 0.2.x
  "moduleDir": "orders-api",     // NEW, derived by be-init from settings ("" when module is absent)
  "taskPrefix": ":orders-api:",  // NEW, derived by be-init ("" when module is absent)
  "sourceDir": "orders-api/src/main/java",   // derived under moduleDir when set
  "testDir": "orders-api/src/test/java",
  "buildCommand": "./gradlew :orders-api:build",   // prefixed when module is set
  "testCommand": "./gradlew :orders-api:test"
}
```

`orders-api` is an invented name. Not knobs (the build fixes them): the list of project dependencies
(read from the build files), the test-results and JaCoCo report paths (always under `moduleDir`), the
resources paths (under `moduleDir`), the checkstyle file (Gradle's default at the root, unless the
module's build sets another).

| State | Where | Committed? | Written by |
|---|---|---|---|
| Config | `.claude/backend-webflux-plugin.json` (one per repository) | per target repository's rule | `be-init` |
| Progress record | `{workDocDir}/.progress/{feature}.json` | yes | `pipeline.verification` and `pipeline.verificationPartial`: `scripts/verify-run.sh` only; other blocks: their skills as today |
| Lock | `{workDocDir}/.progress/.lock` | no | the skill that starts a run; `verify-run.sh` requires it |

## 4. Command set — what changes

| Command / file | Change | Step |
|---|---|---|
| `be-init` | first argument `--module <path>`; derives `moduleDir`, `taskPrefix`; Step 2 checks on the module; root-file fallback for versions; refuses an unknown or unresolvable module; lists records of another module and confirms before replacing the config; mixed web layer no longer asks | 1 |
| `be-verify` | calls `verify-run.sh` (with `--no-write` when no feature is given) and reports its JSON; no longer composes the record or counts XML itself | 2 |
| `be-build`, `be-code` | `taskPrefix`; `{sourceDir}` instead of a literal path; `be-build` reads the `committed` class | 1, 2 |
| `be-crud` | `sourceDir`; migration path under `moduleDir` (SKILL, `references/generate.md`, `references/examples.md`); stops on Boot 3 (Decision 14) | 1 |
| `be-review` | review target's `migration/` and `mapper/` under `moduleDir`; accepts only a `current` record | 1, 2 |
| `be-commit` | Step 1.5 uses the reading-side classes; Step 6.5 calls `verify-run.sh mark-committed` | 2 |
| `be-jira-auto` | migration path under `moduleDir` (SKILL, `references/implement.md`); `references/gate-and-commit.md` uses the reading-side classes | 1, 2 |
| `be-data`, `be-security` | `migration/` and `mapper/` under `moduleDir` | 1 |
| `be-progress` | shows the class (current / committed / stale / other-module / unverifiable / failed), a `not-run` reason, and any `verificationPartial` | 2 |
| `scripts/source-tree-hash.sh` | `--module`, derived dependency closure, full-hash fallback, prints the scope | 1 |
| `scripts/verify-run.sh` | new: runs the rows, derives the record, `--tests` → `verificationPartial`, `mark-committed` | 2 |
| `scripts/check-plugin-consistency.py` (repository root) | `module`, `moduleDir`, `taskPrefix` in the wiring table | 1 |
| agents `implement`, `build-doctor`, `review-fixer`, `debugger` | `taskPrefix` on every Gradle call | 1 |
| agents `code-reviewer`, `backend-planner` | `moduleDir` paths; checkstyle file rule (Decision 10) | 1 |
| `templates/tdd-rules.md` | `{gradleCommand} {taskPrefix}test` replaces the unbound `:{module}:test` | 1 |
| `templates/progress-schema.md` | new fields, `verificationPartial`, reading-side classes; the `verified` row names the script | 2 |

## 5. Order of work — one PR each, two runs per step

| Step | PR | Closed by |
|---|---|---|
| 0 | this design PR (Decisions 9–15, this document, `docs/build-context.md`) | owner review |
| 1 | module scope (Decisions 10, 11, 13, 14) | `examples/employee-service` with no `module` passes its gate · scratch clone of a multi-module target: `be-init --module <path>` writes the right paths with no hand edits, `be-verify` runs only module tasks, a change in a dependency module stales the record, a change in an unrelated module does not, a `projects.x` accessor gives `treeScope: full` |
| 2 | script-run evidence (Decision 12) | sample: `be-verify` ⇒ `status: pass`, `writer: verify-run`, `testsRun: full`, `linePercent` present · sample with `coverage: true` and the report removed ⇒ `fail` · a red test ⇒ `fail` with no caller input · `--tests <filter>` ⇒ `verificationPartial`, `pipeline.verification` unchanged, exit 1 · `be-commit` ⇒ `committed: true` only on a matching staged tree · target: one real ticket from work document to `be-commit` headless with no override |
| 3 | version chore 0.3.0 (`plugin.json`, marketplace entry, root README label) + dual audit round | public-repo scan clean, both checkers clean, owner merges |

Each step adds its runs to `docs/build-context.md` with commands, counts and cost — no transcripts,
nothing from the target's code.

## 6. Questions for the owner

Answered in the review of this PR (2026-11-10); the conditions are met by the revision named.

| # | Question | Decision |
|---|---|---|
| Q1 | Accept `partial` as a value that never passes and `unverifiable` as a reading-side class for records without `writer`/`tree` (Decision 12)? | Yes, once "who writes `partial`" is answered — answered in Decision 12 (`verify-run.sh --tests`, separate block) |
| Q2 | Accept that every pre-0.3.0 record becomes `unverifiable` until re-verified, with no migration of old records? | Yes, once `committed` is covered — Decision 12: a committed pre-0.3.0 record is read as history |
| Q3 | Defer the Boot 3 branch of `be-crud` (Decision 14), given the fit test named it the next experiment? | Yes, defer |
| Q4 | One module per config (Decision 10), or must one config cover several modules? | One per config, once the overwrite case is answered — Decision 10 (confirm before replacing, `other-module` class) |
| Q5 | Keep the `.progress/` layout for 0.3.0 and move to `docs/gates/` only with the current-generation move? | Keep `.progress/` for 0.3.0 |

## 7. Sources

- Plugin build guide v0.1.8 (ELS-4167): §3, §4, §7, §10, B1.
- `docs/decisions.md` Decisions 1–8; `templates/progress-schema.md`, `templates/tdd-rules.md`;
  `skills/be-init`, `be-verify`, `be-crud`, `be-review`, `be-commit`, `be-build`, `be-jira-auto`,
  `be-data`, `be-security`; `agents/code-reviewer.md`, `agents/backend-planner.md`;
  `scripts/source-tree-hash.sh` — at `main` (read at `64e41a7`).
- `frontend-ohmyhotel-plugin/bin/fo-verify-run` (precedent for a gate that runs its own checks).
- `frontend-react-plugin` `docs/design/ota-extension-phase1.md` (precedent for an extension design
  document).
