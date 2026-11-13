# Decision Record — backend-webflux-plugin

This file is the authoritative decision record for the plugin. It exists so the
data-profile decision is written down, with rationale, **before** any template that
depends on it is authored. Everything in `templates/` and `skills/` in this plugin
was written after this record, not before.

## Decision 1: Data profile — support BOTH MyBatis and R2DBC (not R2DBC-only)

**Decision:** The plugin ships two data-profile conventions, selected per project or
per entity via `.claude/backend-webflux-plugin.json` → `dataProfile`:
`"r2dbc" | "mybatis" | "both"`. Default: `"both"`.

**Rationale:**

1. Many real-world WebFlux backends are not uniformly R2DBC. It is common for a
   large, pre-existing module to be WebFlux + **MyBatis** (blocking JDBC, offloaded
   to `boundedElastic`), while newer modules in the same system are WebFlux +
   **R2DBC**. An R2DBC-only plugin generates code for a persistence layer the
   MyBatis-based module doesn't use, which produces a coverage or scaffold output
   that is technically correct but describes the wrong system for that module.
2. R2DBC is equally real and equally common for newer, greenfield modules — a
   plugin that can't emit R2DBC would be incomplete for those.
3. Excluding either profile forces a false choice between "matches the legacy
   MyBatis module" and "matches the reactive-purist pattern used elsewhere in a
   mixed estate." Supporting both avoids that trade entirely — it costs two sets of
   conventions instead of one, which is why items 3-6 below are written as paired
   sections rather than a single R2DBC-only pass.
4. Reactivity is preserved in both paths: MyBatis calls in the generated code are
   wrapped so blocking JDBC executes on `Schedulers.boundedElastic()` and the result
   is bridged back into `Mono`/`Flux`, rather than silently blocking the Netty
   event loop thread.
5. Default guidance for **new** bounded contexts (no existing module to match):
   default to R2DBC — it is the simpler, purely reactive path with no thread-pool
   offload to reason about. Use MyBatis explicitly when a new entity must match the
   conventions of an existing MyBatis-based module, or when a query is too complex
   for R2DBC's more limited dialect support (no joins across aggregates, limited
   native query composition).

**Consequence for templates:** the plugin ships two parallel sets of conventions
(R2DBC / MyBatis) instead of one — `templates/entity-conventions-r2dbc.md` and
`templates/entity-conventions-mybatis.md` — with `templates/entity-conventions.md`
holding only the DTO/exception/validator templates the two profiles share, so a
scaffold or implementation reads just the one profile file it needs instead of both
in full. `be-crud` asks (or reads from config) which profile a given entity uses
before scaffolding it.

## Decision 2: Web layer — RouterFunction is the default, `@RestController` is a named exception, not a ban

**Decision:** `be-crud` and the sample service default to `RouterFunction` +
`HandlerFunction` for new business APIs. `@RestController` returning `Mono`/`Flux` is
an accepted, explicitly-scoped alternative — not banned — used only when a service is
deliberately mirroring the annotated-controller style of an existing MVC-heritage
module it is extending. This is a realistic scenario in any system that has grown
incrementally: older modules commonly stay on `@RestController`, while newer ones
adopt the functional style, and a plugin that bans one style outright can't scaffold
into an existing annotated-controller module without breaking its consistency.

**Rule, stated explicitly:**
- New domain, new bounded context → `RouterFunction`/`HandlerFunction` (functional
  style). This is what `be-crud` generates by default.
- Extending an existing annotated-controller module, or a team explicitly choosing
  parity with that module's existing `@RestController` endpoints for the same domain →
  `@RestController` returning `Mono`/`Flux` is acceptable. Set
  `webLayer: "annotated"` in config to make `be-crud` emit this style instead.
- Never mix both styles for the same domain inside one service — `be-api-review`
  flags this as a warning.

## Decision 3: Migration format — manual SQL, no Flyway/Liquibase

**Decision:** Migrations are hand-written SQL files under
`{sourceDir}/../resources/migration/V{n}__{description}.sql`. No Flyway or Liquibase
dependency is added to generated builds — introducing one would create a
migration-runner most target projects don't already use, and this plugin has no
visibility into whether one is expected. Application of the SQL file is out of scope
for this plugin.

