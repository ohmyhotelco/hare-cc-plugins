# MCP Server Security Checklist (OWASP MCP Top 10)

The risks an agent-facing tool server carries, keyed to the
[OWASP MCP Top 10](https://owasp.org/www-project-mcp-top-10/) IDs, each with the concrete control
this plugin expects and what a reviewer looks for. Used by the `code-reviewer` agent's Security
dimension (full review and `mcp-review --dimension security`) and by `mcp-recall security`.

An MCP server sits between an LLM (which follows text it reads) and a system of record (which
holds data the caller may not be entitled to). Both directions are attack surface: text flowing
**out** of the server can steer the model, and calls flowing **in** can be crafted by a model that
has itself been steered.

| ID | Risk | Control | Reviewer looks for |
|----|------|---------|--------------------|
| MCP01 | **Token mismanagement & secret exposure** | The server calls the upstream with its own scoped credential; the caller's token is never forwarded, stored or logged; no secrets in any profile (secret store instead) | `Authorization` header copied to the outbound call; the inbound JWT logged or persisted; literal secrets or non-empty secret defaults in `application*.yml` |
| MCP02 | **Privilege escalation via scope creep** | Business logic in the server is scope creep too: the server only retrieves data (`templates/scope-rules.md`, reviewed in the Scope dimension). First line: a **read-only upstream credential**. Second line: `readOnly: true` enforced by ArchUnit (`templates/contract-snapshot.md` § 4). Write tools only when designed, idempotent, scoped, and confirmed by a human; no generic "call any endpoint" tool | Mutating HTTP calls; pass-through tools taking a path/URL/query from the model; tools returning whole upstream payloads when a projection suffices |
| MCP03 | **Tool poisoning** — tool/param descriptions or server instructions carrying hidden or manipulative instructions | Descriptions describe the tool only; no instructions about other tools, the user or the conversation; no zero-width/Unicode-tag/control characters; reviewed through the contract snapshot diff | Imperatives aimed at the model that are not about calling this tool; invisible characters in descriptions/`instructions`; description text built from runtime data |
| MCP04 | **Supply chain** | Versions pinned, full graph locked (`gradle.lockfile`) and scanned; MCP/Spring AI starters from the BOM only | Floating versions (`+`, `latest.release`); unlocked graph; unofficial MCP starters |
| MCP05 | **Command injection & execution** — model-supplied parameters reaching an upstream path, query string or query DSL | Parameters bound as encoded values (`uri("/x/{id}", id)`, request-body fields), validated against an allowlist/pattern first; never string-concatenated into a path, query, search DSL, SQL or script | `"/path/" + param`, `String.format` into a URI or query body; free-text params passed into Elasticsearch/JSONPath/SQL fragments |
| MCP06 | **Prompt injection via contextual payloads** — upstream text that reads like instructions | The controls are **design**: field minimization (return only what the use case needs), data framing (results are typed JSON records, never prose that mixes data and guidance), and no write tool without human confirmation. Sanitizing (control, zero-width, Unicode-tag characters stripped; code fences broken; length capped) is a **mitigation** on top | Upstream `String` fields returned without the sanitizer; raw upstream error bodies in messages; upstream text concatenated into a narrative string; write tools callable without confirmation |
| MCP07 | **Insufficient authentication & authorization** | See § HTTP transport baseline. Per-tool RBAC (`@PreAuthorize("@rbac.canCall('{tool}')")` on every tool method), tools/list filtered to what the caller may call, row/field scoping re-applied per caller, fail closed on an empty/erroring entitlement | `permitAll` on the MCP endpoint; JWT decoder without audience validator; a tool method without `@PreAuthorize`; scoping applied only on cache miss; "allow all" on entitlement error; a dev bypass profile reachable in prod |
| MCP08 | **Lack of audit & telemetry** | An audit aspect around every tool method records ALLOW / DENY / ERROR with tool name, caller id, masked parameters, result size and latency; ordered outside `@PreAuthorize` so denials are recorded (`templates/architecture.md` § Call Flow), proven by a wiring test | Tools outside the aspect pointcut; raw parameter values in audit events; DENY paths that bypass the audit |
| MCP09 | **Shadow MCP servers** | The server is in the organization's MCP inventory (owner, URL, transport, tools, data classes); dev/stdio builds are not deployed as network services; no debug/test profile exposing extra tools | Undocumented deployment targets; a second MCP endpoint or profile registering tools absent from the contract snapshot |
| MCP10 | **Context injection & over-sharing** | PII masked in results and audit params; field minimization per tool; result row cap + size warning; no secrets or internal ids beyond the contract | Unmasked email/phone/account/guest names; tools returning credentials or signed URLs; unbounded list results; `details` maps carrying caller identity |
| — | **Outbound destination / SSRF / exfiltration** (not in the Top 10) | The upstream base URL comes only from properties; no model-supplied host or URL; redirects not followed to another host; no tool sends data to a destination the model names (`templates/scope-rules.md` § 7 C8) | A host/URL parameter; `followRedirects`; a webhook/e-mail/"send to" tool; a base URL assembled from input |
| — | **Resource exhaustion** (not in the Top 10) | Rate limiters (global + per caller), upstream quota guard, timeouts below the client's tool timeout, circuit breaker, result limiter | A tool without `@RateLimiter`; unbounded `limit`; no read timeout; retry on every failure class |

## HTTP transport baseline (Streamable HTTP / SSE)

MCP spec 2025-11-25 (Transports § Security Warning, Authorization, Security Best Practices):

- **Origin validation (spec MUST)** — reject a request whose `Origin` header is present and not in
  an allowlist with **403** (DNS-rebinding defense). Spring AI 2.0.0's webmvc transport builders
  accept a `ServerTransportSecurityValidator` (MCP Java SDK `DefaultServerTransportSecurityValidator`,
  allowed origins/hosts), but the autoconfiguration does not set one and the SDK default is a
  no-op; earlier versions have no hook. Unverified for other versions — do not assume it: add a
  servlet/WebFilter on the MCP endpoint (or the validator bean) and pin it with a 403 test
- **Local bind** — a Streamable HTTP server meant to run locally binds `127.0.0.1`
  (`server.address`), never `0.0.0.0`
- **Audience** — the JWT decoder validates issuer **and** audience (the token was minted for this
  server — RFC 8707 resource indicator)
- **Discovery** — an auth-enabled server publishes OAuth Protected Resource Metadata (RFC 9728,
  `/.well-known/oauth-protected-resource`, unauthenticated) and answers 401 with
  `WWW-Authenticate: Bearer resource_metadata="…"`
- **Sessions** — `MCP-Session-Id` is a secure random value, is **never** authentication (every
  request carries and re-validates its token), and server-side session state is bound to the
  authenticated user (key `userId:sessionId`), so a stolen session id alone reaches nothing
- **OAuth proxy** (the server fronts a third-party authorization server with one static client
  ID) — obtain **per-client user consent** before forwarding to the third-party AS (confused
  deputy), PKCE, exact-match redirect URIs, `state` validated

## Candidate discipline (review procedure)

Every match against the table is a **candidate**. Before it becomes a finding, state in one line
either the concrete path (input → sink, e.g. "`sellerCompName` from the upstream reaches the tool
result at `ChannelTools.java:120` without `sanitize`") or the specific reason it is excluded (test
code; a constant; already routed through the sanitizer by a shared helper; the field is numeric).
Only true positives are reported. A missed true positive is worse than an excluded false positive
with a stated reason.

## Severity guide

- **critical** — reachable auth bypass; missing token audience validation; missing Origin
  validation or a local HTTP server bound beyond loopback (HTTP transports); `MCP-Session-Id` used
  as authentication; an OAuth proxy with a static client ID forwarding without per-client user
  consent; a tool without RBAC on a server with security enabled; token passthrough;
  secrets committed; mutating call on a `readOnly` server; outbound host or URL controlled by model input; model input concatenated into an
  upstream path/query/DSL; unmasked PII in results or audit; unsanitized upstream text on a server
  with a write tool
- **warning** — unsanitized upstream text on a read-only server; missing Protected Resource
  Metadata or `WWW-Authenticate: Bearer resource_metadata=…` on 401 (auth-enabled HTTP transport);
  missing rate limiter; missing result cap; audit gap on
  one path; description containing non-contract instructions
- **suggestion** — hardening (per-caller limiter, tools/list visibility filter, lockfile scanning
  in CI, MCP inventory entry)

A server with `security: none` gets **one** warning ("no inbound authentication; acceptable only
for a local STDIO server") — not a critical per tool — unless an HTTP transport is present, in
which case it is critical.
