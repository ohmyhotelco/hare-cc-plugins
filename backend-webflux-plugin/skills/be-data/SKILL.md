---
name: be-data
description: "Audit R2DBC and MyBatis data-layer patterns, schema design, migration safety, and reactive-blocking hazards."
argument-hint: "[file-or-directory-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash
---

# Data Layer Pattern Audit (R2DBC / MyBatis)

## Role

Act as the data-layer reviewer whose sign-off gates merge on schema, transaction, and
reactive-blocking correctness — the categories most likely to cause a production
incident (event-loop starvation, a DB lock held open across a network call, a
half-applied migration, silent data loss) rather than a visible test failure.

KPI: zero Critical findings shipped unflagged. A missed true positive here means a
production incident, not a review nitpick — when a judgment call is genuinely close
(e.g. an index-fit conclusion that depends on runtime query-plan behavior you cannot
observe from static code), surface it as an explicitly unverified Suggestion rather
than silently dropping it or asserting it with false confidence. See Step 3.

Applies the sub-checks matching `config.dataProfile` — see `docs/decisions.md`
Decision 1 for why this plugin supports both R2DBC and MyBatis.

**Tools**: Grep/Glob/Read cover every pattern match in Step 2. Bash is only for
read-only checks those three can't do — e.g. rule 13's "no corresponding entry
recorded" check, which requires confirming whether a migration-tracking mechanism
exists anywhere in the repo (`git log --oneline -- src/main/resources/migration/`,
or a project-specific tracking file). Never use Bash to reimplement a Grep/Glob
pattern match.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, tell the user to run `/backend-webflux-plugin:be-init` first and stop
3. Read `config.dataProfile` (`"r2dbc" | "mybatis" | "both"`) and `config.database` to
   determine which sub-checks apply
4. If `config.dataProfile` is present but not one of the three accepted values, stop
   and ask the user to correct it — do not guess which profile was intended and do
   not silently default to `"both"`

### Step 1: Determine Scope

- If argument provided:
  - If the path does not exist, report `Path not found: {path}` and stop — do not
    fall back to scanning the default scope
  - Otherwise audit the specified file or directory
- If no argument: audit all files in `{sourceDir}/{basePackage}/data/`,
  `{sourceDir}/{basePackage}/commandmodel/`, `{sourceDir}/{basePackage}/querymodel/`,
  `src/main/resources/mapper/` (MyBatis XML), and migration files
  (`src/main/resources/migration/`)
- If the resolved scope matches zero files — the default directories don't exist, or
  an argument-provided directory exists but contains none of the relevant file
  types — stop and report `No data-layer files found in {scope} — nothing to audit`.
  This is a distinct outcome from Step 4's "No issues detected": one means the audit
  never actually ran over any file, the other means it ran and found nothing. Do not
  let the first look like the second.

### Step 2: Scan for Candidate Issues

Check each in-scope file against these rules. Every match found here is a
**candidate** — it only becomes a reportable finding after it survives Step 3.

#### Critical Issues (both profiles)

1. **Blocking call on the event loop**
   - Any mapper method (MyBatis) called directly inside a `Mono`/`Flux` chain
     without `Mono.fromCallable(...).subscribeOn(Schedulers.boundedElastic())`
     (or `Flux` equivalent) wrapping it
   - `.block()` / `.blockFirst()` / `.blockLast()` anywhere in production code
     (`src/main`, not `src/test`)
   - A `Mono`/`Flux` chain that is built but never subscribed to (returned but the
     caller discards it, or assigned to a local variable and never returned/`.subscribe()`d)

2. **Per-element write loop instead of a batch mapper (N+1 write)**
   - A CommandExecutor calling `{Entity}Mapper`/`{Entity}Repository`'s single-row
     insert/update/delete method once per element of a collection — via a plain
     `for` loop (MyBatis) or `Flux.fromIterable(items).flatMap(repo::save, ...)`
     (R2DBC) — instead of a `Batch{Entity}Mapper` call (MyBatis) or a single
     `saveAll(Flux<Entity>)` (R2DBC)
   - This is not just N round trips: on the MyBatis profile each loop iteration is
     independently offloaded to `Schedulers.boundedElastic()`, so an unbounded
     `flatMap` over the collection can fan out to N concurrent threads competing
     for the same fixed-size HikariCP pool that single-row requests are also
     drawing from — flag this even when each individual call is correctly wrapped
   - Fix: move multi-row writes to `Batch{Entity}Mapper` (MyBatis `<foreach>`) or
     `repository.saveAll(Flux<Entity>)` (R2DBC) — see
     `templates/entity-conventions-mybatis.md` "Mapper Naming"

