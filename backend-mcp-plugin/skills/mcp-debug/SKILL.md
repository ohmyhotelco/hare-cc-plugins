---
name: mcp-debug
description: "Systematic debugging for an MCP server with a 4-phase methodology (reproduce, hypothesize, test, confirm): failing tests, build errors, tool-call errors (INVALID_INPUT, UPSTREAM_*), transport problems (stdio stream corruption, tools missing from tools/list), RBAC and cache surprises."
argument-hint: "<error-description or feature-name>"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(bash *scripts/detect-project.sh*), Bash(bash *scripts/pipeline-state.sh *), Bash(bash *scripts/run-gradle.sh *), Bash(rm -f *mcp-gradle.*), Bash(git status*), Bash(git diff *), Bash(git ls-files *), Agent
---

# Systematic Debugging

Diagnose and fix runtime errors, test failures, build issues, or transport problems using a structured 4-phase methodology. Usable at any point in the pipeline as an interrupt tool.

**Done when:** the Step 3 report is shown with evidence per tested hypothesis and the agent's outcome — `resolved` (regression suite and `{buildCommand}` exited 0), `escalated`, or no change; with feature context, `pipeline.status` is `resolved`/`escalated` with `pipeline.debug` written, or untouched for a no-change outcome; the lock is released.

## Instructions

### Step 0: Validate Configuration

1. `pluginRoot`: `${CLAUDE_PLUGIN_ROOT}` — Claude Code substitutes the plugin's install directory here when it loads this skill (the variable is not in the Bash environment, so always use this substituted value); not an absolute path (the substitution did not happen) → stop: this Claude Code version does not substitute plugin paths in skill content — upgrade Claude Code.
2. `config`: run `bash "{pluginRoot}/scripts/detect-project.sh"` (`{pluginRoot}/templates/configuration.md`). Exit 0 → its stdout JSON is `config`; show each `config.warnings` entry once. Any other exit → `config` is unavailable: warn that without it the debugger can diagnose and propose fixes but cannot run build/test verification (no `buildCommand`/`testCommand`), show the script's stderr, and continue.

### Step 1: Gather Problem Context

The argument can be:

- **Error description**: a pasted error, stack trace, MCP client error, or description
- **Feature name** (a single token matching `^[a-z0-9][a-z0-9-]*$` for which `{workDocDir}/{feature}.md` or `{workDocDir}/.progress/{feature}.json` exists — it builds progress- and lock-file paths; any other text is an error description): a tool's kebab-case name — resolve to its work document and source
- **No argument**: ask the user to describe the problem

Gather context:
1. Feature name: read the work document, recent test failures, build output
2. Error message: parse for file paths, line numbers, exception types, MCP error codes, tool names
3. Read the related source files
4. Check `{workDocDir}/.progress/{feature}.json` for pipeline state; not found → scan `{workDocDir}/.progress/*.json` (excluding `review-report-*`, `fix-report-*` and `audit-*`) for `specSource.feature == "{feature}"`, and when several tools match, ask which one

### Step 1.5: Acquire Lock

If config is available and feature context exists:

Acquire per `{pluginRoot}/templates/pipeline-protocol.md` § The Lock: `bash "{pluginRoot}/scripts/pipeline-state.sh" lock acquire "{workDocDir}" mcp-debug {feature}` — exit 0 → keep the printed `runId` for every later lock call and the agent; exit 75 → tell the user which operation holds the lock (stderr) and stop; any other exit → report it and stop. Never write, rewrite or delete the lock file by hand.

Why: a debugging session reverts and reapplies code across up to 3 hypotheses; the lock keeps another skill's read-modify-write of the same progress file from interleaving.

### Step 2: Launch Debugger Agent

**Subagent Isolation**: Pass only the specified parameters below. Do not include conversation history or user feedback from prior steps.

