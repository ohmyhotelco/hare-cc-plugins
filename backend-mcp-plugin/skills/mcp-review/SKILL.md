---
name: mcp-review
description: "Review an MCP server via the code-reviewer agent across 8 dimensions — tool contract & descriptions, upstream integration, security (OWASP MCP Top 10: tool poisoning, prompt injection via output, excessive scope, token passthrough, data exfiltration, RBAC, audit), clean code, logging & audit, test quality, architecture, scope (data retrieval only: business logic in the server is critical) — plus spec compliance when a plan exists; produces a structured report mcp-fix consumes. With --dimension <key> it runs one dimension as a standalone focused audit that touches no pipeline state."
argument-hint: "<feature-name or target-path> [--dimension tool_contract|upstream_integration|security|clean_code|logging|test_quality|architecture|scope] [--full] [--yes]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash(bash *scripts/detect-project.sh*), Bash(bash *scripts/pipeline-state.sh *), Bash(bash *scripts/review-scope.sh *), Bash(bash *scripts/source-tree-hash.sh*), Bash(git status*), Bash(git diff *), Bash(git ls-files *), Bash(date *), Agent
---

# MCP Server Review

Launch the `code-reviewer` agent for a full review (8 core dimensions + optional spec compliance) that gates the pipeline, or for a focused single-dimension audit that does not.

**Done when:** the validated report is saved (`review-report-{feature}.json` or `audit-{key}-{scope}.json`) with `summary.verdict` PASS or FAIL, and — full review with a progress file — `pipeline.review` is written (with its `scope` and the review manifest) and `pipeline.status` is `done`, `reviewed` or `review-failed`, with the lock released.

| Mode | Trigger | Requires `verified` | Lock | Report file | Pipeline state |
|------|---------|---------------------|------|-------------|----------------|
| **Full review** | no `--dimension` | yes (feature argument) | yes (feature argument) | `review-report-{feature}.json` | updated |
| **Focused audit** | `--dimension <key>` | no | no | `audit-{key}-{scope}.json` (`{scope}`: the feature, a slug of the target path, or `project`) | untouched |

A full review of a feature runs in one of two **scopes** (Step 2.8): `full` — every file of the target, every dimension — or `delta` — after an `mcp-fix` round, only the files changed since the last review, and only the dimensions that can have moved. A delta review never sets `done`: only a `full` review with zero issues does.

## Instructions

### Step 0: Validate Configuration

1. `pluginRoot`: `${CLAUDE_PLUGIN_ROOT}` — Claude Code substitutes the plugin's install directory here when it loads this skill (the variable is not in the Bash environment, so always use this substituted value) — every `templates/…` and `scripts/…` path in this document is under `{pluginRoot}`; not an absolute path (the substitution did not happen) → stop: this Claude Code version does not substitute plugin paths in skill content — upgrade Claude Code.
2. `config`: run `bash "{pluginRoot}/scripts/detect-project.sh"` (`{pluginRoot}/templates/configuration.md`). Exit 0 → its stdout JSON is `config`; show each `config.warnings` entry once. Any other exit → show its stderr and stop (not a Spring AI MCP server Gradle project).

### Step 1: Determine Mode and Target

Strip a trailing `--yes` (answers the Step 2 re-review confirmation, and the Step 2.5 staleness prompt only while the work document has no `- [ ]` left). Strip `--full` (forces Step 2.8 to choose `full`). Strip `--dimension <key>`: the key must be one of `tool_contract`, `upstream_integration`, `security`, `clean_code`, `logging`, `test_quality`, `architecture`, `scope` — anything else → stop and list the valid keys. Present → **focused audit**; absent → **full review**.

The remaining argument:

