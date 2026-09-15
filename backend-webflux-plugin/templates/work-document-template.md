# {Feature Name}

<!-- Template used by: be-crud (full work document with entity, commands, queries, API, and test scenarios) -->

Data profile: `{r2dbc | mybatis}`   <!-- read by the implement agent to pick the entity-conventions file; be-crud records it, be-code's manual path does too via templates/test-scenario-template.md -->

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
| createdAt | LocalDateTime | not null, set by executor (no auditing listener) | Creation timestamp (UTC) |
| updatedAt | LocalDateTime | not null, set by executor (no auditing listener) | Last update timestamp (UTC) |

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

### Get{Entity}Page (Paginated)

```java
public record Get{Entity}Page(int page, int size) {}
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
| GET | `/{domain}/{resources}?page=&size=` | Get{Entity}Page | 200 OK |
| GET | `/{domain}/{resources}/{id}` | Find{Entity} | 200 OK / 404 |

## Validation Rules

- {field}: {rule description} (regex: `{pattern}`)
- {field}: {rule description}

## Exceptions

| Exception | HTTP Status | Condition |
|-----------|-------------|-----------|
| Invalid{Field}Exception | 400 | {field} format validation fails |
| Duplicate{Field}Exception | 409 | {field} already exists |
| (none — empty `Mono` from the Find processor) | 404 | Entity not found by id; mapped by the web layer, no exception class |

## Test Scenarios

### POST /{domain}/{resources}

- [ ] valid request returns 201 Created
- [ ] {invalid field} returns 400 Bad Request
- [ ] duplicate {unique field} returns 409 Conflict

### GET /{domain}/{resources}

- [ ] returns paginated results
- [ ] page size capped at 20
<!-- no "returns empty list when no data exists": the shared Spring context and unique-per-test data model (templates/tdd-rules.md) never hand a test an empty table once another class has inserted; the assertion is order-dependent -->

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
