package com.example.employee.hr.api.employees;

import com.example.employee.command.CreateEmployee;
import com.example.employee.view.EmployeeView;
import com.example.employee.view.PageCarrier;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webtestclient.autoconfigure.AutoConfigureWebTestClient;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.test.web.reactive.server.WebTestClient;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureWebTestClient
class GetTests {

    private static final AtomicInteger COUNTER = new AtomicInteger(0);

    @Autowired
    private WebTestClient webTestClient;

    private static String nextEmail() {
        return "list-user" + COUNTER.incrementAndGet() + "@test.com";
    }

    @Test
    void returns_paginated_results() {
        webTestClient.post().uri("/hr/employees")
            .bodyValue(new CreateEmployee(nextEmail(), "Paged"))
            .exchange()
            .expectStatus().isCreated();

        webTestClient.get().uri("/hr/employees?page=0&size=10")
            .exchange()
            .expectStatus().isOk()
            .expectBody(new ParameterizedTypeReference<PageCarrier<EmployeeView>>() { });
    }

    @Test
    void page_size_capped_at_20() {
        webTestClient.post().uri("/hr/employees")
            .bodyValue(new CreateEmployee(nextEmail(), "Capped"))
            .exchange()
            .expectStatus().isCreated();

        webTestClient.get().uri("/hr/employees?page=0&size=999")
            .exchange()
            .expectStatus().isOk()
            .expectBody(new ParameterizedTypeReference<PageCarrier<EmployeeView>>() { })
            .value(page -> org.assertj.core.api.Assertions.assertThat(page.items()).hasSizeLessThanOrEqualTo(20));
    }

    @Test
    void returns_404_when_not_found() {
        webTestClient.get().uri("/hr/employees/{id}", UUID.randomUUID())
            .exchange()
            .expectStatus().isNotFound();
    }

    @Test
    void non_numeric_page_returns_400_Bad_Request() {
        webTestClient.get().uri("/hr/employees?page=abc")
            .exchange()
            .expectStatus().isBadRequest();
    }

    @Test
    void non_numeric_size_returns_400_Bad_Request() {
        webTestClient.get().uri("/hr/employees?size=abc")
            .exchange()
            .expectStatus().isBadRequest();
    }

    @Test
    void malformed_id_returns_400_Bad_Request() {
        webTestClient.get().uri("/hr/employees/not-a-uuid")
            .exchange()
            .expectStatus().isBadRequest();
    }
}