- **Feature name** (no `/` and no `.java` suffix: a tool's kebab-case name, or a planned feature) — must match `^[a-z0-9][a-z0-9-]*$` (it builds progress-file and report paths; anything else → stop). The review target is the **whole** `{sourceDir}/{basePackage}/` (`.` → `/`) — a tool's behavior is spread across `tools/`, `client/`, `config/`, `security/` and `audit/`, and a review of the tool class alone would miss the registration, the limiter and the client it relies on. The feature's work document names the tool under review for `refs`
- **Directory or file path** (contains `/` or ends in `.java`): must exist inside the project (else `Path not found: {path}` and stop); used directly. For a focused audit, `{scope}` = the path lowercased, every run of characters outside `[a-z0-9]` replaced by `-`, leading/trailing `-` trimmed (`src/main/java/com/example/mcp/tools` → `src-main-java-com-example-mcp-tools`)
- **No argument**: the whole base package. Count the `.java` files first; above ~60, tell the user the count, list the top-level packages, and ask them to pick one or confirm the full review

### Step 1.5: Resolve Feature

**Focused audit**: skip this step and Steps 2–2.7 — continue directly at Step 3 (no tool selection, no pipeline check, no lock, no spec context).

Full review: if a feature name was provided and `{workDocDir}/.progress/{feature}.json` does **not** exist:

1. Scan `{workDocDir}/.progress/*.json` (excluding `review-report-*`, `fix-report-*` and `audit-*`) for `specSource.feature == "{feature}"`
2. Matches (several tools of one planned feature) → list them and ask which one, or the whole planned feature; a tool → set `feature` to its kebab-case name; the whole feature → proceed without pipeline context (no status change, no `targetTool`: spec compliance covers every planned tool)
3. No match → proceed without pipeline context

### Step 2: Check Pipeline State (full review)

If a feature name was provided and its progress file exists:

1. Read the progress file
2. `pipeline.status`:
   - `"implementing"` or `"implemented"`: **stop** — `mcp-verify` has not passed; a PASS here would set `done` on unverified code. Run `/backend-mcp-plugin:mcp-verify {feature}` first
   - `"verified"`: proceed
   - `"verify-failed"`: **stop** — the gate failed; run `/backend-mcp-plugin:mcp-verify {feature} --fix` first
   - `"fixing"` or `"resolved"`: **stop** — the code changed after the last verification; run `/backend-mcp-plugin:mcp-verify {feature}` first
   - `"escalated"`: **stop** — resolve it, then `mcp-verify` re-admits the tool
   - `"review-failed"`: proceed (re-reviewing unchanged code is allowed)
   - `"reviewed"` or `"done"`: warn this re-runs the review; ask to confirm
3. On every proceed path, compare the tree: `bash {pluginRoot}/scripts/source-tree-hash.sh` (exit 0 and a 40-hex id, else a tooling error — stop) must equal `pipeline.verification.tree`. Different, or the field missing: **stop** — the code changed since `mcp-verify` ran; run `/backend-mcp-plugin:mcp-verify {feature}` first

### Step 2.5: Work Document Staleness Check (full review)

If a feature name was provided and its progress file exists: compare the work document's mtime (`date -u -r … +%Y-%m-%dT%H:%M:%S`) with the first 19 characters of a `Z`-suffixed `updatedAt`, exactly as `mcp-verify` Step 0.6 does. Newer →
> "Warning: the work document has been modified since the last pipeline update ({updatedAt}). Continue with review anyway?"
Decline → stop. Under `--yes`: proceed only when the work document has no `- [ ]` left.

### Step 2.6: Acquire Lock (full review with a feature)

Acquire per `{pluginRoot}/templates/pipeline-protocol.md` § The Lock: `bash "{pluginRoot}/scripts/pipeline-state.sh" lock acquire "{workDocDir}" mcp-review {feature}` — exit 0 → keep the printed `runId` for every later lock call and the agent; exit 75 → tell the user which operation holds the lock (stderr) and stop; any other exit → report it and stop. Never write, rewrite or delete the lock file by hand.

No feature name: skip lock acquisition.

### Step 2.7: Check Spec Context (full review)

If a feature name was provided:

1. `specSource.planFile` in the progress file, or `docs/specs/{feature}/.implementation/mcp/plan.json` directly → `specAvailable = true`, `planFile` = that path
2. `specDir`: from the plan's own `specDir` field (a planning-plugin spec directory, or the source document)
3. `targetTool`: the progress file's `specSource.tool` when present — the one planned tool this review covers; absent (a whole planned feature reviewed by its plan name, with no single tool's progress file) → no `targetTool`, and spec compliance checks every planned tool
4. Neither plan source → `specAvailable = false`

