# Scope Rules: Data Retrieval Only

The single, authoritative statement of what an MCP server built with this plugin may and may not
do, and the MCP compliance conditions every tool must meet. Used by `mcp-planner` (classification),
`mcp-code` and the `implement` agent (hard stop), the `code-reviewer` agent (Scope dimension),
the `review-fixer` agent (fix direction) and `mcp-recall scope`. Other templates and agents point
here; they do not restate it.

## 1. Principle

An MCP server here is a **thin, auditable data-retrieval adapter** over an upstream API. A tool call
is exactly:

```
validate input shape → one upstream read → project / normalize the response → sanitize + mask
→ cap → return typed result (or a coded error)
```

The server owns **transport, contract, safety and access** (schema, limits, sanitizing, masking,
entitlement, audit, resilience). The upstream service owns **every business rule** (pricing,
eligibility, state, workflow, aggregation semantics). The server never decides what the data
*means*; it only fetches it and makes it safe and bounded for a model to read.

When a request needs a business decision or computation, the answer is never "implement it in the
tool": it is **stop, flag, and route it upstream** (§ 5).

## 2. Allowed (data-access shaping)

| Allowed | Boundary |
|---------|----------|
| Field projection, renaming, envelope unwrapping, sentinel → null | Copies upstream values; no change of meaning |
| Format normalization (date/time format, enum spelling the upstream documents) | No unit, currency, timezone-policy or rounding change |
| Pagination: clamp `limit`/`offset`, pass them to the upstream, report truncation | Arithmetic only on paging, caps and counts of returned rows |
| Input shape validation: type, format, enum set, range/span bound, paired parameters | Shape only — never domain state or rules (§ 3 BL-5) |
| Sanitizing free text, masking PII, field minimization | `templates/tool-conventions.md` § Output |
| Entitlement scoping: null/remove fields and filter rows the caller may not see (RBAC) | Authorization, not business meaning; the rule comes from the entitlement service, never hard-coded business predicates |
| Error classification into `McpToolException` codes | `templates/tool-conventions.md` § Error model |
| Short-TTL cache of the **raw** upstream response | `templates/upstream-client.md` § Caching |
| Timeouts, transport-only retry, rate limit, circuit breaker | `templates/upstream-client.md` |

## 3. Forbidden (business logic) — rule ids used by the reviewer

| Id | Forbidden | Typical signs in code |
|----|-----------|-----------------------|
| BL-1 | **Domain calculation**: price, markup, margin, tax, commission, discount, FX/unit conversion, rounding policy, settlement, balance, date arithmetic with business meaning (cancellation deadline, stay length charges) | `BigDecimal.multiply/add/subtract/divide` on upstream amounts; rate/percent constants; `ChronoUnit.between` feeding a result field |
| BL-2 | **Derived business fields**: a result field the upstream does not return — status, flag, tier, score, rank, eligibility, recommendation, "isX" | result record has fields absent from the upstream DTO; a mapper with logic beyond copy/rename |
| BL-3 | **Aggregation**: sum / count / average / group-by / min-max / top-N / dedup over rows, computed by the server | `Collectors.summing*/averaging*/groupingBy/counting`, `.reduce(`, `.sum()`, `.max(` on result rows (a count of returned rows for the cap or truncation warning is allowed) |
| BL-4 | **Orchestration**: more than one upstream read per tool call, a loop of upstream calls, a join/merge of two endpoints, or a conditional second call | two distinct client methods in one tool method; client call inside a loop or stream; a client method that internally calls another endpoint to enrich |
| BL-5 | **Business-rule decisions**: branching on a domain value (status, type, tier, channel, country) to change behavior; business validation (e.g. "cannot cancel after…", "hotel must be active"); business defaults (default date window, default currency, default channel) | `if/switch` on upstream or caller domain values outside error classification; domain checks in validation helpers |
| BL-6 | **Own state or side effects**: persistence (entity, repository, `JdbcTemplate`), queues/events, files, schedulers, async jobs, mutable fields holding domain state, write-behind caches, calling an LLM | `@Entity`, `*Repository`, `@Scheduled`, `@Async`, `KafkaTemplate`, `Files.write`, non-final tool-class fields |
| BL-7 | **Unsanctioned write tool**: any mutating tool when `readOnly` is true; any write tool that is not a pure pass-through of one upstream endpoint, or lacks the recorded opt-in (§ 6) | mutating HTTP verb in `client/`; write tool with no `writeOptIn` in its work document |
| BL-8 | **Rule duplication / local filtering**: re-implementing a rule or filter the upstream owns instead of passing a parameter (client-side filter on a business predicate, local sort of a truncated page, re-validating upstream rules) | `stream().filter(…)` / `.sorted(…)` on upstream rows with a domain predicate; copies of upstream enum meaning or thresholds |

Corollaries:

- A tool **name or description that promises a computed or decided result** (`calculate_*`,
  `compute_*`, `estimate_*`, `recommend_*`, `rank_*`, `check_eligibility`, `summarize_*`,
  `reconcile_*`, "total revenue", "is eligible") is out of scope unless the upstream endpoint it
  wraps returns exactly that value, in which case the description says the upstream computes it.
