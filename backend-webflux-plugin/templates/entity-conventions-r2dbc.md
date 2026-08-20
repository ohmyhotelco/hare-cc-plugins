# Entity Conventions — R2DBC Profile

Applies when an entity's resolved `dataProfile` is `"r2dbc"`. See
`templates/entity-conventions.md` for the DTO/Domain Exception/Validation templates
shared by both profiles, and `docs/decisions.md` Decision 1 for why this plugin
supports two data profiles.

There is no auto-populating base-entity + auditing-listener equivalent for R2DBC (no
audit-listener mechanism as simple as JPA's). Timestamps are set explicitly by the
CommandExecutor instead — see the pattern below.

## Entity Template

```java
@Table("employee")
public class Employee {

    @Id
    @Column("sequence")
    private Long sequence;

    @Column("id")
    private UUID id;

    @Column("email")
    private String email;

    @Column("display_name")
    private String displayName;

    @Column("created_at")
    private LocalDateTime createdAt;

    @Column("updated_at")
    private LocalDateTime updatedAt;

    // Lombok @Getter @Setter when lombokEnabled: true
}
```

## Key Patterns

- `sequence` (Long): Auto-increment database primary key (`@Id` for R2DBC, since
  Spring Data R2DBC has no dual-key convention out of the box — `sequence` is what
  R2DBC treats as the entity identity). Internal use only, never exposed via API.
- `id` (UUID v7): External identifier. Immutable, unique, time-ordered for efficient
  B-tree indexing. Set explicitly in the CommandExecutor (see below) — R2DBC has no
  `@GeneratedValue` equivalent for anything but the `@Id` column.
- `createdAt`, `updatedAt` (`LocalDateTime`, MySQL `DATETIME(6)`): set explicitly by
  the CommandExecutor, in UTC, at write time. There is no auditing listener; do not
  assume these populate themselves.
- `@Table("snake_case")`: table name always in snake_case.
- `@Column("snake_case")`: explicit column mapping on **every** field, including the
  `@Id` field. Spring Data R2DBC resolves the column name for an unannotated `@Id`
  property through a different path than `@Column`-annotated properties and the two
  can disagree on letter casing against some dialects (observed against H2Dialect) --
  always annotate every field, never rely on the implicit naming strategy.
- Never write `SELECT *` in a custom `@Query`/mapper `<select>` — list columns
  explicitly. A wildcard select loses covering-index potential on that query and
  silently pulls in any large/BLOB column added to the table later.

## UUID v7 Generation

```java
import com.github.f4b6a3.uuid.UuidCreator;

UUID id = UuidCreator.getTimeOrderedEpoch();
```

## Repository Template

```java
public interface EmployeeRepository extends ReactiveCrudRepository<Employee, Long> {

    Mono<Boolean> existsByEmail(String email);

    // Explicit @Query, not derivation: ReactiveCrudRepository already reserves
    // findById(Long) for the sequence PK, so the external UUID lookup needs its own
    // name (derivation cannot bind "findByExternalId" to the "id" field on its own).
    // Column list is explicit, never SELECT * -- a wildcard here loses covering-index
    // potential on this query and silently pulls in any BLOB/TEXT column added later.
    @Query("SELECT sequence, id, email, display_name, created_at, updated_at "
        + "FROM employee WHERE id = :id")
    Mono<Employee> findByExternalId(UUID id);

    Flux<Employee> findAllBy(Pageable pageable);
}
```

- Extends `ReactiveCrudRepository<Entity, Long>` (ID type is always `Long` for the
  sequence PK, matching R2DBC's `@Id` column)
- Use Spring Data query derivation for simple queries — returns `Mono<T>` for
  single-result methods, `Flux<T>` for multi-result methods
- Custom `@Query` (R2DBC's `@Query` annotation, native SQL) only when derivation is
  insufficient — R2DBC's query derivation is more limited than JPA's, so this happens
  more often than in the JPA plugin
- Multi-step writes wrap in `TransactionalOperator` — see `docs/decisions.md`
  Decision 7 for the current (partially open) guidance

## Command Executor

DTO types (`CreateEmployee`, etc.) are defined in `templates/entity-conventions.md` §
DTO Templates.

```java
@Component
public record CreateEmployeeCommandExecutor(
    EmployeeRepository employeeRepository,
    EmployeePropertyValidator validator
) {
    public Mono<Void> execute(CreateEmployee command) {
        // Mono.defer wraps validation so a synchronous throw becomes a reactive error
        // signal at subscription time, not an eagerly-thrown exception at call time —
        // this matters whether execute() is called directly (e.g. StepVerifier unit
        // test) or chained via .flatMap() from a router/handler.
        return Mono.defer(() -> {
                validator.validateEmail(command.email());
                validator.validateDisplayName(command.displayName());
                return employeeRepository.existsByEmail(command.email());
            })
            .flatMap(exists -> {
                if (exists) {
                    return Mono.error(new DuplicateEmailException(command.email()));
                }
                var employee = new Employee();
                employee.setId(UuidCreator.getTimeOrderedEpoch());
                employee.setEmail(command.email());
                employee.setDisplayName(command.displayName());
                var now = LocalDateTime.now(ZoneOffset.UTC);
                employee.setCreatedAt(now);
                employee.setUpdatedAt(now);
                // existsByEmail above is a fast-path only, not the correctness guarantee --
                // two concurrent creates can both pass that check, so the UNIQUE constraint
                // on the email column is what actually prevents the duplicate, and this map
                // turns its rejection into the same domain exception the pre-check throws.
                return employeeRepository.save(employee)
                    .onErrorMap(DataIntegrityViolationException.class,
                        e -> new DuplicateEmailException(command.email()));
            })
            .then();
    }
}
```

## Query Processor

```java
@Component
public record GetEmployeePageQueryProcessor(
    EmployeeRepository employeeRepository
) {
    public Mono<PageCarrier<EmployeeView>> process(GetEmployeePage query) {
        var pageable = PageRequest.of(query.page(), query.size());
        return employeeRepository.findAllBy(pageable)
            .map(e -> new EmployeeView(e.getId(), e.getEmail(), e.getDisplayName()))
            .collectList()
            .zipWith(employeeRepository.count())
            .map(tuple -> new PageCarrier<>(
                tuple.getT1(), query.page(), query.size(), tuple.getT2()));
    }
}
```