**Addendum (senior-database review, 2026-08-20):** a per-service migration file under
`resources/migration/` is how a schema change gets *applied*; it is not the same as
registering that change in whatever location a target project treats as its
canonical schema source of truth (e.g. a central shared DDL definition, if one
exists outside this plugin's repo). This plugin has no visibility into that location
and cannot write to it, so it cannot close that loop automatically — but
`be-crud`/`be-data` must not stay silent about it either. `be-data`'s migration-safety
check now flags any new/changed DDL with no note that it still needs reconciling into
the project's canonical schema source (see `skills/be-data/SKILL.md` rule 13).

## Decision 4: Database default — MySQL 8.0.33, not PostgreSQL

**Decision:** `.claude/backend-webflux-plugin.json` → `database` defaults to
`"mysql"`. All SQL templates use MySQL syntax (`BIGINT AUTO_INCREMENT`, `BINARY(16)`
or `CHAR(36)` for UUID storage, no `TIMESTAMPTZ` — MySQL has no timezone-aware
timestamp type, so `DATETIME(6)` + application-level UTC discipline is used instead).

## Decision 5: R2DBC MySQL driver — pin `io.asyncer:r2dbc-mysql`, not `dev.miku`

**Decision:** The driver line is `io.asyncer:r2dbc-mysql` 1.4.2+ (the sample pins 1.4.3). No skill writes a build file — the pin is enforced where the project's own build file is read: `be-init` Step 2 item 7 (detection), `be-crud` Step 3 (precondition, stops below 1.4.2), plugin `CLAUDE.md` § Database. The 1.4 line is the one whose compatibility table lists Spring Boot 4 / Spring Data R2DBC 4; 1.1.x predates them and was never exercised by the H2-only sample.
`dev.miku:r2dbc-mysql` is archived upstream and must never be emitted by this plugin,
even in a project where an existing module still carries the older driver — that
kind of pre-existing inconsistency is out of this plugin's scope to fix (no change to
code outside what this plugin generates) and is not something this plugin should
propagate into new code.

## Decision 6: Coverage tool — JaCoco, report-only, no threshold yet

**Decision:** JaCoco (`org.gradle.jacoco` core plugin, no external dependency needed)
is the coverage tool — it is the standard, zero-extra-dependency line-coverage tool
for the JVM and needs no new tool for a team to evaluate. `be-verify`'s gate reports a
`Coverage` row with a concrete line-coverage % and PASS/FAIL against the report
having been generated successfully — **not** against a percentage threshold. No
`jacocoTestCoverageVerification` rule is wired yet; that is deferred until a real
coverage baseline is established for the target project.

**If the team later rejects JaCoco:** the only files that reference it directly are
`templates/checkstyle-config.md`'s sibling `templates/coverage-gate.md` (jacoco Gradle
block) and `skills/be-verify/SKILL.md` §1.5 — both isolated, so a swap is a two-file
change, not a plugin-wide rewrite.

## Decision 7: `TransactionalOperator` across nested `Mono` — spike note, not a coding deliverable

This is a genuinely open question, not a solved one. Rather than spend a full,
open-ended spike exploring it blind, this plugin documents the recommended entry
pattern and flags the open edge case explicitly, so `be-crud`-generated multi-step
command executors don't silently get transaction boundaries wrong:

```java
@Component
public record TransferBalanceCommandExecutor(
    TransactionalOperator transactionalOperator,   // Boot's auto-configured bean, backed by
    AccountRepository accountRepository            // the project's ReactiveTransactionManager
) {
    public Mono<Void> execute(TransferBalance command) {
        Mono<Void> steps = accountRepository.debit(command.fromId(), command.amount())
            .then(accountRepository.credit(command.toId(), command.amount()));
        return transactionalOperator.transactional(steps);
    }
}
```

Inject the `TransactionalOperator` Spring Boot auto-configures from the project's
`ReactiveTransactionManager`; never `TransactionalOperator.create(new R2dbcTransactionManager(…))`
inside `execute()` — that allocates a manager per request and bypasses whatever transaction-manager
configuration the project has.

