# Design: Multi-module extension (0.3.0)

> Status: **draft — for owner review, no code in this PR** · target version **0.3.0** (from 0.2.4)
> Fit decision: **B. Extend** (`docs/decisions.md` Decision 9)
> Scope: module-scoped config and gates (Decisions 10, 11, 13); script-written verification evidence
> (Decision 12)
> Out of scope: a Spring Boot 3 branch of `be-crud` (Decision 14); `be-plan` reading ticket text
> (Decision 15); moving the be- layout to the current generation (`<xx>-shared`, `workflows/`, `bin/`,
> `docs/gates/`); the R2DBC profile and blocking-MVC modules (unchanged)
> Date: 2026-11-06

## 1. Goal

Make the be- pipeline produce a verification record that a CI gate can trust on a **multi-module
Gradle repository**, without hand edits to the config and without override fields.

| Axis | 0.2.4 | Multi-module target | 0.3.0 |
|---|---|---|---|
| Where the code is | repository root `src/` | one subproject among many | `module` → `sourceDir`/`testDir` and the Step 2 checks |
| Java / Boot version | module build file `plugins {}` | root `buildscript.ext` / `subprojects {}` | module file, then root file |
| Gradle commands | `./gradlew build`, `./gradlew test` (every subproject) | one subproject | `./gradlew {taskPrefix}<task>` |
| Test results counted | every `TEST-*.xml` in the project | the module's | `<module>/build/test-results/` only |
| Tree hash | all subprojects | module + project dependencies | Decision 13 |
| Verification record | written by the skill's prose; `coverage: skip` ambiguous | — | written by `scripts/verify-record.sh`; `partial`, `not-run`, `writer` |
| Web layer | `be-init` stops to ask when both styles are present | module already mixes styles | `functional` for new domains, existing domain keeps its style, no question (Decision 11) |

## 2. Key decisions

| # | Decision | Rationale |
|---|---|---|
| D9 | Extend, minor version 0.3.0 | Fit-test stops are config gaps; ELS-3869 showed the method works once config is right |
| D10 | Optional `module` + derived `taskPrefix`; one module per config | Gates must build and count only the module under change |
| D11 | Mixed web layer: new domain functional, existing domain keeps its style; no new value | Decision 2 already has both rules; headless runs need `be-init` not to ask |
| D12 | `verify-record.sh` is the only writer of `pipeline.verification`; `partial` and `unverifiable` exist; no override | The CI gate can only count what a script wrote |
| D13 | Hash = module + transitive `project(':x')` + root build files, `gradle/`, `config/`, `libs/` | Shared code changes stale the record, unrelated modules do not |
| D14 | No Boot 3 branch in `be-crud`; clear stop | A dependency branch needs a per-branch sample; no ticket needs it yet |
| D15 | Entry on an existing module = work document → `be-code` | Matches how real tickets entered |

Orchestration model, instruction style and evidence placement do not change: skills stay entry points,
agents keep their current roster, evidence stays under `{workDocDir}/.progress/`.

## 3. Configuration

```jsonc
{
  // existing keys unchanged
  "module": "app-api",          // NEW, optional — absent = single-module behaviour of 0.2.x
  "taskPrefix": ":app-api:",    // NEW, derived by be-init from module; "" when module is absent
  "sourceDir": "app-api/src/main/java",   // derived under module when set
  "testDir": "app-api/src/test/java",
  "buildCommand": "./gradlew :app-api:build",   // prefixed when module is set
  "testCommand": "./gradlew :app-api:test"
}
```

Not knobs (the build fixes them): the list of project dependencies (read from the build files), the
test-results path (always under the module build directory), the JaCoCo report path.

| State | Where | Committed? | Written by |
|---|---|---|---|
| Config | `.claude/backend-webflux-plugin.json` | per target repository's rule | `be-init` |
| Progress record | `{workDocDir}/.progress/{feature}.json` | yes | `pipeline.verification`: `scripts/verify-record.sh` only; other blocks: their skills as today |
| Lock | `{workDocDir}/.progress/.lock` | no | the skill that starts a run |

## 4. Command set — what changes

| Command | Change | Step |
|---|---|---|
| `be-init` | first argument `--module <name>`; Step 2 checks run on the module; root-file fallback for versions; refuses an unknown module; mixed web layer no longer asks | 1 |
| `be-verify` | `taskPrefix` on every row; counts only module test results; calls `verify-record.sh` with `testsRun: full` | 1, 2 |
| `be-build`, `be-code` | `taskPrefix`; `{sourceDir}` instead of a literal path | 1 |
| `be-crud` | reads `sourceDir`; stops on Boot 3 (Decision 14) | 1 |
| `be-review`, `be-commit`, `be-jira-auto` | accept only a current record (Decision 12) | 2 |
| `be-progress` | classifies current / stale / partial / unverifiable / not-run | 2 |
| `scripts/source-tree-hash.sh` | `--module`, derived dependency closure | 1 |
| `scripts/verify-record.sh` | new | 2 |
| `scripts/check-plugin-consistency.py` (repository root) | `module`, `taskPrefix` in the wiring table | 1 |
| agents `implement`, `build-doctor`, `review-fixer`, `debugger` | `taskPrefix` on every Gradle call | 1 |

## 5. Order of work — one PR each, two runs per step

| Step | PR | Closed by |
|---|---|---|
| 0 | this design PR (decisions 9–15, this document, `docs/build-context.md`) | owner review |
| 1 | module scope (Decisions 10, 11, 13, 14) | `examples/employee-service` with no `module` passes its gate · scratch clone of the target: `be-init --module <name>` writes the right paths with no hand edits, `be-verify` runs only module tasks, a change in a dependency module stales the record |
| 2 | script-written evidence (Decision 12) | sample: full run ⇒ `status: pass`, `writer: verify-record`, `linePercent` present · target: one real ticket from work document to `be-commit` headless with no override · `verify-record.sh --status pass` without a tree exits 4 · `--tests-run subset` ⇒ `partial` |
| 3 | version chore 0.3.0 (`plugin.json`, marketplace entry, root README label) + dual audit round | public-repo scan clean, both checkers clean, owner merges |

Each step adds its runs to `docs/build-context.md` with commands, counts and cost — no transcripts,
nothing from the target's code.

## 6. Questions for the owner

| # | Question | Decision |
|---|---|---|
| Q1 | Accept `partial` as a `pass`-blocking value and `unverifiable` as a reading-side class for records without `writer`/`tree` (Decision 12)? | |
| Q2 | Accept that every pre-0.3.0 record becomes `unverifiable` until re-verified, with no migration of old records? | |
| Q3 | Defer the Boot 3 branch of `be-crud` (Decision 14), given the fit test named it the next experiment? | |
| Q4 | One module per config (Decision 10), or must one config cover several modules? | |
| Q5 | Keep the `.progress/` layout for 0.3.0 and move to `docs/gates/` only with the current-generation move? | |

## 7. Sources

- Plugin build guide v0.1.8 (ELS-4167): §3, §4, §7, §10, B1.
- `docs/decisions.md` Decisions 1–8; `templates/progress-schema.md`; `skills/be-init`, `be-verify`,
  `be-crud`, `be-review`, `be-commit` at `main` (read at `64e41a7`).
- `frontend-ohmyhotel-plugin/bin/fo-evidence` (evidence reference); `frontend-react-plugin`
  `docs/design/ota-extension-phase1.md` (precedent for an extension design document).
