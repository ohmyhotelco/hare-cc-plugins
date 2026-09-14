# Checkstyle Configuration Reference

Zero-tolerance checkstyle configuration for Spring Boot projects.

## Gradle Configuration

```kotlin
plugins {
    checkstyle
}

checkstyle {
    toolVersion = "10.20.2"   // what examples/employee-service pins and passes its gate with
    maxErrors = 0
    maxWarnings = 0
    configFile = file("config/checkstyle/checkstyle.xml")
}
```

## `config/checkstyle/checkstyle.xml`

This is the file `be-init`/`be-crud` scaffold and `be-verify` runs — the same one the sample project
ships. What it enforces is exactly the module list below; `code-reviewer` Dimension 3 judges
"checkstyle rules" against **this**, not against conventions the file does not carry.

```xml
<?xml version="1.0"?>
<!DOCTYPE module PUBLIC
    "-//Checkstyle//DTD Checkstyle Configuration 1.3//EN"
    "https://checkstyle.org/dtds/configuration_1_3.dtd">
<module name="Checker">
    <property name="charset" value="UTF-8"/>
    <property name="severity" value="error"/>

    <module name="NewlineAtEndOfFile"/>
    <module name="FileTabCharacter"/>
    <module name="LineLength">
        <property name="max" value="120"/>
    </module>

    <module name="TreeWalker">
        <module name="UnusedImports"/>
        <module name="AvoidStarImport"/>
        <module name="RedundantImport"/>
        <module name="WhitespaceAround">
            <property name="tokens" value="ASSIGN, EQUAL, NOT_EQUAL"/>
        </module>
        <module name="ModifierOrder"/>
    </module>
</module>
```

## Enforced Rules (one per module above)

| Module | Rule |
|--------|------|
| `LineLength` | Maximum **120** characters per line, code and comments alike |
| `UnusedImports` / `RedundantImport` / `AvoidStarImport` | Every import used, none duplicated, no `*` imports |
| `WhitespaceAround` | Spaces around `=`, `==`, `!=` |
| `ModifierOrder` | JLS order: `public`, `protected`, `private`, `abstract`, `static`, `final`, `transient`, `volatile`, `synchronized`, `native`, `strictfp` |
| `FileTabCharacter` | No tabs (4-space indentation) |
| `NewlineAtEndOfFile` | File ends with a newline |

## Conventions (followed by the templates, **not** enforced by the file above)

| Element | Pattern | Example |
|---------|---------|---------|
| Package | `lowercase.separated.by.dots` | `com.example.hr` |
| Type | `PascalCase` | `EmployeeHandler` |
| Method | `camelCase` (`_` allowed in tests) | `findByExternalId`, `valid_request_returns_201_Created` |
| Variable | `camelCase` | `employeeRepository` |
| Constant | `UPPER_SNAKE_CASE` | `MAX_PAGE_SIZE` |

Imports grouped `java.*` → third-party → static, alphabetical within a group; braces on the same
line. A reviewer may mention these as suggestions, never as checkstyle violations.

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
| `LineLength` | Break line at 120 chars, align continuation |
| `UnusedImports` / `RedundantImport` | Remove the import |
| `AvoidStarImport` | Replace `import java.util.*` with specific imports |
| `ModifierOrder` | Reorder modifiers to the JLS sequence |
| `WhitespaceAround` | Add spaces around `=`, `==`, `!=` |
| `FileTabCharacter` | Replace tabs with 4 spaces |
| `NewlineAtEndOfFile` | Add a trailing newline |
