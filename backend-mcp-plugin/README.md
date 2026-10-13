# Backend MCP Plugin

> **Ohmyhotel & Co** — Claude Code plugin for building Model Context Protocol servers on Spring AI with strict TDD

[English](./README.md) | [Tiếng Việt](./README.vi.md) | [한국어](./README.ko.md)

## What It Does

A development pipeline for Spring Boot services whose product is a set of **MCP tools** an LLM
client calls. It treats the things that make an MCP server different from a REST API as
first-class:

- **The tool description is the contract** — sent to every client on every tools/list, so it is
  authored to a compact template, frozen in a contract snapshot, and changed only deliberately
  with a changelog entry
- **The caller is a model** — upstream text is untrusted input to it (sanitized, PII-masked),
  results are capped with machine-readable warnings, errors are coded
- **The server is a deputy** — inbound OAuth2 + per-tool RBAC, its own scoped credential upstream
  (no token passthrough), read-only enforced by ArchUnit, every call audited
- **The upstream is someone else's system** — timeouts, transport-only retry, rate limiting,
  circuit breaking, caching with per-caller RBAC re-applied
- **The server only retrieves data** — no business logic: no calculation, derived field,
  aggregation, multi-endpoint join, business decision or state of its own. A requirement that needs
  one is stopped and routed to the upstream owner (`plan.json` `outOfScopeRequirements`, a scope
  conflict in `mcp-code`, a critical Scope finding in `mcp-review`). Read-only by default; a write
  tool is a pure, explicitly opted-in pass-through (`templates/scope-rules.md`)

Everything runs through a TDD pipeline with a verification gate recorded against a hash of the
source tree, a multi-dimension review with an OWASP-MCP-style security dimension, and a
TDD-disciplined fix loop.

## Tech Stack

| Area | Default |
|------|---------|
| Language / build | Java (21/25 toolchain), Gradle (Groovy or Kotlin DSL), wrapper, optional dependency locking |
| Framework | Spring Boot 4.x + Spring AI MCP server (BOM) |
| Transports | `webmvc` (Streamable HTTP/SSE, servlet), `stdio`, or `webflux` (reactive) — detected |
| Tools | `@Tool` / `@ToolParam` classes, registered as spec lists behind one result limiter |
| Outbound | `RestClient` (or `WebClient` on webflux), Resilience4j, Caffeine |
| Security | OAuth2 resource server, method-security RBAC, audit aspect, output sanitizer, PII masker |
| Tests | JUnit 5, AssertJ, Mockito, spring-security-test, MockRestServiceServer, ArchUnit, contract snapshot |
| Optional | Checkstyle, JaCoCo (report-only) — only when the project already applies them |

## Installation

```
/plugin marketplace add ohmyhotelco/hare-cc-plugins
/plugin install backend-mcp-plugin@ohmyhotelco --scope project
```

No setup step. Every skill runs `scripts/detect-project.sh` at its start, which reads the build
and sources on each run: Java/Boot/Spring AI versions, MCP transports, base and tools packages,
tool registration style, security, the contract snapshot test and changelog, and checkstyle/JaCoCo
presence. Nothing is cached, so the result never drifts from the code. Skills stop with a clear
message when the project has no Spring AI MCP server starter.

Optional policy file `.claude/backend-mcp-plugin.json`, only when a default must change:

```json
{ "readOnly": true, "workDocDir": "work/features", "workingLanguage": "vi" }
```

It can also override a detected key (e.g. `toolsPackage`). Gradle commands need
`"Bash(./gradlew *)"` in `.claude/settings.json` `permissions.allow`.

## Quick Start

### One tool, no spec

```
/backend-mcp-plugin:mcp-code get_channel_qps --class ChannelTools
/backend-mcp-plugin:mcp-verify get-channel-qps
/backend-mcp-plugin:mcp-review get-channel-qps
/backend-mcp-plugin:mcp-commit
```

`mcp-code` asks six questions (what it returns, inputs, upstream endpoint, access, output, tool
class), drafts the tool specification — including the published description — and the test
scenarios, and after your approval runs the RED-GREEN cycle to the final contract scenario
(snapshot + changelog).

### Several tools from a spec or an API inventory

```
/backend-mcp-plugin:mcp-plan booking-reports --source docs/upstream-api-inventory.md
/backend-mcp-plugin:mcp-code booking-reports
```

