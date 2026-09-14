# Web Layer — `@RestController` (named exception)

Only use when the domain deliberately mirrors an existing annotated-controller
module (`config.webLayer == "annotated"`, see `docs/decisions.md` Decision 2). Never
mix `RouterFunction` and `@RestController` for the same domain. DTO types referenced
below are defined in `templates/entity-conventions.md` § DTO Templates.

```java
@RestController
public record EmployeeController(
    CreateEmployeeCommandExecutor createExecutor,
    GetEmployeePageQueryProcessor pageProcessor,
    FindEmployeeQueryProcessor findProcessor
) {
    @PostMapping("/hr/employees")
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<Void> create(@RequestBody CreateEmployee command) {
        return createExecutor.execute(command);
    }

    @GetMapping("/hr/employees")
    public Mono<PageCarrier<EmployeeView>> list(
        @RequestParam(defaultValue = "0") int page,
        @RequestParam(defaultValue = "10") int size
    ) {
        return pageProcessor.process(new GetEmployeePage(page, size));
    }

    @GetMapping("/hr/employees/{id}")
    public Mono<ResponseEntity<EmployeeView>> find(@PathVariable UUID id) {
        // The processor's empty Mono is the not-found signal; a bare Mono<EmployeeView> would
        // answer 200 with an empty body. The status depends on the async result, so the
        // ResponseEntity form is the one Spring documents for it.
        return findProcessor.process(new FindEmployee(id))
            .map(ResponseEntity::ok)
            .defaultIfEmpty(ResponseEntity.notFound().build());
    }

    @ExceptionHandler(DuplicateEmailException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    public void handleDuplicateEmail() {}

    @ExceptionHandler(InvalidEmailFormatException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public void handleInvalidEmail() {}

    @ExceptionHandler(InvalidDisplayNameException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public void handleInvalidDisplayName() {}
}
```

This variant does **not** need the manual-parse wrapping the `RouterFunction`
variant in `templates/web-layer-functional.md` uses — Spring's own
`@RequestParam`/`@PathVariable` binding already rejects a malformed `int`/`UUID`
with 400 before the method body runs.
