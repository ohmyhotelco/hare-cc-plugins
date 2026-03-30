---
name: be-init
description: Initialize Backend Spring Boot Plugin configuration for the current project.
argument-hint: ""
user-invocable: true
allowed-tools: Read, Write, Glob, Bash
---

# Initialize Backend Spring Boot Plugin

Set up the Backend Spring Boot Plugin configuration for this project.

## Instructions

### Step 1: Check Existing Configuration

1. Check if `.claude/backend-springboot-plugin.json` already exists in the current project directory
2. If it exists, read the current configuration and show it to the user:
   > "Backend Spring Boot Plugin is already configured:"
   > ```json
   > { current config contents }
   > ```
   > "Do you want to reconfigure? This will overwrite the existing settings."
3. If the user declines, stop here

### Step 2: Auto-Detect Project Settings

Scan the project to detect settings automatically:

1. **Build tool**: Look for `build.gradle.kts` (gradle-kotlin), `build.gradle` (gradle-groovy), or `pom.xml` (maven)
2. **Java version**: Parse `build.gradle.kts` for `java.toolchain.languageVersion` or `sourceCompatibility`
3. **Spring Boot version**: Parse `build.gradle.kts` plugins block for `org.springframework.boot` version
4. **Base package**: Find the first directory level under `src/main/java/` that contains `.java` files
5. **Database**: Check dependencies for `postgresql`, `mysql-connector`, `h2`, `mariadb`
6. **Migration**: Check dependencies for `flyway` or `liquibase`
7. **Checkstyle**: Check if `checkstyle` plugin is applied in build file
8. **Lombok**: Check if `lombok` is in dependencies
9. **Build command**: Default to `./gradlew build` for Gradle, `mvn package` for Maven
10. **Test command**: Default to `./gradlew test` for Gradle, `mvn test` for Maven

### Step 3: Confirm with User

Present detected values and ask the user to confirm or override:

> "Detected project settings:"
> ```
> Java Version:      {detected or "21"}
> Spring Boot:       {detected or "unknown"}
> Build Tool:        {detected}
> Base Package:      {detected or "com.example"}
> Database:          {detected or "postgresql"}
> Migration:         {detected or "flyway"}
> Checkstyle:        {detected or true}
> Lombok:            {detected or true}
> Architecture:      cqrs (default)
> Work Doc Dir:      work/features (default)
> Working Language:  en (default)
> ```
> "Would you like to change any of these values?"

If the user wants changes, ask for specific values. Accept the following for architecture: `cqrs` (default).

For working language, accept: `en` (English), `ko` (Korean), `vi` (Vietnamese).

### Step 4: Write Configuration

Write `.claude/backend-springboot-plugin.json`:

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
  "database": "{value}",
  "migration": "{value}",
  "checkstyle": {value},
  "lombokEnabled": {value},
  "workDocDir": "{value}",
  "workingLanguage": "{value}"
}
```

### Step 5: Set Up Work Document Directory

1. If `{workDocDir}` does not exist, create it
2. Create `{workDocDir}/done/` directory if it does not exist (for completed work documents)

### Step 6: Add Gradle Permission

Check `.claude/settings.json` for Bash permissions. If `./gradlew *` is not in the allow list, inform the user:

> "To enable Gradle commands, add this to your `.claude/settings.json` permissions.allow:"
> ```
> "Bash(./gradlew *)"
> ```

### Step 7: Confirmation

Display final configuration summary:

> "Backend Spring Boot Plugin initialized successfully."
> "Configuration saved to `.claude/backend-springboot-plugin.json`."
>
> "Available skills:"
> - `/backend-springboot-plugin:be-code` — TDD feature implementation
> - `/backend-springboot-plugin:be-crud` — CQRS CRUD scaffold
> - `/backend-springboot-plugin:be-build` — Build + auto-fix
> - `/backend-springboot-plugin:be-commit` — Smart commit
> - `/backend-springboot-plugin:be-recall` — Rules reference
> - `/backend-springboot-plugin:be-jpa` — JPA audit
> - `/backend-springboot-plugin:be-api-review` — API contract audit
> - `/backend-springboot-plugin:be-clean-code` — Clean code audit
> - `/backend-springboot-plugin:be-logging` — Logging audit
> - `/backend-springboot-plugin:be-test-review` — Test quality audit
> - `/backend-springboot-plugin:be-progress` — Progress dashboard
