---
name: mcp-progress
description: "Show implementation status of MCP tools tracked in work documents: pipeline stage, scenario counts, verify/review/fix history, contract status, and the suggested next command. Trigger on: \"progress\", \"pipeline status\", \"tool status\", \"mcp-progress\", \"tiến độ\", \"trạng thái pipeline\", \"진행 상황\", \"파이프라인 상태\"."
argument-hint: "[feature-name]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash(bash *scripts/detect-project.sh*), Bash(date *)
---

# Implementation Progress Dashboard

Show the implementation progress of MCP tools tracked in work documents.

**Done when:** the dashboard lists every work document under `{workDocDir}` (and every planned tool without one) with its grep-counted scenarios and its progress-file status (`parse-error`/`—` where it cannot be read), each with its Step 4 next command — or the Step 1.5/1.6 stop message is shown. Read-only: no file is written.

## Instructions

### Step 0: Validate Configuration

1. `pluginRoot`: `${CLAUDE_PLUGIN_ROOT}` — Claude Code substitutes the plugin's install directory here when it loads this skill (the variable is not in the Bash environment, so always use this substituted value); not an absolute path (the substitution did not happen) → stop: this Claude Code version does not substitute plugin paths in skill content — upgrade Claude Code.
2. `config`: run `bash "{pluginRoot}/scripts/detect-project.sh"` (`{pluginRoot}/templates/configuration.md`). Exit 0 → its stdout JSON is `config`. Any other exit → show its stderr and stop.

### Step 1: Determine Scope

- Argument provided: the specific tool (kebab-case feature) or planned feature — it must match `^[a-z0-9][a-z0-9-]*$` (it builds file paths), else stop
- No argument: every tool, plus (Step 2) planned tools that have no work document yet

### Step 1.5: Resolve Feature

If an argument was provided and neither `{workDocDir}/.progress/{feature}.json` nor `{workDocDir}/{feature}.md` exists:

1. Scan `{workDocDir}/.progress/*.json` (excluding `review-report-*`, `fix-report-*`, `audit-*`) for `specSource.feature == "{feature}"`
2. Matches → show all matched tools (Summary View filtered to them)
3. No match, but `docs/specs/{feature}/.implementation/mcp/plan.json` exists → show its tools as `Planned — not started` and suggest `/backend-mcp-plugin:mcp-code {feature}`; stop
4. No match → report `No tool or feature matches "{feature}". Checked: {workDocDir}/.progress/{feature}.json, {workDocDir}/{feature}.md, and specSource.feature across {workDocDir}/.progress/*.json.` and stop

### Step 1.6: Error Handling

Never guess a status to fill a gap:

- **Malformed progress file**: show `parse-error`, do not skip the row
- **No work documents**: glob `docs/specs/*/.implementation/mcp/plan.json`. Plans found → list each planned feature (the directory name) with its tool names and `Planned — not started`, and suggest `/backend-mcp-plugin:mcp-code {feature}` for each; none → `No tools found — run /backend-mcp-plugin:mcp-code <tool_name> to specify one.` Stop either way
- **`pipeline.status` absent**: show `—` (not started)

### Step 2: Scan Work Documents

Glob `{workDocDir}/*.md` — never rely on memory of a prior run. For each file:

1. Feature name from the filename; the tool name from the document's `# {tool_name}` heading
2. Grep counts: `- \[x\]` (case-insensitive) and `- \[ \]` — **the authoritative scenario count** (the progress file's `pipeline.scenarios` is a snapshot that can lag)
3. Read `{workDocDir}/.progress/{feature}.json` for pipeline state (Step 1.6 rules)

Then glob `docs/specs/*/.implementation/mcp/plan.json`: every planned `tools[].name` whose kebab-case work document does not exist is a row with Pipeline `planned` and scenarios `—` (suggestion: `/backend-mcp-plugin:mcp-code {plan feature}`).

### Step 3: Display Dashboard

In the working language.

#### Summary View (no argument)

```
MCP Tool Progress
=================

Tool                      Class           Pipeline       Scenarios  Verify  Contract  Review   Fix
────────────────────────  ──────────────  ─────────────  ─────────  ──────  ────────  ───────  ───
get_hotel_bookings        BookingTools    done           9/9        PASS    PASS      9.1/10   —
get_channel_qps           ChannelTools    review-failed  6/6        PASS    PASS      6.4/10   R1
get_settlement            SettlementTools implementing   3/8        —       —         —        —

Total: 18/23 scenarios completed
Pipeline legend: implementing → implemented → verified → reviewed → done
```

`Contract` is `pipeline.verification.contract.status` (`SKIP` when no snapshot gate is configured).

#### Detail View (argument)

**Staleness check**: the work document's mtime (`date -u -r {workDocDir}/{feature}.md +%Y-%m-%dT%H:%M:%S`) against the first 19 characters of a `Z`-suffixed top-level `updatedAt`. Newer → "Warning: work document modified after the last pipeline update. Run `/backend-mcp-plugin:mcp-code {workDoc}` to pick up new scenarios." Check impossible → `Staleness check: not verified`.

```
Tool: {tool_name} ({toolClass})
Pipeline: {status}
Scenarios: {completed}/{total} ({percentage}%)

Pipeline History:
  Verification: {PASS|FAIL|—}  {timestamp}
    compilation, tests {passed}/{total}, contract {status} (snapshot changed: {y/n}, changelog: {y/n})
    tree: {first 12 chars}{, committed}
  Review:       {PASS|FAIL|—}  {timestamp}  Score {score}/10 | Critical {n} | Total {n}
  Fix:          {round} round(s)  {timestamp}  Fixed {n} | Escalated {n}
  Debug:        {resolved|escalated|—}  (was: {previousStatus|—})

Completed Scenarios:
  [x] …
Remaining Scenarios:
  [ ] …

Spec Source: {specSource.feature}/{specSource.tool} → {specSource.planFile} (or "—")
Work document: {workDocDir}/{feature}.md
Progress file: {workDocDir}/.progress/{feature}.json
```

### Step 4: Suggest Next Action

| Pipeline Status | Suggestion |
|----------------|------------|
| `implementing` | `/backend-mcp-plugin:mcp-code {workDocDir}/{feature}.md` (resume) |
| `implemented` | `/backend-mcp-plugin:mcp-verify {feature}` |
| `verified` | `/backend-mcp-plugin:mcp-review {feature}` |
| `verify-failed` | `/backend-mcp-plugin:mcp-verify {feature} --fix` |
| `reviewed` | `/backend-mcp-plugin:mcp-fix {feature}` (optional) or `/backend-mcp-plugin:mcp-commit` |
| `review-failed` | `/backend-mcp-plugin:mcp-fix {feature}` |
| `fixing` | `/backend-mcp-plugin:mcp-verify {feature}` then `mcp-review` |
| `done` | `/backend-mcp-plugin:mcp-commit` |
| `resolved` | `/backend-mcp-plugin:mcp-verify {feature}` (`pipeline.debug`/`pipeline.build` `previousStatus` says how far it had got) |
| `escalated` | Manual intervention, then `/backend-mcp-plugin:mcp-debug {feature}` |
| (no progress file) | `/backend-mcp-plugin:mcp-code {workDocDir}/{feature}.md` |
| `planned` (plan entry, no work document) | `/backend-mcp-plugin:mcp-code {plan feature}` |
| `parse-error` | Show the offending file path and ask the user to repair it — no pipeline command until it parses |