**Open edge case (unresolved, flagged not solved):** nesting a second
`operator.transactional(...)` inside a `Mono` that is itself already wrapped by an
outer `TransactionalOperator` (e.g., a command executor calling another
`@Transactional`-equivalent reactive method) does not compose the way
`@Transactional` propagation (`REQUIRED`, `REQUIRES_NEW`) does on the blocking JDBC
side — R2DBC has no thread-bound transaction context to propagate through. The safe
rule until this is validated: **one `TransactionalOperator.transactional()` wrapper
per command executor, at the outermost call site only.** Do not call a second command
executor's `execute()` method from inside an already-wrapped `Mono` chain if that
second executor also wraps itself — refactor the shared steps into a plain
(non-wrapping) repository-level method instead and let the caller own the single
wrap. Full validation of nested propagation semantics remains open.

**Shared-step refactor pattern (avoiding the double-wrap):** instead of one command
executor calling another already-`transactional()`-wrapped executor's `execute()`,
extract the shared writes into a plain method that returns an unwrapped `Mono` and is
called by both executors, each owning its own single outer wrap:

```java
// Shared steps: no TransactionalOperator here, plain composition only
@Component
public record AccountWriteSteps(AccountRepository accountRepository) {
    public Mono<Void> debitThenCredit(UUID fromId, UUID toId, BigDecimal amount) {
        return accountRepository.debit(fromId, amount)
            .then(accountRepository.credit(toId, amount));
    }
}

@Component
public record TransferBalanceCommandExecutor(
    TransactionalOperator transactionalOperator,
    AccountWriteSteps steps
) {
    public Mono<Void> execute(TransferBalance command) {
        return transactionalOperator.transactional(
            steps.debitThenCredit(command.fromId(), command.toId(), command.amount()));
    }
}
```

`be-crud`/`implement` must never generate a command executor whose `Mono` body calls
another command executor's `execute()` method — that is the double-wrap this pattern
exists to avoid. `code-reviewer`'s Dimension 2 R2DBC sub-checks flag this explicitly
(see `agents/code-reviewer.md`).

**Addendum (senior-database review, 2026-08-20):** nesting is not the only hazard in
this pattern. The `steps` `Mono` passed to `operator.transactional(...)` must contain
*only* repository/mapper calls — never a vendor or HTTP call (`WebClient`, any
external client). A network call inside an open transaction holds that transaction's
row locks for however long the network call takes, turning a normal-latency write
into a lock-hold duration bounded by an external system's response time. If a command
genuinely needs both a DB write and an external call, sequence them so the network
call happens outside the transactional boundary (before it, with the transaction only
covering the DB write; or after, with a compensating step if the DB write must be
rolled back on external failure) — never inside. `be-data`'s transaction-boundary
check now flags this explicitly (see `skills/be-data/SKILL.md` rule 3).

## Decision 8: "CQRS" here means command/query separation of concerns, not full CQRS with separate read/write models

**Decision:** This plugin's `architecture: "cqrs"` scaffolds application-level
command/query separation only — `command/`, `commandmodel/`, `query/`, `querymodel/`,
`view/` are separate packages with separate DTOs, but both sides read and write
through the **same** `{Entity}Repository`/`{Entity}Mapper` against the **same** MySQL
tables. There is no separate read-model store, no projection/event pipeline, and no
eventual consistency between a write side and a read side.

**Rationale:** Most systems this plugin targets have no read-replica or projection
infrastructure to scaffold against, and inventing one speculatively is out of scope
for a code-generation plugin — that is an infrastructure decision a project makes
independently, not something a scaffolding tool should assume. What the plugin *does*
deliver — package-level isolation so a command path can never accidentally serve a
read, and a query path can never accidentally perform a write — is real and enforced
(see `agents/code-reviewer.md` Dimension 6). What it does *not* deliver is
independent scaling or availability of the read side from the write side, since they
share one connection pool and one table.

