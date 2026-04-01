# Backend Implementation Plan Schema

Reference document for `plan.json` — the structured backend implementation plan produced by the `backend-planner` agent and consumed by `be-crud`, `be-code`, and `be-review`.

Used by: `backend-planner` agent (generation), `be-crud` (consumption)

## Type Mapping Table

Mapping from spec/UI DSL types to Java and database column types:

| Spec / UI DSL Type | Java Type | Column Type | Notes |
|---|---|---|---|
| `string` | `String` | `VARCHAR(255)` | Default length 255 unless spec overrides |
| `string` (with max-length) | `String` | `VARCHAR({n})` | Use spec-defined max length |
| `text` / `long-string` | `String` | `TEXT` | For unbounded text content |
| `number` (integer) | `Long` | `BIGINT` | Use `Integer` only when spec explicitly limits range |
| `number` (decimal) | `BigDecimal` | `NUMERIC({p},{s})` | Precision/scale from spec or default (19,4) |
| `boolean` | `boolean` | `BOOLEAN` | Primitive type (not nullable) |
| `boolean` (nullable) | `Boolean` | `BOOLEAN` | Wrapper type when null is meaningful |
| `date` | `LocalDate` | `DATE` | Date without time |
| `datetime` | `OffsetDateTime` | `TIMESTAMPTZ` | Always use offset-aware type |
| `time` | `LocalTime` | `TIME` | Time without date |
| `email` | `String` | `VARCHAR(255)` | Add email-format validation rule |
| `phone` | `String` | `VARCHAR(50)` | Add phone-format validation rule |
| `url` | `String` | `VARCHAR(2048)` | Add URL-format validation rule |
| `uuid` | `UUID` | `UUID` | Import `java.util.UUID` |
| `enum` | `String` | `VARCHAR(50)` | Java enum type when values are defined in spec |
| Entity reference | Entity class | FK (`BIGINT REFERENCES`) | `@ManyToOne` with `@JoinColumn` |

### Enum Handling

When spec defines a fixed set of values (e.g., status: active/inactive/suspended):
- Create a Java enum: `{EntityName}{FieldName}` (e.g., `EmployeeStatus`)
- Column type: `VARCHAR(50)` with `@Enumerated(EnumType.STRING)`
- Add to `entities[].fields[].enumValues` for reference

## plan.json Schema

