# Web Layer — RouterFunction + HandlerFunction (default)

Applies when `config.webLayer == "functional"` (the default — see
`docs/decisions.md` Decision 2). DTO types referenced below are defined in
`templates/entity-conventions.md` § DTO Templates.

```java
@Configuration
public class EmployeeRouter {

    @Bean
    public RouterFunction<ServerResponse> employeeRoutes(EmployeeHandler handler) {
        return RouterFunctions.route()
            .POST("/hr/employees", handler::create)
            .GET("/hr/employees", handler::list)
            .GET("/hr/employees/{id}", handler::find)
            .build();
    }
}

@Component
public record EmployeeHandler(
    CreateEmployeeCommandExecutor createExecutor,
    GetEmployeePageQueryProcessor pageProcessor,
    FindEmployeeQueryProcessor findProcessor
) {
    public Mono<ServerResponse> create(ServerRequest request) {
        return request.bodyToMono(CreateEmployee.class)
            .flatMap(createExecutor::execute)
            .then(ServerResponse.status(HttpStatus.CREATED).build())
            .onErrorResume(DuplicateEmailException.class,
                e -> ServerResponse.status(HttpStatus.CONFLICT).build())
            .onErrorResume(InvalidEmailFormatException.class,
                e -> ServerResponse.badRequest().build());
    }

    public Mono<ServerResponse> list(ServerRequest request) {
        // Mono.fromCallable defers the parse so a malformed page/size becomes a reactive
        // error signal at subscription time, not a synchronous throw at call time -- the
        // functional runtime does not auto-translate a thrown exception into 400 the way
        // an annotated @RequestParam binding does, so the mapping has to be explicit here.
        return Mono.fromCallable(() -> {
                var page = Integer.parseInt(request.param("page").orElse("0"));
                var size = Integer.parseInt(request.param("size").orElse("10"));
                return new GetEmployeePage(page, size);
            })
            .flatMap(pageProcessor::process)
            .flatMap(result -> ServerResponse.ok().bodyValue(result))
            .onErrorResume(NumberFormatException.class, e -> ServerResponse.badRequest().build());
    }

    public Mono<ServerResponse> find(ServerRequest request) {
        var id = request.pathVariable("id");
        return Mono.fromCallable(() -> UUID.fromString(id))
            .flatMap(uuid -> findProcessor.process(new FindEmployee(uuid)))
            .flatMap(result -> ServerResponse.ok().bodyValue(result))
            .switchIfEmpty(ServerResponse.notFound().build())
            .onErrorResume(IllegalArgumentException.class, e -> ServerResponse.badRequest().build());
    }
}
```

The manual-parse wrapping in `list`/`find` above only applies to this style, which
owns its own request parsing — the `@RestController` variant in
`templates/web-layer-annotated.md` does not need it, since Spring's own
`@RequestParam`/`@PathVariable` binding already rejects a malformed `int`/`UUID`
with 400 before the method body runs.