3. **Missing transaction boundary (R2DBC)**
   - CommandExecutor performs multiple sequential repository writes without
     `TransactionalOperator` wrapping (see `docs/decisions.md` Decision 7 for the
     current, partially-open guidance on nested composition)
   - A vendor/HTTP call (`WebClient`, any external client) placed inside the
     `Mono` passed to `operator.transactional(...)` — this holds the DB
     transaction (and its row locks) open for the duration of a network call.
     Flag as critical regardless of whether the transaction is R2DBC or the
     MyBatis/JDBC path: move the external call outside the transactional
     boundary (before it, or after via a compensating step), never inside

4. **Schema Design**
   - NOT NULL constraints missing on required fields (enforced in DB, not just application)
   - UNIQUE constraints missing on business keys (email, external IDs)
   - Foreign keys without explicit `ON DELETE` clause
   - `FLOAT` or `DOUBLE` used for monetary values (use `BigDecimal` / `NUMERIC` / MySQL `DECIMAL`)

#### Warning Issues

5. **Unbounded Queries**
   - R2DBC: repository method with no `Pageable` parameter on a table that could grow large
   - MyBatis: mapper `<select>` with no `LIMIT`/offset parameters on a list query

6. **Access Path — Index Fit** (the core question: does this query's index actually
   serve it, not just "does an index exist")
   - **Missing index**: R2DBC repository has a derived-query method (`findBy{Field}`)
     or MyBatis mapper XML has a `WHERE`/`JOIN`/`ORDER BY` referencing a column with
     no index in the manual SQL migration; login/lookup queries on non-indexed columns
   - **Composite index column order**: a manual SQL migration's composite index does
     not put equality-filtered (`=`) columns before range-filtered (`>`, `<`,
     `BETWEEN`) columns, with any `ORDER BY` column last — a range column placed
     before an equality column in the index definition makes every column after it
     in that index unusable for the query
   - **Sargability**: a query wraps an indexed column in a function or implicit cast
     — `WHERE DATE(created_at) = ...`, `LOWER(email) = ...`, comparing a `VARCHAR`
     column against a numeric literal — which prevents the index on that column from
     being used at all, or a `LIKE '%x'` (leading wildcard) on an indexed column
   - **Covering**: a frequently-run query's `SELECT` list pulls columns outside what
     its index covers, forcing a lookup back to the table row for every matched index
     entry — worth naming as a suggestion when the query is a known hot path, not a
     blanket requirement for every query
   - **Join order / collation**: a mapper XML or R2DBC query joins two tables on
     columns with different charset/collation, or joins without an index on the join
     column — either causes an implicit full scan; also flag a join where the larger
     table is not filtered before joining, rather than after
   - **This whole rule is a static-analysis inference, not a query-plan fact** — you
     cannot run `EXPLAIN` from this audit. Missing-index and composite-column-order
     findings are usually confirmable from the migration file alone and may be
     reported as Warnings. Sargability, covering, and join-order findings often
     depend on data distribution or the optimizer's actual choice — when you cannot
     confirm the conclusion from the migration file and query text alone, report it
     as a Suggestion tagged `unverified: confirm with EXPLAIN` per Step 3, not a
     Warning asserted with full confidence.

7. **`SELECT *` / Unbounded Column List**
   - A mapper XML `<select>` or R2DBC `@Query` uses `SELECT *` instead of an explicit
     column list — never use it; it defeats covering-index potential for that query
     and silently pulls in any large/BLOB/TEXT column added to the table later. See
     `templates/entity-conventions-r2dbc.md` "Key Patterns"

8. **Data Integrity**
   - Unique constraint violations handled with generic 500 instead of domain exception
   - Missing optimistic-locking equivalent (a `version` column checked in the `WHERE`
     clause of the update) on entities with concurrent-update risk — R2DBC/MyBatis have
     no `@Version` annotation, so this must be hand-rolled; flag its absence as a
     warning, not silence, when the entity is clearly mutable under concurrency
   - A reactive chain that swallows an error (`onErrorResume` returning `Mono.empty()`
     without logging) where the caller needed to know the write failed

9. **Entity/POJO Design**
   - Entity/POJO does not follow the `sequence` + UUID `id` dual key pattern
   - R2DBC: mutable `id` field (should only be set once, at creation)
   - R2DBC: `@Table`/`@Column` names do not match the manual SQL migration's table/column names
   - MyBatis: mapper XML result-column aliases do not match the POJO's field names

10. **Cascade / Multi-step risk**
    - A command that deletes a parent row without first confirming (or explicitly
      cascading) dependent rows — R2DBC/MyBatis have no `CascadeType.ALL` equivalent,
      so an implicit assumption of cascading delete is a bug, not a config default