### Straight from a task

```
/backend-mcp-plugin:mcp-plan ELS-2040
/backend-mcp-plugin:mcp-plan promo-report --task "Sales needs the active promotions of a hotel, filterable by date"
```

A Jira key is fetched read-only (through whatever Jira MCP tool the session has; without one you are asked to paste the description) and snapshotted to `docs/specs/{feature}/.implementation/mcp/task-source.md`. `mcp-plan` also reads planning-plugin specifications (`docs/specs/{feature}/`).

## Pipeline

```
mcp-plan → mcp-code → mcp-verify → mcp-review ↔ mcp-fix → mcp-commit
```

| Skill | Purpose |
|-------|---------|
| `mcp-plan` | Jira task / pasted task description / API inventory / spec → MCP tool `plan.json` (data retrieval only; requirements needing business logic are listed as out of scope) |
| `mcp-code` | Tool specification + TDD implementation, ending in the deliberate contract-snapshot update |
| `mcp-verify` | Gate: compilation, tests, contract (snapshot + changelog pairing), build, optional checkstyle/coverage; `--fix` runs the build auto-fix loop first |
| `mcp-review` | 8 dimensions (tool contract, upstream integration, security, clean code, logging & audit, tests, architecture, scope = data retrieval only) + spec compliance; `--dimension <key>` for a focused audit |
| `mcp-fix` | Fixes from the review report — TDD for behavior, direct for mechanics, snapshot + changelog for contract changes |
| `mcp-commit` | Validated commit from staged changes: tree check, secret scan, contract pairing check |
| `mcp-debug` | 4-phase debugging (reproduce, hypothesize, test, confirm) incl. transport and upstream issues |
| `mcp-progress` | Dashboard: pipeline state, scenarios, contract status, next command |
| `mcp-recall` | Rules reference (`commit`, `tdd`, `build`, `coding`, `tool`, `security`, `upstream`, `scope`) + violation scan |

### State machine

```
implementing → implemented → verified → reviewed / done → commit
                   ↓             ↓           ↓
             verify-failed  review-failed  fixing → verified …
mcp-debug at any point → resolved | escalated
```

State lives in `{workDocDir}/.progress/{tool}.json`. A `verified` status carries the hash of the
source tree it was earned on; review and commit refuse (or question) it on a different tree.

## Agents

| Agent | Role |
|-------|------|
| `mcp-planner` | Spec / inventory → tool plan |
| `implement` | RED-GREEN per scenario; bounded contract-snapshot acceptance |
| `build-doctor` | Build, diagnose, fix, retry (never accepts contract drift or lockfile drift) |
| `code-reviewer` | Multi-dimension or single-dimension review, JSON report |
| `review-fixer` | TDD / direct / contract fixes from the report |
| `debugger` | 3-hypothesis systematic debugging |

## Configuration

`.claude/backend-mcp-plugin.json` — see the plugin `CLAUDE.md` § Configuration for every key.
Notable ones: `transports`, `toolRegistration`, `security`, `readOnly`, `contractSnapshot` /
`contractTest` / `contractActual` / `contractChangelog`, `descriptionConvention` (a project
document that overrides the plugin's description template).

## Communication Language

Set `workingLanguage` to `en`, `ko` or `vi`; every skill talks to you in it. Plugin instructions
and generated code comments stay in English.

## Directory Structure

```
backend-mcp-plugin/
├── .claude-plugin/plugin.json
├── CLAUDE.md
├── README.md / README.vi.md / README.ko.md
├── agents/        build-doctor, code-reviewer, debugger, implement, mcp-planner, review-fixer
├── hooks/         hooks.json (SessionStart detection summary, PostToolUse build/contract nudges)
├── scripts/       detect-project.sh, session-init.sh, validate-build-state.sh, source-tree-hash.sh, pre-commit-check.sh, pipeline-state.sh, run-gradle.sh, junit-summary.sh, review-scope.sh
├── skills/        mcp-plan, mcp-code, mcp-verify, mcp-review, mcp-fix, mcp-commit, mcp-debug,
│                  mcp-progress, mcp-recall
└── templates/     core-conventions, scope-rules, tool-conventions, upstream-client, mcp-security,
                   contract-snapshot, tdd-rules, work-document-template, plan-schema,
                   progress-schema, coverage-gate
```

## Author

Daniel — Ohmyhotel & Co
