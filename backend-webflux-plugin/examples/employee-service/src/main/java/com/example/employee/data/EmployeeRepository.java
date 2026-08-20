package com.example.employee.data;

import java.util.UUID;
import org.springframework.data.domain.Pageable;
import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.repository.reactive.ReactiveCrudRepository;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

public interface EmployeeRepository extends ReactiveCrudRepository<Employee, Long> {

    Mono<Boolean> existsByEmail(String email);

    // Explicit @Query rather than derivation: the external UUID column is mapped to
    // the Java field "id", but ReactiveCrudRepository already reserves findById(Long)
    // for the sequence primary key (see CLAUDE.md dual-key convention), so this method
    // is named findByExternalId -- a name Spring Data's derivation cannot match to the
    // "id" field on its own.
    @Query("SELECT \"sequence\", \"id\", \"email\", \"display_name\", \"created_at\", \"updated_at\" "
        + "FROM \"employee\" WHERE \"id\" = :id")
    Mono<Employee> findByExternalId(UUID id);

    Flux<Employee> findAllBy(Pageable pageable);
}
