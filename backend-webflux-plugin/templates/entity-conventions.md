# Entity and DTO Conventions

This plugin supports two data profiles (`dataProfile` in
`.claude/backend-webflux-plugin.json`): **R2DBC** and **MyBatis**. See
`docs/decisions.md` Decision 1 for why both exist.

- R2DBC entity/repository/executor conventions: `templates/entity-conventions-r2dbc.md`
- MyBatis entity/mapper/executor conventions: `templates/entity-conventions-mybatis.md`

Read only the file matching an entity's resolved profile — never mix R2DBC
repository code and MyBatis mapper code for the same entity. The templates below
(DTOs, domain exceptions, validators) are shared by both profiles and defined once,
here, rather than repeated in the profile-specific files.

## DTO Templates (shared by both profiles)

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

public record GetEmployeePage(int page, int size) {
    public GetEmployeePage {
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

Mapped to HTTP status in the router's error handling (functional style, see
`templates/web-layer-functional.md`) or via `@ExceptionHandler` (annotated style,
see `templates/web-layer-annotated.md`).

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

Validators are plain synchronous code in both profiles — they throw, they don't
return `Mono`. The wrapping `Mono`/`Flux` chain around them is what makes the overall
executor reactive.
