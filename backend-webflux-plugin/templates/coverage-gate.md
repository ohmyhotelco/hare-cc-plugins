# Coverage Gate — JaCoco (report-only)

See `docs/decisions.md` Decision 6 for why JaCoco was chosen and why this gate is
report-only (no failing threshold) in this sub-task.

## Gradle Configuration (Kotlin DSL)

Add to the generated project's `build.gradle.kts`:

```kotlin
plugins {
    id("jacoco")
}

jacoco {
    toolVersion = "0.8.12"
}

tasks.jacocoTestReport {
    dependsOn(tasks.test)
    reports {
        xml.required.set(true)
        html.required.set(true)
    }
}

tasks.test {
    finalizedBy(tasks.jacocoTestReport)
}

// Intentionally NOT wired: jacocoTestCoverageVerification with a minimum rule.
// This plugin ships a report-only gate. Do not add a `violationRules` block /
// minimum-percentage failure here until a real coverage baseline is established
// for the target project — see docs/decisions.md Decision 6.
```

## Gradle Configuration (Groovy DSL)

```groovy
plugins {
    id 'jacoco'
}

jacoco {
    toolVersion = "0.8.12"
}

jacocoTestReport {
    dependsOn test
    reports {
        xml.required = true
        html.required = true
    }
}

test {
    finalizedBy jacocoTestReport
}
```

## Reading the Result

`be-verify` runs `{buildCommand} jacocoTestReport` and parses the line-coverage
percentage from `build/reports/jacoco/test/jacocoTestReport.xml`:

```xml
<report>
  ...
  <counter type="LINE" missed="{missed}" covered="{covered}"/>
</report>
```

`linePercent = covered / (covered + missed) * 100`, rounded to 1 decimal place.

## Gate Row Semantics (report-only)

- **PASS**: the report generated successfully and a line-coverage percentage was
  extracted (regardless of the number)
- **FAIL**: `jacocoTestReport` did not run successfully, or the XML report is
  missing/unparseable
- The percentage itself is always displayed but never gates PASS/FAIL in this
  sub-task — see `skills/be-verify/SKILL.md`
