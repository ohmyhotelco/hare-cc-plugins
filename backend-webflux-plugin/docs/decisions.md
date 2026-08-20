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

**Decision:** Generated `build.gradle(.kts)` files pin `io.asyncer:r2dbc-mysql:1.1.3`.
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
    R2dbcEntityTemplate template,
    AccountRepository accountRepository
) {
    public Mono<Void> execute(TransferBalance command) {
        var operator = TransactionalOperator.create(
            new R2dbcTransactionManager(template.getDatabaseClient().getConnectionFactory())
        );
        Mono<Void> steps = accountRepository.debit(command.fromId(), command.amount())
            .then(accountRepository.credit(command.toId(), command.amount()));
        return operator.transactional(steps);
    }
}
```

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
    R2dbcEntityTemplate template,
    AccountWriteSteps steps
) {
    public Mono<Void> execute(TransferBalance command) {
        var operator = TransactionalOperator.create(
            new R2dbcTransactionManager(template.getDatabaseClient().getConnectionFactory())
        );
        return operator.transactional(
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
