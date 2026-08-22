---
name: be-init
description: Initialize Backend WebFlux Plugin configuration for the current project.
argument-hint: ""
user-invocable: true
allowed-tools: Read, Write, Glob, Bash
---

# Initialize Backend WebFlux Plugin

Set up the Backend WebFlux Plugin configuration for this project.

## Instructions

### Step 1: Check Existing Configuration

1. Check if `.claude/backend-webflux-plugin.json` already exists in the current project directory
2. If it exists, read the current configuration and show it to the user:
   > "Backend WebFlux Plugin is already configured:"
   > ```json
   > { current config contents }
   > ```
   > "Do you want to reconfigure? This will overwrite the existing settings."
3. If the user declines, stop here

### Step 2: Auto-Detect Project Settings

Scan the project to detect settings automatically:

1. **Build tool**: Look for `build.gradle.kts` (gradle-kotlin), `build.gradle` (gradle-groovy), or `pom.xml` (maven)
2. **Java version**: Parse whichever build file was detected in item 1:
   - `build.gradle.kts` (gradle-kotlin): `java.toolchain.languageVersion` or `sourceCompatibility`
   - `build.gradle` (gradle-groovy): same keys, Groovy syntax (`sourceCompatibility = '21'` or `languageVersion = JavaLanguageVersion.of(21)`)
   - `pom.xml` (maven): `<properties><java.version>` or `<maven.compiler.release>`
   - If the field can't be parsed from the detected build file, leave it undetected — do not guess a version from an unrelated file.
3. **Spring Boot version**: Parse whichever build file was detected in item 1:
   - `build.gradle.kts` / `build.gradle`: the `org.springframework.boot` entry in the plugins block
   - `pom.xml`: the `<parent><artifactId>spring-boot-starter-parent</artifactId><version>` value, or the `spring-boot.version` property if the project doesn't use the starter parent
   - If the field can't be parsed from the detected build file, leave it undetected — do not guess a version from an unrelated file.
4. **Base package**: Find the first directory level under `src/main/java/` that contains `.java` files
5. **Data profile**: Check dependencies for `spring-boot-starter-data-r2dbc` (→ `r2dbc` present) and `mybatis-spring-boot-starter` (→ `mybatis` present). Both present → `"both"`. Only one present → that profile. Neither present → default `"both"` (plugin default, see `docs/decisions.md` Decision 1)
6. **Web layer**: Check for `RouterFunction` bean definitions vs `@RestController` usage in existing source.
   - Project is empty (no source found yet) → default `"functional"`, no warning needed.
   - One style clearly dominates → that style wins, no warning needed.
   - Both styles are present in meaningful numbers (mixed evenly) → do not silently default. Flag it in Step 3 as a warning: the existing source shows both `RouterFunction` and `@RestController` usage, and per this plugin's architecture rule a domain must never mix both styles (see `CLAUDE.md` § Web Layer) — ask the user which style to standardize on for new code rather than picking `"functional"` for them.