```json
{
  "feature": "string — feature name (kebab-case)",
  "specStatus": "string — spec status at planning time (reviewing|finalized)",
  "workingLanguage": "string — working language code (en|ko|vi)",
  "architecture": "string — architecture type from config (cqrs)",
  "specDir": "string — path to spec markdown files",
  "uiDslAvailable": "boolean — whether UI DSL was available",
  "planGeneratedAt": "string — ISO 8601 timestamp",

  "entities": [
    {
      "name": "string — PascalCase entity name",
      "tableName": "string — snake_case table name",
      "domain": "string — domain package name (e.g., hr, leave)",
      "fields": [
        {
          "name": "string — camelCase field name",
          "type": "string — spec/UI DSL type",
          "javaType": "string — Java type (e.g., String, Long, UUID)",
          "columnType": "string — SQL column type (e.g., VARCHAR(255))",
          "constraints": ["string — constraint descriptors: not null, unique, etc."],
          "enumValues": ["string — enum values if type is enum (optional)"],
          "ref": "string — referenced entity name for FK (optional)",
          "source": "string — spec references (e.g., FR-001, dataEntity: Employee)"
        }
      ],
      "indexes": [
        {
          "name": "string — index name (e.g., idx_employee_email)",
          "columns": ["string — column names"],
          "unique": "boolean",
          "source": "string — spec reference (e.g., BR-001)"
        }
      ],
      "source": "string — spec references"
    }
  ],

  "commands": [
    {
      "name": "string — PascalCase command name (e.g., CreateEmployee)",
      "entity": "string — target entity name",
      "action": "string — action verb (create, update, delete, or domain-specific)",
      "fields": ["string — field names included in command DTO"],
      "validations": [
        {
          "field": "string — field name",
          "rule": "string — rule descriptor (e.g., email-format, unique, not-blank, max-length:100)",
          "source": "string — BR-nnn reference"
        }
      ],
      "sideEffects": ["string — side effect descriptions (e.g., send email notification)"],
      "source": "string — FR-nnn reference"
    }
  ],

  "queries": [
    {
      "name": "string — PascalCase query name (e.g., GetEmployeePage)",
      "entity": "string — target entity name",
      "action": "string — query type (list, find, search)",
      "pagination": "boolean — whether pagination is supported",
      "maxPageSize": "number — max page size (default 20)",
      "filters": [
        {
          "field": "string — filter field name",
          "type": "string — filter type (exact, contains, range, enum)",
          "source": "string — FR-nnn reference"
        }
      ],
      "sortFields": ["string — sortable field names"],
      "lookupField": "string — field name for single lookup (optional, e.g., id)",
      "lookupType": "string — field type for single lookup (optional, e.g., UUID)",
      "source": "string — FR-nnn reference"
    }
  ],

  "endpoints": [
    {
      "method": "string — HTTP method (POST, GET, PUT, PATCH, DELETE)",
      "path": "string — URL path (e.g., /hr/employees/{id})",
      "command": "string — command name (for write endpoints, optional)",
      "query": "string — query name (for read endpoints, optional)",
      "responseStatus": "number — HTTP status code (201, 200, 204)",
      "responseBody": "string — response type (e.g., EmployeeView, PageCarrier<EmployeeView>, null)",
      "source": "string — FR-nnn reference"
    }
  ],

  "exceptions": [
    {
      "name": "string — PascalCase exception name (e.g., DuplicateEmailException)",
      "httpStatus": "number — HTTP status code (400, 404, 409)",
      "condition": "string — human-readable trigger condition",
      "entity": "string — related entity name",
      "source": "string — E-nnn, BR-nnn references"
    }
  ],

  "validationRules": [
    {
      "entity": "string — entity name",
      "field": "string — field name",
      "rules": [
        {
          "type": "string — rule type (pattern, unique, not-blank, max-length, min-length, min, max, enum)",
          "value": "string|number — rule value (regex pattern, length, etc., optional)",
          "source": "string — BR-nnn reference"
        }
      ]
    }
  ],

  "testScenarios": [
    {
      "endpoint": "string — endpoint descriptor (e.g., POST /hr/employees)",
      "entity": "string — related entity name",
      "scenarios": [
        {
          "description": "string — test scenario in work document format (lowercase, present tense)",
          "source": "string — TS-nnn, AC-nnn references"
        }
      ]
    }
  ],

  "entityDependencyOrder": ["string — entity names in scaffold order (FK targets first)"],

  "skippedScreens": [
    {
      "screenId": "string — screen identifier from spec",
      "reason": "string — why this screen has no backend requirement"
    }
  ],

  "skippedEntities": [
    {
      "name": "string — entity name that already exists in the project",
      "reason": "string — e.g., Already exists at {path}"
    }
  ],

  "summary": {
    "entities": "number — total entity count (new only)",
    "commands": "number — total command count",
    "queries": "number — total query count",
    "endpoints": "number — total endpoint count",
    "exceptions": "number — total exception count",
    "testScenarios": "number — total backend-relevant test scenario count",
    "skippedScreens": "number — skipped screen count",
    "skippedEntities": "number — skipped entity count"
  }
}
```

## Source Reference Format

Source references link plan elements back to spec identifiers for traceability.

Format: comma-separated list of spec identifiers.

| Prefix | Meaning | Example |
|---|---|---|
| `FR-nnn` | Functional Requirement | `FR-001` |
| `BR-nnn` | Business Rule | `BR-001` |
| `AC-nnn` | Acceptance Criteria | `AC-001` |
| `US-nnn` | User Story | `US-001` |
| `TS-nnn` | Test Scenario | `TS-001` |
| `E-nnn` | Error Code | `E-001` |
| `screen:` | Screen ID | `screen: employee-list` |
| `dataEntity:` | UI DSL data entity | `dataEntity: Employee` |

Example: `"source": "FR-001, BR-002, dataEntity: Employee"`

## Validation Rule Descriptors

Rule descriptors used in `commands[].validations[].rule` and `validationRules[].rules[].type`:

| Rule | Format | Example |
|---|---|---|
| Email format | `email-format` | Email regex validation |
| Pattern match | `pattern` (value = regex) | Custom regex |
| Unique | `unique` | Database uniqueness check |
| Not blank | `not-blank` | Non-empty string |
| Max length | `max-length` (value = number) | `max-length:100` |
| Min length | `min-length` (value = number) | `min-length:2` |
| Min value | `min` (value = number) | `min:0` |
| Max value | `max` (value = number) | `max:1000` |
| Enum | `enum` (value = comma-separated values) | `enum:active,inactive` |
