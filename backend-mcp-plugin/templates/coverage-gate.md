# Coverage Gate — JaCoCo (optional, report-only)

Coverage is optional in this plugin: `mcp-verify` runs its Coverage row only when
`config.coverage == true`, which `detect-project.sh` reports only when the project already applies the
`jacoco` plugin. The percentage is **report-only** — it never fails the gate; the row fails only
when the report cannot be produced. A threshold is a team decision taken once a real baseline
exists, made explicitly in the project's own build file.

## Gradle Configuration (Groovy DSL)

```groovy
plugins {
    id 'jacoco'
}

jacoco {
    toolVersion = "0.8.14"
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

## Gradle Configuration (Kotlin DSL)

```kotlin
plugins {
    id("jacoco")
}

jacoco {
    toolVersion = "0.8.14"
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
```

Use a JaCoCo version that supports the project's Java toolchain: Java 25 needs ≥ 0.8.14 (0.8.13
support is experimental). With `dependencyLocking`, regenerate the lockfile after adding the plugin.

## Reading the Result

`mcp-verify` runs `{gradleCommand} jacocoTestReport` and parses the line-coverage percentage from
`build/reports/jacoco/test/jacocoTestReport.xml` — the **report-level** counter, XPath
`/report/counter[@type='LINE']` (package, class and method elements carry their own LINE counters;
never take the first match in the file):

```xml
<report>
  ...
  <counter type="LINE" missed="{missed}" covered="{covered}"/>
</report>
```

`linePercent = covered / (covered + missed) * 100`, rounded to 1 decimal place.

## Gate Row Semantics

- **PASS**: the report generated and a percentage was extracted (whatever the number)
- **FAIL**: `jacocoTestReport` failed, or the XML report is missing/unparseable
- **SKIP**: `config.coverage == false`
