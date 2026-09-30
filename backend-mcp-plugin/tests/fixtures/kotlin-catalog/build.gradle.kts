plugins {
    java
    alias(libs.plugins.spring.boot)
}
kotlin { jvmToolchain(17) }
dependencies {
    implementation(platform(libs.spring.ai.bom))
    implementation(libs.spring.ai.starter.mcp.server.webflux)
    implementation(libs.bundles.security)
}
