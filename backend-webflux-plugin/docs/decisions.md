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
setting (Decision 10) and script-written verification evidence (Decision 12), released as `0.3.0`.
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

**Consequence:** the extension is three PRs after this one — module scope (Decision 10, 13), evidence
(Decision 12), version chore — each closed by two runs: `examples/employee-service` with no `module`
key (current behaviour) and a scratch clone of the new target with `module` set. Decisions 14 and 15
record what is deliberately not changed.

## Decision 10: Module scope — one `module` and one `taskPrefix` per config

**Decision:** `.claude/backend-webflux-plugin.json` gains two optional keys:

- `module` — the Gradle subproject the plugin works in (for example `"app-api"`). Absent means the
  single-module behaviour of 0.2.x.
- `taskPrefix` — derived as `":<module>:"` when `module` is set, `""` otherwise. Every Gradle call
  made by a be- skill or agent is `./gradlew {taskPrefix}<task>`.

`be-init` gains its first argument, `--module <name>`; without it, it asks only when `settings.gradle`
includes subprojects. When `module` is set, `be-init` derives `sourceDir` and `testDir` under it, runs
its Step 2 checks (base package, data profile, database, migration directory, checkstyle, coverage)
against the module, reads the Java and Spring Boot versions from the module build file **or, if
absent there, from the root build file** (`buildscript.ext`, `subprojects {}`, `allprojects {}`), writes
`buildCommand` and `testCommand` with the prefix, and refuses a `module` that `settings.gradle` does
not include. `be-verify` reads test results only from `<module>/build/test-results/`.

**Rationale:** without a prefix every gate builds and tests every subproject, and a test report from a
module the change did not touch can fail or pass the gate. One module per config keeps one answer per
question; a developer who works in two modules runs `be-init` per module. No knob branches a dependency
set, so the guide's per-branch sample rule (§3) does not apply and `examples/employee-service` stays
the only sample.

**Consequence:** `be-init`, `be-verify`, `be-build`, `be-code` and the `implement`, `build-doctor`,
`review-fixer`, `debugger` agents read `taskPrefix` for every task-level Gradle call (`classes`,
`checkstyleMain`, `test`, `jacocoTestReport`, `build`); the repository's
`scripts/check-plugin-consistency.py` gets both keys in its wiring table. A config written by 0.2.x
keeps working unchanged.

## Decision 11: Web layer in a module that already mixes styles

**Decision:** when `be-init` finds both `RouterFunction` and `@RestController` classes in meaningful
numbers (Step 2 item 6), it no longer stops to ask: it writes `webLayer: "functional"` and says why in
Step 7. `webLayer` keeps its two values. It governs **new domains**; a new file in an **existing
domain** follows the style that domain already uses, whatever `webLayer` says.

**Rationale:** Decision 2 already sets the two rules this needs — functional for a new domain, never
two styles in one domain. The question in Step 2 item 6 asks the user to pick one style for a module
that, by Decision 2's own rule, legitimately holds both; and it blocks a headless run. Rewriting an
existing domain to the other style is a refactor, not a feature.

**Consequence:** `be-init` Step 2 item 6 and Step 3 lose the mixed-case question; `be-code` and the
code-reviewer agent check the style per domain. No new config value.

## Decision 12: What "verified" means — one script writes the record, a subset run is `partial`

**Decision:** `scripts/verify-record.sh` becomes the only writer of `pipeline.verification` in
`{workDocDir}/.progress/{feature}.json`. Skills and agents never edit that block. The layout stays
`.progress/` (guide §7: the older layout of the be- plugins stays as it is); the record gains fields,
it is not moved.

| Field | Values | Rule |
|---|---|---|
| `status` | `pass` · `fail` · `partial` · `not-run` | `pass` needs `tree` (exit 4 otherwise, file unchanged); `partial` when `testsRun` is `subset`; `not-run` when the toolchain is missing |
| `tree` | `scripts/source-tree-hash.sh` value | as today |
| `testsRun` | `full` · `subset` | `be-verify` always runs the full test task of the module and records `full`; any run narrowed by a Gradle `--tests` filter is `subset` |
| `module` | the configured module, or absent | copied from config |
| `coverage.status` | `pass` · `fail` · `not-run` | `not-run` when no JaCoCo report exists (guide §7.5: could not check is not nothing to check); `skip` in 0.2.x records is read as `not-run`. Still report-only (Decision 6): `fail` and `not-run` do not fail `status` |
| `coverage.linePercent` | number, or absent | present whenever a JaCoCo report was read |
| `writer` | `verify-record` | absent ⇒ the record was not written by the script |

Reading side (`be-progress`, `be-review`, `be-commit`, `be-jira-auto`): a record is **current** when
`writer` is `verify-record`, `status` is `pass`, `testsRun` is `full` and `tree` equals the recomputed
hash; **stale** when the hash differs; **partial** when `status` is `partial`; **unverifiable** when
`writer` or `tree` is missing. Only current lets `be-review` and `be-commit` proceed. There is no
override field; `gateOverride` and similar hand-added keys are ignored.

The script needs `jq` (exit 6 if missing), takes a `mkdir` lock released by `trap` (Git Bash and macOS
bash 3.2 have no `flock`), and replaces the file atomically (write a temporary file, then `mv`).
`frontend-ohmyhotel-plugin/bin/fo-evidence` is the reference.

**Rationale:** records written in prose drift: a subset run recorded as `pass`, a red suite recorded as
`pass` with an override, a coverage row of `skip` that cannot be told apart from "not configured". The
CI gate will count verified records; it can only count what a script
wrote. Keeping `status` (not renaming it) keeps 0.2.x readers and existing records parseable.

**Consequence:** every record written before 0.3.0 is `unverifiable` until `be-verify` runs again;
`be-progress` says so and names the command. A target whose full module suite cannot pass on a
developer machine cannot reach current — that is a target-side fix (test isolation in the product
repository), not a gate setting in this plugin.

## Decision 13: Tree hash scope with a module

**Decision:** with `module` set, `scripts/source-tree-hash.sh --module <m>` hashes the module, every
subproject it depends on through `project(':x')` (transitively), the root build files
(`settings.gradle`, `build.gradle`, `gradle.properties`), `gradle/`, `config/` and `libs/` if present.
The dependency list is derived from the build files at run time, never written into the plugin.

**Rationale:** a change in a shared module changes what the verified module runs; a change in an
unrelated module does not. Hashing all subprojects (0.2.x) makes every unrelated commit stale the
record; hashing only the module misses shared code.

**Consequence:** the script parses Groovy and Kotlin DSL `project(':x')` references; a dependency it
cannot resolve stops the hash with a non-zero exit instead of being skipped.

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
