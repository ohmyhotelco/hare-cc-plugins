package com.example.employee.querymodel;

import com.example.employee.data.EmployeeRepository;
import com.example.employee.query.FindEmployee;
import com.example.employee.view.EmployeeView;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

@Component
public record FindEmployeeQueryProcessor(
    EmployeeRepository employeeRepository
) {

    public Mono<EmployeeView> process(FindEmployee query) {
        return employeeRepository.findByExternalId(query.id())
            .map(e -> new EmployeeView(e.getId(), e.getEmail(), e.getDisplayName()));
    }
}
