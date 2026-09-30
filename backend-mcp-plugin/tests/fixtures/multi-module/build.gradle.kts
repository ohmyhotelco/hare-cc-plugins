plugins { id("org.springframework.boot") version "3.4.1" apply false }
subprojects { java { toolchain { languageVersion = JavaLanguageVersion.of(21) } } }
