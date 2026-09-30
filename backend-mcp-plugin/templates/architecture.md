# Architecture

Package roles and the tool call flow every MCP server built with this plugin follows. Read from
`{pluginRoot}/templates/architecture.md`.


## Package Structure

```
{basePackage}/
├── {App}Application.java
├── tools/                      <- @Tool classes, one per business domain ({toolsPackage})
│   └── {Domain}Tools.java          e.g. BookingTools: get_hotel_bookings, get_hotel_booking_stats
├── client/                     <- Outbound client to the upstream system (the ONLY HTTP caller)
│   ├── {Upstream}Client.java       e.g. EllisRestClient
│   ├── {Upstream}ApiException.java
│   └── dto/                    <- Upstream request/response records
├── config/                     <- McpToolConfig (tool registration), McpResourceConfig,
│                                   client config, security config, properties classes
├── security/                   <- RBAC service, output sanitizer, PII masker, result limiter,
│                                   rate-limit aspects, caller identity
├── audit/                      <- Tool audit aspect, audit event, param masker, audit sinks
├── common/                     <- Shared tool helpers (paging clamp, date parsing, free-text clean)
└── error/                      <- McpToolException (structured tool error: code + message + details)
```

Not every server needs every package — a local STDIO server with `security: none` has no
`security/` RBAC classes — but a package that exists holds only what its name says.

## Call Flow

```
MCP client (tools/call)
  → transport (webmvc / webflux / stdio) — HTTP: Origin allowlist, JWT (issuer + audience)
    → registered tool spec (McpToolConfig; result limiter wraps the call handler)
      → ExposeInvocationInterceptor (HIGHEST_PRECEDENCE + 1)
        → ToolAuditAspect @Order(150): audit ALLOW/DENY/ERROR, AccessDeniedException → ACCESS_DENIED,
          field-level RBAC prune
          → [per-caller limiter aspect, e.g. @Order(175)]
            → rate-limit translator @Order(190): RequestNotPermitted → RATE_LIMITED
              → @PreAuthorize("@rbac.canCall('{tool}')") (AuthorizationInterceptorsOrder.PRE_AUTHORIZE = 200)
                → Resilience4j RateLimiterAspect (@RateLimiter; default Integer.MAX_VALUE - 3)
                  → {Domain}Tools method: validate → {Upstream}Client → sanitize + mask → record
                    → {Upstream}Client: cache → rate limit → circuit breaker → retry (transport) → HTTP
  ← CallToolResult: JSON block (+ warnings block); a thrown McpToolException → isError: true,
    text = its JSON getMessage() (templates/tool-conventions.md § Error model)
```

The audit aspect must sit **outside** `@PreAuthorize` (order < 200) or denials are never audited,
and inside `ExposeInvocationInterceptor` or its `@annotation` binding fails. Numbers are from the
reference project; what is required is the relative order, proven by a `@SpringBootTest` wiring
test that a denied call is audited as DENY (`templates/tdd-rules.md` § Wiring test).
