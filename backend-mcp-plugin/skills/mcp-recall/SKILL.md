---
name: mcp-recall
description: "Recall the MCP server development rules (commit, TDD, build, coding, tool contract, security, upstream, scope = data retrieval only / no business logic) and check recent work for concrete violations."
argument-hint: "[commit | tdd | build | coding | tool | security | upstream | scope]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash(bash *scripts/detect-project.sh*), Bash(git log *), Bash(git diff *)
---

# Recall Rules

Display development rules and scan recent work for concrete violations of them. Every check names an exact scope (a git range, a directory, a file glob) — report results against that scope only, never as a claim about the whole codebase.

**Done when:** the Step 4 report shows the requested section's rules and, for each check, its stated scope with `{file}:{line}` violations, "none found in {scope}", or "not verified: {reason}". Read-only: no file is written.

## Instructions

### Step 0: Validate Configuration

1. `pluginRoot`: `${CLAUDE_PLUGIN_ROOT}` — Claude Code substitutes the plugin's install directory here when it loads this skill (the variable is not in the Bash environment, so always use this substituted value) — every `templates/…` path in this document is `{pluginRoot}/templates/…`; not an absolute path (the substitution did not happen) → stop: this Claude Code version does not substitute plugin paths in skill content — upgrade Claude Code.
2. `config`: run `bash "{pluginRoot}/scripts/detect-project.sh"` (`{pluginRoot}/templates/configuration.md`). Any non-zero exit: show the rules only and skip Step 3 entirely. Report: "not verified: this is not a Spring AI MCP server Gradle project ({the script's stderr}), so project-specific checks (tools package, security, read-only, contract paths) cannot be scoped. Showing rules only."
3. When exit 0, hold `toolsPackage`, `security`, `readOnly`, `transports`, `contractSnapshot`, `contractChangelog`, `descriptionConvention` — Step 3 scopes on them

### Step 1: Parse Argument

| Argument | Section | Source |
|----------|---------|--------|
| (none) | All rules summary | templates/pipeline-protocol.md + templates/commit-standards.md + templates/architecture.md + templates/core-conventions.md |
| `commit` | Commit Standards | templates/commit-standards.md |
| `tdd` | TDD Process + rules | templates/core-conventions.md § Test-Driven Development + templates/tdd-rules.md |
| `build` | Build Standards | templates/core-conventions.md § Build Standards |
| `coding` | Coding Standards + Naming | templates/core-conventions.md § Coding Standards + § Naming Conventions |
| `tool` | Tool contract & descriptions | templates/tool-conventions.md (+ the project's `descriptionConvention` document) + templates/contract-snapshot.md |
| `security` | OWASP MCP Top 10 checklist | templates/mcp-security.md |
| `upstream` | Upstream client rules | templates/upstream-client.md |
| `scope` | Data retrieval only — no business logic, write-tool policy, MCP compliance conditions | templates/scope-rules.md |

### Step 2: Display Rules

Read the relevant source and display it in the working language. For each rule: the statement, why it exists (one line — what lets a reader apply it to an unlisted case), and a brief example when useful.

### Step 3: Check for Violations

State the scope before scanning. A scan that cannot run (not a git repo, directory missing) reports "not verified: <reason>" — never zero violations.

#### `commit`
- Scope: `git log --oneline -5`; failure → "not verified: no git history available"
- Check each message: tense, prefix, > 50-character subject, lowercase start, missing blank line, body lines > 72 characters, attribution trailers or branding

#### `tdd`
- Scope: test files under `{testDir}`; missing → "not verified: {testDir} not found"
- Tool classes under `{toolsPackage}` with no `{Class}Test` → violation
- Mixed test naming styles within one class → violation
- Test methods with no assertion (`assertThat`/`assertThrows`/`verify` absent) → violation

#### `build`
- Scope: the build file and `gradle.lockfile`
- Floating versions (`+`, `latest.release`, `-SNAPSHOT` outside a snapshot build) → violation
- `dependencyLocking` declared but `gradle.lockfile` missing → violation

#### `coding`
- Scope: `{sourceDir}/{basePackage}/`
- `System.out`/`System.err` in `src/main` → violation (critical on a `stdio` transport)
- `Mono`/`Flux` imports in `src/main` on a server without the `webflux` transport → violation
- A class under `{toolsPackage}` importing `org.springframework.web.client` / `org.springframework.web.reactive.function.client` → violation (tools call the upstream client only)

#### `tool`
- Scope: `@Tool(`/`@ToolParam(` declarations under `{toolsPackage}`
- Tool names not matching `^[a-z][a-z0-9]*(_[a-z0-9]+)+$` or longer than 64 characters
- Descriptions missing the `<tool_scope>`/`<input>` blocks (unless the project convention says otherwise), or containing zero-width/control characters
- `@ToolParam` without a description
- Contract pairing: `git log -5 --name-only` commits touching `{contractSnapshot}` without `{contractChangelog}` → violation (when both are configured)

#### `security`
- Scope: `{toolsPackage}`, `security/`, `audit/`, `config/`, `src/main/resources/application*.yml`
- When `security != "none"`: a `@Tool` method without `@PreAuthorize` → violation
- A `@Tool` method without `@RateLimiter` → violation
- `readOnly: true` and `.put(`/`.patch(`/`.delete(` on an HTTP client in `src/main` → violation
- An inbound `Authorization` header read and set on an outbound request → violation
- Literal secret values or non-empty secret defaults in `application*.yml` → violation
- For judgment-heavy rows of `templates/mcp-security.md` (sanitizing coverage, masking coverage), point to `/backend-mcp-plugin:mcp-review --dimension security` rather than guessing here

#### `scope`
- Scope: `{toolsPackage}`, `client/`, `common/`, `config/` and `application*.yml`; the semantic judgment is `/backend-mcp-plugin:mcp-review --dimension scope`, this scan only surfaces candidates
- Arithmetic or rounding on upstream amounts (`.multiply(`, `.divide(`, `.setScale(`, `.subtract(`) in `{toolsPackage}` or `client/` → violation candidate (BL-1)
- `Collectors.summing`/`averaging`/`groupingBy`/`counting`, `.reduce(`, `.sum()` over result rows → violation candidate (BL-3)
- A `{toolsPackage}` class importing a persistence, scheduling or messaging type (`jakarta.persistence`, `org.springframework.jdbc`, `org.springframework.data`, `@Scheduled`, `KafkaTemplate`) → violation (BL-6)
- A package named `service`, `domain`, `rules`, `policy`, `calculator` or `repository` under the base package → violation (no home for business logic)
- More than one distinct `{Upstream}Client` method called in one `@Tool` method → violation candidate (BL-4)
- `readOnly: true` and a tool named `create_`/`update_`/`delete_`/`set_`/`cancel_`/`approve_`, or a mutating HTTP verb in `client/` → violation (BL-7)
- `@Tool` without `ToolAnnotations` on a `spec-list` server → violation (`templates/scope-rules.md` § 7 C2)

#### `upstream`
- Scope: the `client/` and `config/` packages and `application*.yml`
- No connect/read timeout property for the client → violation
- A retry configuration without an attempt cap, or one that retries on HTTP status → violation
- A shared circuit-breaker instance name used for different upstreams → violation

### Step 4: Report

```
Rule Recall: {section}
======================

{rules}

Violations ({scope}):
  {file}:{line} — {rule} — {what was found}
  … or "none found in {scope}" / "not verified: {reason}"
```
