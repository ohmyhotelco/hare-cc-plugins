package com.example.employee.hr;

import java.util.regex.Pattern;
import org.springframework.stereotype.Component;

@Component
public class EmployeePropertyValidator {

    private static final Pattern EMAIL_PATTERN =
        Pattern.compile("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$");

    private static final Pattern DISPLAY_NAME_PATTERN =
        Pattern.compile("^[a-zA-Z0-9]+( [a-zA-Z0-9]+)*$");

    public void validateEmail(String email) {
        if (email == null || !EMAIL_PATTERN.matcher(email).matches()) {
            throw new InvalidEmailFormatException(email);
        }
    }

    public void validateDisplayName(String displayName) {
        if (displayName == null || displayName.isEmpty() || displayName.length() > 20
            || !DISPLAY_NAME_PATTERN.matcher(displayName).matches()) {
            throw new InvalidDisplayNameException(displayName);
        }
    }
}
