# MCP Tool Conventions

Authoritative rules for authoring MCP tools, resources and prompts on Spring AI. Used by
`mcp-code`, the `implement` agent (writing), the `code-reviewer` agent (Tool Contract dimension)
and the `review-fixer` agent.

**Scope**: a tool retrieves upstream data and nothing else — no calculation, derived field, aggregation, multi-endpoint join, business decision or server-side state (`templates/scope-rules.md` is authoritative; every rule below assumes it).

**Project override**: when `config.descriptionConvention` names a document, read it first — its
template, vocabulary and naming rules win over the defaults below wherever they differ.

**Annotation scope**: the rules are written for Spring AI's `@Tool`/`@ToolParam`. On
`config.toolRegistration == "annotation-scanner"` (`@McpTool`/`@McpToolParam`) the same authoring
rules apply, and three wiring points must name both annotations: the audit/rate-limit pointcuts
(`@annotation(Tool) || @annotation(McpTool)`), the `@PreAuthorize`-on-every-tool rule, and the
contract snapshot (built from the registered specs — `templates/contract-snapshot.md` § 1).

## Why descriptions are a budget, not prose

Every tool's `description` (and its `@ToolParam` descriptions, rendered into the input schema) is
sent to the client on **every** tools/list, whether or not the model calls that tool. With five
tools a 700-character description is noise; with twenty it is a permanent token tax on every
request and a reading cost for the model choosing among them. A description exists to make the
model (1) pick the right tool and (2) fill its input correctly on the first call. Anything that
changes neither decision belongs in Javadoc or the contract changelog.

## Tool name

`<verb>_<domain>[_<qualifier>]`, snake_case, `^[a-z][a-z0-9]*(_[a-z0-9]+)+$`, at most 64
characters. The spec (2025-11-25) allows 1–128 characters of `A-Za-z0-9_-.`; 64 is a
client-observed limit (some clients prefix a server name), a plugin convention a project may relax
in its `descriptionConvention` document:

| Verb | Returns | Example |
|------|---------|---------|
| `list_` | the whole set, no filter, no id | `list_channels` |
| `get_` | one entity, or a result narrowed by id/condition | `get_channel`, `get_booking` |
| `query_` | a potentially large set needing filters / date range / paging | `query_bookings` |

A verb never promises computation or a decision: `calculate_`, `compute_`, `estimate_`, `recommend_`, `rank_`, `check_` (eligibility), `summarize_`, `reconcile_` names are out of scope unless the wrapped upstream endpoint returns exactly that value (`templates/scope-rules.md` § 3). A write verb is allowed only under `templates/scope-rules.md` § 6.

Domain after the verb so tools of one domain sort together. **Never rename a published tool in
place** — clients and RBAC registries key on the name. A breaking change ships as a new name; the
old one stays until it is retired with a changelog entry.

## `@Tool.description` template

Two adjacent XML-tagged blocks, no whitespace between them:

```
<tool_scope>{What}. {The one gotcha}. {Access-scope tag}</tool_scope><input>{Required input + key constraint + cross-reference}</input>
```

