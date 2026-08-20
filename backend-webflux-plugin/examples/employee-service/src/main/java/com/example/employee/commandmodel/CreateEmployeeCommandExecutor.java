package com.example.employee.commandmodel;

import com.example.employee.command.CreateEmployee;
import com.example.employee.data.Employee;
import com.example.employee.data.EmployeeRepository;
import com.example.employee.hr.DuplicateEmailException;
import com.example.employee.hr.EmployeePropertyValidator;
import com.github.f4b6a3.uuid.UuidCreator;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

@Component
public record CreateEmployeeCommandExecutor(
    EmployeeRepository employeeRepository,
    EmployeePropertyValidator validator
) {

    public Mono<Void> execute(CreateEmployee command) {
        // Mono.defer wraps validation so a synchronous throw from the validator becomes
        // a reactive error signal at subscription time, not an eagerly-thrown exception
        // at call time. This matters for callers that invoke execute(command) directly
        // (e.g. a unit test with StepVerifier) as well as callers that .flatMap() into
        // it from a router/handler -- both need the same error-as-signal behavior.
        return Mono.defer(() -> {
                validator.validateEmail(command.email());
                validator.validateDisplayName(command.displayName());
                return employeeRepository.existsByEmail(command.email());
            })
            .flatMap(exists -> {
                if (Boolean.TRUE.equals(exists)) {
                    return Mono.error(new DuplicateEmailException(command.email()));
                }
                var employee = new Employee();
                employee.setId(UuidCreator.getTimeOrderedEpoch());
                employee.setEmail(command.email());
                employee.setDisplayName(command.displayName());
                var now = LocalDateTime.now(ZoneOffset.UTC);
                employee.setCreatedAt(now);
                employee.setUpdatedAt(now);
                // existsByEmail above is a fast-path only, not the correctness guarantee --
                // two concurrent creates can both pass that check, so the UNIQUE constraint
                // on the email column is what actually prevents the duplicate, and this map
                // turns its rejection into the same domain exception the pre-check throws.
                return employeeRepository.save(employee)
                    .onErrorMap(DataIntegrityViolationException.class,
                        e -> new DuplicateEmailException(command.email()));
            })
            .then();
    }
}
