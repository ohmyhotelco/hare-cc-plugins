# Entity and DTO Conventions

## BaseEntity

All entities extend `BaseEntity` for automatic timestamp management:

```java
@MappedSuperclass
@EntityListeners(AuditingEntityListener.class)
@Getter
public abstract class BaseEntity {

    @CreatedDate
    @Column(nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @LastModifiedDate
    @Column(nullable = false)
    private OffsetDateTime updatedAt;
}
```

Requires `@EnableJpaAuditing` on the main application class.

## Entity Template

```java
@Entity
@Table(name = "employee")
@Getter
@Setter
public class Employee extends BaseEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long sequence;

    @Column(nullable = false, unique = true, updatable = false)
    private UUID id;

    @Column(nullable = false, unique = true, updatable = false)
    private String email;

    @Column(nullable = false, length = 20)
    private String displayName;
}
```

### Key Patterns

- `sequence` (Long): Auto-increment database primary key. Internal use only, never exposed via API.
- `id` (UUID v7): External identifier. Immutable, unique, time-ordered for efficient B-tree indexing.
- `createdAt`, `updatedAt`: Managed by JPA Auditing, never set manually.
- `@Table(name = "snake_case")`: Table name always in snake_case.
- Column mapping: Spring default implicit naming strategy converts `camelCase` to `snake_case`.
- Lombok `@Getter @Setter`: Used for all entity fields.

### UUID v7 Generation

```java
import com.github.f4b6a3.uuid.UuidCreator;

UUID id = UuidCreator.getTimeOrderedEpoch();
```

## Repository Template

```java
public interface EmployeeRepository extends JpaRepository<Employee, Long> {

    boolean existsByEmail(String email);

    Optional<Employee> findById(UUID id);
}
```

- Extends `JpaRepository<Entity, Long>` (ID type is always `Long` for the sequence PK)
- Use Spring Data query derivation for simple queries
- Custom `@Query` only when derivation is insufficient

## DTO Templates

### Command (Write Request)

```java
public record CreateEmployee(
    String email,
    String displayName
) {}
```

### View (Read Response)

```java
public record EmployeeView(
    UUID id,
    String email,
    String displayName
) {}
```

### Query (Read Request)

```java
public record FindEmployee(UUID id) {}

public record GetEmployees(int page, int size) {
    public GetEmployees {
        if (size > 20) size = 20;
    }
}
```

### Generic Pagination Wrapper

```java
public record PageCarrier<T>(
    List<T> items,
    int page,
    int size,
    long total
) {}
```

## Domain Exception Template

```java
public class DuplicateEmailException extends RuntimeException {
    public DuplicateEmailException(String email) {
        super("Duplicate email: " + email);
    }
}
```

Mapped to HTTP status in the controller via `@ExceptionHandler`.

## Validation Utility Template

```java
@Component
public class EmployeePropertyValidator {

    private static final Pattern EMAIL_PATTERN =
        Pattern.compile("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$");

    private static final Pattern DISPLAY_NAME_PATTERN =
        Pattern.compile("^[a-zA-Z0-9]+( [a-zA-Z0-9]+)*$");

    public void validateEmail(String email) {
        if (email == null || !EMAIL_PATTERN.matcher(email).matches()) {
            throw new InvalidEmailFormatException(email);
        }
    }

    public void validateDisplayName(String displayName) {
        if (displayName == null || displayName.length() > 20
            || !DISPLAY_NAME_PATTERN.matcher(displayName).matches()) {
            throw new InvalidDisplayNameException(displayName);
        }
    }
}
```
