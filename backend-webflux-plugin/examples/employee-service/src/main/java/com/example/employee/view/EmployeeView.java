package com.example.employee.view;

import java.util.UUID;

public record EmployeeView(
    UUID id,
    String email,
    String displayName
) {
}
