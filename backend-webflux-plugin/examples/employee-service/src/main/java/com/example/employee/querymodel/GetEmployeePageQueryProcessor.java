package com.example.employee.querymodel;

import com.example.employee.data.EmployeeRepository;
import com.example.employee.query.GetEmployeePage;
import com.example.employee.view.EmployeeView;
import com.example.employee.view.PageCarrier;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

@Component
public record GetEmployeePageQueryProcessor(
    EmployeeRepository employeeRepository
) {

    public Mono<PageCarrier<EmployeeView>> process(GetEmployeePage query) {
        var pageable = PageRequest.of(query.page(), query.size());
        return employeeRepository.findAllBy(pageable)
            .map(e -> new EmployeeView(e.getId(), e.getEmail(), e.getDisplayName()))
            .collectList()
            .zipWith(employeeRepository.count())
            .map(tuple -> new PageCarrier<>(tuple.getT1(), query.page(), query.size(), tuple.getT2()));
    }
}
