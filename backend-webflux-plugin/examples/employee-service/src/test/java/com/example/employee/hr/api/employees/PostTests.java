package com.example.employee.hr.api.employees;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.employee.command.CreateEmployee;
import com.example.employee.data.EmployeeRepository;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webtestclient.autoconfigure.AutoConfigureWebTestClient;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.reactive.server.WebTestClient;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureWebTestClient
class PostTests {

    private static final AtomicInteger COUNTER = new AtomicInteger(0);

    @Autowired
    private WebTestClient webTestClient;

    @Autowired
    private EmployeeRepository employeeRepository;

    private static String nextEmail() {
        return "user" + COUNTER.incrementAndGet() + "@test.com";
    }

    @Test
    void valid_request_returns_201_Created() {
        var command = new CreateEmployee(nextEmail(), "John");

        webTestClient.post().uri("/hr/employees")
            .bodyValue(command)
            .exchange()
            .expectStatus().isEqualTo(HttpStatus.CREATED);
    }

    @Test
    void valid_request_persists_employee() {
        var email = nextEmail();
        var command = new CreateEmployee(email, "Jane");

        webTestClient.post().uri("/hr/employees")
            .bodyValue(command)
            .exchange()
            .expectStatus().isCreated();

        var exists = employeeRepository.existsByEmail(email).block();
        assertThat(exists).isTrue();
    }

    @Test
    void duplicate_email_returns_409_Conflict() {
        var email = nextEmail();
        var first = new CreateEmployee(email, "Alice");
        var duplicate = new CreateEmployee(email, "Alice Two");

        webTestClient.post().uri("/hr/employees").bodyValue(first).exchange().expectStatus().isCreated();

        webTestClient.post().uri("/hr/employees")
            .bodyValue(duplicate)
            .exchange()
            .expectStatus().isEqualTo(HttpStatus.CONFLICT);
    }

    @Test
    void invalid_email_format_returns_400_Bad_Request() {
        var command = new CreateEmployee("not-an-email", "Bob");

        webTestClient.post().uri("/hr/employees")
            .bodyValue(command)
            .exchange()
            .expectStatus().isBadRequest();
    }

    @Test
    void empty_display_name_returns_400_Bad_Request() {
        var command = new CreateEmployee(nextEmail(), "");

        webTestClient.post().uri("/hr/employees")
            .bodyValue(command)
            .exchange()
            .expectStatus().isBadRequest();
    }
}