**Consequence:** Do not present this pattern to users as "full CQRS." If a feature
request implies independent read-side scaling, a separate read datastore, or
eventual consistency between write and read paths, that is out of this plugin's
current scope — say so explicitly rather than silently scaffolding the same
single-datastore package split and calling it done.

## Decision 9: Fit decision for multi-module Gradle targets — extend this plugin (minor version 0.3.0), not configure, not copy

**Date:** 2026-11-06 · **Tickets:** ELS-4416 (decision), ELS-4167 (method)

**Decision:** Option B of the plugin build guide (§3): extend `backend-webflux-plugin` with a module
setting (Decision 10) and script-produced verification evidence (Decision 12), released as `0.3.0`.
No new plugin, no new prefix.

**Rationale:**

1. The fit test of 2026-10-19 (two headless runs on a scratch clone of a multi-module Gradle target,
   Spring Boot 3.2, MyBatis starter 3.0.x, mixed web layer) stopped in `be-init` and `be-crud`. Every
   `be-init` stop is a config gap, not a method gap: the Java and Boot versions live in the root build
   file, the config has no module field, so `sourceDir`/`testDir` and the Gradle commands point at the
   repository root.
2. A real ticket in the same weeks (ELS-3869) ran `be-code` → `be-verify` → `be-review` → `be-fix` on the same
   target once the config was corrected by hand, and the method held. The remaining gaps are config
   and how the verification result is recorded.
3. Option A (configure) is out: no knob says which module the plugin works in. Option C (copy) is only
   right if the templates are wrong for the target rather than incomplete; nothing measured so far
   shows that, and a copy would double the maintenance of a plugin the owner keeps simple.

**Consequence:** the extension is three PRs after this one — module scope (Decisions 10, 11, 13, 14),
evidence (Decision 12), version chore. The first two are each closed by two runs:
`examples/employee-service` with no `module` key (current behaviour) and a scratch clone of a
multi-module target with `module` set. The version chore is closed by the repository checks (design
§5). Decisions 14 and 15 record what is deliberately not changed.

## Decision 10: Module scope — one `module` per config, its directory and task prefix derived

**Decision:** `.claude/backend-webflux-plugin.json` gains one optional key and two keys derived from it:

| Key | Value | Written by |
|---|---|---|
| `module` | the **Gradle project path** as `settings.gradle` includes it, with the leading colon (`":orders-api"`, `":services:orders"`). Absent ⇒ the single-module behaviour of 0.2.x | `be-init --module` |
| `moduleDir` | the project's directory relative to the Gradle root: `:a:b` → `a/b`, or the relocated `projectDir` when settings sets one. `""` when `module` is absent | `be-init`, derived |
| `taskPrefix` | `module` + `":"` (`":services:orders:"`); `""` when `module` is absent | `be-init`, derived |

`module` names the project, not a directory, because the two differ for a nested path (`:a:b`) and
for a relocated `projectDir`; Gradle task paths use the project path, file paths use `moduleDir`.

`be-init` gains its first argument, `--module <path>`; without it, it asks only when `settings.gradle`
includes subprojects. It refuses a `module` that settings does not include or whose directory it
cannot resolve. With `module` set it derives `sourceDir` and `testDir` under `moduleDir`, runs its
Step 2 checks (base package, data profile, database, migration directory, checkstyle, coverage)
against the module, reads the Java and Spring Boot versions from the module build file **or, if
absent there, from the root build file** (`buildscript.ext`, `subprojects {}`, `allprojects {}`), and
writes `buildCommand` and `testCommand` with the prefix. Every task-level Gradle call is
`{gradleCommand} {taskPrefix}<task>`.

**Paths with no config key.** Paths the skills write as repository-root literals move under
`moduleDir`:

