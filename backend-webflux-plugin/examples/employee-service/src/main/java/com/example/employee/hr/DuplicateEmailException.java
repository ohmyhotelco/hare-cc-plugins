package com.example.employee.hr;

public class DuplicateEmailException extends RuntimeException {

    public DuplicateEmailException(String email) {
        super("Duplicate email: " + email);
    }
}
