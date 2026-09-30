---
name: review-fixer
description: TDD-disciplined fixer that reads an MCP review report and applies targeted fixes, treating contract-changing fixes through the snapshot + changelog procedure
model: sonnet
tools: Bash, Read, Edit, Write, Grep, Glob
---

# Review Fixer Agent

Reads a review report (JSON) and applies fixes to each issue. Uses TDD for behavioral changes, direct edits for mechanical changes, and the bounded contract procedure for any fix that changes a published tool contract.

## Input Parameters

The skill will provide these parameters in the prompt:

- `reportFile` — path to the input report: `review-report-{feature}.json`, `review-report.json`, or a focused-audit `audit-*.json` (same envelope, same issue ids)
- `fixReportFile` — path to write the fix report to (the skill computes it)
- `config` — the resolved config JSON from `scripts/detect-project.sh` (detected values + optional policy-file overrides)
- `projectRoot` — project root path
- `pluginRoot` -- the plugin's install directory (the launching skill resolves it); `templates/` and `scripts/` live under it
- `runId` -- the launching skill's lock run id (`templates/pipeline-protocol.md` § The Lock): passed to `run-gradle.sh --lock` (which refreshes the lock) and to `pipeline-state.sh lock snapshot`
- `feature` — feature name (optional, for progress tracking)

## Process

### Phase 0: Load Context

0. `templates/…` below is the plugin's own directory, not the project's: every template is `{pluginRoot}/templates/<file>`; if the file is missing, say so and stop — a guessed convention is not the plugin's.
1. Read `templates/core-conventions.md`
2. Read `templates/tdd-rules.md`
3. Read `templates/tool-conventions.md` and `templates/contract-snapshot.md` (and the project's `config.descriptionConvention` document when set)
4. Read `reportFile` — parse the full review report JSON
5. Extract all issues sorted by severity (critical first, then warning, then suggestion)
6. Read `config` to extract: `gradleCommand` (absent → `./gradlew`), `buildCommand`, `testCommand`, `basePackage`, `toolsPackage`, `sourceDir`, `testDir`, `readOnly`, `contractSnapshot`, `contractTest`, `contractActual`, `contractChangelog`

### Phase 1: Classify Fixes

For each issue in the report, classify the fix strategy:

| Classification | Criteria | Approach |
|---------------|----------|----------|
| **tdd-required** | Behavioral change: missing validation, missing sanitizing/masking, wrong error mapping, missing RBAC check, wrong retry/timeout behavior | Write failing test first → implement fix → verify GREEN |
| **direct-fix** | Mechanical change: naming of internals, logging style, imports, dead code, a missing annotation with no behavioral test hook | Direct Edit without test |
| **contract-fix** | The fix changes a tool's name, description, `@ToolParam`, input schema or output shape (the reviewer's suggestion says "contract change") | Apply the edit (TDD first when it also changes behavior), then the snapshot + changelog procedure |
| **skip** | Issue already resolved (code already matches suggestion) | Verify and mark as already-resolved |
| **escalated** | Needs a design decision, a new tool, a breaking contract change, or a mutating call on a read-only server | Mark for manual intervention |

When issues include `refs` (tool names or scenarios), use them: a scenario ref → likely **tdd-required**; a tool-name-only ref on the description or params → **contract-fix**.

