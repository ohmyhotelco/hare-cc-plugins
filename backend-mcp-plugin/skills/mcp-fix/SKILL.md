---
name: mcp-fix
description: "Read an mcp-review report (or, with --report, a focused-audit report) and apply TDD-disciplined fixes via the review-fixer agent — behavioral fixes test-first, mechanical fixes directly, contract-changing fixes through the snapshot + changelog procedure. Closes the review-fix loop."
argument-hint: "[feature-name] | --report <audit-file>"
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(bash *scripts/detect-project.sh*), Bash(bash *scripts/pipeline-state.sh *), Bash(bash *scripts/run-gradle.sh *), Bash(rm -f *mcp-gradle.*), Bash(git status*), Bash(git diff *), Bash(git ls-files *), Agent
---

# Fix Review Issues

Read the review report produced by `mcp-review` (full review mode) — or a focused-audit report named with `--report` — and apply targeted fixes.

**Done when:** the fix report exists, parses, and its `issueId`s are exactly the input report's ids (Step 5), the lock is released, and — review report with a progress file — `pipeline.fix` is written and `pipeline.status` is `fixing` or `escalated` (an audit run changes no progress file).

## Role

`mcp-fix` is the fix-loop orchestrator between `mcp-review` and `mcp-commit`. It does not judge code quality itself — it reads an existing review verdict, delegates the fixing to the `review-fixer` agent, and reports only what that agent's output proves. Success KPI: every issue in the report reaches exactly one of `fixed`, `already-resolved`, or `escalated`, each backed by cited evidence — zero issues silently dropped.

## Constraints

- Never display Fixed/Escalated counts (Step 5) without first confirming the fix report exists, is well-formed, and accounts for exactly the review's issue ids
- Release the lock on every path with `bash "{pluginRoot}/scripts/pipeline-state.sh" lock release "{workDocDir}" mcp-fix {runId}` (`{pluginRoot}/templates/pipeline-protocol.md` § The Lock — it also removes a validated agent snapshot directory) — never by deleting the file
- Never leave `.progress/.lock` held past a failed or non-returning Step 4 agent call
- Never advance `pipeline.status` to `"reviewed"` or `"done"` from this skill — only `mcp-review` sets those; this skill leaves `"fixing"` or `"escalated"`
- Never re-run fixes past round 3 without explicit user confirmation (Step 3)
- Never treat `"done"` or `"reviewed"` as safe to overwrite silently (Step 2.5)
- Never fabricate or reword an escalation reason — display only what the agent returned
- A focused-audit report (`audit-*.json`) is an input only when named with `--report`, and then no progress file is read or written

## Instructions

### Step 0: Validate Configuration

1. `pluginRoot`: `${CLAUDE_PLUGIN_ROOT}` — Claude Code substitutes the plugin's install directory here when it loads this skill (the variable is not in the Bash environment, so always use this substituted value) — every `templates/…` path in this document is `{pluginRoot}/templates/…`; not an absolute path (the substitution did not happen) → stop: this Claude Code version does not substitute plugin paths in skill content — upgrade Claude Code.
2. `config`: run `bash "{pluginRoot}/scripts/detect-project.sh"` (`{pluginRoot}/templates/configuration.md`). Exit 0 → its stdout JSON is `config`; show each `config.warnings` entry once. Any other exit → show its stderr and stop (not a Spring AI MCP server Gradle project).

### Step 0.5: Parse Arguments and Resolve Feature

- **`--report <file>`** → `mode = audit`: the file must exist, resolve inside `{workDocDir}/.progress/`, and be named `audit-*.json` (else stop: "`--report` takes a focused-audit report, `{workDocDir}/.progress/audit-*.json`"). `feature = null`; `fixReportFile` = `{workDocDir}/.progress/fix-report-{the audit file name without .json}.json`. Skip the rest of this step
- **Feature argument** → `mode = review`. Validate it: `^[a-z0-9][a-z0-9-]*$` (it builds progress-, report- and lock-file paths), else stop. If `{workDocDir}/.progress/{feature}.json` does **not** exist:
  1. Scan `{workDocDir}/.progress/*.json` (excluding `review-report-*`, `fix-report-*` and `audit-*`) for `specSource.feature == "{feature}"`
  2. Matches → list the tools and ask the user to select one; set `feature` to its kebab-case name
  3. No match → proceed without a progress file
- **No argument** → `mode = review`, `feature = null` (no progress file)

### Step 1: Locate the Report

- `mode = audit`: `reportFile` = the `--report` file
- `mode = review`, `feature` set: `reportFile` = `{workDocDir}/.progress/review-report-{feature}.json`; `fixReportFile` = `{workDocDir}/.progress/fix-report-{feature}.json`
- `mode = review`, `feature = null`: `reportFile` = `review-report.json` at the project root; `fixReportFile` = `fix-report.json` at the project root