| Path today | 0.3.0 | Read or written by |
|---|---|---|
| `src/main/resources/migration/` | `{moduleDir}/src/main/resources/migration/` | `be-init` item 8, `be-crud` (SKILL, `references/generate.md`, `references/examples.md`), `be-jira-auto` (SKILL, `references/implement.md`), `be-review`, `be-data`, `backend-planner`; the `implement` agent through `templates/cqrs-module.md` |
| `src/main/resources/mapper/` | `{moduleDir}/src/main/resources/mapper/` | `be-review`, `be-data`, `be-security`; the `implement` agent through `templates/entity-conventions-mybatis.md` |
| `build/test-results/test/`, `build/reports/jacoco/test/` | under `{moduleDir}/build/` only | `be-verify` (Decision 12), `be-test-review` (coverage and timing); the report path in `templates/coverage-gate.md` |
| `config/checkstyle/checkstyle.xml` | stays at the Gradle root, Gradle's default for every subproject; another file only when the build sets `configDirectory`, `config` or `configFile` for the module | `be-init` item 9, `code-reviewer` |
| `./gradlew test --tests …`, `./gradlew :{module}:test --tests …` and `./gradlew build` in `templates/tdd-rules.md` | `{gradleCommand} {taskPrefix}test --tests …` and `{gradleCommand} {taskPrefix}build`; the separate multi-module line goes, the prefix covers it | `implement`, `review-fixer`, `be-test-review` |

The plugin's `CLAUDE.md` (maintainer notes, not loaded into agents) gives the two resource paths at
the root too; it moves to the same form.

**One config per repository.** The config file is per repository, so `be-init` for a second module
replaces the first. `be-init` Step 1 already asks before it overwrites a config; when the `module`
changes, the same question also lists the progress records whose `module` differs from the new one
and says they stop counting as current until the config names their module again. The reading side compares a record's `module` with the configured
one (Decision 12, class `other-module`). A developer who works in two modules runs `be-init` when
switching.

**Rationale:** without a prefix every gate builds and tests every subproject, and a test report from a
module the change did not touch can fail or pass the gate. One module per config keeps one answer per
question. No knob branches a dependency set, so the guide's per-branch sample rule (§3) does not apply
and `examples/employee-service` stays the only sample.

**Consequence:** `be-init`, `be-verify`, `be-build`, `be-code`, `be-crud`, `be-review`, `be-data`,
`be-security`, `be-jira-auto`, `be-test-review`, the `implement`, `build-doctor`, `review-fixer`,
`debugger`, `code-reviewer`, `backend-planner` agents and the templates `tdd-rules.md`,
`cqrs-module.md`, `entity-conventions-mybatis.md` and `coverage-gate.md` read the new keys; the
repository's `scripts/check-plugin-consistency.py` gets all three in its wiring table. A config
written by 0.2.x has no `module` and keeps working unchanged.

## Decision 11: Web layer in a module that already mixes styles

**Decision:** when `be-init` finds both `RouterFunction` and `@RestController` classes in meaningful
numbers (Step 2 item 6), it no longer raises a separate warning that asks for one style: it proposes
`webLayer: "functional"` with the other detected values and says why. `webLayer` keeps its two values.
It governs **new domains**; a new file in an **existing domain** follows the style that domain already
uses, whatever `webLayer` says.

**Rationale:** Decision 2 already sets the two rules this needs — functional for a new domain, never
two styles in one domain. The warning asks the user to pick one style for a module that, by Decision
2's own rule, legitimately holds both. Rewriting an existing domain to the other style is a refactor,
not a feature. The Step 1 (existing config) and Step 3 (confirm detected values) questions stay as
they are; this decision removes one question, it does not make `be-init` non-interactive.

**Consequence:** `be-init` Step 2 item 6 and the matching Step 3 warning lose the mixed-case question;
`be-code` and the `code-reviewer` agent check the style per domain. No new config value.

## Decision 12: What "verified" means — a script runs the gate and writes the record

**Decision:** `scripts/verify-run.sh` runs the verification rows itself and is the only writer of
`pipeline.verification` in `{workDocDir}/.progress/{feature}.json`. The caller never passes a result:
the script works out every value from what it ran. `be-verify` calls it inside its own lock and
reports the JSON it prints; skills and agents never edit the block. The layout stays `.progress/`
(guide §7: the older layout of the be- plugins stays as it is); the record gains fields, it is not
moved. `frontend-ohmyhotel-plugin/bin/fo-verify-run` is the precedent for a gate that runs its own
checks.

**What the script derives.**

1. It records `tree` (`scripts/source-tree-hash.sh`, Decision 13) **before** the first task, as
   `be-verify` does today.
