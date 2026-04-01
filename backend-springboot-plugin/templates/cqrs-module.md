# CQRS Module Structure

Reference template for creating new modules following the CQRS (Command Query Responsibility Segregation) pattern.

## Package Layout

When adding a new domain entity (e.g., `Leave`), create files in the following packages:

```
{basePackage}/
├── command/
│   ├── Create{Entity}.java          <- Write request DTO (record)
│   └── Update{Entity}.java          <- Write request DTO (record)
├── commandmodel/
│   ├── Create{Entity}CommandExecutor.java   <- Write logic (@Component record)
│   └── Update{Entity}CommandExecutor.java
├── query/
│   ├── Get{Entity}Page.java          <- Paginated list query DTO (record)
│   └── Find{Entity}.java             <- Single item query DTO (record)
├── querymodel/
│   ├── Get{Entity}PageQueryProcessor.java   <- List logic (@Component record)
│   └── Find{Entity}QueryProcessor.java      <- Single item logic (@Component record)
├── view/
│   └── {Entity}View.java             <- Read response DTO (record)
├── data/
│   ├── {Entity}.java                  <- JPA entity
│   └── {Entity}Repository.java        <- Spring Data JPA repository
└── {domain}/
    ├── api/
    │   └── {Entity}Controller.java    <- REST controller (record)
    ├── {Description}Exception.java    <- Domain exception
    └── {Entity}PropertyValidator.java <- Validation utility
```

## Code Templates

### Command (Request DTO)

```java
public record CreateEmployee(
    String email,
    String displayName
) {}
```

### Command Executor

```java
@Component
public record CreateEmployeeCommandExecutor(
    EmployeeRepository employeeRepository,
    EmployeePropertyValidator validator
) {
    @Transactional
    public void execute(CreateEmployee command) {
        validator.validateEmail(command.email());
        validator.validateDisplayName(command.displayName());

        if (employeeRepository.existsByEmail(command.email())) {
            throw new DuplicateEmailException(command.email());
        }

        var employee = new Employee();
        employee.setId(UuidCreator.getTimeOrderedEpoch());
        employee.setEmail(command.email());
        employee.setDisplayName(command.displayName());
        employeeRepository.save(employee);
    }
}
```

### Query (Request DTO)

```java
public record GetEmployeePage(
    @Min(0) int page,
    @Min(1) @Max(20) int size
) {
    public GetEmployeePage {
        if (size > 20) size = 20;
    }
}
```

### Query Processor

```java
@Component
public record GetEmployeePageQueryProcessor(
    EmployeeRepository employeeRepository
) {
    public PageCarrier<EmployeeView> process(GetEmployeePage query) {
        var pageable = PageRequest.of(query.page(), query.size());
        var page = employeeRepository.findAll(pageable);
        var items = page.getContent().stream()
            .map(e -> new EmployeeView(e.getId(), e.getEmail(), e.getDisplayName()))
            .toList();
        return new PageCarrier<>(items, page.getNumber(), page.getSize(), page.getTotalElements());
    }
}
```

### View (Response DTO)

```java
public record EmployeeView(
    UUID id,
    String email,
    String displayName
) {}

public record PageCarrier<T>(
    List<T> items,
    int page,
    int size,
    long total
) {}
```

### Controller (Record-based DI)

```java
@RestController
public record EmployeeController(
    CreateEmployeeCommandExecutor createExecutor,
    GetEmployeePageQueryProcessor pageProcessor,
    FindEmployeeQueryProcessor findProcessor
) {
    @PostMapping("/hr/employees")
    @ResponseStatus(HttpStatus.CREATED)
    public void create(@RequestBody CreateEmployee command) {
        createExecutor.execute(command);
    }

    @GetMapping("/hr/employees")
    public PageCarrier<EmployeeView> list(
        @RequestParam(defaultValue = "0") int page,
        @RequestParam(defaultValue = "10") int size
    ) {
        return pageProcessor.process(new GetEmployeePage(page, size));
    }

    @GetMapping("/hr/employees/{id}")
    public EmployeeView find(@PathVariable UUID id) {
        return findProcessor.process(new FindEmployee(id));
    }

    @ExceptionHandler(DuplicateEmailException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    public void handleDuplicateEmail() {}

    @ExceptionHandler(InvalidEmailFormatException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public void handleInvalidEmail() {}
}
```

### Flyway Migration

```sql
-- V{N}__{description}.sql
CREATE TABLE employee (
    sequence     BIGSERIAL    PRIMARY KEY,
    id           UUID         NOT NULL UNIQUE,
    email        VARCHAR(255) NOT NULL UNIQUE,
    display_name VARCHAR(20)  NOT NULL,
    created_at   TIMESTAMPTZ  NOT NULL,
    updated_at   TIMESTAMPTZ  NOT NULL
);
```

## Flow Diagram

```
POST /hr/employees
  -> EmployeeController.create()
    -> CreateEmployee (record) validated by Spring
      -> CreateEmployeeCommandExecutor.execute()
        -> EmployeePropertyValidator (business validation)
        -> EmployeeRepository.save() (persistence)
  <- 201 Created

GET /hr/employees?page=0&size=10
  -> EmployeeController.list()
    -> GetEmployeePage (record)
      -> GetEmployeePageQueryProcessor.process()
        -> EmployeeRepository.findAll(pageable)
        -> map to EmployeeView
  <- 200 OK + PageCarrier<EmployeeView>
```
