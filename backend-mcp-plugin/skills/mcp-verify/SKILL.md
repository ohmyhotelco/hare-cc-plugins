---
name: mcp-verify
description: "Verification gate for an MCP server: compilation, tests, tool-contract snapshot + changelog pairing, full build, and optional checkstyle/coverage — structured PASS/FAIL per row, recorded against a hash of the source tree. With --fix it first runs the build-doctor auto-fix loop (up to 3 attempts), then the same gate. Use only in a Spring AI MCP server Gradle project (a project with a spring-ai MCP server starter) — for other backends use that stack's own build skill. Trigger on: \"mcp-verify\", \"verify the MCP server\", \"run the MCP gate\", \"MCP server build failing\", \"fix the MCP server build\", \"build MCP server lỗi\", \"MCP 서버 빌드 실패\"."
argument-hint: "[feature-name] [--fix] [--yes]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(bash *scripts/detect-project.sh*), Bash(bash *scripts/pipeline-state.sh *), Bash(bash *scripts/run-gradle.sh *), Bash(bash *scripts/junit-summary.sh*), Bash(rm -f *mcp-gradle.*), Bash(bash *scripts/source-tree-hash.sh*), Bash(git status*), Bash(git diff *), Bash(git ls-files *), Bash(date *), Agent
---

# Verification Gate

**Done when:** the Step 3 report shows a PASS/FAIL/SKIP for every row and an `Overall`, and — feature with a progress file — `pipeline.verification` is replaced with the 2.0 `tree` and `pipeline.status` is `verified` (Overall PASS) or `verify-failed`, with the lock released.

Run compilation, tests, the contract check, the full build, and (when configured) checkstyle and coverage, producing a structured report. Without `--fix` this is a **read-only gate**: it reports and changes nothing. With `--fix` the `build-doctor` agent first tries to make the build pass (up to 3 attempts); the gate then runs on whatever tree results, so its verdict always describes the code as it is.

## Instructions

### Step 0: Validate Configuration

1. `pluginRoot`: `${CLAUDE_PLUGIN_ROOT}` — Claude Code substitutes the plugin's install directory here when it loads this skill (the variable is not in the Bash environment, so always use this substituted value) — every `templates/…` and `scripts/…` path in this document is under `{pluginRoot}`; not an absolute path (the substitution did not happen) → stop: this Claude Code version does not substitute plugin paths in skill content — upgrade Claude Code.
2. `config`: run `bash "{pluginRoot}/scripts/detect-project.sh"` (`{pluginRoot}/templates/configuration.md`). Exit 0 → its stdout JSON is `config`; show each `config.warnings` entry once. Any other exit → show its stderr and stop (not a Spring AI MCP server Gradle project).
3. Strip the `--fix` and `--yes` flags from the argument. If a feature argument remains, it must match `^[a-z0-9][a-z0-9-]*$` (it builds progress- and lock-file paths) — else stop. Then:
   - `{workDocDir}/.progress/{feature}.json` exists → read it for pipeline context
   - Else scan `{workDocDir}/.progress/*.json` (excluding `review-report-*`, `fix-report-*` and `audit-*`) for `specSource.feature == "{feature}"`; matches (a planned feature with several tools) → list the tools and ask which one; set `feature` to its kebab-case name
   - No match → warn that no progress file exists and proceed without pipeline context

### Step 0.5: Demotion Check

`--yes` answers items 4–5 below and the Step 1 demotion prompt with yes, and Step 0.6 only while the work document has no `- [ ]` left — for an unattended caller; without it the prompts are asked. Item 2 under `--yes`: proceed when the work document has no `- [ ]` left; stop and report when a scenario is unfinished (a PASS would certify a subset).

If a feature argument was provided and its progress file exists:

1. Read `pipeline.status`
2. `"implementing"`:
   > "This tool is currently 'implementing'. Implementation may be incomplete — not all test scenarios have been finished. Continue with verification anyway?"
   If the user declines, stop here.
3. `"fixing"` or `"resolved"`: proceed — a fix or a debug changed the code, and re-verifying is the required next step (no confirmation).
4. `"reviewed"`, `"review-failed"`, or `"done"`:
   > "This tool is currently '{status}'. Re-running verification will reset the status, discarding review progress. Continue?"
   If the user declines, stop here.
5. `"escalated"`:
   > "This tool was escalated (manual intervention required). Verify that the underlying issue has been resolved before running verification. Continue?"
   If the user declines, stop here.

### Step 0.6: Work Document Staleness Check

If a feature argument was provided **and its progress file exists** (otherwise skip and say so):

