#!/bin/bash
# A Spring WebFlux project the plugin has not been set up for: no .claude config.
set -e
mkdir -p src/main/java/com/example src/test/java/com/example
cat > build.gradle.kts <<'EOF'
plugins { java; id("org.springframework.boot") version "4.0.2" }
EOF
cat > src/main/java/com/example/Application.java <<'EOF'
package com.example;

public class Application {}
EOF
git init -q >/dev/null 2>&1 || true
git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 || true
