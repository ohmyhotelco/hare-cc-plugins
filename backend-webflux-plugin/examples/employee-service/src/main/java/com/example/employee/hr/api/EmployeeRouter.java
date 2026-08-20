package com.example.employee.hr.api;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.MediaType;
import org.springframework.web.reactive.function.server.RequestPredicates;
import org.springframework.web.reactive.function.server.RouterFunction;
import org.springframework.web.reactive.function.server.RouterFunctions;
import org.springframework.web.reactive.function.server.ServerResponse;

@Configuration
public class EmployeeRouter {

    @Bean
    public RouterFunction<ServerResponse> employeeRoutes(EmployeeHandler handler) {
        return RouterFunctions.route()
            .POST("/hr/employees", RequestPredicates.accept(MediaType.APPLICATION_JSON), handler::create)
            .GET("/hr/employees", handler::list)
            .GET("/hr/employees/{id}", handler::find)
            .build();
    }
}