7. **Database**: Check dependencies for `mysql-connector-j` / `io.asyncer:r2dbc-mysql` (mysql, default), the R2DBC/JDBC driver for another vendor, `h2`, `mariadb`
8. **Migration**: Check for a `src/main/resources/migration/` directory (manual-sql, default) or a migration-runner dependency (only if the project has explicitly opted into one)
9. **Checkstyle**: Check if `checkstyle` plugin is applied in build file
10. **Coverage**: Check if `jacoco` plugin is applied (default: enabled regardless, since this plugin's gate always reports it — see `templates/coverage-gate.md`)
11. **Lombok**: Check if `lombok` is in dependencies
12. **Build command**: Default to `./gradlew build` for Gradle, `mvn package` for Maven
13. **Test command**: Default to `./gradlew test` for Gradle, `mvn test` for Maven

### Step 3: Confirm with User

Present detected values and ask the user to confirm or override:

> "Detected project settings:"
> ```
> Java Version:      {detected or "21"}
> Spring Boot:       {detected or "unknown"}
> Build Tool:        {detected}
> Base Package:      {detected or "com.example"}
> Data Profile:      {detected or "both"}   (r2dbc | mybatis | both — see docs/decisions.md)
> Web Layer:         {detected or "functional"}   (functional | annotated)
> Database:          {detected or "mysql"}
> Migration:         {detected or "manual-sql"}
> Checkstyle:        {detected or true}
> Coverage:          {detected or true}   (report-only JaCoco gate — see docs/decisions.md Decision 6)
> Lombok:            {detected or true}
> Architecture:      cqrs (default)
> Work Doc Dir:      work/features (default)
> Working Language:  en (default)
> ```
> "Would you like to change any of these values?"

If the user wants changes, ask for specific values. Accept the following for architecture: `cqrs` (default).

For working language, accept: `en` (English), `ko` (Korean), `vi` (Vietnamese).

#### Worked example — clean detection

A project with `build.gradle.kts`, `spring-boot-starter-data-r2dbc` only, no
`@RestController` usage, and `io.asyncer:r2dbc-mysql` in dependencies produces:

> "Detected project settings:"
> ```
> Java Version:      21
> Spring Boot:       4.0.2
> Build Tool:        gradle-kotlin
> Base Package:      com.example.demo
> Data Profile:      r2dbc   (r2dbc | mybatis | both — see docs/decisions.md)
> Web Layer:         functional   (functional | annotated)
> Database:          mysql
> Migration:         manual-sql
> Checkstyle:        true
> Coverage:          true   (report-only JaCoco gate — see docs/decisions.md Decision 6)
> Lombok:            true
> Architecture:      cqrs (default)
> Work Doc Dir:      work/features (default)
> Working Language:  en (default)
> ```
> "Would you like to change any of these values?"

The user replies "looks good" → proceed to Step 4 with these values as-is.

#### Worked example — edge cases

**No build file present** (fresh/empty repository): every build-file-derived field
(`javaVersion`, `springBootVersion`, `buildTool`, `buildCommand`, `testCommand`) has
no detected value. Present the plugin defaults explicitly instead of leaving fields
blank, and say so:

> "No `build.gradle.kts`, `build.gradle`, or `pom.xml` found — this looks like a new
> project. Using plugin defaults below; correct any that don't match your plan:"
> ```
> Java Version:      21 (default, undetected)
> Spring Boot:       4.0.2 (default, undetected)
> Build Tool:        gradle-kotlin (default, undetected)
> ...
> ```

**Mixed web-layer usage** (per Step 2 item 6): do not silently pick `"functional"`.
Surface the conflict before presenting the confirmation table:

> "Note: existing source under `src/main/java/` shows both `RouterFunction` beans
> and `@RestController` classes in roughly equal numbers. This plugin's rule is
> that a domain must never mix both styles (see `CLAUDE.md` § Web Layer). Which
> style should new code use — `functional` or `annotated`?"

Only after the user answers does `webLayer` get a value in the confirmation table;
do not default it in this case.

### Step 4: Write Configuration

Write `.claude/backend-webflux-plugin.json`:

```json
{
  "javaVersion": "{value}",
  "springBootVersion": "{value}",
  "buildTool": "{value}",
  "buildCommand": "{value}",
  "testCommand": "{value}",
  "basePackage": "{value}",
  "sourceDir": "src/main/java",
  "testDir": "src/test/java",
  "architecture": "{value}",
  "dataProfile": "{value}",
  "webLayer": "{value}",
  "database": "{value}",
  "migration": "{value}",
  "checkstyle": {value},
  "coverage": {value},
  "lombokEnabled": {value},
  "workDocDir": "{value}",
  "workingLanguage": "{value}"
}
```

After the Write tool call returns, read `.claude/backend-webflux-plugin.json` back and
confirm its contents match what was just written. This is the evidence Step 7's
success message relies on — do not skip it. If the write failed or the read-back
doesn't match, stop and report the error instead of proceeding to Step 5.

### Step 5: Set Up Work Document Directory

1. If `{workDocDir}` does not exist, create it

### Step 6: Add Gradle Permission

Check `.claude/settings.json` for Bash permissions. If `./gradlew *` is not in the allow list, inform the user:

> "To enable Gradle commands, add this to your `.claude/settings.json` permissions.allow:"
> ```
> "Bash(./gradlew *)"
> ```

### Step 7: Confirmation

Only reached if the Step 4 read-back succeeded. Display final configuration summary:

> "Backend WebFlux Plugin initialized successfully."
> "Configuration saved to `.claude/backend-webflux-plugin.json`."
> "Data profile: {dataProfile}. Web layer: {webLayer}. See `docs/decisions.md` if you want the rationale behind these defaults before changing them."
>
> "Available skills:"
>
> Core pipeline:
> - `/backend-webflux-plugin:be-plan` — Spec → backend plan.json
> - `/backend-webflux-plugin:be-crud` — CQRS CRUD scaffold
> - `/backend-webflux-plugin:be-code` — TDD feature implementation
> - `/backend-webflux-plugin:be-verify` — Verification gate (build + checkstyle + tests + coverage)
> - `/backend-webflux-plugin:be-review` — Multi-dimension code review
> - `/backend-webflux-plugin:be-fix` — TDD-disciplined review fix
> - `/backend-webflux-plugin:be-commit` — Smart commit
>
> Utility:
> - `/backend-webflux-plugin:be-build` — Build + auto-fix
> - `/backend-webflux-plugin:be-debug` — Systematic debugging
> - `/backend-webflux-plugin:be-recall` — Rules reference
> - `/backend-webflux-plugin:be-progress` — Progress dashboard
>
> Standalone audits:
> - `/backend-webflux-plugin:be-data` — R2DBC / MyBatis data-layer audit
> - `/backend-webflux-plugin:be-api-review` — API contract audit
> - `/backend-webflux-plugin:be-clean-code` — Clean code audit
> - `/backend-webflux-plugin:be-logging` — Logging audit
> - `/backend-webflux-plugin:be-test-review` — Test quality audit
> - `/backend-webflux-plugin:be-security` — Security audit
> - `/backend-webflux-plugin:be-integrate-review` — Vendor/outbound-integration audit
