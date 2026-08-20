package com.example.employee.data;

import static org.assertj.core.api.Assertions.assertThat;

import com.github.f4b6a3.uuid.UuidCreator;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.r2dbc.test.autoconfigure.DataR2dbcTest;
import reactor.test.StepVerifier;

@DataR2dbcTest
class EmployeeRepositoryTests {

    private static final AtomicInteger COUNTER = new AtomicInteger(0);

    @Autowired
    private EmployeeRepository repository;

    private static Employee newEmployee(String email) {
        var employee = new Employee();
        employee.setId(UuidCreator.getTimeOrderedEpoch());
        employee.setEmail(email);
        employee.setDisplayName("Repo Test");
        var now = LocalDateTime.now(ZoneOffset.UTC);
        employee.setCreatedAt(now);
        employee.setUpdatedAt(now);
        return employee;
    }

    @Test
    void find_by_email_returns_matching_employee() {
        var email = "repo-user" + COUNTER.incrementAndGet() + "@test.com";
        var employee = newEmployee(email);

        StepVerifier.create(
                repository.save(employee)
                    .then(repository.existsByEmail(email))
            )
            .assertNext(exists -> assertThat(exists).isTrue())
            .verifyComplete();
    }

    @Test
    void find_by_external_id_returns_saved_employee() {
        var employee = newEmployee("repo-lookup" + COUNTER.incrementAndGet() + "@test.com");

        StepVerifier.create(
                repository.save(employee)
                    .flatMap(saved -> repository.findByExternalId(saved.getId()))
            )
            .assertNext(found -> assertThat(found.getEmail()).isEqualTo(employee.getEmail()))
            .verifyComplete();
    }
}
