package com.example.employee.hr;

public class InvalidDisplayNameException extends RuntimeException {

    public InvalidDisplayNameException(String displayName) {
        super("Invalid display name: " + displayName);
    }
}
