# Upstream Client Conventions

Rules for the outbound client an MCP server's tools read from (the "upstream": an internal admin
API, a partner API, a search cluster). Used by the `implement` agent (writing) and the
`code-reviewer` agent (Upstream Integration dimension).

An MCP tool call is interactive: a model is waiting, and it will retry or re-plan on failure. The
client's job is to fail **fast, classified and bounded**, never to hang, never to amplify load on
an upstream that is already struggling, and never to repeat a call that is not safe to repeat.

## Placement

- One class per upstream in `client/` — `{Upstream}Client` / `{Upstream}RestClient` — the **only**
  class that holds the HTTP client. Tools call it; an ArchUnit rule forbids the tool layer from
  depending on `org.springframework.web.client..` / `org.springframework.web.reactive.function.client..`
- Request/response records in `client/dto/`; the adapter boundary normalizes upstream quirks
  (field renames, sentinel values, envelope unwrapping) so tools see one clean shape
- Configuration in `config/{Upstream}ClientConfig` + a `@ConfigurationProperties` class; base URL,
  timeouts and limits are properties per Spring profile, never literals in code

## HTTP client

- `webmvc` / `stdio` servers: `RestClient` built from `RestClient.Builder` with a request factory
  that sets **connect timeout and read timeout separately** (JDK `HttpClient` or Apache
  HttpClient 5 request factory)
- `webflux` servers: `WebClient` on Reactor Netty with connect timeout, response timeout, and an
  independent `.timeout(Duration)` on the reactive chain
- Model-supplied values reach a request only as encoded URI variables or typed body fields
  (`.uri("/bookings/{id}", id)`), never concatenated into a path, query string or query DSL
  (`templates/mcp-security.md` MCP05)
- Every timeout comes from properties with a stated worst case: `connect + read × attempts +
  backoff` must stay below the MCP client's own tool-call timeout, or the model sees a hang
  instead of a classified error

## Credentials

- The server calls the upstream with its **own scoped service credential** (least privilege,
  read-only when `readOnly: true`), loaded from a secret store (e.g. AWS Secrets Manager via
  `spring.config.import`) — never the MCP caller's token (**no token passthrough**: it breaks the
  audience boundary and turns the server into a confused deputy)
- Signing/credential attachment is an interceptor; a retried attempt is re-signed (a signature
  with a timestamp must never be replayed)
- Secrets rotate: when the secret store supports reload, enable it and test that the reload path
  actually activates

## Retry — transport failures only, idempotent calls only

- Retry only failures where **no response was received** (connect refused, DNS failure,
  connect/read timeout — `IOException` at the request-execution layer). Never retry an HTTP
  status: a 4xx is the caller's problem, a 5xx on a read is surfaced, not hammered
- Never retry a non-idempotent call (a write without an upstream idempotency key); with
  `readOnly: true` the server has none, except audit/telemetry writes — exclude those explicitly
- Bounded: max attempts (2–3), exponential backoff with jitter, and an exclusion list for paths
  where a retry only adds latency (precondition checks every call pays, "live" endpoints that are
  never cached)
- Implement once — an outermost `ClientHttpRequestInterceptor` (RestClient) or `retryWhen` with a
  filter (WebClient) — not per call site

## Resilience4j per Boot line

Boot 3 → `resilience4j-spring-boot3`. Boot 4 has no official module yet
([resilience4j#2371](https://github.com/resilience4j/resilience4j/issues/2371)); the
`resilience4j-spring-boot3` artifact (2.2.0) is known to run on Boot 4.1 but is unsupported there —
cover every annotation-driven limiter/breaker with a wiring test that proves it actually fires.

## Rate limiting

- Inbound: a Resilience4j `@RateLimiter` bucket on every tool method (global) and, when callers are
  identified, a per-caller bucket — refusal → `RATE_LIMITED` with `retryAfterMs`
- Outbound: when the upstream enforces a quota per credential, guard it on the MCP side (per path,
  global and per caller) so one heavy user cannot exhaust the shared service account; a cache hit
  never consumes the budget
- An in-memory limiter is only correct for a single instance — say so in the config comment when
  the deployment runs one instance, and revisit on scale-out

## Circuit breaker

- One named Resilience4j instance per upstream (or per heavy endpoint group), never shared across
  upstreams; opens on overload signals (timeouts, connect failures), not on 4xx
- An open circuit → `UPSTREAM_UNAVAILABLE` immediately; a rate-limit refusal does not count as a
  circuit failure

## Caching

- Cache the **raw** upstream response (pre-RBAC, pre-masking) with Caffeine, keyed by the full
  request, with a TTL per endpoint class and a max size
- RBAC scoping, field pruning, sanitizing and masking are re-applied **per caller on every call,
  cache hit or miss** — a cache must never leak one caller's view to another
- Never cache "live" endpoints (current quota, current status) and never cache errors
- Protect heavy report endpoints from stampede (a single loader per key)

## Error classification

The client converts every failure into one of the `McpToolException` upstream codes
(`templates/tool-conventions.md` § Error model):

| Failure | Code |
|---------|------|
| No response after retries; circuit open | `UPSTREAM_UNAVAILABLE` |
| Non-2xx status | `UPSTREAM_HTTP_ERROR` (status in `details`, body never echoed raw) |
| 2xx with an unexpected payload | `UPSTREAM_SHAPE_ERROR` |
| 2xx with a business-failure envelope | `UPSTREAM_ERROR` |
| Upstream "not found" semantics | `NOT_FOUND` |
| Upstream authorization failure for the service credential | `UPSTREAM_HTTP_ERROR` + an ERROR log — it is an ops problem, not the caller's |

## Read-only enforcement

With `readOnly: true`, the first line is the read-only service credential; an ArchUnit rule is the
second — it forbids `put`/`patch`/`delete`/`method(HttpMethod)` on the HTTP client, `RestTemplate`,
and raw `java.net.http` outside `client/`/`config/` in `src/main` (`templates/contract-snapshot.md`
§ 4). When the upstream uses `POST`
for reads (common with functional-routing admin APIs), `POST` stays allowed and the read-only
guarantee rests on the verb rule plus the scoped read-only credential.

## Logging

- Log the upstream path, status, latency and attempt number at DEBUG/INFO; never the credential,
  the signed headers, or the raw response body (it may hold PII)
- Correlate with the tool audit event (MDC request/session id)

## Testing

- `MockRestServiceServer` bound to the `RestClient.Builder` (or a mock web server for `WebClient`):
  success mapping, each error class, retry on `IOException` only, no retry on 4xx/5xx, timeout
  classification
- Cache tests: hit returns the raw value, RBAC re-applied per caller on the hit
- YAML sanity tests for timeouts/retry/limiter properties per profile, so a profile override
  cannot silently drop a guard
