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
import org.springframework.web.server.ServerWebInputException;
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
            // An empty body completes without a value; without this, flatMap is skipped and
            // `.then(201)` still answers Created for a command that never ran.
            .switchIfEmpty(Mono.error(new ServerWebInputException("request body is required")))
            .flatMap(createExecutor::execute)
            .then(ServerResponse.status(HttpStatus.CREATED).build())
            .onErrorResume(ServerWebInputException.class,
                e -> ServerResponse.badRequest().build())
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
        // The 400 mapping is attached to the parse alone: an IllegalArgumentException raised
        // further down (a corrupt CHAR(36) row failing UUID.fromString in the converter) is a
        // server fault and must stay a 500, not be reported as the caller's mistake.
        return Mono.fromCallable(() -> UUID.fromString(request.pathVariable("id")))
            .onErrorMap(IllegalArgumentException.class,
                e -> new ServerWebInputException("id must be a UUID"))
            .flatMap(id -> findProcessor.process(new FindEmployee(id)))
            .flatMap(result -> ServerResponse.ok().bodyValue(result))
            .switchIfEmpty(ServerResponse.notFound().build())
            .onErrorResume(ServerWebInputException.class, e -> ServerResponse.badRequest().build());
    }
}
