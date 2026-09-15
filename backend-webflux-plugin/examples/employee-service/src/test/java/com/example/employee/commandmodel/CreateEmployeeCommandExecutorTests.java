package com.example.employee.commandmodel;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

import com.example.employee.command.CreateEmployee;
import com.example.employee.data.Employee;
import com.example.employee.data.EmployeeRepository;
import com.example.employee.hr.DuplicateEmailException;
import com.example.employee.hr.EmployeePropertyValidator;
import com.example.employee.hr.InvalidEmailFormatException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

@ExtendWith(MockitoExtension.class)
class CreateEmployeeCommandExecutorTests {

    @Mock
    private EmployeeRepository employeeRepository;

    private CreateEmployeeCommandExecutor executor;

    @BeforeEach
    void setUp() {
        executor = new CreateEmployeeCommandExecutor(employeeRepository, new EmployeePropertyValidator());
    }

    @Test
    void execute_completes_without_error_for_valid_command() {
        when(employeeRepository.existsByEmail(anyString())).thenReturn(Mono.just(false));
        when(employeeRepository.save(any(Employee.class)))
            .thenAnswer(invocation -> Mono.just(invocation.getArgument(0)));

        var command = new CreateEmployee("valid@example.com", "Valid User");

        StepVerifier.create(executor.execute(command))
            .verifyComplete();
    }

    @Test
    void execute_errors_with_duplicate_email_exception() {
        when(employeeRepository.existsByEmail(anyString())).thenReturn(Mono.just(true));

        var command = new CreateEmployee("dup@example.com", "Dup User");

        StepVerifier.create(executor.execute(command))
            .expectError(DuplicateEmailException.class)
            .verify();
    }

    @Test
    void execute_maps_concurrent_unique_violation_to_duplicate_email_exception() {
        when(employeeRepository.existsByEmail(anyString())).thenReturn(Mono.just(false));
        // what the driver reports when the named constraint rejects the row
        when(employeeRepository.save(any(Employee.class)))
            .thenReturn(Mono.error(new DataIntegrityViolationException(
                "Duplicate entry 'race@example.com' for key 'employee.uk_employee_email'")));

        var command = new CreateEmployee("race@example.com", "Race Loser");

        StepVerifier.create(executor.execute(command))
            .expectError(DuplicateEmailException.class)
            .verify();
    }

    @Test
    void execute_does_not_report_an_unrelated_integrity_violation_as_a_duplicate() {
        when(employeeRepository.existsByEmail(anyString())).thenReturn(Mono.just(false));
        when(employeeRepository.save(any(Employee.class)))
            .thenReturn(Mono.error(new DataIntegrityViolationException(
                "Column 'display_name' cannot be null")));

        var command = new CreateEmployee("null@example.com", "Someone");

        // a NOT NULL rejection is not a duplicate email; it must not become a 409
        StepVerifier.create(executor.execute(command))
            .expectError(DataIntegrityViolationException.class)
            .verify();
    }

    @Test
    void execute_errors_with_invalid_email_format() {
        var command = new CreateEmployee("not-an-email", "Some User");

        StepVerifier.create(executor.execute(command))
            .expectError(InvalidEmailFormatException.class)
            .verify();
    }
}
