package com.example.employee.query;

public record GetEmployeePage(int page, int size) {

    public GetEmployeePage {
        if (size > 20) {
            size = 20;
        }
        if (size < 1) {
            size = 10;
        }
        if (page < 0) {
            page = 0;
        }
    }
}
