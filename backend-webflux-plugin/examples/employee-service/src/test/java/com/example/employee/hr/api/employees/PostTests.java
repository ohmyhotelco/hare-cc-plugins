package com.example.employee.hr.api.employees;

import com.example.employee.command.CreateEmployee;
import com.example.employee.data.EmployeeRepository;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webtestclient.autoconfigure.AutoConfigureWebTestClient;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.reactive.server.WebTestClient;
import reactor.test.StepVerifier;

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

        // StepVerifier, not .block(): the test asserts a reactive result reactively.
        StepVerifier.create(employeeRepository.existsByEmail(email))
            .expectNext(true)
            .verifyComplete();
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
    void valid_request_with_a_non_json_accept_header_returns_201_Created() {
        // The route must match on the body's Content-Type, not on what the client says it
        // can Accept -- a client that accepts text/plain still sends a JSON command.
        webTestClient.post().uri("/hr/employees")
            .header("Accept", "text/plain")
            .bodyValue(new CreateEmployee(nextEmail(), "Kim"))
            .exchange()
            .expectStatus().isEqualTo(HttpStatus.CREATED);
    }

    @Test
    void empty_body_returns_400_Bad_Request() {
        // An empty bodyToMono completes without emitting, which skips flatMap and lets
        // `.then(201)` answer as if the command had run -- nothing is persisted.
        webTestClient.post().uri("/hr/employees")
            .header("Content-Type", "application/json")
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
