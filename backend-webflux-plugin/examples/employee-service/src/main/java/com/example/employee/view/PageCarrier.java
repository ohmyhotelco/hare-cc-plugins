package com.example.employee.view;

import java.util.List;

public record PageCarrier<T>(
    List<T> items,
    int page,
    int size,
    long total
) {
}