11. **Write cost of new indexes**
    - A newly proposed index on a table whose CommandExecutors show heavy/frequent
      writes (inserts/updates outnumber the read paths that would use the index) —
      every index is a tax on each `INSERT`/`UPDATE` to that table, not a free win;
      name the write-cost tradeoff explicitly rather than only naming the read benefit

12. **Growth**
    - No note (in the migration file's surrounding context, work document, or
      `docs/decisions.md`-style record) of the expected row-count growth for a new
      table, when the entity's nature suggests high volume (append-only event/log
      style tables, one row per request, etc.) — flag as a suggestion to record
      whether partitioning or an archival/cleanup strategy will be needed, not to
      implement one

#### Migration Issues (manual SQL — skip if `config.migration != "manual-sql"`)

13. **Manual SQL Migration Safety**
    - Migration version does not follow sequential order (V1, V2, V3...)
    - Migration is not backward-compatible with currently deployed code
    - `ALTER TABLE ... ADD COLUMN ... NOT NULL` without a multi-step approach (add nullable → backfill → add constraint)
    - `DROP TABLE` or `DROP COLUMN` without confirming no dependent code
    - Column types in migration SQL do not match entity/POJO field types
    - No corresponding entry recorded anywhere that this SQL has been applied (this
      plugin generates migrations but never applies them — flag if the project has no
      visible process for tracking which migrations ran, since that is now entirely
      the project's responsibility, not a tool's)
    - New/changed DDL in `src/main/resources/migration/` has no corresponding note
      that it still needs to be reconciled into the project's canonical schema
      source of truth (e.g. a central `db-schema/` definition, where one exists) —
      this plugin's migration file is how the change gets applied to a running
      database, not a substitute for registering the change wherever the project
      tracks its authoritative DDL; flag the gap, do not assume it is handled

#### Suggestions (MySQL-specific, skip if `config.database != "mysql"`)

14. **MySQL Optimizations**
    - `VARCHAR(255)` default where a shorter length is appropriate
    - `DATETIME` without `(6)` fractional-seconds precision where sub-second ordering matters
    - `CHAR(36)` used for UUID storage when `BINARY(16)` would be more compact (note the tradeoff: `BINARY(16)` is not human-readable in `SELECT` output — only suggest this for high-volume tables)
    - `InnoDB` engine and `utf8mb4` charset explicitly declared on every `CREATE TABLE`

### Step 3: Verify Each Candidate

Do not skip this step — for CC-tier judgment calls (rule 3's
transaction-boundary-vs-network-call analysis, rule 6's index-fit/sargability
analysis) it is what separates a finding from a guess. For every candidate from
Step 2, before it is allowed into the Step 4 report, write one line stating the
concrete evidence: which line of code or which config value makes this a true
positive, and which rule it violates.

- **True positive**: cite the file:line (or migration filename) and the specific
  fact — e.g. "`CreateBookingCommandExecutor.java:41` calls `AcmeClient.confirm()`
  inside the `Mono` passed to `operator.transactional(...)` opened at line 38 — the
  network call sits inside the transactional boundary."
- **Excluded — not a true positive**: state the specific reason (e.g. already
  wrapped in `boundedElastic`, test file, the loop body is a single batch call, the
  index already covers the equality-then-range column order).
- **Unverified (rule 6 only)**: when sargability, covering, or join-order cannot be
  confirmed from the migration file and query text alone — no `EXPLAIN` output is
  available in this audit — report it as a Suggestion tagged
  `unverified: confirm with EXPLAIN`, not a Warning asserted with full confidence.
  Do this instead of silently dropping the candidate or overstating certainty.

Only true positives (and explicitly tagged unverified suggestions) proceed to
Step 4. Excluded candidates are not reported — their exclusion reasoning does not
need to appear in the final output, but you must have produced it before dropping
the candidate. Retain every verification line (true positive, excluded, and
unverified) instead of discarding it once Step 4 is produced — if the user asks
"why did you flag this" or "why wasn't X flagged", show them the Step 3
verification line for that candidate rather than re-deriving or guessing at the
reasoning after the fact.

### Step 4: Report

Display findings in the working language. Use this header on every report — a
clean result carries the same evidence trail as a failing one, it just has zero
counts:

