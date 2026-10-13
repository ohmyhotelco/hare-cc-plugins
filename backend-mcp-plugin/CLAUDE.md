# Backend MCP Plugin

A Claude Code plugin that applies tech stack and coding conventions for building
**Model Context Protocol (MCP) servers on Spring AI** with strict TDD methodology.

The target is a Spring Boot service whose product is a set of MCP tools (and optionally
resources and prompts) that an LLM client calls: `@Tool`/`@ToolParam` methods, a published
tool contract that must only change deliberately, an outbound client to the upstream system
the tools read from, and the security controls an agent-facing server needs (inbound OAuth2,
per-tool RBAC, audit, output sanitizing, result caps). There is no database layer in this
plugin's conventions — an MCP server here is a thin, auditable adapter over an upstream API,
and its scope is **data retrieval only** (see § Scope below).
It is self-contained: using it does not require any other plugin in this repository.

> **Maintainer documentation.** Claude Code does not load a plugin-root `CLAUDE.md` as context, so
> nothing here is load-bearing for skills or agents. Every rule they follow lives in `templates/`
> and is read explicitly at runtime: `pipeline-protocol.md` (lock, progress files, demotion,
> tree hash), `commit-standards.md`, `configuration.md`, `architecture.md`, `scope-rules.md` (data
> retrieval only, write-tool policy, MCP compliance conditions). Change a rule there.

## Scope: Data Retrieval Only

The plugin forces every generated MCP server to be a thin data-retrieval adapter. The authoritative
rules are `templates/scope-rules.md`; this is the summary the other documents point to.

- A tool call is: validate input shape → one upstream read → project/normalize → sanitize + mask →
  cap → return. The server owns transport, contract, safety and access; the **upstream owns every
  business rule**
- **No business logic** (`BL-1`..`BL-8`): no domain calculation, derived field, aggregation,
  multi-endpoint join/orchestration, business decision/default/validation, server-side state or side
  effect, or rule duplicated from the upstream. A requirement that needs it is **stopped and routed
  upstream**: `mcp-plan` records it in `plan.json.outOfScopeRequirements` (with the upstream ask),
  `mcp-code`/`implement` report a scope conflict and write nothing, `code-reviewer` rates it critical
  (Scope dimension) and `review-fixer` deletes it instead of relocating it
- **Read-only by default** (`config.readOnly`). A write tool needs `readOnly: false`, an explicit
  per-tool opt-in, to be a pure pass-through of one upstream endpoint, and honest annotations
- **MCP compliance conditions C1–C13** (strict input schema, explicit annotations, typed bounded
  output, deterministic errors, side-effect-free idempotent reads, least privilege, outbound
  destination control, untrusted upstream data, resilience, audit, contract stability) are enumerated
  with their enforcement points in `templates/scope-rules.md` § 7
- The plugin has no override flag for scope; widening it is a deliberate project decision made outside
  the pipeline

## Tech Stack

- Java (toolchain from config), **Gradle only** (Kotlin or Groovy DSL; wrapper preferred). Run
  Gradle with a 10-minute Bash timeout (600000 ms)
- Spring Boot 3.x/4.x + **Spring AI MCP server** 1.x/2.x (via `spring-ai-bom`). Transports
  (`config.transports`, detected from the build file):
  - `webmvc` — `spring-ai-starter-mcp-server-webmvc`: Streamable HTTP on Spring MVC; blocking tools
  - `stdio` — `spring-ai-starter-mcp-server`: local clients. **Nothing may write to stdout** except
    the MCP stream: banner off, console logging routed to stderr
  - `webflux` — `spring-ai-starter-mcp-server-webflux`: only when the project chose it
    (`templates/core-conventions.md` § Reactive Note)
- Outbound: one client class per upstream — `RestClient` (webmvc/stdio) or `WebClient` (webflux) —
  per `templates/upstream-client.md`
- Security (`config.security`): `oauth2-resource-server` (JWT, audience validated) + `@PreAuthorize`
  per tool; `none` only for a local STDIO-only server (`templates/mcp-security.md`)