### Step 2.8: Choose the Review Scope (full review with a feature)

**Review paths** (`{reviewPaths}`) — the same file set `agents/code-reviewer.md` Phase 0 item 4 reviews, as paths relative to the project root: the target directory, its matching `{testDir}` directory, and — base-package target — `{moduleDir}/src/main/resources` plus `config.contractSnapshot` / `config.contractChangelog` when set. `{manifestFile}` = `{workDocDir}/.progress/review-manifest-{feature}.txt`.

`scope = delta` only when **all** hold — otherwise `scope = full`:

1. `--full` was not given, and a feature with a progress file is being reviewed
2. `pipeline.review` exists with `scope` set, and `pipeline.fix.round` ≥ 1 (an `mcp-fix` round ran since a review) — a first review is always full
3. the previous report `pipeline.review.reportFile` exists and parses, and `{manifestFile}` exists
4. `bash "{pluginRoot}/scripts/review-scope.sh" changed "{manifestFile}" {reviewPaths}` exits 0. Its lines (`M`/`A`/`D` + path) are `{changes}`; `{changedFiles}` = the `M`/`A` paths. More than 15 changed files → `full` (a delta that large saves little and loses the cross-file view)

For `delta`, resolve `{deltaDimensions}`: every dimension with at least one issue in the previous report; plus `security` and `scope` always (the highest-blast-radius dimension and the one a fix is most likely to break — a fixer relocating logic — are never skipped); plus `test_quality` when a changed file is under `{testDir}`; plus `tool_contract` when a changed file is `config.contractSnapshot` or a `*Tools.java`; plus `architecture` when a file was added or deleted. `spec_compliance` only when it is in the previous report and had issues.

`{changes}` empty (nothing changed since the last review — a re-run on the same code): skip the agent. Re-save nothing; take the previous report's verdict for Step 6 exactly as it is (same `scope`), tell the user the review is unchanged since `{previous timestamp}`, release the lock, and stop after Step 7.