1. Read the work document path from the progress file (`workDocument`)
2. Compare, both as `YYYY-MM-DDTHH:MM:SS` UTC:
   - the work document's mtime: `date -u -r {workDocPath} +%Y-%m-%dT%H:%M:%S` (the one mtime form BSD and GNU `date` share)
   - the first 19 characters of `updatedAt`, which must end in `Z`; any other suffix is a writer bug — skip the check and report the malformed value
   - equal means not stale; a missing or unreadable mtime means the check is skipped, never assumed
3. If the work document is newer:
   > "Warning: the work document has been modified since the last pipeline update ({updatedAt}). New or modified scenarios may not be implemented. Consider `/backend-mcp-plugin:mcp-code {workDoc}`. Continue with verification anyway?"
   If the user declines, stop here. Under `--yes`: proceed only when the work document has no `- [ ]` left.

### Step 0.7: Acquire Lock

Taken when a feature argument was provided **or** `--fix` was given (the fix loop edits code and records its revert snapshot in the lock). Otherwise skip.

Acquire per `{pluginRoot}/templates/pipeline-protocol.md` § The Lock: `bash "{pluginRoot}/scripts/pipeline-state.sh" lock acquire "{workDocDir}" mcp-verify {feature, omitted when absent}` — exit 0 → keep the printed `runId` for every later lock call and the agent; exit 75 → tell the user which operation holds the lock (stderr) and stop; any other exit → report it and stop. Never write, rewrite or delete the lock file by hand. Every Gradle row in Step 2 refreshes it through `run-gradle.sh --lock` (several ten-minute runs can outlast the 30-minute stale rule).

Release it on every exit from here on — release with `bash "{pluginRoot}/scripts/pipeline-state.sh" lock release "{workDocDir}" mcp-verify {runId}` (`{pluginRoot}/templates/pipeline-protocol.md` § The Lock — it also removes a validated agent snapshot directory).

### Step 1: Fix Loop (`--fix` only)

Skip entirely without `--fix`.

Launch the `build-doctor` agent (`subagent_type: "backend-mcp-plugin:build-doctor"` — qualified with this plugin's name) with:

- `config`: the parsed plugin config
- `projectRoot`: current project root
- `pluginRoot`: {pluginRoot}
- `runId`: {runId} (from the Step 0.7 acquire — the agent refreshes the lock and takes its snapshot directory with it)

The agent builds, diagnoses (compilation, test, contract drift, architecture rule, checkstyle, dependency, configuration — `agents/build-doctor.md` § Step 3), fixes and retries up to 3 times. It never updates the contract snapshot or the dependency lockfile and never weakens an ArchUnit rule: those failures come back as stop-and-report categories.

If the agent errors or times out: release the lock (`bash "{pluginRoot}/scripts/pipeline-state.sh" lock release "{workDocDir}" mcp-verify {runId}` (`{pluginRoot}/templates/pipeline-protocol.md` § The Lock — it also removes a validated agent snapshot directory)), report the partial output, and stop.

Record its result for Step 3 (`fixLoop`: attempts, changes kept, changes reverted, final category/root cause when it failed). Then, when changes were **kept**:

- Every **other** tool at `verified`, `reviewed` or `done` whose `pipeline.verification.committed` is not `true` (scanning `{workDocDir}/.progress/*.json`, excluding `review-report-*`, `fix-report-*` and `audit-*`) now carries a status its code no longer earned. If **every** progress file is a committed `reviewed`/`done` record — nothing in flight would re-verify the edited tree — those committed records are the candidates instead. List the candidates and ask (`{pluginRoot}/templates/pipeline-protocol.md` § Demotion Warning; `--yes` answers yes):
  > "The kept fix changed code these tools were verified/reviewed on: {tools}. Demote them to 'resolved' so they are re-verified? (Declining leaves their status; `mcp-review`/`mcp-commit` will still see the changed tree.)"
  Yes → set each one's `pipeline.status` to `"resolved"` with `pipeline.build: { "timestamp", "previousStatus", "by": "mcp-verify", "filesModified": [...] }` (read-modify-write, under this run's lock; a committed record also loses its `committed` mark), and list them in Step 3. No → list them in Step 3 as "not demoted (declined)"
- The tool named by the feature argument is not demoted here: Step 2 re-verifies it now

Continue to Step 2 whatever the loop's outcome — the gate reports the tree as it is.

### Step 2: Run Verification Rows