- A server-side aggregate or ranking over a **paged or truncated** result is wrong even when
  allowed in principle: the model is told never to aggregate over `ROWS_TRUNCATED` results, and the
  server must not do it either.
- Config keys with business meaning (`markup`, `commission`, `tax`, `threshold`, `currency`) do not
  belong in this server's properties; the limiter/resilience/cap/TTL properties do.

## 4. Scope test (apply to every tool, every scenario, every review candidate)

A tool is in scope only if **all** answers are as shown:

1. Is the result obtainable from **one** upstream read plus copying/projecting fields? → yes
2. Would a change to a business rule (price policy, eligibility, status meaning) require editing
   this code? → no
3. Does the code compare, branch on, or do arithmetic with a domain value, other than for paging,
   caps, row counts, timeouts or shape validation? → no
4. Does every returned field either come from the upstream response or describe the response
   itself (`limit`, `offset`, `returnedCount`, `restrictedFields`, `warnings`)? → yes
5. Does the tool keep no state between calls (beyond the raw-response cache) and cause no side
   effect on a read? → yes

Any other answer is a business-logic finding (BL-1..BL-8).

## 5. When business logic is needed: stop and route upstream

- **Planning** (`mcp-planner`): do not plan the tool. Record the requirement in
  `plan.json.outOfScopeRequirements` with the rule id (`BL-n`), why, and the upstream ask. The
  closest in-scope tool (e.g. the raw listing with a narrow filter) may be planned instead, and the
  plan says so; the model then answers from rows, never from a server-computed number
- **Specifying / implementing** (`mcp-code`, `implement`): stop for that tool before writing code or
  tests; report `Scope conflict: {tool} — {BL-n}: {what}`; the user decides (change the requirement,
  ask the upstream owner to expose the endpoint, or take the logic to a different service). A scenario
  that turns out to need it mid-cycle is treated the same way: revert the scenario, stop, report
- **Reviewing** (`code-reviewer`, Scope dimension): **critical**. **Fixing** (`review-fixer`): delete
  the logic and return the upstream value; never move it into a helper, `common/`, the client or
  a config class (that is the same logic, relocated)
- **The upstream ask** names the endpoint or field to request, e.g. "expose
  `GET /bookings/summary?from&to` returning `totalAmount` per hotel"; the MCP server then wraps that
  endpoint as an ordinary read tool

The plugin has no override flag. Widening the server's scope is a deliberate product decision made
outside the pipeline, by editing this template for the project.

## 6. Write tools

Default: **read-only**. `config.readOnly` defaults to `true`; every tool is a read tool.

A write tool is permitted only when **all** hold:

1. The project set `"readOnly": false` in `.claude/backend-mcp-plugin.json` deliberately, **and**
   the user explicitly opted in to this tool: the work document carries
   `Write opt-in: {who/when/why}` and the plan entry has `writeOptIn` set (`mcp-code` asks; it
   never infers consent from a task text)
2. It is a **pure pass-through** of exactly one upstream endpoint: the model's validated arguments
   in, the upstream's response out. The upstream validates the business rules and owns the state
   change; the tool decides nothing, computes nothing, defaults nothing with business meaning, and
   does not read-then-write
3. Annotations are set honestly (§ 7 C2): `readOnlyHint=false`, `destructiveHint` true for any
   delete/overwrite/irreversible change, `idempotentHint` true only when repeating the same call
   changes nothing further (the upstream honors an idempotency key or the verb is naturally
   idempotent), `openWorldHint` per § 7 C2
4. Never retried unless idempotent with an idempotency key (`templates/upstream-client.md` § Retry);
   a human confirmation step exists on the client side by design (the description says the tool
   changes data and what it changes); the audit event records the masked arguments
5. It appears in the contract snapshot with its annotations, so adding or changing a write tool is
   always a visible diff

Anything else → BL-7 (**critical**). Mutating tools are never planned from a task text alone.

## 7. MCP compliance conditions

Each condition names where its detail lives. "NEW" rows are added by this template; the rest are
already specified elsewhere and only enforced here by reference — do not duplicate their text.