2. It runs the five rows of `be-verify` Step 1 with its own commands, `{gradleCommand}` and
   `{taskPrefix}` on every task: `classes testClasses`, `checkstyleMain checkstyleTest` (when
   `checkstyle` is true), `test`, `build`, `jacocoTestReport` (when `coverage` is true; `-x test` after
   a red test row). As in 0.2.4 Step 1.4, after a red test row the `build` row is not run and is `fail`
   with the reason `tests failed; build not re-run`. Every other row's status comes from that run's
   exit code. The script does not run `testCommand` or `buildCommand`; those keys stay for the skills
   and agents that build and test during work. A gate whose test call a config value can change (a
   filter, `-x test`, a dry run) has an override by another name; a setting the tests need belongs in
   the build files, which the tree hash covers.
3. The test row makes Gradle execute the test task in this invocation:
   `{gradleCommand} {taskPrefix}cleanTest {taskPrefix}test --no-build-cache`. A test task that Gradle
   reports as UP-TO-DATE (nothing changed since the last run, such as right after a green `be-build`)
   writes no new XML, so step 4 would read no suite and fail a tree that did not change; one restored
   FROM-CACHE did not run in this invocation.
4. It reads test counts from `{moduleDir}/build/test-results/test/TEST-*.xml` only, summing the
   `<testsuite>` attributes, and checks that the XML files were written by this run (newer than its
   start). `tests.status` is `pass` only when the task exited 0, at least one suite was read, and
   `failures + errors` is 0.
5. `testsRun` is `full` when the script ran the module's test task with no filter, which is what the
   test row always does. Only the script's own `--tests <filter>` (diagnosis only) runs a filter, and
   that run is `subset`; see below.
6. After the last row it recomputes the hash with the same scope. If it differs from `tree`, or cannot
   be computed, `status` is `fail` with the reason `source changed during verification`, as in 0.2.4
   Step 2: the rows describe a tree that no longer exists.
7. `status` is `pass` only when every row passed, `testsRun` is `full` and the tree did not change
   (step 6); `fail` when any row failed or the tree changed; `not-run` when the toolchain is missing
   (no `gradlew` or `gradle`, no `java`), with a `reason`.

| Field | Values | Rule |
|---|---|---|
| `status` | `pass` · `fail` · `not-run` | derived as above, never passed in |
| `compilation`, `checkstyle`, `tests`, `build` | as in 0.2.4 | from the task exit codes and the module's JUnit XML |
| `coverage` | as in 0.2.4: `status` `pass` · `fail` · `skip`, `linePercent`, `thresholdEnforced: false` | **unchanged** (Decision 6): `coverage: true` with a missing or unparseable report is `fail` and fails `status`; `skip` means exactly `coverage: false`. The percentage stays report-only |
| `tree`, `treeScope` | hash, `module` · `full` | Decision 13 |
| `testsRun` | `full` · absent | `full` when the test row ran the module's test task unfiltered (step 5); absent on `not-run`, where no row ran |
| `module` | the configured `module`, or absent | copied from config |
| `writer` | `verify-run` | absent ⇒ the record was not written by the script |
| `committed`, `committedAt` | `true`, timestamp | set only by `verify-run.sh mark-committed` (below) |

`pipeline.status` follows `status` as in 0.2.4: `pass` → `verified`; `fail` and `not-run` →
`verify-failed`. `not-run` adds no pipeline status; `be-progress` shows its `reason` and the command
to fix the toolchain.

**`partial` — who writes it.** Only `verify-run.sh --tests <filter>` produces `partial`, and it writes
it to a separate block, `pipeline.verificationPartial` (`status: partial`, `testsRun: subset`, the
filter, counts, `tree`, `writer`), never to `pipeline.verification`, and it exits 1. It does not change
`pipeline.status`: a subset run can never stand in for the gate, and it cannot replace a full record.
No skill calls it in 0.3.0; it exists so a developer's narrowed run leaves a record that is visibly
not a pass.

