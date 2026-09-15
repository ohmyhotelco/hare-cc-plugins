# Entity Conventions — MyBatis Profile

Applies when an entity's resolved `dataProfile` is `"mybatis"`. See
`templates/entity-conventions.md` for the DTO/Domain Exception/Validation templates
shared by both profiles, and `docs/decisions.md` Decision 1 for why this plugin
supports two data profiles.

There is no auto-populating base-entity + auditing-listener equivalent for MyBatis
either (no audit-listener mechanism as simple as JPA's) — timestamps are set
explicitly by the CommandExecutor instead, same as the R2DBC profile.

## Entity (POJO) Template

MyBatis has no entity annotations — it maps a plain POJO to SQL results via XML.

```java
public class Employee {
    private Long sequence;
    private UUID id;
    private String email;
    private String displayName;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    // Lombok @Getter @Setter when lombokEnabled: true; plain getters/setters otherwise
}
```

## Mapper Interface

```java
@Mapper
public interface EmployeeMapper {
    boolean existsByEmail(@Param("email") String email);

    Employee findById(@Param("id") UUID id);

    List<Employee> findAllPage(@Param("offset") long offset, @Param("limit") int limit);   // long: page * size overflows int

    long count();

    void insert(Employee employee);
}
```

Every method here has a bound statement in the XML below — MyBatis fails at the first call, not
at startup, with `BindingException: Invalid bound statement` when one is missing.

## Mapper Naming — `{Entity}Mapper` / `{Entity}FluxMapper` / `Batch{Entity}Mapper`

`{Entity}Mapper` above covers single-row and small-page CRUD. Two more mapper
variants exist for the cases that pattern does not fit — never widen
`{Entity}Mapper` itself to cover them:

- **`{Entity}FluxMapper`**: a separate interface for methods whose result is
  streamed into a `Flux` (e.g. a bulk export/report query) rather than collected
  into a `List` inside the `boundedElastic` callable first. Only introduce this
  interface when a query genuinely needs to stream rather than materialize —
  most list endpoints should stay on `{Entity}Mapper.findAllPage(offset, limit)`.
- **`Batch{Entity}Mapper`**: a separate interface for multi-row writes
  (`<insert>`/`<update>` with MyBatis `<foreach>`). Any CommandExecutor that
  would otherwise call `{Entity}Mapper.insert(...)` in a loop over a collection
  — one mapper call per element, each independently offloaded to
  `boundedElastic` — must use `Batch{Entity}Mapper` instead. A per-element loop
  is the N+1 write pattern: it does not just cost N round trips, it can also
  fan out to N concurrent `boundedElastic` threads if the loop is expressed as
  `Flux.fromIterable(items).flatMap(...)`, competing for the same fixed-size
  HikariCP pool that single-row requests are also drawing from.

`be-data` flags a loop that calls a plain `{Entity}Mapper` write method over a
collection as a critical issue — the fix is always "move to
`Batch{Entity}Mapper`", not "add `.subscribeOn` around the loop".

## Mapper XML

`src/main/resources/mapper/EmployeeMapper.xml` — and `application.yml` must carry
`mybatis.mapper-locations: classpath:mapper/**/*.xml`: the starter's default is empty, and on its own
MyBatis looks only next to the interface's package path, so an unregistered XML surfaces as
`BindingException: Invalid bound statement` on the first call, not at startup:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE mapper PUBLIC "-//mybatis.org//DTD Mapper 3.0//EN" "https://mybatis.org/dtd/mybatis-3-mapper.dtd">
<mapper namespace="com.example.data.EmployeeMapper">

    <!-- MyBatis ships no UUID type handler: a CHAR(36) column reads back as String and cannot
         be set on the UUID field, and a UUID parameter falls to setObject(). The result map
         and every #{id} name the handler explicitly. -->
    <resultMap id="employee" type="com.example.data.Employee">
        <id     property="sequence"    column="sequence"/>
        <result property="id"          column="id" typeHandler="com.example.data.UuidTypeHandler"/>
        <result property="email"       column="email"/>
        <result property="displayName" column="display_name"/>
        <result property="createdAt"   column="created_at"/>
        <result property="updatedAt"   column="updated_at"/>
    </resultMap>

    <select id="existsByEmail" resultType="boolean">
        SELECT COUNT(*) > 0 FROM employee WHERE email = #{email}
    </select>

    <select id="findById" resultMap="employee">
        SELECT sequence, id, email, display_name, created_at, updated_at
        FROM employee WHERE id = #{id, typeHandler=com.example.data.UuidTypeHandler}
    </select>

    <select id="findAllPage" resultMap="employee">
        SELECT sequence, id, email, display_name, created_at, updated_at
        FROM employee ORDER BY sequence LIMIT #{limit} OFFSET #{offset}
    </select>

    <select id="count" resultType="long">
        SELECT COUNT(*) FROM employee
    </select>

    <insert id="insert" useGeneratedKeys="true" keyProperty="sequence">
        INSERT INTO employee (id, email, display_name, created_at, updated_at)
        VALUES (#{id, typeHandler=com.example.data.UuidTypeHandler}, #{email}, #{displayName},
                #{createdAt}, #{updatedAt})
    </insert>

</mapper>
```

`src/main/java/{basePackage}/data/UuidTypeHandler.java`, generated once per project:

```java
@MappedTypes(UUID.class)
public class UuidTypeHandler extends BaseTypeHandler<UUID> {
    @Override
    public void setNonNullParameter(PreparedStatement ps, int i, UUID parameter, JdbcType jdbcType)
            throws SQLException {
        ps.setString(i, parameter.toString());
    }

    @Override
    public UUID getNullableResult(ResultSet rs, String columnName) throws SQLException {
        return toUuid(rs.getString(columnName));
    }

    @Override
    public UUID getNullableResult(ResultSet rs, int columnIndex) throws SQLException {
        return toUuid(rs.getString(columnIndex));
    }

    @Override
    public UUID getNullableResult(CallableStatement cs, int columnIndex) throws SQLException {
        return toUuid(cs.getString(columnIndex));
    }

    private static UUID toUuid(String value) {
        return value == null ? null : UUID.fromString(value);
    }
}
```

## Command Executor — Bridging Blocking MyBatis Calls into the Reactive Pipeline

**This is the pattern that keeps the WebFlux event loop unblocked.** MyBatis is
blocking JDBC — never call a mapper method directly inside a `Mono`/`Flux` chain
without offloading it. This is the standard bridge pattern for any MyBatis-backed
reactive module. DTO types (`CreateEmployee`, etc.) are defined in
`templates/entity-conventions.md` § DTO Templates.

```java
@Component
public record CreateEmployeeCommandExecutor(
    EmployeeMapper employeeMapper,
    EmployeePropertyValidator validator
) {
    public Mono<Void> execute(CreateEmployee command) {
        return Mono.fromCallable(() -> {
                validator.validateEmail(command.email());
                validator.validateDisplayName(command.displayName());

                if (employeeMapper.existsByEmail(command.email())) {
                    throw new DuplicateEmailException(command.email());
                }

                var employee = new Employee();
                employee.setId(UuidCreator.getTimeOrderedEpoch());
                employee.setEmail(command.email());
                employee.setDisplayName(command.displayName());
                var now = LocalDateTime.now(ZoneOffset.UTC);
                employee.setCreatedAt(now);
                employee.setUpdatedAt(now);
                // existsByEmail above is a fast-path only, not the correctness guarantee --
                // two concurrent creates can both pass that check on separate threads, so
                // the UNIQUE constraint on the email column is what actually prevents the
                // duplicate; MyBatis's exception translator surfaces its rejection as
                // DataIntegrityViolationException. Remap ONLY the email constraint's rejection
                // (named uk_employee_email in the migration) -- a NOT NULL or another unique
                // column is not a duplicate email and must not become 409.
                try {
                    employeeMapper.insert(employee);
                } catch (DataIntegrityViolationException e) {
                    if (String.valueOf(e.getMessage()).toLowerCase().contains("uk_employee_email")) {
                        throw new DuplicateEmailException(command.email());
                    }
                    throw e;
                }
                return (Void) null;
            })
            .subscribeOn(Schedulers.boundedElastic());
    }
}
```

- Every mapper call in a CommandExecutor/QueryProcessor is wrapped in
  `Mono.fromCallable(...)` (or `Flux.fromIterable(mapper.findAllPage(...))` for
  list results) and `.subscribeOn(Schedulers.boundedElastic())`
- Never call a mapper method bare inside a reactive chain — that blocks the Netty
  event loop thread and is exactly the anti-pattern this bridge exists to prevent
- `be-data` (the standalone audit skill) flags any mapper call found outside a
  `boundedElastic`-scheduled block as a critical issue
- A pre-check (`existsByEmail`/`existsBy*`) is a UX fast-path only, never the
  correctness mechanism for a uniqueness rule — the DB's `UNIQUE` constraint is,
  and the insert/save call must catch or map `DataIntegrityViolationException`
  to the matching domain exception so the concurrent-write race still returns
  the correct HTTP status instead of a raw 500

## Query Processor

```java
@Component
public record GetEmployeePageQueryProcessor(
    EmployeeMapper employeeMapper
) {
    public Mono<PageCarrier<EmployeeView>> process(GetEmployeePage query) {
        return Mono.fromCallable(() -> {
                var offset = (long) query.page() * query.size();   // int arithmetic wraps negative past page 107374182
                var rows = employeeMapper.findAllPage(offset, query.size());
                var views = rows.stream()
                    .map(e -> new EmployeeView(e.getId(), e.getEmail(), e.getDisplayName()))
                    .toList();
                var total = employeeMapper.count();
                return new PageCarrier<>(views, query.page(), query.size(), total);
            })
            .subscribeOn(Schedulers.boundedElastic());
    }
}

@Component
public record FindEmployeeQueryProcessor(
    EmployeeMapper employeeMapper
) {
    // The mapper's findById takes the external UUID (there is no Spring Data name clash in
    // MyBatis). Mono.fromCallable completes EMPTY when the callable returns null, which is the
    // not-found signal the web layer maps to 404; the blocking call is offloaded like every other
    // mapper call.
    public Mono<EmployeeView> process(FindEmployee query) {
        return Mono.fromCallable(() -> employeeMapper.findById(query.id()))
            .subscribeOn(Schedulers.boundedElastic())
            .map(e -> new EmployeeView(e.getId(), e.getEmail(), e.getDisplayName()));
    }
}
```