Execute these rows sequentially. Set Bash tool timeout to 600000ms (10 minutes) for all Gradle commands. Every Gradle row is **one** call to `bash "{pluginRoot}/scripts/run-gradle.sh"` — it validates the command, redirects the output to a log outside the repository, takes the exit code from Gradle itself, refreshes the lock (`--lock "{workDocDir}" {runId}`; drop it when no lock was taken) and prints only `exit=`, the `junit:` counts and failures, or the first `build errors:` lines. Script exit 3 → the lock was lost: mark `Overall: FAIL` (`lock lost during verification`) and stop running rows; exit 64 → the command was refused: mark the row FAIL with reason `verification tooling error: refused command`. Delete every kept `log=` file at the end.

#### 2.0: Tree and tooling

Before 2.1, record the tree the gate is about to run against: `tree=$(bash {pluginRoot}/scripts/source-tree-hash.sh)`. The script's contract: exit 0 and exactly one 40-hex id, or it failed — a non-zero exit, an empty or non-hex value, or a missing script is a tooling error: mark `Overall: FAIL` with reason `verification tooling error: source-tree-hash.sh …` and record no tree.

If a Bash invocation errors before producing a Gradle exit code (command not found, malformed `buildCommand`/`testCommand`, the 10-minute timeout), mark that row **FAIL** with reason `verification tooling error: {message}` and continue with the remaining rows.

`{config.gradleCommand}` is the wrapper (absent → `./gradlew`). Never append a task to `buildCommand`.

#### 2.1: Compilation

```bash
bash "{pluginRoot}/scripts/run-gradle.sh" --cmd "{config.gradleCommand} classes testClasses" --lock "{workDocDir}" {runId}
```

- **Pass**: exit 0. **Fail**: error count and the first 10 error lines

#### 2.2: Checkstyle (only when `config.checkstyle == true`)

```bash
bash "{pluginRoot}/scripts/run-gradle.sh" --cmd "{config.gradleCommand} checkstyleMain checkstyleTest" --lock "{workDocDir}" {runId}
```

- **Pass**: exit 0. **Fail**: violation count (console or `build/reports/checkstyle/`). **Skip**: `config.checkstyle == false`

#### 2.3: Tests

```bash
bash "{pluginRoot}/scripts/run-gradle.sh" --cmd "{config.testCommand}" --junit --max 10 --lock "{workDocDir}" {runId}
```

- **Pass**: exit 0, all tests pass. **Fail**: failed test names and assertion messages (from the JUnit XML)
- Counts: the script's `junit:` line (every `TEST-*.xml` under the project, `buildSrc/` excluded — `scripts/junit-summary.sh`). Never infer a count from console output, never read the XML yourself

#### 2.4: Contract

Only when `config.contractTest` is set; otherwise **SKIP** ("no contract snapshot gate configured").

1. **Snapshot test** — `bash "{pluginRoot}/scripts/junit-summary.sh" --class '*{contractTest}'` (the result files 2.3 wrote for that class): `xml≥1` with `failures=0 errors=0` → pass; failed → **FAIL** "tool contract drifted from the snapshot" with the first lines of the failure message; absent (2.3 did not run it) → **FAIL** "contract test did not run"
2. **Changelog pairing** (inside a git repository, `config.contractChangelog` set): the snapshot changed since `HEAD` (`git diff --quiet HEAD -- {contractSnapshot}` exits 1, staged or not) while the changelog did not (`git diff --quiet HEAD -- {contractChangelog}` exits 0) → **FAIL** "contract snapshot changed without a changelog entry". Outside git, or no changelog configured → report pairing "not verified" (not a failure)
3. Record `snapshotChanged` / `changelogChanged` for Step 4

#### 2.5: Full Build

```bash
bash "{pluginRoot}/scripts/run-gradle.sh" --cmd "{config.buildCommand}" --lock "{workDocDir}" {runId}
```

- **Pass**: exit 0. **Fail**: build errors not caught by earlier rows
- **2.3 FAILed**: do not run — mark FAIL with reason `tests failed (2.3); build not re-run` (`build` depends on `test`)

#### 2.6: Coverage (only when `config.coverage == true`, report-only)

```bash
bash "{pluginRoot}/scripts/run-gradle.sh" --cmd "{config.gradleCommand} jacocoTestReport" --lock "{workDocDir}" {runId}
```

- **Pass**: the task completes and at least one `build/reports/jacoco/test/jacocoTestReport.xml` exists and parses (one per subproject in a multi-module build); `linePercent` sums each report's report-level `/report/counter[@type='LINE']` (never package/class/method counters) (`templates/coverage-gate.md`)
- **Fail**: task fails, or no parseable report. **Skip**: `config.coverage == false`
- **2.3 FAILed**: run `{config.gradleCommand} jacocoTestReport -x test` instead
- The percentage never gates PASS/FAIL

#### 2.7: Tree re-check

Recompute `bash {pluginRoot}/scripts/source-tree-hash.sh`. Different from the 2.0 value → `Overall: FAIL` with reason `source changed during verification`.

