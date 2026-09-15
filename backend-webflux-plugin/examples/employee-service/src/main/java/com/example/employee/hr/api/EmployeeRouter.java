package com.example.employee.hr.api;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.server.RouterFunction;
import org.springframework.web.reactive.function.server.RouterFunctions;
import org.springframework.web.reactive.function.server.ServerResponse;

@Configuration
public class EmployeeRouter {

    @Bean
    public RouterFunction<ServerResponse> employeeRoutes(EmployeeHandler handler) {
        return RouterFunctions.route()
            // No media-type predicate: accept() tests the client's Accept header and 404s a JSON
            // command sent with Accept: text/plain; contentType() 404s a body sent without a
            // Content-Type. bodyToMono() already answers 415 for a body it cannot decode, which
            // is the honest status -- the route exists, the media type is wrong.
            .POST("/hr/employees", handler::create)
            .GET("/hr/employees", handler::list)
            .GET("/hr/employees/{id}", handler::find)
            .build();
    }
}