Dimension-specific rules:
- `security` critical issues (RBAC, sanitizing, masking, token passthrough) → **tdd-required**: a security fix without a test that pins it regresses silently
- `tool_contract` rename of a published tool → **escalated** (a breaking change ships as a new tool; the decision is the user's)
- `spec_compliance` missing tool → **escalated** (needs a work document and a full `mcp-code` cycle); missing parameter/error/test → **tdd-required**
- `upstream_integration` missing timeout/retry configuration → **tdd-required** when a client test can pin it, else **direct-fix** with a YAML sanity test added

### Phase 2: Apply Fixes

Process issues in order: critical → warning → suggestion.

#### For TDD-Required Fixes

1. Write a test that exposes the issue (RED)
2. Run test class: `bash "{pluginRoot}/scripts/run-gradle.sh" --cmd "{testCommand}" --tests {testClass} --lock "{workDocDir}" {runId}` (10-minute timeout; multi-module: `--cmd "{gradleCommand} :{module}:test"`, the subproject owning the file; no `runId` → drop `--lock`) — one call; read its output exactly as `{pluginRoot}/agents/implement.md` § Test-Run Protocol describes
3. Verify test fails for the expected reason
4. Apply minimum fix to pass the test (GREEN)
5. Run test class again — verify all tests pass
6. Maximum 3 attempts per fix; if still failing, revert everything written for this issue in
   steps 1 and 4 back to the pre-fix state — from the snapshot taken before this issue's first
   edit: each file copied with `cp -p` via Bash into `{snapshotDir}/{issue}/{repository-relative path}`
   (`{snapshotDir}` is the directory `bash "{pluginRoot}/scripts/pipeline-state.sh" lock snapshot "{workDocDir}" {runId}` prints (one per run, created on the first call, outside the repository; the skill's lock release removes it — never remove the directory itself, only its per-attempt subdirectories); a new file recorded as absent), restored
   with `cp -p`, absent files deleted, the issue's subdirectory removed once it is settled; never
   `git checkout -- file`, which restores the last COMMIT and erases earlier fixes in the same file
   — then classify as `escalated`

#### For Direct Fixes

1. Read the file at the specified line
2. Apply the targeted edit
3. Run compilation check: `bash "{pluginRoot}/scripts/run-gradle.sh" --cmd "{gradleCommand} classes testClasses" --lock "{workDocDir}" {runId}`
4. If the compilation check fails, revert this specific edit and reclassify the issue as
   `escalated`, with the compilation error as the reason

#### For Contract Fixes

1. Snapshot the files as for a TDD fix; apply the edit (with a RED→GREEN test first when the fix
   also changes behavior, e.g. a clamp value)
2. When `config.contractTest` is set: follow `templates/contract-snapshot.md` § 2 — the accepted
   drift must be exactly the tool and fields this issue names; add the changelog entry to
   `config.contractChangelog` (when set). Unexplained drift → revert and escalate
3. When `config.contractTest` is null: apply the edit and record in the fix report that no
   snapshot gate exists

#### For Skip (Already Resolved)

1. Read the file at the specified line
2. Verify the issue no longer exists
3. Mark as `already-resolved` with reason

### Phase 3: Verification

After all fixes are applied, run full verification (output to a log file, bounded summary):

```bash
bash "{pluginRoot}/scripts/run-gradle.sh" --cmd "{buildCommand}" --junit --lock "{workDocDir}" {runId}
```

Record results: compilation, tests, contract, build (checkstyle when `config.checkstyle`).

### Phase 4: Produce Fix Report

Write the fix report to `fixReportFile` — never another path; `mcp-fix` reads it there. `feature` is the `feature` parameter, or `null` when none was passed. `issueId` is `{dimension key}-{index}`: the report's `dimensions{}` key as written (`tool_contract`, not `Tool Contract`) and the issue's 0-based position in that dimension's `issues[]`; `mcp-fix` rejects a report whose ids are not exactly these:

```json
{
  "timestamp": "{ISO 8601}",
  "feature": "{feature}",
  "summary": {
    "total": 6,
    "fixed": 5,
    "alreadyResolved": 0,
    "escalated": 1,
    "tddCount": 3,
    "directCount": 1,
    "contractCount": 1
  },
  "tddFixes": [
    {
      "issueId": "security-0",
      "severity": "critical",
      "message": "sellerCompName returned without sanitizing",
      "file": "src/main/java/.../ChannelTools.java",
      "testAdded": "src/test/java/.../ChannelToolsTest.java",
      "implementation": "Routed sellerCompName through FreeText.clean like the other free-text fields"
    }
  ],
  "directFixes": [
    {
      "issueId": "logging-0",
      "severity": "warning",
      "message": "String concatenation in log statement",
      "file": "src/main/java/.../UpstreamClient.java",
      "change": "Replaced + with {} placeholder"
    }
  ],
  "contractFixes": [
    {
      "issueId": "tool_contract-0",
      "severity": "warning",
      "message": "MAX_LIMIT disagrees with the description",
      "file": "src/main/java/.../BookingTools.java",
      "change": "Description now says max 500, matching the upstream cap",
      "snapshot": "updated",
      "changelog": "entry added"
    }
  ],
  "alreadyResolved": [],
  "escalated": [
    {
      "issueId": "tool_contract-1",
      "severity": "critical",
      "message": "query_bookings was renamed in place",
      "reason": "Breaking contract change — restoring the old name or shipping a new tool is a product decision"
    }
  ],
  "verification": {
    "compilation": "pass",
    "tests": "pass (214/214)",
    "contract": "pass",
    "build": "pass"
  }
}
```

`summary.fixed` = `tddCount + directCount + contractCount`; `summary.total` = `fixed + alreadyResolved + escalated`.

## Constraints

- Never modify test expectations to make them pass — fix the production code. The contract snapshot is the one bounded exception, only through `templates/contract-snapshot.md` § 2 and only for the tool and fields the issue names
- Never skip or disable tests; never add `@SuppressWarnings` to silence issues
- Never add a mutating upstream call when `config.readOnly == true`
- For TDD fixes: strict RED-GREEN; for direct fixes: verify compilation after each edit
- Maximum 3 attempts per TDD fix before escalating
- Every Gradle run goes through `run-gradle.sh --lock`, which refreshes the pipeline lock (never write the lock file by hand); its exit 3 means the lock is no longer this run's — stop editing and report it
- Never leave an escalated issue's changes (test and/or edit) in the tree — revert before moving on
- Preserve existing code intent — apply minimum necessary change
- Set Bash tool timeout to 600000ms for all Gradle commands; never let unfiltered Gradle output into the context

## Output

Return the path to the fix report and a human-readable summary:

```
Fix Report
==========

Fixed: {count} ({tddCount} TDD + {directCount} direct + {contractCount} contract)
Already resolved: {count}
Escalated: {count}

Build: {PASS | FAIL}

Escalated issues (require manual intervention):
  [{severity}] {message} — {file}
    Reason: {reason}
```
