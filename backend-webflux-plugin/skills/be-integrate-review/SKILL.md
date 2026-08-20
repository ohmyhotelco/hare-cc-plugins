---
name: be-integrate-review
description: "Audit outbound vendor/HTTP integration code in a {domain}/client/ package for timeout, retry, circuit-breaker, and reconciliation hazards — not for DB/query issues (use be-data) or general PII/log-masking depth (use be-security)."
argument-hint: "[file-or-directory-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep
---

# Vendor Integration Pattern Audit

Audit code that calls an external vendor/third-party HTTP API (a `{domain}/client/`
package, see `templates/vendor-integration.md`) for the failure modes that only show
up under load or during a vendor outage, not in a normal test run: ambiguous
timeouts, blind retries on non-idempotent calls, a shared circuit breaker across
vendors, and state left out of sync between this service and the vendor.

Skip this audit entirely for a domain with no `{domain}/client/` package — a CRUD-only
domain calling only its own database has nothing for this skill to check; use
`be-data` for that.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, tell the user to run `/backend-webflux-plugin:be-init` first and stop

### Step 1: Determine Scope

- Read `templates/vendor-integration.md` in full before scanning any code — its code
  blocks (timeout, retry, ambiguous-timeout reconciliation, cancel, circuit breaker,
  fan-out, adapter-boundary normalization) are the canonical fix pattern behind every
  `Fix:` suggestion in Step 3. Scanning without reading it first produces vague or
  invented fixes instead of the plugin's actual convention.
- If argument provided: audit the specified file or directory
- If no argument: audit all files under any `{sourceDir}/{basePackage}/*/client/`
  directory, plus `commandmodel/`/`querymodel/` files that reference a class ending
  in `Client`
- If no `client/` directory exists anywhere in scope, report "No vendor client code
  found — nothing to audit" and stop; do not scan unrelated files

### Step 2: Scan for Issues

Rules 1, 2, 3, 6, 9, and 10 require judging intent, not just matching a pattern —
e.g. rule 1 requires reasoning about whether the vendor's contract supports an
idempotency key at all, not just that this call site omits one; rule 6 requires
reading what the retry filter actually excludes, not just that a filter exists. When
the code leaves genuine doubt, report the finding with the confidence marker
described in Step 3 rather than asserting it flatly. Rules 4, 5, 7, 8, and 11 are
mechanical — the pattern is either present in the code or it isn't — and never need
the marker.

#### Critical Issues

1. **Blind retry on a non-idempotent call**
   - A `{Vendor}Client.book(...)` (or any create/write vendor call) wrapped in
     `.retry(...)` / `.retryWhen(...)` with no idempotency key passed to the vendor
     request — this risks creating a duplicate vendor-side booking/charge on every
     retried attempt

2. **Ambiguous timeout treated as failure, no reconciliation**
   - A `book()` (or other write) call's `onErrorResume`/`onErrorReturn` for
     `TimeoutException`/`ConnectException` resolves directly to a failure state
     (exception surfaced, or local record marked failed) without first calling
     `{Vendor}Client.retrieve(...)` to confirm what the vendor actually did — see
     `templates/vendor-integration.md` "Ambiguous Timeout"

3. **Cancel marks local state before vendor confirms**
   - A cancel CommandExecutor writes a "cancelled" state to the local
     repository/mapper before, or without checking, `vendorClient.cancel(...)`
     returning success — and especially if the cancelled write also happens on the
     `onErrorResume` path of a failed vendor cancel call

4. **No independent timeout on the reactive chain**
   - A `{Vendor}Client` method chain (`webClient...retrieve().bodyToMono(...)`) with
     no `.timeout(Duration)` call — relying solely on the underlying `HttpClient`'s
     configured timeout (or its default) leaves no guard visible to
     `StepVerifier`/tests and no protection if that configuration is ever missing
     or misapplied

#### Warning Issues

5. **Retry without backoff, jitter, or a cap**
   - `.retry(n)` (fixed count, no backoff) or a `Retry.backoff(...)` missing
     `.jitter(...)` — a uniform retry interval synchronizes every caller's retry
     against an already-struggling vendor
   - No `maxAttempts`/cap at all (an effectively unbounded retry)

6. **Retry filter does not exclude 4xx**
   - A `Retry`/`retryWhen` filter that does not distinguish 4xx (client error —
     will fail identically on retry) from 5xx/timeout/connection-reset (potentially
     transient) — retrying a 4xx wastes attempts and vendor quota for no benefit

7. **Circuit breaker shared across vendors**
   - A single `CircuitBreaker` instance/config applied to calls for more than one
     vendor (check the name passed to `CircuitBreakerRegistry.circuitBreaker(...)`)
     — one vendor's failures should never open the breaker for a different vendor

8. **Unbounded fan-out across vendors**
   - `Flux.fromIterable(vendors).flatMap(...)` (or equivalent) with no explicit
     concurrency argument — competes for the same connection pool / `boundedElastic`
     threads that other request paths draw from; see `skills/be-data/SKILL.md` rule 2
     for the DB-side equivalent of this same hazard

