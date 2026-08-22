# CQRS Module Structure

Reference template for creating new modules following the CQRS (Command Query
Responsibility Segregation) pattern on the WebFlux stack. `CommandExecutor` and
`QueryProcessor` return `Mono`/`Flux`, never a materialized value or a blocking call
— see `docs/decisions.md` Decision 1 and Decision 2 before touching this file.

## Package Layout

When adding a new domain entity (e.g., `Leave`), create files in the following packages:

```
{basePackage}/
├── command/
│   ├── Create{Entity}.java          <- Write request DTO (record)
│   └── Update{Entity}.java          <- Write request DTO (record)
├── commandmodel/
│   ├── Create{Entity}CommandExecutor.java   <- Write logic, returns Mono<Void>/Mono<Id>
│   └── Update{Entity}CommandExecutor.java
├── query/
│   ├── Get{Entity}Page.java          <- Paginated list query DTO (record)
│   └── Find{Entity}.java             <- Single item query DTO (record)
├── querymodel/
│   ├── Get{Entity}PageQueryProcessor.java   <- List logic, returns Mono<PageCarrier<View>>
│   └── Find{Entity}QueryProcessor.java      <- Single item logic, returns Mono<View>
├── view/
│   └── {Entity}View.java             <- Read response DTO (record)
├── data/
│   ├── {Entity}.java                  <- R2DBC entity or MyBatis POJO
│   └── {Entity}Repository.java        <- R2DBC repository, or {Entity}Mapper.java for MyBatis
└── {domain}/
    ├── api/
    │   ├── {Entity}Router.java        <- RouterFunction config (default, see Decision 2)
    │   └── {Entity}Handler.java       <- HandlerFunction implementation (default)
    │   (or {Entity}Controller.java when webLayer: "annotated" — named exception)
    ├── {Description}Exception.java    <- Domain exception
    └── {Entity}PropertyValidator.java <- Validation utility
```

## Code Templates

The code that fills each package above is split by `dataProfile` and `webLayer`
rather than kept in this file, so a scaffold or implementation only has to read the
branch it actually needs:

- **DTOs** (Command/Query/View/PageCarrier), the Domain Exception template, and the
  Validation Utility template are shared by both data profiles — one canonical copy
  in `templates/entity-conventions.md` § DTO Templates.
- **Entity, Repository/Mapper, CommandExecutor, QueryProcessor** — read exactly one,
  matching the entity's resolved `dataProfile` (never `"both"` for a single entity):
  - `dataProfile: "r2dbc"` → `templates/entity-conventions-r2dbc.md`
  - `dataProfile: "mybatis"` → `templates/entity-conventions-mybatis.md`
- **Router/Handler or Controller** — read exactly one, matching `config.webLayer`:
  - `webLayer: "functional"` (default) → `templates/web-layer-functional.md`
  - `webLayer: "annotated"` (named exception, see Decision 2) → `templates/web-layer-annotated.md`
  - Never mix `RouterFunction` and `@RestController` for the same domain.

### Manual SQL Migration (see Decision 3 — no migration-runner tool)

`src/main/resources/migration/V{N}__create_employee_table.sql`:

```sql
CREATE TABLE employee (
    sequence     BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id           CHAR(36)     NOT NULL UNIQUE,
    email        VARCHAR(255) NOT NULL UNIQUE,
    display_name VARCHAR(20)  NOT NULL,
    created_at   DATETIME(6)  NOT NULL,
    updated_at   DATETIME(6)  NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

This file is applied manually (or by whatever the target project's own process is —
out of scope for this plugin, see `docs/decisions.md` Decision 3). `be-crud` only
generates it; it never executes it.

## Flow Diagram

```
POST /hr/employees
  -> EmployeeRouter routes to EmployeeHandler.create()
    -> CreateEmployee (record) parsed from request body
      -> CreateEmployeeCommandExecutor.execute() -> Mono<Void>
        -> EmployeePropertyValidator (business validation, synchronous)
        -> EmployeeRepository.save() / EmployeeMapper.insert() (persistence)
  <- 201 Created (subscribed by the WebFlux runtime when ServerResponse is returned)

GET /hr/employees?page=0&size=10
  -> EmployeeRouter routes to EmployeeHandler.list()
    -> GetEmployeePage (record)
      -> GetEmployeePageQueryProcessor.process() -> Mono<PageCarrier<EmployeeView>>
        -> EmployeeRepository.findAllBy(pageable) / EmployeeMapper.findAllPage()
        -> map to EmployeeView
  <- 200 OK + PageCarrier<EmployeeView>
```