- **What** — open with the business noun ("Hotel booking records for…", "Seller contract
  detail for…"), not the source system name ("Get UPSTREAM channel detail…")
- **Gotcha** — the single most misread behavior, if any: a field that is null because of access
  scope rather than absence; masked PII; a part of the upstream contract not implemented
- **Access-scope tag** at the end: `Read-only.` / `Finance-scoped.` / `Read-only, no side
  effects.` — a write tool says what it changes and whether it is idempotent
- **Input** — the required input and its most important constraint (paired parameters, no
  "fetch everything" mode, valid enum values, max range) plus a short cross-reference to the tool
  that supplies a value: `(see list_channels' sellerCompCode)`. A tool with no input says
  `No input — {what the one call returns}.`
- Never: a promise of a result the server computes or decides (totals, eligibility, recommendations) — a description says what the upstream returns, and when the upstream computes a value, that it does; narrative ("Use this to answer…"), repeated server-wide rules (they belong in
  `instructions` once), instructions to the model that are not about calling this tool (that is
  tool poisoning, even when well-meant), hidden or zero-width characters, markdown/HTML

## `@ToolParam`

- `description`: the shortest text that fills the value correctly — format (`yyyy-MM-dd`), enum
  (`EN|KO|VI`), cross-field rule (`required unless sellerCompName is given`), source tool
- `required = false` only for a genuinely optional input; a parameter that is required in pairs
  says so in both descriptions
- Types: `String`, boxed numerics (`Integer`, `Long`) for optional numbers, `Boolean`, records for
  structured input. Avoid `Map`/`Object` inputs — the generated schema tells the model nothing
- Do not repeat what the tool-level description already says

## Input validation (in the tool, before the upstream call)

Validation checks the **shape** of the input only (type, format, enum set, range/span bound, paired parameters, size bounds). A rule about domain state or business policy ("hotel must be active", "cannot cancel after check-in") is the upstream's: the tool passes the request through and maps the upstream's rejection to `UPSTREAM_ERROR` / `UPSTREAM_HTTP_ERROR`. Defaults are static and carry no business meaning (a default `limit`, never a default date window computed from "today" or a default channel).

The published `inputSchema` is a closed object (`additionalProperties: false` — confirm it in the contract snapshot), every string bounded by an enum, pattern or max length, numbers by min/max, arrays by a max size; the bounds are enforced in the tool even when the schema generator cannot publish them (`templates/scope-rules.md` § 7 C1).

- Enum-like strings: validated against a `Set` constant; reject with `INVALID_INPUT` naming the
  allowed values (an upstream schema rejection surfaces as an opaque business failure)
- Dates: parsed with an explicit format; ranges bounded (max span) and ordered (from ≤ to)
- Paging: `limit`/`offset` clamped to `[1, MAX_LIMIT]` / `[0, …]` via one shared helper; the cap
  constant matches the upstream's server-side cap and is quoted in the description
- Paired/conditional parameters: checked explicitly, with a message saying which one is missing

## Error model

One exception type, `McpToolException`, carrying `code`, a message safe to show a model, and a
`details` map. Spring AI turns an exception thrown from a tool into a **tool-execution error** —
`CallToolResult{isError: true}` whose text is `getMessage()` — not a JSON-RPC error (those are
protocol failures the SDK raises: unknown tool, malformed request). So `getMessage()` must render
compact JSON `{"code":…,"message":…,"details":{…}}` (the constructor passes the rendered JSON to
`super`), and every other exception that can escape a tool is translated to it at one point:
`AccessDeniedException` (`@PreAuthorize`) → `ACCESS_DENIED` in the audit aspect; Resilience4j
`RequestNotPermitted` → `RATE_LIMITED` in a translator aspect (`templates/architecture.md` § Call Flow). A test pins
it: invoke a registered spec's call handler (or the proxied tool) on a failing path and assert
`isError` and that the text parses as JSON with the expected `code`.

When the project already defines codes (e.g. `INVALID_ARGUMENT` for `INVALID_INPUT`), use its
codes; the table is the default set:

| Code | When |
|------|------|
| `INVALID_INPUT` | tool-side validation failed |
| `NOT_FOUND` | the requested entity does not exist (a filter matching nothing is an empty result, not an error) |
| `ACCESS_DENIED` | RBAC denied the call or the entity is outside the caller's scope |
| `RATE_LIMITED` | a rate limiter refused; `details` carries `scope` and `retryAfterMs`, never the caller identity |
| `UPSTREAM_UNAVAILABLE` | transport failure after retries (connect/read timeout, DNS, refused), or circuit open |
| `UPSTREAM_HTTP_ERROR` | the upstream answered with a non-2xx status |
| `UPSTREAM_SHAPE_ERROR` | the upstream answered 2xx but the payload did not match the expected shape |
| `UPSTREAM_ERROR` | the upstream answered 2xx with a business failure (e.g. `success=false`, an error envelope) |

Never let a stack trace, class name, SQL, upstream URL with credentials, or raw upstream error
body reach the tool result.

## Output

- Return records, not `Map`/`JsonNode` — the output shape is part of the contract
- **Pass-through fidelity**: every returned field is a value the upstream returned, or describes the response itself (`limit`, `offset`, `returnedCount`, `restrictedFields`, `warnings`). No re-derived, recalculated, converted, rounded or relabeled value, no computed total, flag or status. Mapping is projection, rename and format normalization only. Row scoping filters rows by the caller's **entitlement**, never by a business predicate
- Upstream free text (names, notes, terms) is **untrusted**: `sanitize` (strip control,
  zero-width and Unicode-tag characters; break markdown code fences; cap field length) and then
  `mask` PII (email/phone/account; names per project rule) before it is returned — e.g.
  `pii.mask(sanitizer.sanitize(raw))` through one shared helper
- Field-level RBAC: a field the caller may not see is nulled (or removed) **and** disclosed
  (e.g. a `restrictedFields` list) so "hidden by access" is distinguishable from "not configured"
- Size: one choke point (a result limiter wrapping every registered tool's call handler) caps list
  rows and flags oversize results by appending a **second** content block
  `{"warnings":[{"code":"ROWS_TRUNCATED"|"RESULT_TOO_LARGE","message":…,"details":…}]}` — the JSON
  block keeps its shape; nothing is cut silently. The server `instructions` tell the model to check
  for it and never aggregate over a truncated result
- Structured output (optional): when a tool publishes an `outputSchema`, every nullable property is
  typed `[type, "null"]` — clients reject the whole result on the first unexpected null. Order is
  **limit → build `structuredContent`** (from the capped JSON block), so both carry the same rows;
  a client reading only `structuredContent` misses the warnings block — consider an optional
  `warnings` property in the `outputSchema`
- Tool annotations: on `spec-list` registration set `McpSchema.ToolAnnotations` on the
  `McpSchema.Tool` with **all four hints explicit** (the MCP defaults are `destructiveHint` true,
  `idempotentHint` false, `openWorldHint` true — an unset hint states the wrong thing): a read tool is
  `readOnlyHint=true`, `destructiveHint=false`, `idempotentHint=true`, `openWorldHint=false` (true
  only when results carry content from an open external system); a write tool
  (`templates/scope-rules.md` § 6) sets `readOnlyHint=false` and `destructiveHint`/`idempotentHint`
  honestly. They are contract (in the snapshot); the access-scope text tag in the description is
  then optional. Hints are advisory to clients, not a security control — the read-only credential
  and the ArchUnit rule are

## Registration

Match `config.toolRegistration`:

- `spec-list` — tools are built from `MethodToolCallbackProvider` and exposed as a
  `List<McpServerFeatures.SyncToolSpecification>` bean (e.g. in `McpToolConfig`), each call handler
  wrapped by the result limiter. A new tool class is added to that bean's tool objects; **do not**
  also expose a `ToolCallbackProvider`, `ToolCallback` or `List<ToolCallback>` bean — the
  autoconfiguration registers those a second time, unwrapped
- `callback-provider` — a `ToolCallbackProvider` bean lists the tool objects; add the new class
  there
- `annotation-scanner` — the Spring AI annotation scanner discovers the tool bean; confirm the
  scanner is enabled and the class is a bean

Every tool class is covered by a registration test that asserts the registered tool names.

## Server instructions, resources and prompts

- `spring.ai.mcp.server.instructions` frames the whole server once (domain, entry-point tool,
  result-limit rule). It is sent once per initialize; some clients display only the first ~2,000
  characters, silently (client-observed, not a spec limit — the budget is a project setting). Keep
  it under budget and lock the budget with a size test
- Use a YAML literal block (`|-`), not folded (`>-`), and group rules in XML tags
  (`<domain_context>`, `<result_limits>`, …)
- When shared guidance outgrows the budget, or would repeat across three or more tool
  descriptions, publish it as an **MCP resource** (a `List<SyncResourceSpecification>` bean, or
  the annotation form when the scanner is enabled) and cross-reference the resource URI
- Prompts (`SyncPromptSpecification`) are templates the user picks; they never carry secrets or
  per-caller data, and their arguments are validated like tool inputs

## Tool class skeleton

```java
// One class per business domain; every public @Tool method is part of the published contract.
@Service
public class BookingTools {

    // Mirrors the upstream's server-side cap so the description and the clamp never disagree.
    private static final int MAX_LIMIT = 1000;

    private final UpstreamClient upstream;
    private final RbacAuthorizationService rbac;
    private final PiiMasker pii;
    private final OutputSanitizer sanitizer;

    public BookingTools(UpstreamClient upstream, RbacAuthorizationService rbac, PiiMasker pii,
                        OutputSanitizer sanitizer) {
        this.upstream = upstream;
        this.rbac = rbac;
        this.pii = pii;
        this.sanitizer = sanitizer;
    }

    @Tool(name = "get_hotel_bookings",
            description = "<tool_scope>Hotel booking records for one check-in date range; guestName is "
                    + "masked. Read-only.</tool_scope><input>fromDate+toDate required (yyyy-MM-dd, "
                    + "max 31 days); limit max 1000.</input>")
    @PreAuthorize("@rbac.canCall('get_hotel_bookings')")
    @RateLimiter(name = "mcpTools")
    public BookingResult getHotelBookings(
            @ToolParam(description = "Check-in from, yyyy-MM-dd") String fromDate,
            @ToolParam(description = "Check-in to, yyyy-MM-dd, at most 31 days after fromDate") String toDate,
            @ToolParam(description = "Rows per page, 1-1000 (default 100)", required = false) Integer limit) {
        // validate shape → one upstream read → scope rows per caller (entitlement) → sanitize + mask → record;
        // no calculation, derived field, aggregation or second upstream call
        ...
    }
}
```