Launch the `debugger` agent (`subagent_type: "backend-mcp-plugin:debugger"` — qualified with this plugin's name). **Model**: the agent defaults to Sonnet; pass `model: "opus"` on the Agent call when `pipelineStatus` is `escalated` (a previous attempt already failed), or the problem is a concurrency, transport (stdio stream corruption) or security/RBAC behavior issue. Parameters:

- `problem`: the error description or context gathered
- `config`: parsed plugin config (if available)
- `projectRoot`: current project root
- `pluginRoot`: {pluginRoot}
- `runId`: {runId} (from the Step 1.5 acquire; omit when no lock was taken)
- `feature`: feature name (if provided)
- `pipelineStatus`: current pipeline status (if available)

**Constraints** (restated so this session recognizes a violation — `agents/debugger.md` § Constraints is authoritative):

- Maximum 3 hypotheses per session
- Revert each failed hypothesis fully before the next
- Never modify a test to make it pass, never update the contract snapshot, never add `@SuppressWarnings`/`@Disabled`
- Always run the full regression suite after a hypothesis succeeds

### Step 3: Display Debug Report

In the working language:

```
Debug Report
============

Classification: {type-error | test-failure | build-error | runtime-error | config-error | contract-drift | transport-error | upstream-error}

Root Cause:
  {file}:{line} — {description}

Hypotheses Tested:
  1. {hypothesis} — {SUCCESS | FAILED} — Evidence: {what was observed} — {file}:{line}
  2. {hypothesis} — {FAILED | not tested} — Evidence: {…} — {file}:{line}
  3. {hypothesis} — {FAILED | not tested} — Evidence: {…} — {file}:{line}

Fix Applied:
  {description}

Files Modified:
  {file}:{line-range} — {one-line description}

Verification:
  Compilation: {pass|fail}
  Tests: {pass|fail} ({count}/{total})
  Build: {pass|fail}
```

Every tested hypothesis carries evidence and a source location — a FAILED line with no evidence is a guess, not a result.

If escalated (all 3 failed):

```
Status: ESCALATED — Manual intervention required

Hypotheses tested (all failed):
  1. {hypothesis} — {why it failed} — Evidence: {…} — {file}:{line}
  2. …
  3. …

Suggested investigation:
  {guidance citing the most implicated {file}:{line} locations}
```

### Worked Example

Input: `mcp-debug "Claude Desktop shows 'MCP server disconnected' right after start (stdio)"`

```
Debug Report
============

Classification: transport-error

Root Cause:
  src/main/resources/logback-spring.xml:12 — the stdio profile's console appender writes to
  System.out, so the first INFO line interleaves with the JSON-RPC stream and the client drops
  the connection.

Hypotheses Tested:
  1. Log output on stdout corrupts the stdio stream — SUCCESS — Evidence: a stdio wiring test that
     starts the context with spring.ai.mcp.server.stdio=true and captures System.out saw a log line
     before the first JSON-RPC frame; after routing the console appender to System.err the captured
     stdout held only JSON-RPC — src/main/resources/logback-spring.xml:12
  2. (not tested — hypothesis 1 succeeded)
  3. (not tested — hypothesis 1 succeeded)

Fix Applied:
  The stdio profile's console appender targets System.err; banner-mode stays off.

Files Modified:
  src/main/resources/logback-spring.xml:10-14 — console appender target System.err under the stdio profile
  src/test/java/com/example/mcp/config/StdioStdoutHygieneTest.java — new regression test

Verification:
  Compilation: pass
  Tests: pass (215/215)
  Build: pass
```

### Step 4: Update Pipeline State

If config is available and feature context exists:

0. **No-change outcome** — the agent returned `not-reproduced`, or `resolved` with an empty `filesModified` (nothing in the tree changed): write nothing to the progress file — `pipeline.status` stays as it was — release the lock (item 6) and say "No code changed — pipeline status unchanged ({status})". Skip items 1–5 and Step 5's table
1. Read the progress file
2. Save the current `pipeline.status` as `previousStatus`
3. `pipeline.debug`:
   ```json
   {
     "status": "resolved",
     "previousStatus": "{status before debug}",
     "timestamp": "{ISO 8601}",
     "classification": "{error type}",
     "rootCause": "{description}",
     "filesModified": ["list"]
   }
   ```
   (`status` is `resolved` or `escalated`.)
4. `pipeline.status`: `"resolved"` or `"escalated"`
5. Write back (read-modify-write)
6. Release the lock — release with `bash "{pluginRoot}/scripts/pipeline-state.sh" lock release "{workDocDir}" mcp-debug {runId}` (`{pluginRoot}/templates/pipeline-protocol.md` § The Lock — it also removes a validated agent snapshot directory) — and do the same on every other exit after Step 1.5: the agent erroring or timing out, a no-change outcome (item 0), a refusal

### Step 5: Suggest Next Action

From `pipeline.debug.previousStatus`:

| `previousStatus` | Suggestion |
|-------------------|------------|
| `implementing` | Resume: `/backend-mcp-plugin:mcp-code {feature}` |
| `implemented`, `verify-failed` | `/backend-mcp-plugin:mcp-verify {feature}` |
| `verified`, `reviewed`, `done`, `review-failed`, `fixing`, `resolved` | Re-verify, then re-review — the fix changed code: `/backend-mcp-plugin:mcp-verify {feature}` then `mcp-review` |
| `escalated` | Review report exists → `/backend-mcp-plugin:mcp-fix {feature}`; otherwise `/backend-mcp-plugin:mcp-verify {feature}` |
| (unknown or missing) | `/backend-mcp-plugin:mcp-verify --fix` |

A `contract-drift` classification is never resolved here: the suggestion is `mcp-code` (a planned change) or `mcp-fix` (a review-driven change), which accept drift through the bounded procedure.