Only `D` lines (files deleted, nothing modified or added): skip the agent; Step 3.6 merges with an empty result for `{deltaDimensions}` (the deleted files' issues drop out) — still a delta, still never `done`.

Tell the user the scope chosen and why: `Scope: delta — {n} changed files, dimensions {list} (run with --full for a complete review)` or `Scope: full`.

### Step 3: Launch Code Reviewer Agent

**Subagent Isolation**: Pass only the specified parameters below. Do not include conversation history or user feedback from prior steps.

Launch the `code-reviewer` agent (`subagent_type: "backend-mcp-plugin:code-reviewer"` — qualified with this plugin's name) with:

- `targetPath`: the resolved target path
- `config`: parsed plugin config
- `projectRoot`: current project root
- `pluginRoot`: {pluginRoot}
- `dimensions`: `[{key}]` for a focused audit; omit it for a full review
- `planFile`: path to plan.json (full review with `specAvailable` only; omit otherwise)
- `specDir`: the plan's source path (full review with `specAvailable` only; omit otherwise)
- `targetTool`: from Step 2.7 (full review with `specAvailable` and a `targetTool` only; omit otherwise) — scopes spec compliance to that tool, so tools of the same plan not yet built are not reported as missing
- `changedFiles`, `baselineReport`: **delta scope only** — `{changedFiles}` and the previous report path; with them `dimensions` is `{deltaDimensions}`

`agents/code-reviewer.md` Phase 1 is the single source of truth for each dimension's checks — do not restate or extend them here. The keys, for orchestration only: `tool_contract`, `upstream_integration`, `security`, `clean_code`, `logging`, `test_quality`, `architecture`, `scope`, and `spec_compliance`.

### Step 3.5: Validate Agent Output

Do not trust the response as complete just because it returned. Check:

1. **Dimension set** — full review: exactly the 8 core keys, plus `spec_compliance` iff `specAvailable`; delta scope: exactly `{deltaDimensions}`; focused audit: exactly `[{key}]`. A missing or extra key fails validation
2. **Numeric consistency** — `summary.totalIssues` equals the total entries across every `issues[]`; `summary.critical`/`warning`/`suggestion` match the actual severities
3. **Score and verdict** — recompute `overallScore` as the mean of the scores present, rounded to 1 decimal; a dimension below 7 carries at least one issue; recompute the verdict (all ≥ 7 and zero critical → PASS) and compare
4. **Agent failure** — errored, empty, or visibly truncated output (unterminated JSON) fails validation
5. **Coverage** — delta scope: `filesReviewed` equals the number of `{changedFiles}` (every one exists). Otherwise `filesReviewed` > 0 and equal to the count you compute yourself with the rule in `agents/code-reviewer.md` Phase 0 item 4: `.java` files under the target + `.java` files under the matching `{testDir}` path + (base-package target only) `src/main/resources/application*.yml`/`application*.properties` and the configured contract snapshot and changelog files that exist; `target` equals the Step 1 path
6. **Issue completeness** — every issue has non-empty `file`, `line`, `suggestion`

Any check fails — or writing the report (Step 4) or the progress file (Step 6) fails: do not leave a partial report, release the lock if one was taken, report exactly which check failed (name the check and the offending field/dimension), and stop.

### Step 3.6: Merge a Delta Review (delta scope only)

The agent judged only `{changedFiles}`; the saved report must still describe the whole target. Build it from the previous report (`baselineReport`):

1. Every dimension **not** in `{deltaDimensions}`: copied unchanged (score and issues) — it had no issues and the changed files could not move it
2. Every dimension in `{deltaDimensions}`: issues = the previous issues of that dimension whose `file` is **not** in `{changes}` (untouched files keep their findings) + the agent's issues. Score = the agent's score when no previous issue was carried over, otherwise the lower of the agent's score and the previous score
3. `filesReviewed` = the previous report's value; add `"scope": "delta"`, `"changedFiles": [...]` and `"baseline": "{previous report timestamp}"` to the envelope
4. Recompute `summary` (counts, `overallScore` as the mean, verdict) with the Step 3.5 rules

A full-scope report carries `"scope": "full"`.

### Step 4: Save Report

- **Full review**: `{workDocDir}/.progress/review-report-{feature}.json` (`review-report.json` at the project root when there is no feature context)
- **Focused audit**: `{workDocDir}/.progress/audit-{key}-{scope}.json` (`{scope}` per Step 1: the feature, the path slug, or `project`) — a record for the user; never a pipeline input, and read by `mcp-fix` only when named explicitly with `--report`

The envelope is the agent's JSON as validated (`agents/code-reviewer.md` § Output Format).

**Verdict rules**: PASS — all evaluated dimensions >= 7 and no critical issues; FAIL — any dimension < 7 or any critical issue.

### Step 5: Display Report

In the working language:

```
{MCP Server Review | Focused Audit: {key}}
==========================================

Target: {targetPath}
Files reviewed: {count}

Dimension Scores:
  Tool Contract:         {score}/10
  Upstream Integration:  {score}/10
  Security:              {score}/10
  Clean Code:            {score}/10
  Logging & Audit:       {score}/10
  Test Quality:          {score}/10
  Architecture:          {score}/10
  Scope (data only):     {score}/10
  Spec Compliance:       {score}/10  (only when spec context exists)

Overall: {score}/10 — {PASS | FAIL}

Issues ({total}): Critical {n} | Warning {n} | Suggestion {n}

{For each issue, sorted by severity:}
  [{severity}] {message}
    {file}:{line} — Fix: {suggestion}
    Refs: {refs (if present)}

Notes: {notes, if any}
```

A focused audit shows only its one dimension. A clean result still prints the Target / Files reviewed / Overall block — that is the evidence the review ran over the stated scope.

### Step 6: Update Pipeline State (full review whose feature has a progress file only)

1. Read the progress file
2. `pipeline.review`:
   ```json
   {
     "status": "pass",
     "timestamp": "{ISO 8601}",
     "overallScore": 8.6,
     "criticalIssues": 0,
     "totalIssues": 3,
     "reportFile": "{path to review-report-{feature}.json}",
     "scope": "full",
     "manifest": "{manifestFile}"
   }
   ```
   (`status` is `pass` or `fail`; `scope` is `full` or `delta`.)
3. `pipeline.status`: **full** scope — PASS with 0 issues → `"done"`; PASS with warnings/suggestions → `"reviewed"`; FAIL → `"review-failed"`. **Delta** scope — PASS (with or without issues) → `"reviewed"`, never `done`; FAIL → `"review-failed"`
4. Fix round counter: reset `pipeline.fix.round` to `0` **only** on a PASS with zero issues (`done`) — otherwise `mcp-fix`'s round-3 guard could never trigger inside a review ↔ fix loop
5. Write back (read-modify-write)
6. Record what this review saw, for the next delta: `bash "{pluginRoot}/scripts/review-scope.sh" manifest "{manifestFile}" {reviewPaths}` (exit ≠ 0 → drop `manifest` from `pipeline.review`, so the next review is full)

Release the lock if one was taken in Step 2.6 — release with `bash "{pluginRoot}/scripts/pipeline-state.sh" lock release "{workDocDir}" mcp-review {runId}` (`{pluginRoot}/templates/pipeline-protocol.md` § The Lock — it also removes a validated agent snapshot directory).

### Step 7: Suggest Next Action

- **Full review, PASS with no issues**: stage the changes (`git add`), then `/backend-mcp-plugin:mcp-commit`
- **Delta review, PASS**: `/backend-mcp-plugin:mcp-review {feature} --full` for the final full review (the only way to `done`), or commit as `reviewed`
- **Full review, PASS with warnings/suggestions**: `/backend-mcp-plugin:mcp-fix {feature}` to clean up, or commit
- **Full review, FAIL**: `/backend-mcp-plugin:mcp-fix {feature}`, then `mcp-verify` → `mcp-review`
- **Focused audit with findings**: `/backend-mcp-plugin:mcp-fix --report {audit file path}` fixes them without touching any tool's pipeline status (afterwards, re-verify the affected tools); or `mcp-code` for a change to a tool's specified behavior

## Worked Examples

**Example 1 — full review, spec context**

`/backend-mcp-plugin:mcp-review get-hotel-bookings`: status `verified`, tree matches → lock taken; the plan exists → `specAvailable`, `targetTool = get_hotel_bookings` (the plan's other two tools are not built yet and are not reported). The agent reviews `src/main/java/com/example/mcp/` with 9 dimensions; validation passes (9 keys, counts consistent, `filesReviewed` 61 = 38 main + 20 test + `application.yml` + snapshot + changelog). Security finds one warning (a tool without `@RateLimiter`), Tool Contract one suggestion. Verdict PASS → status `reviewed`; lock released; suggests `mcp-fix` or commit.

**Example 2 — focused security audit**

`/backend-mcp-plugin:mcp-review src/main/java/com/example/mcp/tools --dimension security`: no pipeline check, no lock. The agent applies the OWASP MCP checklist with candidate discipline to the tools package and its tests; it finds `ChannelTools.java:120` returning `sellerCompName` unsanitized (critical). The report is saved as `audit-security-src-main-java-com-example-mcp-tools.json`; no progress file changes.

**Example 4 — delta re-review after a fix**

Round 1 (full) failed: 1 critical in Security, 2 warnings in Test Quality. `mcp-fix` (round 1) changed `BookingTools.java` and `BookingToolsTest.java`; `mcp-verify` passed. `/backend-mcp-plugin:mcp-review get-hotel-bookings` → Step 2.8: `fix.round` 1, manifest present, 2 files changed → `scope = delta`, dimensions `security`, `scope`, `test_quality`, `tool_contract` (a `*Tools.java` changed). The agent reads 2 files instead of 61. Merge: the 4 untouched dimensions are copied, the 4 re-judged ones take the agent's issues; verdict PASS with 0 issues → status `reviewed` (not `done`), and Step 7 suggests `--full` for the final pass.

**Example 3 — validation failure**

The agent's JSON omits `logging`. Check 1 fails; nothing is saved; the lock is released; the user is told which key was missing and to re-run with a narrower target if the agent was truncated. The status stays `verified`.