### Step 3: Compile Report

```
Verification Report
===================

{--fix only:}
Fix loop:  {PASSED on attempt n | FAILED after 3 attempts | stopped: contract drift / lockfile / …}
  Changes kept:     {list or "(none)"}
  Changes reverted: {list or "(none)"}
  Demoted to resolved: {tools, or "(none)"}   Not demoted (declined): {tools, or "(none)"}

Step              Status    Details
────────────────  ────────  ──────────────────────
Compilation       {PASS|FAIL}  {error count or "clean"}
Checkstyle        {PASS|FAIL|SKIP}  {violation count or "clean"}
Tests             {PASS|FAIL}  {passed}/{total} passed
Contract          {PASS|FAIL|SKIP}  {snapshot ok, changelog paired | reason}
Build             {PASS|FAIL}  {details}
Coverage          {PASS|FAIL|SKIP}  {linePercent}% lines (report-only)

Overall: {PASS | FAIL}
```

`Overall` is FAIL when any row is FAIL (a Coverage row that could not produce its report included), or the tree changed during verification, or the tree hash could not be computed. `SKIP` never fails `Overall`; the coverage percentage never matters.

If any row failed, show the first few errors per row (file:line and message).

### Step 4: Update Pipeline State

If a feature argument was provided and its progress file exists:

1. Read the progress file
2. **Replace** `pipeline.verification` with (not merge: a `committed: true` left by an earlier commit would let the next commit skip its tree check):
   ```json
   {
     "status": "pass",
     "timestamp": "{ISO 8601}",
     "compilation": { "status": "pass", "errors": 0 },
     "checkstyle": { "status": "skip", "violations": 0 },
     "tests": { "status": "pass", "passed": 212, "total": 212 },
     "contract": { "status": "pass", "snapshotChanged": true, "changelogChanged": true },
     "build": { "status": "pass" },
     "coverage": { "status": "skip", "linePercent": null, "thresholdEnforced": false },
     "tree": "{the hash recorded in 2.0}"
   }
   ```
   (`status` values: `pass` | `fail` | `skip` per row; the top-level `status` is `pass` or `fail`.)
3. `pipeline.status`: `Overall: PASS` → `"verified"`; `Overall: FAIL` → `"verify-failed"`
4. With `--fix` and kept changes: `pipeline.build: { "timestamp", "previousStatus", "by": "mcp-verify", "filesModified" }` for this tool too
5. Update `updatedAt`; write back (read-modify-write). If the write fails, report the error with the Step 3 result — the gate ran; only its record did not land — and still release the lock

Release the lock (Step 0.7) if one was taken — release with `bash "{pluginRoot}/scripts/pipeline-state.sh" lock release "{workDocDir}" mcp-verify {runId}` (`{pluginRoot}/templates/pipeline-protocol.md` § The Lock — it also removes a validated agent snapshot directory).

### Step 5: Suggest Next Action

- **PASS** (feature): `/backend-mcp-plugin:mcp-review {feature}`
- **PASS** (no feature): run `mcp-review` with a tool's feature name or a target path
- **FAIL**: `/backend-mcp-plugin:mcp-verify {feature} --fix`; for a Contract FAIL, `mcp-code` (planned change) or `mcp-fix` (review-driven change) — the gate never accepts drift itself
- Tools demoted to `resolved` by the fix loop: `/backend-mcp-plugin:mcp-verify {tool}` for each

### Example

`/backend-mcp-plugin:mcp-verify get-channel-qps`

1. Step 0 reads the progress file: `implemented`. Step 0.5 fires no prompt; Step 0.6 finds the work document older than `updatedAt`.
2. Step 0.7 takes the lock; no `--fix`, so Step 1 is skipped.
3. Step 2: tree `a1b2…`; compilation clean; checkstyle SKIP; 214/214 tests; Contract: `ToolContractSnapshotTest` passed, snapshot and changelog both changed since `HEAD` → PASS; build clean; coverage SKIP; tree unchanged.
4. Step 4 records `verified` with the tree; lock released; Step 5 suggests `/backend-mcp-plugin:mcp-review get-channel-qps`.

**Edge case — snapshot without changelog**: the same run where only `tool-contract.snapshot.json` changed → Contract FAIL "contract snapshot changed without a changelog entry" → `Overall: FAIL`, status `verify-failed`.

### Constraints

- Without `--fix`: do NOT modify any source code
- Never accept contract drift (never copy the actual manifest over the snapshot) and never regenerate the lockfile — in either mode
- Always run all rows even if earlier rows fail — the one exception is 2.5 after a failed 2.3
- Never wire a coverage threshold here
- Report in the working language from config
