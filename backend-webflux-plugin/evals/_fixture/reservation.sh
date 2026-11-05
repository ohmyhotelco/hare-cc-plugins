#!/bin/bash
# One Spring WebFlux project shared by the routing cases, so a skill is chosen by the request, not by what the project holds.
set -e
P=src/main/java/com/example/reservation
T=src/test/java/com/example/reservation
mkdir -p .claude "$P/client" "$T" work/features/.progress docs/specs/reservation/.progress docs/specs/reservation/en

cat > .claude/backend-webflux-plugin.json <<'EOF'
{ "javaVersion": "21", "springBootVersion": "4.0.2", "buildTool": "gradle-kotlin", "gradleCommand": "./gradlew", "buildCommand": "./gradlew build", "testCommand": "./gradlew test", "basePackage": "com.example", "sourceDir": "src/main/java", "testDir": "src/test/java", "architecture": "cqrs", "dataProfile": "both", "webLayer": "functional", "database": "mysql", "migration": "manual-sql", "checkstyle": true, "coverage": true, "lombokEnabled": false, "workDocDir": "work/features", "workingLanguage": "en" }
EOF
cat > build.gradle.kts <<'EOF'
plugins { java; id("org.springframework.boot") version "4.0.2" }
EOF
cat > gradlew <<'EOF'
#!/bin/sh
echo "> Task :compileJava FAILED"
echo "src/main/java/com/example/reservation/ReservationRouter.java:14: error: cannot find symbol"
echo "BUILD FAILED"
exit 1
EOF
chmod +x gradlew

cat > "$P/Reservation.java" <<'EOF'
package com.example.reservation;

import java.time.LocalDate;
import org.springframework.data.annotation.Id;

public record Reservation(@Id Long id, String guestName, String guestEmail, LocalDate checkIn) {}
EOF
cat > "$P/ReservationRepository.java" <<'EOF'
package com.example.reservation;

import org.springframework.data.r2dbc.repository.Query;
import org.springframework.data.r2dbc.repository.R2dbcRepository;
import reactor.core.publisher.Flux;

public interface ReservationRepository extends R2dbcRepository<Reservation, Long> {
    @Query("select * from reservation where guest_name like :name")
    Flux<Reservation> search(String name);
}
EOF
cat > "$P/client/PaymentGatewayClient.java" <<'EOF'
package com.example.reservation.client;

import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

public class PaymentGatewayClient {
    private final WebClient webClient = WebClient.create("https://pay.example.com");

    public Mono<String> charge(String reservationId, long amount) {
        return webClient.post().uri("/charges?reservation=" + reservationId + "&amount=" + amount)
            .retrieve().bodyToMono(String.class).retry(5);
    }
}
EOF
cat > "$P/CreateReservationHandler.java" <<'EOF'
package com.example.reservation;

import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

public class CreateReservationHandler {
    private final ReservationRepository repository;

    public CreateReservationHandler(ReservationRepository repository) {
        this.repository = repository;
    }

    public Mono<Reservation> handle(Reservation reservation) {
        if (reservation.guestName() == null || reservation.guestName().isBlank()) return Mono.error(new IllegalArgumentException("name"));
        if (reservation.guestEmail() == null || reservation.guestEmail().isBlank()) return Mono.error(new IllegalArgumentException("email"));
        return repository.save(reservation);
    }

    public Mono<Reservation> handleForGroup(Reservation reservation) {
        if (reservation.guestName() == null || reservation.guestName().isBlank()) return Mono.error(new IllegalArgumentException("name"));
        if (reservation.guestEmail() == null || reservation.guestEmail().isBlank()) return Mono.error(new IllegalArgumentException("email"));
        return repository.save(reservation);
    }

    public Flux<Reservation> search(String name) {
        return repository.search(name);
    }
}
EOF
cat > "$P/ReservationRouter.java" <<'EOF'
package com.example.reservation;

import org.springframework.context.annotation.Bean;
import org.springframework.web.reactive.function.server.RouterFunction;
import org.springframework.web.reactive.function.server.RouterFunctions;
import org.springframework.web.reactive.function.server.ServerResponse;

public class ReservationRouter {
    @Bean
    public RouterFunction<ServerResponse> routes(CreateReservationHandler handler) {
        return RouterFunctions.route()
            .POST("/createReservation", request -> request.bodyToMono(Reservation.class)
                .doOnNext(r -> System.out.println("creating reservation for " + r.guestEmail()))
                .flatMap(handler::handle)
                .flatMap(saved -> ServerResponse.ok().bodyValue(saved)))
            .GET("/getReservations", request -> ServerResponse.ok().body(handler.search(request.queryParam("name").orElse("")), Reservation.class))
            .build();
    }
}
EOF
cat > "$T/CreateReservationHandlerTests.java" <<'EOF'
package com.example.reservation;

import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.time.LocalDate;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import reactor.core.publisher.Mono;

class CreateReservationHandlerTests {
    @Test
    void test1() {
        ReservationRepository repository = Mockito.mock(ReservationRepository.class);
        Reservation reservation = new Reservation(null, "Kim", "kim@example.com", LocalDate.now());
        Mockito.when(repository.save(reservation)).thenReturn(Mono.just(reservation));
        assertNotNull(new CreateReservationHandler(repository).handle(reservation).block());
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
  { "id": 1, "severity": "critical", "dimension": "api", "file": "src/main/java/com/example/reservation/ReservationRouter.java", "line": 13, "message": "POST returns 200, and the path holds a verb" },
  { "id": 2, "severity": "warning", "dimension": "logging", "file": "src/main/java/com/example/reservation/ReservationRouter.java", "line": 14, "message": "System.out logs the guest's email" }
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
