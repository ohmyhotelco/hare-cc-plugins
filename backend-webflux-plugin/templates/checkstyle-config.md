# Checkstyle Configuration Reference

Zero-tolerance checkstyle configuration for Spring Boot projects.

## Gradle Configuration

```kotlin
plugins {
    checkstyle
}

checkstyle {
    toolVersion = "13.3.0"  // or latest
    maxErrors = 0
    maxWarnings = 0
    configFile = file("config/checkstyle/checkstyle.xml")
}
```

## Key Rules

### Line Length
- Maximum 100 characters per line
- Applies to both code and comments

### Imports
- Standard Java packages first (`java.*`, `javax.*`)
- Third-party packages second
- Static imports last
- Alphabetically sorted within each group
- No star imports (`*`) -- always import specific classes

### Naming Conventions

| Element | Pattern | Example |
|---------|---------|---------|
| Package | `lowercase.separated.by.dots` | `com.example.hr` |
| Type | `PascalCase` | `EmployeeController` |
| Method | `camelCase` (`_` allowed in tests) | `findById`, `valid_request_returns_200` |
| Variable | `camelCase` | `employeeRepository` |
| Constant | `UPPER_SNAKE_CASE` | `MAX_PAGE_SIZE` |

### Formatting
- 4-space indentation (no tabs)
- No trailing whitespace
- Newline at end of file
- Braces on same line for classes, methods, and control structures

### Modifiers
- Correct order: `public`, `protected`, `private`, `abstract`, `static`, `final`, `transient`, `volatile`, `synchronized`, `native`, `strictfp`

### Suppressions

Create `config/checkstyle/checkstyle-suppressions.xml` for legitimate exceptions:

```xml
<?xml version="1.0"?>
<!DOCTYPE suppressions PUBLIC
    "-//Checkstyle//DTD SuppressionFilter Configuration 1.2//EN"
    "https://checkstyle.org/dtds/suppressions_1_2.dtd">
<suppressions>
    <suppress checks=".*" files="(^build/|^bin/|^target/|generated-sources)" />
</suppressions>
```

## Common Violations and Fixes

| Violation | Fix |
|-----------|-----|
| `LineLength` | Break line at 100 chars, align continuation |
| `UnusedImports` | Remove unused import statement |
| `AvoidStarImport` | Replace `import java.util.*` with specific imports |
| `MissingJavadocType` | Add Javadoc to public class/interface |
| `ModifierOrder` | Reorder modifiers to standard sequence |
| `WhitespaceAround` | Add space around operators and keywords |
| `FinalNewline` | Add empty line at end of file |