Not found:
> "No review report found at {reportFile}. Run `/backend-mcp-plugin:mcp-review {feature or a target}` first."

### Step 1.5: Entry-State Guard (`mode = review` with a progress file)

1. `pipeline.status` must be `review-failed`, `reviewed`, `done` or `escalated`. Anything else → stop, naming the status and the command to run first: `implementing`/`implemented` → finish and verify it (`mcp-code` / `mcp-verify`); `verified`, `verify-failed`, `fixing`, `resolved` → `/backend-mcp-plugin:mcp-verify {feature}` then `/backend-mcp-plugin:mcp-review {feature}` — the report on disk does not describe the current code
2. The review must postdate the last verification: `pipeline.review.timestamp` (fallback: the report's own `timestamp`) is later than `pipeline.verification.timestamp` (both `Z`-suffixed UTC, compared textually). Not later, or either missing → stop:
   > "The review report ({review timestamp}) predates the last verification ({verification timestamp}) — it describes older code. Run `/backend-mcp-plugin:mcp-review {feature}` first."

### Step 2: Analyze Report

1. Read the report
2. Count issues by severity
3. No issues → "No issues to fix." and **stop** — no lock, no agent, no demotion
4. Display:
   > "Review report found ({timestamp}): Critical {n}, Warning {n}, Suggestion {n}. Proceeding to fix {total} issues."

### Step 2.5: Demotion Check

`mode = review` and the progress file exists:

1. Read `pipeline.status`
2. `"done"`:
   > "This tool is currently 'done'. Running fixes will reset the status to 'fixing', discarding the completed state. Continue?"
   Decline → stop.
3. `"reviewed"`:
   > "This tool is currently 'reviewed'. Running fixes will reset the status to 'fixing' — you will need to re-verify and re-review before committing. Continue?"
   Decline → stop.

`"review-failed"` and `"escalated"` need no confirmation (`{pluginRoot}/templates/pipeline-protocol.md` § Demotion Warning).

### Step 3: Check Fix Round

`mode = review` and the progress file exists:

1. Read `pipeline.fix.round` (default 0)
2. Increment: `round + 1`
3. If round >= 3:
   > "This is fix round {round}. Multiple fix rounds may indicate a deeper issue. Continue anyway? (y/n)"
   Decline → stop.

### Step 3.5: Acquire Lock

Acquire per `{pluginRoot}/templates/pipeline-protocol.md` § The Lock: `bash "{pluginRoot}/scripts/pipeline-state.sh" lock acquire "{workDocDir}" mcp-fix {feature, omitted when null}` — exit 0 → keep the printed `runId` for every later lock call and the agent; exit 75 → tell the user which operation holds the lock (stderr) and stop; any other exit → report it and stop. Never write, rewrite or delete the lock file by hand.

### Step 4: Launch Review Fixer Agent

**Subagent Isolation**: Pass only the specified parameters below. Do not include conversation history or user feedback from prior steps.

Launch the `review-fixer` agent (`subagent_type: "backend-mcp-plugin:review-fixer"` — qualified with this plugin's name). **Model**: the agent defaults to Sonnet (most fixes are mechanical); pass `model: "opus"` on the Agent call when the report has any `critical` issue, any issue whose suggestion is marked as a contract change (snapshot + changelog), or `pipeline.fix.round` is already ≥ 1 (a previous round did not converge). Parameters:

- `reportFile`: the Step 1 report
- `fixReportFile`: the Step 0.5 / Step 1 fix-report path
- `config`: parsed plugin config
- `projectRoot`: current project root
- `pluginRoot`: {pluginRoot}
- `runId`: {runId} (from the Step 3.5 acquire — the agent refreshes the lock with it)
- `feature`: feature name (omit when null)

The agent classifies each issue (tdd-required, direct-fix, contract-fix, skip, escalated), applies fixes in severity order, runs the full build, and writes the fix report to `fixReportFile`. Its per-issue reasoning is in that file (`tddFixes[].implementation`, `directFixes[].change`, `contractFixes[].change`, `escalated[].reason`) — cite it when the user asks why.

**If the Agent call fails** (errors, times out, or returns no fix report path): release the lock immediately (release with `bash "{pluginRoot}/scripts/pipeline-state.sh" lock release "{workDocDir}" mcp-fix {runId}` (`{pluginRoot}/templates/pipeline-protocol.md` § The Lock — it also removes a validated agent snapshot directory)), report the failure with whatever partial output exists, and stop.

### Step 5: Display Fix Report

**Before displaying anything**: confirm the fix report exists at `fixReportFile`, parses, and its `issueId`s across `tddFixes[]`, `directFixes[]`, `contractFixes[]`, `alreadyResolved[]` and `escalated[]` are exactly the input report's ids (`{dimension key}-{index}` — the same envelope for a review and an audit) — each once, none missing, none invented — and `summary.total` equals their count. Otherwise state "Fix report incomplete/unverifiable — {reason}", **release the lock**, and stop without updating pipeline state.

```
Fix Report
==========

Round: {round}
Issues processed: {total}

Fixed: {count}
  TDD fixes: {tddCount} (test added → code fixed)
  Direct fixes: {directCount} (targeted edit)
  Contract fixes: {contractCount} (snapshot + changelog updated)
Already resolved: {count}
Escalated: {count}

Build after fixes: {PASS | FAIL}
```

Escalated issues:

```
Escalated (require manual intervention):
  [{severity}] {message}
    {file}:{line}
    Reason: {reason}
```

### Step 6: Update Pipeline State

`mode = review` and the progress file exists (an audit run skips this step — no pipeline status changes):

1. Read it
2. `pipeline.fix`:
   ```json
   {
     "status": "completed",
     "round": 1,
     "timestamp": "{ISO 8601}",
     "fixed": 5,
     "escalated": 1,
     "tddCount": 3,
     "directCount": 1,
     "contractCount": 1,
     "reportFile": "{fixReportFile}"
   }
   ```
   (`status`: `completed` — everything fixed; `partial` — some escalated; `failed` — all escalated or the build fails.)
3. `pipeline.status`: all fixed and build passes → `"fixing"`; some escalated → `"fixing"`; all escalated or build fails → `"escalated"`
4. Write back (read-modify-write)

Release the lock (always — it was taken in Step 3.5) — release with `bash "{pluginRoot}/scripts/pipeline-state.sh" lock release "{workDocDir}" mcp-fix {runId}` (`{pluginRoot}/templates/pipeline-protocol.md` § The Lock — it also removes a validated agent snapshot directory).

### Step 7: Suggest Next Action

- **All fixed, build passes**: "Fixes applied. Re-verify, then re-review — `mcp-review` admits only `verified`:" `/backend-mcp-plugin:mcp-verify {feature}` → `/backend-mcp-plugin:mcp-review {feature}`
- **Some escalated**: address them manually, then the same two commands
- **Build fails after fixes** (status `escalated`): `/backend-mcp-plugin:mcp-verify {feature} --fix` → `/backend-mcp-plugin:mcp-review {feature}`
- **Audit run**: no status changed, but the code did — a tool whose `verification.tree` no longer matches is refused by `mcp-review` and questioned by `mcp-commit`. Run `/backend-mcp-plugin:mcp-verify {tool}` for each tracked tool, then re-run the audit to confirm

## Error Handling

| Situation | Required behavior |
|---|---|
| `detect-project.sh` exits non-zero (Step 0) | Show its stderr, stop |
| No review report (Step 1) | Tell the user to run `mcp-review {feature}` first, stop |
| Status not a fix entry state, or the review predates the last verification (Step 1.5) | Name the status/timestamps and the command to run first, stop — no lock taken |
| Lock held < 30 min by another operation | Warn which operation holds it, stop |
| Lock held >= 30 min (stale) | Remove it, proceed, note it in the output |
| Agent errors / times out / no fix report | Release the lock, report the failure and partial output, stop |
| Fix report ids do not match the review | "fix report incomplete/unverifiable", release the lock, no Step 6 |
| Build fails after fixes | Status `escalated`, release the lock, point to `mcp-verify --fix` |

## Worked Example

Review report excerpt for `get-channel`:

```json
{
  "summary": { "critical": 1, "warning": 1, "suggestion": 0, "totalIssues": 2 },
  "dimensions": {
    "security": { "issues": [
      { "severity": "critical", "file": "src/main/java/.../ChannelTools.java", "line": 120,
        "message": "sellerCompName returned without sanitizing",
        "suggestion": "Route it through FreeText.clean like the other free-text fields" }
    ]},
    "tool_contract": { "issues": [
      { "severity": "warning", "file": "src/main/java/.../ChannelTools.java", "line": 95,
        "message": "Description says 'max 500' but EXCLUDE_MAX_LIMIT is 300",
        "suggestion": "Say 'max 300' (contract change: snapshot + changelog)" }
    ]}
  }
}
```

The agent classifies `security-0` as **tdd-required** (a test pins that a zero-width character in `sellerCompName` is stripped, then the fix) and `tool_contract-0` as **contract-fix** (the description edit, then the contract test shows drift of exactly `get_channel_exclude`'s description → snapshot updated, changelog entry added). Step 5 confirms the fix report's ids are exactly `security-0` and `tool_contract-0` and displays Fixed 2 (1 TDD, 1 contract). Step 6 sets `fixing`; Step 7 points to `mcp-verify` → `mcp-review`.

## Review-Fix Loop

```
mcp-review → FAIL → mcp-fix → mcp-verify → mcp-review → PASS → mcp-commit
               ↑                                │
               └────────────────────────────────┘ (if still failing)
```