```
Data Layer Audit Report (R2DBC / MyBatis)
==========================================

Scope: {target path}
Data profile: {config.dataProfile}
Files scanned: {count} (entities/POJOs: {n}, repositories: {n}, mappers: {n}, executors: {n}, processors: {n}, migrations: {n})

Critical ({count}):
  {file}:{line} — {description}
  Suggestion: {fix}

Warnings ({count}):
  {file}:{line} — {description}
  Suggestion: {fix}

Migration Issues ({count}):
  {file} — {description}
  Suggestion: {fix}

Suggestions ({count}):
  {file}:{line} — {description}
  Suggestion: {fix}
```

When a Suggestion carries an unverified index-fit finding (rule 6), prefix its
description with `unverified: confirm with EXPLAIN —` so the reader can tell it
apart from a suggestion you're fully confident in.

If no issues found:
> "Data layer audit passed. No issues detected."

## Error Handling

- **Config missing** — see Step 0; stop with the `be-init` instruction.
- **Unrecognized `dataProfile` value** — see Step 0; stop and ask the user to
  correct it, do not guess or silently default.
- **Path argument does not exist** — see Step 1; stop with `Path not found`, do not
  silently fall back to the default scope.
- **Zero files in scope** — see Step 1; stop and say so explicitly rather than
  reporting "No issues detected" for a scope that was never actually scanned —
  those are different outcomes and must not look identical.
- **File unreadable (permissions, binary, encoding)** — skip the file, list it under
  a `Skipped ({count}):` line in the report with the reason, and continue scanning
  the rest of the scope. Do not let one unreadable file abort the whole audit, and
  do not silently drop it from the file count either.

## Worked Examples

### Example 1 — blocking call not offloaded (Critical, true positive)

Input code (`EmployeeMapper.java` usage inside `FindEmployeeQueryProcessor.java`):

```java
public Mono<Employee> process(FindEmployee query) {
    return Mono.just(employeeMapper.findById(query.id())); // mapper call is blocking JDBC
}
```

Step 3 verification line:
> True positive — `employeeMapper.findById(...)` is a MyBatis (blocking JDBC) call
> invoked directly inside `Mono.just(...)` at `FindEmployeeQueryProcessor.java:12`,
> with no `Mono.fromCallable(...).subscribeOn(Schedulers.boundedElastic())`
> wrapping it. This blocks a Netty event-loop thread on every call.

Resulting report line:
```
Critical (1):
  FindEmployeeQueryProcessor.java:12 — blocking JDBC call not wrapped in
    Schedulers.boundedElastic()
  Suggestion: Mono.fromCallable(() -> employeeMapper.findById(query.id()))
    .subscribeOn(Schedulers.boundedElastic())
```

### Example 2 — network call inside a transactional boundary (Critical, true positive)

Input code (`CreateBookingCommandExecutor.java`):

```java
return operator.transactional(
    bookingRepository.save(booking)
        .then(acmeClient.confirm(booking.getVendorRef())) // network call, line 41
        .then(bookingRepository.updateStatus(booking.getId(), CONFIRMED))
);
```

Step 3 verification line:
> True positive — `acmeClient.confirm(...)` at `CreateBookingCommandExecutor.java:41`
> is inside the `Mono` passed to `operator.transactional(...)` opened at line 38.
> The DB transaction (and any row locks held by the preceding `save`) stays open
> for the duration of the vendor HTTP call.

Resulting report line:
```
Critical (1):
  CreateBookingCommandExecutor.java:41 — vendor call inside TransactionalOperator
    boundary holds DB locks open across a network call
  Suggestion: Move acmeClient.confirm(...) outside the transactional Mono — call
    it before the transaction opens, or as a compensating step after it commits.
```

### Example 3 — index-fit finding that cannot be confirmed statically (Suggestion, unverified)

Input code (`BookingMapper.xml`):

```xml
<select id="findActiveByHotelAndDate" resultType="Booking">
  SELECT id, hotel_id, check_in, status FROM booking
  WHERE hotel_id = #{hotelId} AND check_in BETWEEN #{from} AND #{to}
  ORDER BY check_in
</select>
```

with a migration index `INDEX idx_booking_hotel_checkin (hotel_id, check_in)` —
column order is correct (equality before range), but whether MySQL's optimizer
actually uses this index over a full scan depends on the table's cardinality and
row distribution, which this audit cannot observe.

Step 3 verification line:
> Unverified — index column order is correct for this query (equality column
> `hotel_id` before range column `check_in`), so this is not a Critical/Warning
> finding. Whether the optimizer chooses this index over a full scan on the
> production data distribution cannot be confirmed without running `EXPLAIN`.

Resulting report line:
```
Suggestions (1):
  BookingMapper.xml:2 — unverified: confirm with EXPLAIN — idx_booking_hotel_checkin
    column order looks correct for this query; confirm actual index usage with
    EXPLAIN against production-scale data before treating it as settled.
```
