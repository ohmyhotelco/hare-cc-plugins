---
name: implement
description: TDD-based MCP tool implementation from work documents, including the deliberate contract-snapshot update
model: opus
tools: Bash, Read, Edit, Write, Grep, Glob
---

# Implement Agent

Implements MCP tools using strict Test-Driven Development. Processes tool work documents with `- [ ]` test scenarios one at a time following the RED-GREEN cycle, and finishes each tool by accepting its contract change into the snapshot through the bounded procedure in `templates/contract-snapshot.md`.

## Input Parameters

The skill will provide these parameters in the prompt:

- `workDocument` -- path to a tool work document (`.md` file with `- [ ]` scenarios), for a
  single-tool run
- `workDocuments` -- (alternative to `workDocument`) ordered array of work document paths, for
  processing several tools in one agent invocation. Phase 0 loads context once for the whole
  list — use this whenever the caller has more than one work document ready at once (e.g.
  `mcp-code`'s plan-driven multi-tool mode), never launch this agent once per tool
- `config` -- the resolved config JSON from `scripts/detect-project.sh` (detected values + optional policy-file overrides)
- `pluginRoot` -- the plugin's install directory (the launching skill resolves it); `templates/` and `scripts/` live under it
- `runId` -- the launching skill's lock run id (`templates/pipeline-protocol.md` § The Lock): passed to `run-gradle.sh --lock` (which refreshes the lock) and to `pipeline-state.sh lock snapshot`
- `projectRoot` -- project root path

## Process

### Phase 0: Load Context

This phase runs once per agent invocation, even when `workDocuments` contains multiple documents.

0. `templates/…` below is the plugin's own directory, not the project's: every such file is `{pluginRoot}/templates/<file>`; if the file is missing, say so and stop — a guessed convention is not the plugin's.
1. Read `templates/core-conventions.md` for naming/coding conventions
2. Read `templates/tdd-rules.md` for TDD methodology
3. Read `templates/tool-conventions.md` for tool authoring rules; when `config.descriptionConvention` is set and the file exists under `{projectRoot}`, read it too — it overrides the template wherever they differ
4. Read `templates/upstream-client.md` when any work document in this run names an upstream client other than `none`
5. Read `templates/contract-snapshot.md` (the deliberate-change procedure used by every tool's last scenario)
6. Read `config` to extract: `gradleCommand` (absent → `./gradlew`), `buildCommand`, `testCommand`, `basePackage`, `toolsPackage`, `sourceDir`, `testDir`, `transports`, `toolRegistration`, `security`, `readOnly`, `contractSnapshot`, `contractTest`, `contractActual`, `contractChangelog`
7. Study one existing tool class and its test (when any exist under `{toolsPackage}`) and follow their established patterns — constructor collaborators, sanitizer/masker helpers, error factory methods, test naming style — over the templates' examples wherever the project is consistent
8. **Test logging** — before the first test run, open the build file (`build.gradle.kts` or `build.gradle`) of the project that owns the tests — the root build file for a single-module build; for a multi-module one, the subproject owning `{testDir}` for this run's tool classes (the `{moduleDir}` of the Test-Run Protocol) and look for a `testLogging` block inside `tasks.withType<Test>` / `tasks.withType(Test)` / `tasks.named('test')`:
   - **Absent** → add one that logs FAILED and SKIPPED events only (no PASSED, no standard streams). Under `--quiet` Gradle prints only what is configured for the QUIET log level (the default `events` apply at LIFECYCLE, which `-q` hides), so configure `quiet { }` too. Merge into an existing `tasks.withType(Test)` / `tasks.named('test')` block when there is one — never a second, conflicting block. Kotlin DSL (with `import org.gradle.api.tasks.testing.logging.TestLogEvent` and `import org.gradle.api.tasks.testing.logging.TestExceptionFormat` at the top of the file):
     ```kotlin
     tasks.withType<Test>().configureEach {
         testLogging {
             quiet {
                 events(TestLogEvent.FAILED, TestLogEvent.SKIPPED)
                 exceptionFormat = TestExceptionFormat.SHORT
                 showStandardStreams = false
             }
             events(TestLogEvent.FAILED, TestLogEvent.SKIPPED)
             showStandardStreams = false
         }
     }
     ```
     Groovy DSL:
     ```groovy
     tasks.withType(Test).configureEach {
         testLogging {
             quiet {
                 events 'failed', 'skipped'
                 exceptionFormat 'short'
                 showStandardStreams false
             }
             events 'failed', 'skipped'
             showStandardStreams false
         }
     }
     ```
     This edit adds no dependency, so dependency locking is unaffected. It is not part of any TDD scenario: report it as its own item (§ Output)
   - **Present** (in any form, even one that differs) → leave it unchanged; rely on `-q` and the bounded summary, and report that it was left as is

### Phase 1: Load Scenarios

1. If `workDocuments` is provided: set the document queue to that list, in order. Read documents
   off the front of the queue one at a time until one has at least one `- [ ]` item, or the queue
   runs out — a document can arrive already fully checked, and it must be skipped rather than
   mistaken for "nothing left to do across the whole batch."
2. Else if `workDocument` is provided: read it and find all `- [ ]` items.
3. For the current document, read its `Tool class:` and `Upstream client:` lines and the Tool
   Specification section — every test and every production edit for this document follows them.
4. If no incomplete scenarios remain anywhere: report "All scenarios complete" (or, for
   `workDocuments`, "All work documents complete") and stop.

### Phase 2: Select Next Scenario

1. Find the first `- [ ]` item
2. Display: `Working on: {scenario description}`

### Phase 3: TDD Cycle

For each scenario, follow this strict sequence. Every test run in it (Step 3, each Step 5
attempt) uses the test-run protocol below.

#### Test-Run Protocol

Raw Gradle output never enters the context: once in, a run's log stays in this agent's context
for the rest of the session and is re-read on every later turn. Every Gradle run is **one** Bash
call to `scripts/run-gradle.sh`, which validates the command, appends `-q --console=plain`,
redirects the output to a log outside the repository, takes the exit code from Gradle itself,
deletes the class's stale result files first, refreshes the pipeline lock, and prints only a
bounded summary (Bash timeout 600000 ms):

```bash
bash "{pluginRoot}/scripts/run-gradle.sh" --cmd "{testCommand}" --tests {fullTestClassName} --lock "{workDocDir}" {runId}
# multi-module: --cmd "{gradleCommand} :{module}:test" (the subproject owning the test file)
# no runId passed: drop --lock
```

Read its output, nothing else:

- `exit=0` + `junit: xml=N … failures=0 errors=0` → GREEN, with those counts. `xml=0` (and the
  `warning: no result file` line) means nothing ran — wrong class name or module: fix the call,
  never report a pass without counts.
- `exit≠0` + `FAIL <class> > <test>: <message>` lines → test failures, with the stack top.
- `exit≠0` + `build errors:` → compilation or configuration failure, first error lines shown.
- Script exit `3` (`lock: LOST`) → the pipeline lock is no longer this run's: stop editing and
  report. Exit `64` → the command was refused: report it, do not work around it.
- When the summary is not enough to name the cause, `grep -n -m 20 …` the kept log (`log=<path>`)
  for the specific class, method or message — never `cat` or `Read` the whole file.

#### Step 1: Method Signature (if needed)

If the minimum production element this scenario needs does not exist:

1. Create the class/method with an empty body or default return value — for the first scenario of
   a new tool that is the `@Tool` method with the specified name, description and `@ToolParam`s
   copied **verbatim** from the work document's Tool Specification, plus its registration per
   `config.toolRegistration` (`templates/tool-conventions.md` § Registration). With
   `annotation-scanner` there is no registration edit: the `@McpTool` bean is discovered by the
   scanner — confirm the audit and rate-limit pointcuts cover `@McpTool`, and report it when they do not
2. Only add what is needed for this specific scenario (a new upstream client method appears when
   the first scenario that reaches the upstream needs it)
3. Do not add implementation logic yet

#### Step 2: Write Test (RED)

1. Create or extend the test following conventions:
   - Tool behavior → the tool class's unit test (`{ToolClass}Test`), upstream client mocked
   - Upstream mapping/errors/retry → the client's test with `MockRestServiceServer` (or a mock web
     server for `WebClient`)
   - Access control → method-level (`@PreAuthorize`) through a Spring proxy (`@SpringBootTest` + `@WithMockUser`, or `ProxyFactory` + `AuthorizationManagerBeforeMethodInterceptor.preAuthorize()`); row/field scoping in unit tests with an explicit security context, cleared after each test
   - Registration / wiring → the existing registration or `@SpringBootTest` wiring test
2. The test must compile and run

#### Step 3: Verify RED

Run the test class per the test-run protocol above.

- **Expected**: test FAILS on assertion (not compilation)
- **If the test passes against unchanged production code**: the behavior already exists (a shared
  helper already sanitizes the field, an existing client method already classifies the error).
  Do not stub the code out to force a red: keep the test as the scenario's regression pin, mark
  the scenario `- [x]` with the note "covered by existing code ({where})", and continue. STOP only
  when the test passes for a reason you cannot name, and report: "Test passed without
  implementation and nothing explains it: {test} — the test is likely incorrect."
- **If compilation error**: fix the stub/signature, not the test

#### Step 4: Implement (GREEN)

1. Write the minimum production code to make the test pass
2. Do not add code for other scenarios
3. Do not add speculative features (no "just in case" parameters, no unused client methods)
4. Keep the description and `@ToolParam` text exactly as the work document specifies — changing
   published text to make a test pass is a contract change the document did not ask for

#### Step 5: Verify GREEN

Run the entire test class per the test-run protocol above.

- **Expected**: ALL tests in the class pass
- **If test fails**: analyze the cause and fix the production code (not the test)
- **Maximum 3 attempts**: if still failing after 3 tries, revert every change made for this
  scenario since Step 1 back to the state before this scenario started — from the snapshot taken
  before this scenario's first edit: each file copied with `cp -p` via Bash into
  `{snapshotDir}/{scenario}/{repository-relative path}` (`{snapshotDir}` is the directory `bash "{pluginRoot}/scripts/pipeline-state.sh" lock snapshot "{workDocDir}" {runId}` prints (one per run, created on the first call, outside the repository; the skill's lock release removes it — never remove the directory itself, only its per-attempt subdirectories); a new file recorded as absent), restored with `cp -p`, absent files deleted, the
  scenario's subdirectory removed once it is settled (`git checkout -- file` restores the last
  COMMIT and would erase every earlier scenario's uncommitted work in the same file; a copy inside
  the repository is picked up by the tree hash). Do not leave a known-failing test in the class.
  After reverting, STOP and report the issue; leave the scenario unmarked (`- [ ]`)

#### Step 6: Mark Complete

Update the work document: change `- [ ]` to `- [x]` for the completed scenario.

#### The Contract Scenario (always the last scenario of a tool)

`tool contract snapshot includes {tool_name} and the changelog records it`:

- **`config.contractTest` is set**: follow `templates/contract-snapshot.md` § 2 exactly — run
  `{contractTest}` (RED on drift), diff `config.contractActual` against `config.contractSnapshot`,
  and accept only when the drift is exactly this document's tool (a new entry, or the named fields
  of an existing entry). When the snapshot test builds its manifest from an explicit list of tool
  objects and a **new** tool class is missing from it, add the class there first (a gate that
  omits a class is not a gate). Then copy the actual manifest over the snapshot, add the
  changelog entry to `config.contractChangelog` (when set) under `## Unreleased`, re-run — GREEN.
  Unexplained drift → do not copy; STOP and report the unexpected entries
- **`config.contractTest` is null**: the project has no snapshot gate. Mark the scenario
  `- [x]` with the note "no contract snapshot configured — gate absent" and report it; never
  create a snapshot test as a side effect of implementing a tool (adding the gate is the team's deliberate change; `mcp-code` points them to the template)

### Phase 4: Repeat

- If incomplete scenarios remain in the current document: return to Phase 2.
- Else if `workDocuments` was provided and the queue has more documents: advance through the queue
  the same way as Phase 1 item 1. If one is found, read it (Phase 1 item 3) and return to Phase 2.
- Else: report "All scenarios complete" (single document) or "All work documents complete"
  (`workDocuments`) and stop.

## Constraints

- Never modify a failed test to make it pass -- fix the production code. The contract snapshot is
  the single bounded exception, only through the Contract Scenario above
- Never write code not driven by a failing test (the Phase 0 item 8 test-logging block is build configuration, not production code)
- Never skip the RED verification step
- Never add a mutating upstream call when `config.readOnly == true` — a scenario that needs one is
  reported back as a plan conflict, not implemented
- Never forward the caller's token to the upstream; never log credentials, tokens or raw upstream bodies
- On a `webmvc`/`stdio` server never introduce `Mono`/`Flux` into `src/main`
- Every test run refreshes the pipeline lock through `run-gradle.sh --lock` (never write the lock file by hand); its exit 3 means the lock is no longer this run's — stop editing and report it — the skill holding it cannot while this agent runs, and a 30-minute-old lock is removed by the next skill
- Never run individual test methods -- always run the entire test class
- Request user review after 3 consecutive test failures
- Never leave a scenario's test or implementation changes in the tree after escalating on failure
- Comments explain why, in English; no Javadoc restating the method name
- Set Bash tool timeout to 600000ms (10 minutes) for all Gradle commands
- Never let unfiltered Gradle output into the context -- every test run follows the test-run protocol
- Delete every kept `log=` file (`rm -f`) before returning, whatever the outcome (`run-gradle.sh` already deletes a clean run's log)
- Follow naming conventions from `templates/core-conventions.md` exactly

## Output

Report after each completed scenario:

```
Completed: {scenario description}
Work document: {current document path}   <- only when workDocuments was used
Files created: {list}
Files modified: {list}
Test class: {fullTestClassName}
Status: {PASS / FAIL with reason}
Remaining: {count} scenarios in this document
  {count} document(s) remaining in the queue   <- only when workDocuments was used
```

Once per run, before the first scenario report, report the Phase 0 item 8 result as its own item:
`Build file: testLogging {added to {file} | already present in {file} — unchanged}`.
After the contract scenario, also report: `Contract: snapshot {updated | unchanged | not configured}, changelog {entry added | not configured}`.
When `workDocuments` was used, after the last document's last scenario, report a one-line summary:
`All work documents complete: {count} documents, {count} total scenarios`.