- Cross-cutting: Spring AOP (audit aspect), Resilience4j, Spring Cache + Caffeine; Lombok when
  detected
- Tests: JUnit 5 + AssertJ + Mockito, `spring-security-test`, `MockRestServiceServer`,
  `@SpringBootTest` wiring tests, the **tool contract snapshot** and **ArchUnit** rules
  (`templates/contract-snapshot.md`); Checkstyle/JaCoCo only when the project applies them
  (coverage is report-only — `templates/coverage-gate.md`)

### Version notes

Verify each against the project's actual versions — they move between releases.

| Topic | Note |
|-------|------|
| HTTP protocol | `spring.ai.mcp.server.protocol: STREAMABLE` (or `STATELESS`); `SSE` is deprecated in Spring AI 2.0 |
| stdio | `spring.ai.mcp.server.stdio: true` (reference project, Spring AI 2.0.0 — docs and versions differ, verify); stdio-only server: `spring.main.web-application-type: none` |
| Tool spec handler | MCP Java SDK `SyncToolSpecification`: `callHandler` (`CallToolRequest`) in newer SDKs, `call` (argument map) in older ones |
| Auto-registration | the autoconfiguration registers every `List<SyncToolSpecification>`, `ToolCallbackProvider`, `ToolCallback` and `List<ToolCallback>` bean — expose only one path |
| Resilience4j | Boot 3: `resilience4j-spring-boot3`. Boot 4: no official module ([#2371](https://github.com/resilience4j/resilience4j/issues/2371)); the reference runs `resilience4j-spring-boot3:2.2.0` on Boot 4.1, covered by wiring tests |
| Jackson / AOP | Boot 4: `tools.jackson.*`, `spring-boot-starter-aspectj`. Boot 3: `com.fasterxml.jackson.*`, `spring-boot-starter-aop` |

## Architecture

Package structure and call flow: `templates/architecture.md`.

## Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Tool class | `{Domain}Tools` | `BookingTools` |
| Tool name | `{verb}_{domain}[_{qualifier}]` | `get_hotel_bookings` |
| Tool method | camelCase of the tool name | `getHotelBookings` |
| Upstream client | `{Upstream}Client` / `{Upstream}RestClient` | `EllisRestClient` |
| Upstream DTO | `{Thing}` record in `client/dto/` | `BookingItem`, `BookingResult` |
| Upstream error | `{Upstream}ApiException` | `EllisApiException` |
| Tool error | `McpToolException` (one class, coded) | `McpToolException.notFound(...)` |
| Config / properties | `{Area}Config` / `{Area}Properties` | `McpToolConfig`, `OutputLimitProperties` |
| Aspect | `{Concern}Aspect` | `ToolAuditAspect` |
| Test | `{ClassUnderTest}Test` | `BookingToolsTest` |
| Work document / feature | kebab-case of the tool name | `get-hotel-bookings` |

## Commit Standards

The 13 rules `mcp-commit` writes by and `mcp-recall commit` checks: `templates/commit-standards.md`.

## Pipeline

```
mcp-plan (spec) → mcp-code (tool spec + TDD) → mcp-verify → mcp-review ↔ mcp-fix → mcp-commit
   ↕                      ↕                                     ↕
mcp-planner agent    implement agent                     code-reviewer agent
(spec → plan.json;   (RED → GREEN, contract snapshot;    (8 dimensions + optional spec)
 out-of-scope →      scope conflict → stop)
 upstream owner)

  mcp-plan is optional: without a spec, mcp-code takes a tool name and drafts the tool
  specification and scenarios with the user.
  When plan.json exists, mcp-code auto-detects spec-driven mode.

Interrupt skills (usable at any stage):
  mcp-debug    — systematic debugging (4-phase hypothesis-test methodology)
  mcp-progress — pipeline status dashboard
  mcp-verify --fix — build + auto-fix loop (build-doctor agent), then the verification gate
  mcp-recall   — rules reference and violation check

Focused audits (standalone, no pipeline state):
  mcp-review --dimension <tool_contract | upstream_integration | security | clean_code |
                          logging | test_quality | architecture | scope>
  mcp-fix --report <audit-file>   — fixes an audit's findings, no pipeline status change
```

### Pipeline State Machine

```
implementing → implemented → verified ─→ reviewed ─→ mcp-commit
                                     └→ done ────→ mcp-commit
                  ↓            ↓          ↓
            verify-failed  review-failed  fixing
                  ↓            ↓          ↓
       mcp-verify --fix     mcp-fix    mcp-verify (the fix changed code)
                  ↓            ↓          ↓
              verified       fixing    verified → mcp-review → reviewed/done
                               ↓
                           escalated (all issues escalated, or the build fails after fixes)

At any point:
  mcp-debug → resolved | escalated | (status unchanged: not reproduced, or no file modified)
  mcp-verify --fix, edit kept → other verified/reviewed/done tools → resolved (after confirmation)
  mcp-commit, confirmed staged-tree mismatch → that reviewed/done tool → resolved
  resolved → mcp-verify → verified | verify-failed
  escalated → (manual intervention) → mcp-verify → verified | verify-failed
```

State is tracked in `{workDocDir}/.progress/{feature}.json`. See `templates/progress-schema.md` for the full schema.

Lock, progress-file writes, demotion warning and the tree-hash rule: `templates/pipeline-protocol.md`.
The lock itself is `scripts/pipeline-state.sh` (atomic acquire, owner-checked release, validated
snapshot cleanup) — skills and agents never edit `.progress/.lock` by hand.

## Agents

Subagents never inherit session history: coordinator skills pass only the parameters each agent
needs, so every phase judges fresh.

Models: `implement`, `code-reviewer` and `mcp-planner` run on Opus (design and judgment);
`review-fixer`, `debugger` and `build-doctor` on Sonnet. `mcp-fix` and `mcp-debug` pass
`model: "opus"` for the hard cases (critical or contract-changing findings, a non-converging fix
round, an escalated or concurrency/transport/security problem).

Cost levers, kept on purpose: a Gradle run is one `run-gradle.sh` call (no raw log, no XML in
context); a re-review after `mcp-fix` is a **delta** review of the changed files only
(`mcp-review` Step 2.8), and only a full review reaches `done`.

- `mcp-planner` -- Reads a task description (Jira issue or pasted text), an upstream API inventory or a functional specification and produces an MCP tool plan (plan.json) of data-retrieval tools; requirements needing business logic go to `outOfScopeRequirements`
- `implement` -- TDD-based tool implementation from work documents, including the deliberate contract-snapshot update; stops with a scope conflict instead of writing business logic
- `build-doctor` -- Gradle build execution, failure diagnosis, and automatic fix with retry
- `code-reviewer` -- Multi-dimension review (tool contract, upstream integration, security, clean code, logging, tests, architecture, scope = data retrieval only, + optional spec compliance); also one dimension as a focused audit
- `review-fixer` -- TDD-disciplined fixer that reads review reports and applies targeted fixes (business logic is deleted or escalated, never relocated)
- `debugger` -- Systematic debugger using 4-phase methodology (reproduce, hypothesize, test, confirm)

## Skills

| Skill | Purpose |
|-------|---------|
| `/backend-mcp-plugin:mcp-plan` | Jira task / task description / API inventory / spec → MCP tool plan.json (data-retrieval tools; business-logic requirements flagged out of scope) |
| `/backend-mcp-plugin:mcp-code` | Tool specification + TDD implementation (manual or spec-driven) |
| `/backend-mcp-plugin:mcp-verify` | Verification gate (compile + tests + contract + build + optional checkstyle/coverage); `--fix` runs the build auto-fix loop first |
| `/backend-mcp-plugin:mcp-review` | Multi-dimension review, or one dimension as a focused audit (`--dimension`) |
| `/backend-mcp-plugin:mcp-fix` | TDD-disciplined fix from a review report, or a focused-audit report (`--report`) |
| `/backend-mcp-plugin:mcp-commit` | Smart commit from staged changes (secret scan + contract/changelog pairing check) |
| `/backend-mcp-plugin:mcp-debug` | Systematic debugging (4-phase hypothesis-test) — utility |
| `/backend-mcp-plugin:mcp-recall` | Rules reference and violation check (incl. `scope`) — utility |
| `/backend-mcp-plugin:mcp-progress` | Pipeline status dashboard — utility |

## Templates

- `core-conventions.md` -- The single home of naming (mirror), coding standards, TDD process, build standards, verification philosophy and the tool-conventions and scope summaries (used by: mcp-code, mcp-recall, implement/code-reviewer/review-fixer/mcp-planner)
- `scope-rules.md` -- Data retrieval only: allowed shaping, forbidden business logic (BL-1..BL-8), scope test, stop-and-route-upstream procedure, write-tool policy, MCP compliance conditions C1–C13, ArchUnit scope guards (used by: mcp-planner, mcp-code, implement, code-reviewer, review-fixer, mcp-recall)
- `tool-conventions.md` -- Tool authoring, description template, naming, error model, output sanitizing/masking, result limits, tool annotations, registration, resources/prompts, instructions budget (used by: mcp-code, implement, code-reviewer, review-fixer)
- `upstream-client.md` -- Outbound client: timeouts, retry (transport-only, idempotent-only), rate limiting, circuit breaker, caching with per-caller RBAC, credentials, error classification (used by: implement, code-reviewer)
- `mcp-security.md` -- OWASP MCP Top 10 (MCP01–MCP10) checklist, HTTP transport baseline, severity guide (used by: code-reviewer, mcp-recall)
- `contract-snapshot.md` -- Contract snapshot test, changelog convention, ArchUnit rules (used by: mcp-code, implement, mcp-verify, code-reviewer, mcp-commit)
- `tdd-rules.md` -- TDD rules and test types for MCP tools / Gradle / JUnit 5 (used by: implement, review-fixer)
- `work-document-template.md` -- Tool work document: tool specification + test scenarios (used by: mcp-code)
- `plan-schema.md` -- MCP tool plan.json schema (used by: mcp-planner, mcp-code)
- `progress-schema.md` -- Pipeline state file schema and status transitions
- `coverage-gate.md` -- JaCoCo Gradle configuration reference, report-only (used by: mcp-verify)
- `pipeline-protocol.md` -- Lock protocol via `scripts/pipeline-state.sh`, progress-file writes, demotion warning, tree-hash rule (used by: every skill that writes `.progress/`, implement/review-fixer/debugger/build-doctor)
- `commit-standards.md` -- The 13 commit-message rules (used by: mcp-commit, mcp-recall)
- `configuration.md` -- `config` resolution, the policy file, every key (used by: every skill)
- `architecture.md` -- Package structure and tool call flow / aspect order (used by: code-reviewer, tdd-rules, tool-conventions)

Outside the instruction corpus: `scripts/` (project detection, tree hash, pre-commit, the pipeline
lock (`pipeline-state.sh`), Gradle runs (`run-gradle.sh` + `junit-summary.sh`: one tool call per
run, bounded output), review scope (`review-scope.sh`: the delta re-review) and state validation,
run by skills, agents and hooks) and `tests/` (fixture projects + `tests/run.sh`, a smoke test
for the scripts — run it after editing any script).

## Configuration

There is no init step. Every skill runs `bash "{pluginRoot}/scripts/detect-project.sh"` at its start;
exit 0 → stdout JSON is `config`. Resolution rules, the optional policy file
`.claude/backend-mcp-plugin.json` and every key: `templates/configuration.md`.

### Communication Language

Skills read `workingLanguage` from config (`en` English, `ko` Korean, `vi` Vietnamese). All
user-facing output (summaries, questions, feedback, next-step guidance) is in that language.
