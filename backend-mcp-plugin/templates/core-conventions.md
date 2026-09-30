# Core Conventions

The single home of the plugin's coding, TDD, build and verification rules, read by the subagents
that generate or review code (`implement`, `code-reviewer`, `review-fixer`, `mcp-planner`) and by
`mcp-code`, `mcp-recall`. `architecture.md`, `commit-standards.md`, `pipeline-protocol.md` and
`configuration.md` hold architecture, commit standards, pipeline and configuration; the other
templates hold the detailed rules each summary below points to. (The plugin `CLAUDE.md` is
maintainer documentation only — Claude Code never loads it.)

## Tech Stack (need-to-know)

- Java (version from config), Gradle, Spring Boot + Spring AI MCP server
- Transports from `config.transports`: `webmvc` (servlet, blocking tools), `stdio` (nothing but
  the MCP stream on stdout), `webflux` (reactive — § Reactive Note)
- On a `webmvc`/`stdio` server: no `Mono`/`Flux` in `src/main` (accidental complexity the servlet
  stack gains nothing from); outbound calls use `RestClient`
- One outbound client class per upstream system; tools never touch the HTTP client directly
- Security from `config.security`: OAuth2 resource server + `@PreAuthorize` per tool
- Lombok when `config.lombokEnabled == true`
- Checkstyle only when `config.checkstyle == true` — judged by the project's own
  `config/checkstyle/checkstyle.xml`

### Reactive Note (webflux transport only)

Never block the Netty event loop inside a tool: either keep blocking tool methods and confirm how
your Spring AI version dispatches synchronous tool calls on the webflux transport before relying
on it, or use the async server type with `Mono`/`Flux`-returning tools and `WebClient`. Never call
`.block()` in production code on this transport.

## Naming Conventions

Mirrors `CLAUDE.md` § Naming Conventions (change both together).

| Type | Pattern | Example |
|------|---------|---------|
| Tool class | `{Domain}Tools` | `BookingTools` |
| Tool name | `{verb}_{domain}[_{qualifier}]` (`list_` / `get_` / `query_`) | `get_hotel_bookings` |
| Tool method | camelCase of the tool name | `getHotelBookings` |
| Upstream client | `{Upstream}Client` / `{Upstream}RestClient` | `EllisRestClient` |
| Upstream DTO | record in `client/dto/` | `BookingResult` |
| Upstream error | `{Upstream}ApiException` | `EllisApiException` |
| Tool error | `McpToolException` with a code | `McpToolException.notFound(...)` |
| Config / properties | `{Area}Config` / `{Area}Properties` | `McpToolConfig` |
| Aspect | `{Concern}Aspect` | `ToolAuditAspect` |
| Test | `{ClassUnderTest}Test` | `BookingToolsTest` |

## Coding Standards

- `var` when the type is obvious from context; avoid it when it harms readability
- `record` for every DTO (upstream request/response, tool result)
- Constructor injection; tool classes are `@Service`/`@Component` with `final` collaborators
- Comments explain *why* (a non-obvious constraint, an upstream quirk, a security decision), in
  English; never narrate what the code already says
- Always add a final newline when creating a new code file
- Work in the smallest possible increments
- A constant that encodes a contract (page cap, enum set, finance-scoped field list) is defined
  once and referenced by both the check and anything that discloses it

## Tool Conventions (summary — `templates/tool-conventions.md` is authoritative)

- `@Tool(name = "...", description = "<tool_scope>…</tool_scope><input>…</input>")` — compact,
  no narrative; the project's `config.descriptionConvention` document overrides this template
- `@ToolParam(description = "...", required = …)` — format/enum/cross-field constraint only
- Never rename a published tool; a breaking change is a new tool name
- Inputs validated in the tool before the upstream call (enum sets, date formats, paired
  parameters, limit clamps) → `McpToolException` `INVALID_INPUT` (or the project's own code)
- Errors are tool-execution errors: `McpToolException.getMessage()` renders compact JSON
  `{"code","message","details"}`; `AccessDeniedException` and `RequestNotPermitted` are translated
- Upstream free text is sanitized and PII-masked before it is returned
- Results are records; list results respect the row cap; a cap or size ceiling hit is reported
  as a warning block, never a silent cut
- RBAC: `@PreAuthorize("@rbac.canCall('{tool}')")` on every tool method when security is enabled;
  field-level scoping re-applied per caller, including on cache hits
- Every contract change → snapshot + changelog in the same change

## Test-Driven Development

1. Write a list of the test scenarios you want to cover — prepared in advance
2. Turn exactly one item into a concrete, runnable test — never more than one at a time
3. Change the code to make it (and all previous tests) pass — no code a test does not require
4. Optionally refactor
5. Until the list is empty, go back to step 2

Never modify a failed test; a test that needs to change is updated manually. The bounded
exceptions (the tool stub, the deliberate contract-snapshot update) and the test types are in
`templates/tdd-rules.md`.

## Build Standards

- Run Gradle with a 10-minute Bash timeout (600000 ms); run the full build before committing
- Agent-run Gradle commands append `-q --console=plain` (output redirected to a log file, bounded
  summary read back); failing tests surface through the JUnit XML and a `quiet { }`-level
  `testLogging` block (FAILED/SKIPPED only) the implement agent adds when the build file has none
- Address all errors and warnings systematically, classified: compilation, test failures, contract
  drift, architecture rule violations, dependency issues (including lockfile drift), configuration
  problems, checkstyle violations — then apply targeted fixes
- When the project locks its graph (`dependencyLocking { lockAllConfigurations() }` +
  `gradle.lockfile`), a dependency change is not done until the lockfile is regenerated
  deliberately (`{gradleCommand} dependencies --write-locks`) and committed with it

## Verification Philosophy

"Evidence before claims, always." 5-Step Gate: IDENTIFY the target to verify → RUN the
verification tool (build, test, contract snapshot, coverage) → READ the full output (exit code,
error count, test counts) → VERIFY it matches the claim → CLAIM the result citing evidence.

| Thought | Reality |
|---------|---------|
| "Should work" / "probably fine" | Run the build. Evidence or silence. |
| "The change is small, no need to verify" | Small changes cause big bugs. Verify always. |
| "I already verified this earlier" | Code changed since. Verify again. |
| "Tests passed, so it's correct" | Tests cover what was written, not what was missed. Check the spec. |
| "Only the description changed" | The description IS the contract. Snapshot + changelog, then verify. |
| "The model will figure out the input" | If the description does not say it, the first call fails. Fix the description. |
| "Upstream data is trusted" | It is untrusted input to an LLM. Sanitize and mask. |
