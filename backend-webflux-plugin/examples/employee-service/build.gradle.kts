plugins {
    java
    checkstyle
    jacoco
    id("org.springframework.boot") version "4.0.2"
    id("io.spring.dependency-management") version "1.1.7"
}

group = "com.example"
version = "0.1.0"

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("org.springframework.boot:spring-boot-starter-webflux")
    implementation("org.springframework.boot:spring-boot-starter-data-r2dbc")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    implementation("com.github.f4b6a3:uuid-creator:6.0.0")

    // R2DBC MySQL driver, pinned per docs/decisions.md Decision 5 (io.asyncer, not the
    // archived dev.miku driver). Not used at runtime by this sample (H2 in-memory is
    // used so the sample runs without an external MySQL instance) but included so the
    // generated build reflects the real production dependency this plugin always pins.
    runtimeOnly("io.asyncer:r2dbc-mysql:1.1.3")

    // Sample-only runtime database: H2 R2DBC in-memory, so `./gradlew test` and
    // `./gradlew bootRun` work with zero external services. See src/main/resources/schema.sql.
    runtimeOnly("io.r2dbc:r2dbc-h2")
    runtimeOnly("com.h2database:h2")

    compileOnly("org.projectlombok:lombok")
    annotationProcessor("org.projectlombok:lombok")

    testCompileOnly("org.projectlombok:lombok")
    testAnnotationProcessor("org.projectlombok:lombok")

    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation("io.projectreactor:reactor-test")
    testImplementation("org.springframework.boot:spring-boot-starter-data-r2dbc-test")
    testImplementation("org.springframework.boot:spring-boot-starter-webflux-test")
    testImplementation("org.springframework.boot:spring-boot-webtestclient")
}

checkstyle {
    toolVersion = "10.20.2"
    maxErrors = 0
    maxWarnings = 0
    isIgnoreFailures = false
    configFile = file("config/checkstyle/checkstyle.xml")
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
    useJUnitPlatform()
    finalizedBy(tasks.jacocoTestReport)
}

// Intentionally NOT wired: jacocoTestCoverageVerification with a minimum rule.
// See docs/decisions.md Decision 6 — report-only coverage gate in this sub-task.
