#!/bin/bash
# One Spring Boot project shared by the routing cases, so a skill is chosen by the request, not by what the project holds.
set -e
P=src/main/java/com/example/reservation
T=src/test/java/com/example/reservation
mkdir -p .claude "$P" "$T" work/features/.progress docs/specs/reservation/.progress docs/specs/reservation/en

cat > .claude/backend-springboot-plugin.json <<'EOF'
{ "javaVersion": "21", "springBootVersion": "4.0.2", "buildTool": "gradle-kotlin", "buildCommand": "./gradlew build", "testCommand": "./gradlew test", "basePackage": "com.example", "sourceDir": "src/main/java", "testDir": "src/test/java", "architecture": "cqrs", "database": "postgresql", "migration": "flyway", "checkstyle": true, "lombokEnabled": false, "workDocDir": "work/features", "workingLanguage": "en" }
EOF
cat > build.gradle.kts <<'EOF'
plugins { java; id("org.springframework.boot") version "4.0.2" }
EOF
cat > gradlew <<'EOF'
#!/bin/sh
echo "> Task :compileJava FAILED"
echo "src/main/java/com/example/reservation/ReservationController.java:22: error: cannot find symbol"
echo "BUILD FAILED"
exit 1
EOF
chmod +x gradlew

cat > "$P/Charge.java" <<'EOF'
package com.example.reservation;

import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;

@Entity
public class Charge {
    @Id @GeneratedValue Long id;
    long amount;
}
EOF
cat > "$P/Reservation.java" <<'EOF'
package com.example.reservation;

import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import java.time.LocalDate;
import java.util.List;

@Entity
public class Reservation {
    @Id @GeneratedValue Long id;
    String guestName;
    String guestEmail;
    LocalDate checkIn;
    @OneToMany(fetch = FetchType.EAGER) List<Charge> charges;
}
EOF
cat > "$P/ReservationRepository.java" <<'EOF'
package com.example.reservation;

import org.springframework.data.jpa.repository.JpaRepository;

public interface ReservationRepository extends JpaRepository<Reservation, Long> {}
EOF
cat > "$P/CreateReservationHandler.java" <<'EOF'
package com.example.reservation;

public class CreateReservationHandler {
    private final ReservationRepository repository;

    public CreateReservationHandler(ReservationRepository repository) {
        this.repository = repository;
    }

    public Reservation handle(Reservation reservation) {
        if (reservation.guestName == null || reservation.guestName.isBlank()) throw new IllegalArgumentException("name");
        if (reservation.guestEmail == null || reservation.guestEmail.isBlank()) throw new IllegalArgumentException("email");
        return repository.save(reservation);
    }

    public Reservation handleForGroup(Reservation reservation) {
        if (reservation.guestName == null || reservation.guestName.isBlank()) throw new IllegalArgumentException("name");
        if (reservation.guestEmail == null || reservation.guestEmail.isBlank()) throw new IllegalArgumentException("email");
        return repository.save(reservation);
    }
}
EOF
cat > "$P/ReservationController.java" <<'EOF'
package com.example.reservation;

import jakarta.persistence.EntityManager;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ReservationController {
    private final CreateReservationHandler handler;
    private final EntityManager entityManager;

    public ReservationController(CreateReservationHandler handler, EntityManager entityManager) {
        this.handler = handler;
        this.entityManager = entityManager;
    }

    @PostMapping("/createReservation")
    public Reservation create(@RequestBody Reservation reservation) {
        System.out.println("creating reservation for " + reservation.guestEmail);
        return handler.handle(reservation);
    }

    @GetMapping("/getReservations")
    public List<?> search(@RequestParam String name) {
        return entityManager.createQuery("select r from Reservation r where r.guestName = '" + name + "'").getResultList();
    }
}
EOF
cat > "$T/CreateReservationHandlerTests.java" <<'EOF'
package com.example.reservation;

import static org.junit.jupiter.api.Assertions.assertNotNull;

import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

class CreateReservationHandlerTests {
    @Test
    void test1() {
        ReservationRepository repository = Mockito.mock(ReservationRepository.class);
        Reservation reservation = new Reservation();
        reservation.guestName = "Kim";
        reservation.guestEmail = "kim@example.com";
        Mockito.when(repository.save(reservation)).thenReturn(reservation);
        assertNotNull(new CreateReservationHandler(repository).handle(reservation));
    }
}
EOF

cat > work/features/reservation.md <<'EOF'
# Reservation

## Test scenarios
- [x] creating a reservation with a guest name and a check-in date returns 201
- [ ] a check-in date in the past returns 400
- [ ] searching by guest name returns matching reservations
EOF
cat > work/features/.progress/reservation.json <<'EOF'
{ "feature": "reservation", "workDocument": "work/features/reservation.md", "createdAt": "2026-10-01T10:00:00Z", "updatedAt": "2026-10-02T15:30:00Z", "pipeline": { "status": "review-failed", "scenarios": { "total": 3, "completed": 1 }, "review": { "status": "fail", "timestamp": "2026-10-02T15:30:00Z" } } }
EOF
cat > work/features/.progress/review-report-reservation.json <<'EOF'
{ "feature": "reservation", "timestamp": "2026-10-02T15:30:00Z", "status": "fail", "issues": [
  { "id": 1, "severity": "critical", "dimension": "security", "file": "src/main/java/com/example/reservation/ReservationController.java", "line": 29, "message": "JPQL built by string concatenation" },
  { "id": 2, "severity": "warning", "dimension": "api", "file": "src/main/java/com/example/reservation/ReservationController.java", "line": 22, "message": "POST returns 200, and the path holds a verb" }
] }
EOF
cat > docs/specs/reservation/.progress/reservation.json <<'EOF'
{ "feature": "reservation", "workingLanguage": "en", "status": "finalized", "updatedAt": "2026-09-20T09:00:00Z" }
EOF
cat > docs/specs/reservation/en/reservation-spec.md <<'EOF'
# Reservation: functional specification

## Functional requirements
- FR-001: A guest creates a reservation with a name, an email and a check-in date.
- FR-002: A staff member searches reservations by guest name.

## Business rules
- BR-001: The check-in date cannot be in the past.
EOF

git init -q >/dev/null 2>&1 || true
git add -A >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1 || true
# A staged change, for the request to commit it.
sed -i.bak 's/"name"/"guest name is required"/' "$P/CreateReservationHandler.java" && rm -f "$P/CreateReservationHandler.java.bak"
git add -A >/dev/null 2>&1 || true
