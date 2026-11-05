#!/bin/bash
set -e
mkdir -p .claude src/main/java/com/example/reservation src/test/java/com/example/reservation work/features/reservation
cat > build.gradle.kts <<'EOF'
plugins { java; id("org.springframework.boot") version "3.4.0" }
EOF
cat > .claude/backend-webflux-plugin.json <<'EOF'
{ "javaVersion": "21", "buildTool": "gradle-kotlin", "gradleCommand": "./gradlew", "basePackage": "com.example", "sourceDir": "src/main/java", "testDir": "src/test/java", "workDocDir": "work/features", "workingLanguage": "en" }
EOF
cat > src/main/java/com/example/reservation/Reservation.java <<'EOF'
package com.example.reservation;

import java.time.LocalDate;

public record Reservation(String guestName, LocalDate checkIn) {}
EOF
cat > src/main/java/com/example/reservation/CreateReservationHandler.java <<'EOF'
package com.example.reservation;

public class CreateReservationHandler {
    public Reservation handle(Reservation reservation) {
        return reservation;
    }
}
EOF
cat > src/test/java/com/example/reservation/CreateReservationHandlerTests.java <<'EOF'
package com.example.reservation;

class CreateReservationHandlerTests {}
EOF
cat > work/features/reservation/work.md <<'EOF'
# Reservation

## Test scenarios
- [ ] creating a reservation with a guest name and a check-in date returns 201
- [ ] a check-in date in the past returns 400
EOF
git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 || true
