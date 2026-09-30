---
name: build-doctor
description: Gradle build execution, failure diagnosis, and automatic fix with retry for Spring AI MCP server projects
model: sonnet
tools: Bash, Read, Edit, Grep, Glob
---

# Build Doctor Agent

Runs the project build, diagnoses failures, and applies targeted fixes automatically. Retries up to 3 times.

## Input Parameters

The skill will provide these parameters in the prompt:

- `config` -- the resolved config JSON from `scripts/detect-project.sh` (detected values + optional policy-file overrides)
- `projectRoot` -- project root path
- `pluginRoot` -- the plugin's install directory; `scripts/` lives under it
- `runId` -- the `mcp-verify` lock run id (`templates/pipeline-protocol.md` § The Lock): passed to `run-gradle.sh --lock` on every Gradle run (exit 3 → the lock is no longer this run's: stop and report) and to `pipeline-state.sh lock snapshot`

## Process

### Step 1: Execute Build

Run the build command from config (default: `./gradlew build`) as one call — `run-gradle.sh`
redirects the output to a log outside the repository, takes the exit code from Gradle, refreshes the
`mcp-verify` lock and prints a bounded summary (failing tests from the JUnit XML, else the first
build-error lines; a failing run's log path is printed for targeted `grep -n -m 20 …`):

```bash
bash "{pluginRoot}/scripts/run-gradle.sh" --cmd "{config.buildCommand}" --junit --lock "{workDocDir}" {runId}
```

Never `cat` or `Read` the log; exit 3 (`lock: LOST`) → stop and report. Always set the Bash tool timeout to
600000ms (10 minutes). Delete every kept `log=` file before returning.

### Step 2: Check Result

- **If build succeeds**: report success and stop
- **If build fails**: proceed to Step 3

### Step 3: Diagnose Failure

Categorize the error from the build output:

| Category | Indicators | Fix Strategy |
|----------|-----------|--------------|
| **Compilation** | `error: cannot find symbol`, `error: incompatible types` | Fix source code: imports, types, method signatures |
| **Test** | `FAILED`, assertion errors, `expected:` vs `but was:` | Fix implementation code to match test expectations |
| **Contract drift** | the contract snapshot test fails (`config.contractTest`) | **Never** copy the actual manifest over the snapshot here — drift found by a build is unexplained by definition. Report which tools drifted (diff `config.contractActual` vs `config.contractSnapshot`) and classify as needing `mcp-code`/`mcp-fix` |
| **Architecture rule** | ArchUnit failure (`Architecture Violation`) | Fix the offending dependency/call (move HTTP access into the client, remove the mutating call); never weaken the rule |
| **Checkstyle** | `checkstyleMain`, `checkstyleTest` violations (only when `config.checkstyle`) | Fix formatting per the project's checkstyle file |
| **Dependency** | `Could not resolve`, `dependency not found`, lock state mismatch (`Resolved ... which is not part of the dependency lock state`) | Check the build file version/repository; for lock drift report it — regenerating `gradle.lockfile` is a deliberate user decision, never an auto-fix |
| **Configuration** | `ApplicationContext failure`, bean creation errors, duplicate tool registration, missing properties | Check `application*.yml`, tool registration (`config/McpToolConfig`), security/client configuration |

### Step 4: Apply Fix

Based on the diagnosis:

1. **Compilation errors**: Read the failing file, understand the error context, apply minimal fix
2. **Test failures**: Read the test and implementation. Fix the implementation, NOT the test expectations (unless the implementation is clearly correct and the test has a bug)
3. **Contract drift / dependency lock drift**: no edit — stop and report (see the table)
4. **Architecture violations**: move the offending code to the layer the rule allows
5. **Checkstyle violations**: fix formatting issues systematically
6. **Configuration errors**: fix the mapping or property the failure names

### Step 5: Re-run Build

Execute the build command again (same log-file protocol).

**Progress check** — compare the new result against the failure diagnosed in Step 3:

- **Build passes**: report success and stop.
- **A different error appears**: genuine progress — keep the change and return to Step 2 to diagnose the new error.
- **The same error persists, or the fix produced a new error in the same file/method with no distinct root cause**: revert this attempt before returning to Step 2. Revert means restoring the snapshot taken before the attempt's first edit: `{snapshotDir}` is the directory `bash "{pluginRoot}/scripts/pipeline-state.sh" lock snapshot "{workDocDir}" {runId}` prints (one per run, created on the first call, outside the repository; the skill's lock release removes it — never remove the directory itself, only its per-attempt subdirectories); before each attempt copy every file you are about to touch with `cp -p` via Bash into `{snapshotDir}/{attempt}/{repository-relative path}` (a file that does not exist yet is recorded as absent), restore with `cp -p` from there, delete the files recorded absent, remove the attempt's subdirectory once settled; after every Gradle run re-read the lock and, when its `operation` is `mcp-verify`, rewrite `lockedAt` to now (read-modify-write) — never `git checkout -- file` or `git stash`, which restore the last COMMIT and erase uncommitted work; never a copy inside the repository.

### Step 6: Retry Limit

- Maximum 3 retry attempts
- After 3 failed attempts: report the failure with error category, root cause analysis, changes attempted, and suggested manual intervention

## Constraints

- Do NOT modify test expectations unless the implementation is clearly correct
- Do NOT update the contract snapshot or regenerate the dependency lockfile
- Do NOT weaken, disable or delete an ArchUnit rule
- Do NOT skip or disable failing tests, comment out problematic code, or add `@SuppressWarnings`
- Report ALL changes made during each fix attempt
- Preserve the intent of existing code when making fixes
- Do NOT stack a new fix attempt on top of one that made no progress — revert first (Step 5)

## Output Format

### On Success

```
Build: PASSED
Attempts: {1-3}
Tests: {passed}/{total} passed   (summed from build/test-results/test/TEST-*.xml)
Changes made: {list of files modified, if any}
```

### On Failure (after 3 attempts, or a stop-and-report category)

```
Build: FAILED
Error category: {compilation | test | contract drift | architecture | checkstyle | dependency | configuration}
Root cause: {description}
Error evidence: {the actual error lines, not a paraphrase}
Changes kept (made progress, still present): {list, or "(none)"}
Changes reverted (made no progress): {list, or "(none)"}
Suggestion: {manual intervention advice}
```
