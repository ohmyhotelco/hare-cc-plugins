package com.example.employee.hr.api;

import com.example.employee.command.CreateEmployee;
import com.example.employee.commandmodel.CreateEmployeeCommandExecutor;
import com.example.employee.hr.DuplicateEmailException;
import com.example.employee.hr.InvalidDisplayNameException;
import com.example.employee.hr.InvalidEmailFormatException;
import com.example.employee.query.FindEmployee;
import com.example.employee.query.GetEmployeePage;
import com.example.employee.querymodel.FindEmployeeQueryProcessor;
import com.example.employee.querymodel.GetEmployeePageQueryProcessor;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.server.ServerRequest;
import org.springframework.web.reactive.function.server.ServerResponse;
import reactor.core.publisher.Mono;

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
                e -> ServerResponse.badRequest().build())
            .onErrorResume(InvalidDisplayNameException.class,
                e -> ServerResponse.badRequest().build());
    }

    public Mono<ServerResponse> list(ServerRequest request) {
        // Mono.fromCallable defers the parse so a malformed page/size becomes a reactive
        // error signal at subscription time, not a synchronous throw at call time -- the
        // same reasoning create() applies via Mono.defer, needed here because the WebFlux
        // functional runtime does not auto-translate a thrown exception into 400 the way
        // an annotated @RequestParam binding does.
        return Mono.fromCallable(() -> {
                var page = Integer.parseInt(request.queryParam("page").orElse("0"));
                var size = Integer.parseInt(request.queryParam("size").orElse("10"));
                return new GetEmployeePage(page, size);
            })
            .flatMap(pageProcessor::process)
            .flatMap(result -> ServerResponse.ok().bodyValue(result))
            .onErrorResume(NumberFormatException.class, e -> ServerResponse.badRequest().build());
    }

    public Mono<ServerResponse> find(ServerRequest request) {
        return Mono.fromCallable(() -> UUID.fromString(request.pathVariable("id")))
            .flatMap(id -> findProcessor.process(new FindEmployee(id)))
            .flatMap(result -> ServerResponse.ok().bodyValue(result))
            .switchIfEmpty(ServerResponse.notFound().build())
            .onErrorResume(IllegalArgumentException.class, e -> ServerResponse.badRequest().build());
    }
}