**`committed` — who writes it.** `be-commit` Step 6.5 keeps its job but calls
`verify-run.sh mark-committed --feature <f>`: the script recomputes the staged tree hash itself
(`source-tree-hash.sh --staged`, with the record's `treeScope` and `module`) and sets
`committed: true` and `committedAt` only when the record is `current` against the index: `writer` is
`verify-run`, `status` is `pass`, `testsRun` is `full`, `module` equals the configured one, and
`tree` equals the staged hash. It leaves the record unchanged otherwise. The two places that
remove the mark today call `verify-run.sh unmark-committed --feature <f>` instead of editing the
block: `be-build` when it demotes committed records because nothing else is in flight, and
`be-commit` when the commit command fails and it undoes Step 6.5 (only where Step 6.5 set the mark;
a mark an earlier commit set stays). `be-verify` still **replaces** the block, so a new verification
drops an old `committed` mark (0.2.4 Step 3).

**Reading side** (`be-progress`, `be-review`, `be-commit`, `be-build`, `be-jira-auto`), first match wins;
`be-review` skips the first row (below):

| Class | When | Effect |
|---|---|---|
| `committed` | `committed` is `true` | history for `be-progress`, `be-commit` and `be-build`: not compared with later trees or the configured module, blocks nothing; `be-build` keeps its committed-record rule; a pre-0.3.0 record with `committed: true` is read the same way |
| `unverifiable` | `writer` or `tree` missing | not verified: `be-review` refuses, `be-commit` warns (below); `be-progress` names `be-verify` |
| `other-module` | `module` differs from the configured `module` | not verified, as above; `be-progress` names both modules (Decision 10) |
| `stale` | `tree` differs from the hash recomputed with the record's `treeScope` | not verified, as above; re-run `be-verify` |
| `current` | `writer` is `verify-run`, `status` is `pass`, `testsRun` is `full`, tree equal | `be-review` proceeds; `be-commit` proceeds without a warning |
| `failed` | otherwise (`fail`, `not-run`) | not verified, as above, as `verify-failed` is today |

There is no override field: the reading side ignores any key this schema does not define.

`be-review` reviews code, so a `committed` mark does not let it through: it classifies the record by
the rows after the first and proceeds only on `current`. 0.2.4 `be-review` already compares the tree
on every proceed path (Step 2 item 3), committed or not.

**`be-commit` warns, it does not refuse.** `be-commit` takes no feature argument, so it cannot tell
which record a commit belongs to. Step 1.5 keeps its 0.2.4 shape: for each `reviewed`/`done` record
not yet `committed` it works out the class against the staged tree (`source-tree-hash.sh --staged`,
with the record's `treeScope`), and for any class other than `current` it names the feature and the
class and asks whether to continue. A record of another feature, such as a pre-0.3.0 record or one
from the module configured before the last `be-init`, must not stop unrelated work. Continuing
changes nothing in the record: `mark-committed` sets `committed` only on a `current` record, so a
record that was not `current` still reads as not verified. `be-jira-auto` never answers the
prompt: as today (`references/gate-and-commit.md`, Step 9 item 2a) it checks the records before it
calls `be-commit` and stops with `NEEDS-INPUT` where `be-commit` would ask.

The script needs `jq` (exit 6 if missing). It takes no lock of its own: when it writes, it requires
the caller's lock and exits 5 otherwise: `operation` `be-verify` for a run, `be-commit` for
`mark-committed` and `unmark-committed`, `be-build` for `unmark-committed`, each with `--run-id` equal
to the lock's `runId`. It replaces the file atomically (write a temporary file, then `mv`). `be-verify`
with no feature argument takes no lock today; it calls the script with `--no-write`, which runs the
same rows, prints the same JSON and writes nothing.

**Rationale:** a record whose values the caller supplies is only as good as the caller; a CI gate that
counts verified records can only count what a script derived from what it ran. Coverage keeps the
0.2.4 rule because loosening it is a separate decision with its own case, and `skip` keeps its single
meaning. Keeping `status` (not renaming it) keeps 0.2.x readers and existing records parseable.
`be-commit` asks rather than refuses because what a gate counts is the record, not whether a commit
was made.

**Consequence:** a record written before 0.3.0 and not yet committed is `unverifiable` until
`be-verify` runs again; `be-progress` says so and names the command. A committed one stays history.
`current` needs a full run of the module's test task; no setting accepts less. A CI gate reads a
record with the `current` rule against the tree it checks; `committed` is history for the be- skills,
not evidence on its own.

## Decision 13: Tree hash scope with a module

**Decision:** with `module` set, `scripts/source-tree-hash.sh --module <path>` hashes:

- the module (`src/`, its build file, `gradle.properties`, `config/`);
- every subproject it depends on through `project(':x')` in its build file, transitively, each with
  the same paths;
- the root set, always: `settings.gradle(.kts)`, the root build file and `gradle.properties`,
  `gradlew`, `gradlew.bat`, `gradle/`, `buildSrc/` (as today), `config/` and `libs/` if present;
- every included build inside the repository (`includeBuild(...)` in settings, inside or outside
  `pluginManagement {}`, such as `build-logic/`), **whole**: every file under its directory except
  `build/` and `.gradle/` output. An included build is a separate build with its own settings,
  subprojects and version catalog, so picking paths inside it would miss some.

The narrow hash is taken only when the closure can be established. The script falls back to the
0.2.x full hash (every subproject) when any of these holds: a `project(...)` or `includeBuild(...)`
argument that is not a string literal; a `projects.x` type-safe accessor; a root `subprojects {}` or
`allprojects {}` block that declares dependencies; a `project(` reference under `buildSrc/` or an
included build; a referenced project the settings do not include. The record carries
`treeScope: module` or `full`, and the reading side recomputes with the same scope. In both scopes
the included builds inside the repository are hashed whole; the full hash is otherwise the 0.2.x
hash. An included build outside the repository is refused as a project directory outside it is
today: no hash, unless `BEWF_IGNORE_EXTERNAL=1` accepts the omission.

**Rationale:** a change in a shared module changes what the verified module runs; a change in an
unrelated module does not. Hashing all subprojects (0.2.x) makes every unrelated commit stale the
record; hashing only what a parser happened to find misses dependencies it could not see. When in
doubt the hash covers too much, never too little. An included build can change what the module
compiles and tests (a convention plugin, or a library that replaces a dependency), as `buildSrc/`
can, so it is always in the hash. 0.2.x hashes only the `src/`, build file, `gradle.properties` and
`config/` of each directory in it that has a build file, not its settings file or `gradle/`; 0.3.0
hashes it whole.

**Consequence:** the script parses Groovy and Kotlin DSL `project(':x')` and `includeBuild(...)`
references; anything it cannot read moves the hash to `full` and says so on stderr instead of being
skipped.

## Decision 14: `be-crud` on Spring Boot 3 — deferred, with a clear stop

**Decision:** 0.3.0 adds no Boot 3 branch to `be-crud`. `be-crud` reads `sourceDir` from config and,
on a Boot 3 project, stops before writing anything with "Spring Boot 3 is not supported by be-crud
(Decision 14); use be-code from a work document", releasing its lock.

**Rationale:** two of the artifacts `be-crud` Step 3 requires have no Boot 3 release, so a Boot 3 path
is a dependency branch, and the guide (§3) then requires the sample to run per branch value or a second
sample. No real ticket on the Boot 3 target has entered through `be-crud`; work enters through a work
document and `be-code` (Decision 15). The fit test named a Boot 3 branch as the next experiment; it
stays the next experiment for when a team needs scaffolding.

**Consequence:** reopen when a Boot 3 team asks for scaffolding; the reopening PR adds the `bootLine`
knob and a Boot 3 sample together.

## Decision 15: How work enters the pipeline on an existing module

**Decision:** on an existing module the supported entry is a work document with test scenarios →
`be-code`. `be-plan` keeps reading a planning-plugin spec only; `be-jira-auto` keeps its current input.

**Rationale:** the fit test showed `be-plan` refuses ticket text by design, and the real tickets that
used the plugin on the target all started from a work document. Teaching `be-plan` to read ticket text
is a separate feature with its own evidence rules.

**Consequence:** the README and the target's golden path document this entry; no skill changes for it.
