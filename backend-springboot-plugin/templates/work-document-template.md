# {Feature Name}

## Related Documents

- CLAUDE.md (development rules)
- Plugin CLAUDE.md (architecture and conventions)

## Entity

### {EntityName}

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| sequence | Long | PK, auto-increment | Database primary key |
| id | UUID | unique, not null | External identifier (UUID v7) |
| {field} | {Type} | {constraints} | {description} |
| createdAt | LocalDateTime | not null, auto | Creation timestamp |
| updatedAt | LocalDateTime | not null, auto | Last update timestamp |

Table name: `{snake_case_entity_name}`

### Indexes

- `idx_{table}_{column}` on `{column}` -- {purpose}

## Commands

### Create{Entity}

```java
public record Create{Entity}(
    {Type} {field},
    ...
) {}
```

### Create{Entity}CommandExecutor

1. Validate {field} format
2. Check for duplicates
3. Generate UUID v7 for `id`
4. Save entity
5. {Any side effects: send email, publish event, etc.}

## Queries

### Get{Entities} (Paginated)

```java
public record Get{Entities}(int page, int size) {}
```

- Max page size: 20
- Returns: `PageCarrier<{Entity}View>`

### Find{Entity}

```java
public record Find{Entity}(UUID id) {}
```

- Returns: `{Entity}View`
- 404 if not found

## API Endpoints

| Method | URL | Command/Query | Status |
|--------|-----|---------------|--------|
| POST | `/{domain}/{resources}` | Create{Entity} | 201 Created |
| GET | `/{domain}/{resources}?page=&size=` | Get{Entities} | 200 OK |
| GET | `/{domain}/{resources}/{id}` | Find{Entity} | 200 OK / 404 |

## Validation Rules

- {field}: {rule description} (regex: `{pattern}`)
- {field}: {rule description}

## Exceptions

| Exception | HTTP Status | Condition |
|-----------|-------------|-----------|
| Invalid{Field}Exception | 400 | {field} format validation fails |
| Duplicate{Field}Exception | 409 | {field} already exists |
| {Entity}NotFoundException | 404 | Entity not found by id |

## Test Scenarios

### POST /{domain}/{resources}

- [ ] valid request returns 201 Created
- [ ] {invalid field} returns 400 Bad Request
- [ ] duplicate {unique field} returns 409 Conflict

### GET /{domain}/{resources}

- [ ] returns empty list when no data exists
- [ ] returns paginated results
- [ ] page size capped at 20

### GET /{domain}/{resources}/{id}

- [ ] returns entity when found
- [ ] returns 404 when not found

## Test Data

### {Entity}Generator

```java
public class {Entity}Generator {
    private static final AtomicInteger counter = new AtomicInteger(0);

    public static {Type} next{Field}() {
        return "{prefix}" + counter.incrementAndGet();
    }
}
```

## Implementation Notes

- {Any special considerations}
- {Dependencies on other modules}
- {Performance considerations}