| Id | Condition | Detail / enforcement |
|----|-----------|----------------------|
| C1 | **Strict input schema**: closed object (`additionalProperties: false`), every string bounded by an enum, pattern or max length, every number by min/max, every array by `maxItems`; `required` honest; no `Map`/`Object`/free-form inputs; no parameter that carries a URL, path, query fragment, filter expression or script | NEW (bounds); `templates/tool-conventions.md` § Input validation and § `@ToolParam`; `templates/mcp-security.md` MCP02/MCP05. Verify closure and bounds in the contract snapshot's `inputSchema` |
| C2 | **Annotations on every tool, set explicitly and honestly**: `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`. Read tool: `readOnlyHint=true`, `idempotentHint=true`, `destructiveHint=false`, `openWorldHint=false` (the MCP default for `openWorldHint` is `true`, so a closed upstream must set `false`; `true` only when results include content from an open external system). Hints are advisory to clients — the real controls are the read-only credential and the ArchUnit rule | NEW (explicit set, defaults trap); `templates/tool-conventions.md` § Output (annotations) |
| C3 | **Typed, structured output**: records, never `Map`/`JsonNode`; nullable properties typed `[type, "null"]` when an `outputSchema` is published; no narrative strings mixing data and guidance | `templates/tool-conventions.md` § Output |
| C4 | **Bounded results**: no "fetch everything" mode, a default limit when absent, clamp to the upstream's own cap, row cap + size ceiling at one choke point, truncation reported as a warning block, no server-side loop that pages the upstream to completion | `templates/tool-conventions.md` § Output and § Input validation; no-paging-loop is NEW (also BL-4) |
| C5 | **Deterministic error mapping**: a failure is an `isError` tool result with a stable code, never a protocol error or a thrown raw exception; no stack trace, class name, SQL, URL with credentials or raw upstream body in any message; the same failure always maps to the same code | `templates/tool-conventions.md` § Error model; `templates/upstream-client.md` § Error classification |
| C6 | **Read tools are side-effect-free and idempotent**: no write to a database, file, queue or event bus; the only state is the raw-response cache; the same arguments produce the same upstream request (no hidden `now()`/random defaults — a relative-date default is a business default, BL-5) | NEW; BL-6 and BL-5 in the Scope dimension; ArchUnit: no persistence or file-writing dependency from `tools..` |
| C7 | **Auth and least privilege**: inbound OAuth2 with audience validation, per-tool RBAC deny-by-default, row/field scoping per caller; outbound uses the server's **own** minimally scoped (read-only) credential — the caller's token is never forwarded, stored or logged (no token passthrough). The caller's identity is used for authorization and audit only | `templates/mcp-security.md` MCP01/MCP02/MCP07; `templates/upstream-client.md` § Credentials |
| C8 | **Outbound destination control**: the upstream base URL comes only from properties; no model-supplied host/URL; redirects not followed to another host; no tool that sends data to a destination the model names (SSRF / exfiltration) | NEW; `templates/upstream-client.md` § Outbound destination; `templates/mcp-security.md` |
| C9 | **Untrusted upstream data**: free text sanitized, PII masked, fields minimized, results framed as typed data; tool descriptions are static (never built from runtime data) and carry no instructions beyond how to call the tool | `templates/mcp-security.md` MCP03/MCP06/MCP10 |
| C10 | **Resilience on every upstream call**: separate connect/read timeouts with a stated worst case below the client's tool timeout, transport-only retry on idempotent calls, rate limit, circuit breaker | `templates/upstream-client.md` |
| C11 | **No secrets in logs, config or results**; STDIO keeps stdout clean | `templates/mcp-security.md` MCP01; Logging dimension |
| C12 | **Audit**: every tool call recorded ALLOW / DENY / ERROR with tool, caller, masked parameters, result size, latency | `templates/mcp-security.md` MCP08; `templates/architecture.md` § Call Flow |
| C13 | **Contract stability**: the manifest (name, description, input/output schema, annotations) is snapshot-tested; changes are deliberate, additive, and logged in the changelog; a new or changed write tool or annotation is a visible diff | `templates/contract-snapshot.md` |

## 8. ArchUnit guards that make scope a build property

Add to the project's `ArchitectureTest` (`templates/contract-snapshot.md` § 4) in addition to the
read-only and layering rules; they are the structural half of BL-3, BL-4 and BL-6 (the Scope
dimension judges the semantic half):

```java
// Tools hold no business-logic or persistence layers: nothing under tools.. may depend on them.
@Test
void toolsDoNotDependOnPersistenceOrSchedulers() {
    noClasses().that().resideInAPackage("..tools..")
            .should().dependOnClassesThat().resideInAnyPackage(
                    "javax.persistence..", "jakarta.persistence..", "org.springframework.jdbc..",
                    "org.springframework.data..", "org.springframework.scheduling..",
                    "org.springframework.kafka..", "org.springframework.amqp..")
            .because("an MCP tool retrieves upstream data; it keeps no state of its own")
            .check(CLASSES);
}

// No home for business logic: a service/domain/rules layer must not exist beside tools/ and client/.
@Test
void noBusinessLogicLayerExists() {
    noClasses().should().resideInAnyPackage(
            "..service..", "..domain..", "..rules..", "..policy..", "..calculator..", "..repository..")
            .because("business logic belongs to the upstream service")
            .check(CLASSES);
}

// A tool method calls at most one upstream client method: no orchestration (BL-4) — assert with a
// custom ArchCondition over the tool classes' method calls to {Upstream}Client.
```

## 9. Severity

- **critical** — BL-1 … BL-7 present (calculation, derived business field, aggregation,
  orchestration, business decision/validation, own state, unsanctioned write); a write tool with
  dishonest annotations
- **warning** — BL-8 (local filter/sort/rule duplication); a description or name promising a
  computed result; business-meaning config keys; missing or defaulted annotations (C2); an open
  input schema or unbounded input (C1)
- **suggestion** — scope hardening (ArchUnit guards of § 8 absent; an upstream ask not yet
  recorded for an out-of-scope requirement)