9. **One vendor's failure kills the whole fan-out result**
   - A multi-vendor search/aggregation `flatMap` with no per-vendor
     `onErrorResume`/`onErrorContinue` — an unhandled error from one vendor call
     propagates and fails the entire combined result instead of excluding just that
     vendor's contribution

10. **Booking off a stale cache read**
    - A `book()` call that reads price/availability directly from the vendor cache
      (10-minute TTL) and proceeds to book without either revalidating immediately
      before booking or explicitly handling a vendor-side price-mismatch response
      as its own case

11. **Unnormalized vendor data crossing the adapter boundary**
    - A vendor's raw currency code, vendor-local timestamp, or vendor-specific
      room/fare code used directly in `commandmodel`/`querymodel`/`view` code
      instead of being normalized inside `{Vendor}Client` at parse time

#### Suggestions

12. **Raw vendor payload logged**
    - A log statement printing an entire vendor request/response object/JSON
      verbatim — flag as a suggestion to mask or omit fields that may carry PII or
      payment data; this skill does not judge which fields are sensitive — treat
      the finding as "needs a security-focused look," not as resolved either way

### Examples

Two worked cases, from raw code to the Step 3 report line, calibrating how much
evidence justifies a finding versus how much doesn't.

**Easy case — Rule 4 (no independent timeout on the reactive chain)**

```java
// AcmeClient.java
public Mono<BookingResult> book(BookCommand command) {
    return webClient.post().uri(bookingUri)
        .bodyValue(command)
        .retrieve()
        .bodyToMono(BookingResult.class);
}
```

No `.timeout(Duration)` anywhere in the chain — this is mechanical, flag it directly,
no confidence marker needed:

```
Critical (1):
  AcmeClient.java:12 — book() has no independent .timeout() on the reactive chain
  Fix: add .timeout(Duration.ofSeconds(8)) after .bodyToMono(...), per
       templates/vendor-integration.md "Timeout — two independent guards, never one"
```

**Tricky case — Rule 2 (ambiguous timeout, incomplete reconciliation predicate)**

```java
// CreateBookingCommandExecutor.java
public Mono<Void> execute(CreateBooking command) {
    return vendorClient.book(command)
        .flatMap(this::persistConfirmed)
        .onErrorResume(this::isAmbiguous, e -> vendorClient.retrieve(command.reference())
            .flatMap(this::resolveFromState));
}

private boolean isAmbiguous(Throwable e) {
    return e instanceof TimeoutException;
}
```

At a glance this looks compliant — it does call `retrieve()` on an ambiguous
outcome, matching the reconciliation pattern in `templates/vendor-integration.md`.
The bug is narrower: this executor's `isAmbiguous` matches only `TimeoutException`,
while the template's own `isAmbiguous` example matches both `TimeoutException` and
`ConnectException`. A connection reset during `book()` falls straight through to a
hard failure instead of reconciling — the exact state mismatch rule 2 exists to
prevent, just for one exception type instead of all of them. Report it, but hedge
because it turns on whether a connection reset is actually reachable on this call
path, which the source alone doesn't prove:

```
Critical (1):
  CreateBookingCommandExecutor.java:8 — isAmbiguous() omits ConnectException, so a
  connection reset resolves as a hard failure instead of reconciling via retrieve()
  Fix: match ConnectException alongside TimeoutException in isAmbiguous(), per
       templates/vendor-integration.md "Ambiguous Timeout" (needs manual
       confirmation: verify book() can actually raise ConnectException on this
       WebClient's error-handling chain before treating this as certain)
```

### Step 3: Report

Display findings in the working language. For a finding under rule 1, 2, 3, 6, 9, or
10 (the judgment-based rules — see Step 2) that you are not fully certain about,
append a confidence marker to the `Fix:` line: `(needs manual confirmation:
<reason>)`, the same hedge already required for rule 12's raw-payload-logging
findings. Mechanical findings (rules 4, 5, 7, 8, 11) never carry the marker — the
pattern is either in the code or it isn't. Never silently drop a finding because
you're unsure; hedge it and report it.

```
Vendor Integration Audit
=========================

Files scanned: {count} (clients: {n}, executors calling a client: {n})

Critical ({count}):
  {file}:{line} — {description}
  Fix: {suggestion} [(needs manual confirmation: {reason}) if rule 1/2/3/6/9/10 and uncertain]

Warnings ({count}):
  {file}:{line} — {description}
  Fix: {suggestion} [(needs manual confirmation: {reason}) if rule 1/2/3/6/9/10 and uncertain]

Suggestions ({count}):
  {file}:{line} — {description}
  Fix: {suggestion} (needs a security-focused look, not resolved either way — rule 12)
```

If no `client/` package exists in scope:
> "No vendor client code found — nothing to audit."

If `client/` code exists and no issues found:
> "Vendor integration audit passed. No issues detected."
