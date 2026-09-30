---
name: mcp-code
description: "Specify and TDD-implement MCP tools: drafts (or generates from plan.json) a tool work document — name, compact description, params, upstream call, RBAC, output safety, errors, scenarios — then runs the RED-GREEN cycle through the tool class, upstream client, registration, and the deliberate contract-snapshot update. Accepts a tool name (manual), a planned feature, or a work document path."
argument-hint: "<tool_name | feature-name | work-doc-path> [--class <DomainTools>] [--yes]"
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(bash *scripts/detect-project.sh*), Bash(bash *scripts/pipeline-state.sh *), Bash(bash *scripts/run-gradle.sh *), Bash(rm -f *mcp-gradle.*), Bash(git status*), Bash(git diff *), Bash(git ls-files *), Agent
---

# Implement MCP Tools with TDD

Specify and implement MCP tools using strict Test-Driven Development. This skill orchestrates the whole workflow: tool specification (the published contract), scenario writing, and the RED-GREEN cycle executed by the `implement` agent.

**Done when:** each processed tool has its work document and `{workDocDir}/.progress/{feature}.json` with `pipeline.scenarios.completed` equal to the document's `- [x]` count and `pipeline.status` `implemented` (all scenarios `- [x]` and `{buildCommand}` exited 0) or `implementing`, the Step 6 report is grounded in `git status`, and the lock is released.

This skill holds an exclusive cross-skill lock (`{workDocDir}/.progress/.lock`) for the duration of the run and can demote a tool's pipeline status, discarding verification/review progress (Step 3.5). Ground every claim in the Step 6 report in evidence — build output, `git status`/`git diff` — never narrate completion from memory, and never leave the lock file behind on failure or cancellation (§ Error Handling) — the release (`pipeline-state.sh lock release`, `{pluginRoot}/templates/pipeline-protocol.md`) also removes the implement agent's revert-snapshot directory.

## Instructions

### Step 0: Validate Configuration

1. `pluginRoot`: `${CLAUDE_PLUGIN_ROOT}` — Claude Code substitutes the plugin's install directory here when it loads this skill (the variable is not in the Bash environment, so always use this substituted value) — every `templates/…` path in this document is `{pluginRoot}/templates/…`, the plugin's own directory, not the project's; not an absolute path (the substitution did not happen) → stop: this Claude Code version does not substitute plugin paths in skill content — upgrade Claude Code.
2. `config`: run `bash "{pluginRoot}/scripts/detect-project.sh"` (`{pluginRoot}/templates/configuration.md`). Exit 0 → its stdout JSON is `config`; show each `config.warnings` entry once. Any other exit → show its stderr and stop (not a Spring AI MCP server Gradle project).

### Step 1: Parse Argument

Strip a trailing `--yes` flag (unattended confirmation of demotion prompts) and a `--class <DomainTools>` option first. Then classify the argument:

- **Work document path** — contains `/` or ends in `.md`: `workDocMode`. `feature-name` = the filename without directory and `.md` (`work/features/get-hotel-bookings.md` → `get-hotel-bookings`)
- **Planned feature** — `docs/specs/{arg}/.implementation/mcp/plan.json` exists: `planMode`, `planFeature = {arg}`
- **Tool name** — matches `^[a-z][a-z0-9]*(_[a-z0-9]+)+$` and is at most 64 characters:
  - Glob `docs/specs/*/.implementation/mcp/plan.json` and look for `tools[].name == {arg}`; one match → `planMode` for that single tool (`targetTool = {arg}`); several → list the plans and ask which one
  - `feature-name` = the tool name with `_` replaced by `-`
  - No match and `{workDocDir}/{feature-name}.md` exists → `workDocMode` on that document: the tool is already specified, and redrafting would overwrite its scenarios and their `- [x]` history. Tell the user; to re-specify, they edit the document
  - No match and no work document → `manualMode` for a new or changed tool named `{arg}`
- **Kebab-case name with `{workDocDir}/{arg}.md` present** → `workDocMode` on that document
- Anything else → stop: "`{arg}` is neither a tool name (snake_case, e.g. `get_hotel_bookings`), a planned feature, nor a work document. Run `/backend-mcp-plugin:mcp-plan {feature}` or pass a tool name."

Validate every `feature-name` (however derived): reject and stop if it contains `/`, `\`, `..`, or any character outside `[a-z0-9-]` — it builds progress-file and lock-file paths under `{workDocDir}/.progress/`. Validate `--class`: `^[A-Z][A-Za-z0-9]*Tools$`.

### Step 1.5: Load Plan (planMode)

1. Read the plan.json. Validate each tool's `name` with the tool-name rule above and each `toolClass` with the class rule — `plan.json` is a generated artifact and gets no more trust than user input; a failing tool is skipped with the reason
2. **Plan order** = the tool names in `toolOrder` (the planner puts tools that introduce shared client methods first), then any `tools[]` entry `toolOrder` omits, in `tools[]` order; a `toolOrder` name with no `tools[]` entry is ignored. Every later "plan order" in this skill means this list
3. `targetTool` set → process only that tool. Otherwise, when the plan has several tools:
   > "Plan contains {count} tools: {names in plan order}. 1. Process all in plan order  2. Select one"
   Option 2 → ask which, set `targetTool`
4. For each tool to process, check `{workDocDir}/{kebab-tool}.md`: build `toolsWithWorkDoc` and `toolsWithoutWorkDoc`

### Step 2: Gather Context

1. Read `templates/core-conventions.md` and `templates/tool-conventions.md`; when `config.descriptionConvention` is set and the file exists, read it — the project's rules win
2. Scan `{sourceDir}` under `config.toolsPackage` for existing `@Tool(name = "…")` declarations and their classes, and the `client/` package for existing upstream methods
3. **Existing tool check** — for every tool to process whose name is already declared: this run **changes** a published tool. Only additive changes are allowed in place (new optional parameter, new output field, clearer description with the same meaning, new error detail key). A rename, a removed/renamed parameter, a parameter that becomes required, or a removed output field is breaking → stop for that tool and tell the user a breaking change ships as a new tool name (`templates/contract-snapshot.md` § 3)
4. **Contract gate check** — when `config.contractTest` is `null`, tell the user once: "No contract snapshot gate is configured: contract changes from this run will not be build-verified. `templates/contract-snapshot.md` § 1 has the test to add; the next skill run detects it (nothing to re-run)." Continue — the gate is the team's deliberate addition, never a side effect of implementing a tool
5. **Read-only check** — `config.readOnly == true` and the tool needs a mutating upstream call (a write verb, `PUT`/`PATCH`/`DELETE`) → stop for that tool: it contradicts the server's read-only guarantee (an ArchUnit rule will fail the build). The user either changes the design or deliberately sets `"readOnly": false` in `.claude/backend-mcp-plugin.json` (`{pluginRoot}/templates/configuration.md`)
6. **Registration** — `config.toolRegistration == "annotation-scanner"`: the `@McpTool` bean is discovered by the scanner (no registration edit); confirm the audit and rate-limit pointcuts cover `@McpTool` and tell the user when they do not
7. `workDocMode`: read the document, extract `- [ ]` scenarios, and continue at Step 3.5

### Step 3: Write the Tool Work Document

#### planMode, for each tool in `toolsWithoutWorkDoc`

1. Read `templates/work-document-template.md`
2. Generate `{workDocDir}/{kebab-tool}.md` from the plan entry: `Tool class:` and `Upstream client:` lines, Tool Specification (name, verb, access scope, RBAC permission, rate limiter), Description (`<tool_scope>{description.scope}</tool_scope><input>{description.input}</input>`), Parameters, Upstream Call, Output (including `Field-scoped (RBAC)` from `rbac.fieldScoped` and `Row scope` from `rbac.rowScope`), Errors, Contract, and Test Scenarios from `testScenarios[]` as `- [ ]` items with source references in comments (`<!-- TS-003 -->`), ending with the contract scenario
3. Present each generated document:
   > "Work document generated from plan.json for `{tool}`: {scenario count} scenarios. The description below is published on every tools/list — review it now:"
   > ```
   > {description}
   > ```
   > "Confirm to proceed with TDD implementation, or tell me what to change."
4. Wait for approval; apply requested changes

#### manualMode

1. Read `templates/work-document-template.md`
2. Ask for the facts the specification needs, in one message (the user may answer "same as {existing tool}" for any item):
   > "To specify `{tool_name}`:
   > 1. What does it return, in business terms? Any behavior a caller would misread (masked, access-scoped, partial)?
   > 2. Inputs: name, type, required?, format/enum/range for each
   > 3. Upstream: which client and endpoint (method + path)? Is it safe to retry? Can the response be cached, and for how long?
   > 4. Access: which permission gates it? Any fields only some callers may see? Row scoping (region/tenant)?
   > 5. Output: list or single object? Row cap? Which fields are free text or PII?
   > 6. Tool class: an existing `{Domain}Tools` or a new one?"
3. Draft the work document: name the class (`--class` when given), write the description to the template — compact, business noun first, one gotcha, access-scope tag, `<input>` block — with a `<!-- manual -->` source comment on each scenario (or the reference the user names), and every scenario group (validation, behavior, access control when `config.security != "none"`, output safety for each free-text/PII field, upstream error mapping, and the final contract scenario). Mark uncertain scenarios with `?`
4. Present the specification and scenarios:
   > "Here is the specification for `{tool_name}` — the description and parameter texts are the published contract:"
   > {document}
   > "I'll remove scenarios marked `?` unless you confirm them."
5. Wait for approval; run the Step 3.5 demotion check now (declined → stop without writing anything); then save to `{workDocDir}/{feature-name}.md` — only when that file still does not exist (it appeared meanwhile → stop and point to workDocMode; never overwrite a work document)

### Step 3.5: Demotion Check

`--yes` answers this step's and Step 3.6a's confirmations with yes; without it the prompts are asked.

**workDocMode / manualMode** (manualMode runs it from Step 3 item 5, before the document is saved, and does not repeat it here): If `{workDocDir}/.progress/{feature-name}.json` exists:

1. Read `pipeline.status`
2. If status is past `"implementing"` — `"implemented"`, `"verified"`, `"verify-failed"`, `"reviewed"`, `"review-failed"`, `"fixing"`, `"resolved"`, `"escalated"`, `"done"` (`{pluginRoot}/templates/pipeline-protocol.md` § Demotion Warning):
   > "This tool is currently '{status}'. Re-running TDD implementation will reset the pipeline status to 'implementing', discarding verification/review progress."
   > "Continue?"
   If the user declines, stop here.
3. `resolved` counts only when the `previousStatus` recorded beside it (`pipeline.debug` or `pipeline.build` — whichever has the newer `timestamp`) is itself past `implementing`.

**planMode**: skipped here; performed per tool in Step 3.6a, after the lock and before Step 3.7 writes any progress file.

### Step 3.6: Acquire Lock

Acquire per `{pluginRoot}/templates/pipeline-protocol.md` § The Lock: `bash "{pluginRoot}/scripts/pipeline-state.sh" lock acquire "{workDocDir}" mcp-code {feature-name}` — exit 0 → keep the printed `runId` for every later lock call and the agent; exit 75 → tell the user which operation holds the lock (stderr) and stop; any other exit → report it and stop. Never write, rewrite or delete the lock file by hand.

**Multi-tool planMode**: the lock is acquired once here and held for the whole run; it is released once in Step 7.

### Step 3.6a: Per-tool Demotion Check

planMode only. Before Step 3.7 writes any progress file, loop over every tool being processed and check `{workDocDir}/.progress/{kebab-tool}.json`:
1. If it exists, read `pipeline.status`
2. If status is past `"implementing"` (the Step 3.5 list): warn with the Step 3.5 message and ask for this tool
3. If the user declines for a tool: leave it out of the batch and continue with the next

Build `confirmedTools` from every tool not declined, in plan order. If it is empty, do not launch the implement agent and do not run the Step 5 build — continue at Step 6 with an empty "Tools implemented" list, then Step 7 only releases the lock.

### Step 3.7: Initialize Pipeline State

For each tool in `confirmedTools` (planMode) or the one tool (other modes), create or update `{workDocDir}/.progress/{feature}.json`:

1. If the progress file does not exist, create it:
   ```json
   {
     "feature": "{kebab-tool}",
     "tool": "{tool_name}",
     "toolClass": "{toolsPackage}.{DomainTools}",
     "workDocument": "{workDocDir}/{kebab-tool}.md",
     "createdAt": "{ISO 8601}",
     "updatedAt": "{ISO 8601}",
     "pipeline": {
       "status": "implementing",
       "scenarios": { "total": 9, "completed": 0 }
     }
   }
   ```
   In planMode also write `specSource`: `{ "planFile": "{plan path}", "tool": "{tool_name}", "feature": "{planFeature}" }`.
2. If it exists: **read-modify-write** — update only `pipeline.status` to `"implementing"`, the scenario counts and `updatedAt`; preserve every other field (`specSource`, `pipeline.verification`, `pipeline.review`, …)

Initialize only the tools Step 3.6a confirmed — a declined tool keeps its progress file untouched.

Scenario source references: every `- [ ]` scenario in the work document carries its source in a trailing comment — `<!-- TS-003 -->` / `<!-- AC-2 -->` / `<!-- BR-004 -->` from the plan's `testScenarios[].source`, `<!-- manual -->` for one drafted with the user. In workDocMode, add `<!-- manual -->` to any scenario that has none before launching the agent.

### Step 4: TDD Cycle

**Batching**: several tools run through **one** `implement` agent call (it loads its context once); Step 7 still updates each tool's own progress file.

**Subagent Isolation**: Pass only the specified parameters below. Do not include conversation history or user feedback from prior steps.

**Baseline for evidence**: before launching the agent, run `git status --porcelain` once and keep the output — Step 6 diffs against it.

Launch the `implement` agent (`subagent_type: "backend-mcp-plugin:implement"` — qualified with this plugin's name, so another installed plugin's agent of the same name is never reached) **once** with:

- **Single tool**: `workDocument`: path to the work document
- **Several tools**: `workDocuments`: ordered array of work document paths, one per tool in `confirmedTools`
- `config`: the parsed plugin config
- `projectRoot`: current project root
- `pluginRoot`: {pluginRoot}
- `runId`: {runId} (from the Step 3.6 acquire — the agent refreshes the lock with it)

The agent processes each document's scenarios in order — RED, GREEN, mark `- [x]` — ending each tool with the contract scenario.

**Agent stopped by its 3-failure rule**: before Step 5, present the scenario and the three failures, and ask:
> "1. Relaunch the implement agent (after you adjust the work document or the code)  2. Stop here — build, report, and leave the tool `implementing`"

The lock stays held while waiting (run `bash "{pluginRoot}/scripts/pipeline-state.sh" lock refresh "{workDocDir}" {runId}` when the user answers). Option 1 → relaunch this Step 4 with the same parameters (the agent resumes at the first `- [ ]`); option 2, or `--yes` (nobody to ask) → continue at Step 5, whose Step 7 releases the lock.

### Step 5: Final Build

Skip when `confirmedTools` was empty (report `Build: not run — no tools to build`). Otherwise, after the agent returns complete, or stopped by its 3-failure rule and the user chose to stop (Step 4), run the full build with its output redirected to a log file outside the repository and read only a bounded summary (exit code from Gradle, test counts from the JUnit XML, the first error lines):

```bash
bash "{pluginRoot}/scripts/run-gradle.sh" --cmd "{config.buildCommand}" --junit --lock "{workDocDir}" {runId}
```

Set Bash tool timeout to 600000ms. One call: the script keeps the log only when the build fails (`log=<path>`, for a targeted `grep`; delete it afterwards). Exit 3 → the lock was lost: report it and stop.

### Step 6: Report

Derive "Files created" and "Files modified" from `git status --porcelain` (against the Step 4 baseline) and `git diff --stat` — never from memory or the agent's self-report. `??` = created, `M` = modified. Outside version control, state "not verified: file lists".

Display in the working language:

```
Tool Implementation Complete: {feature-name | planFeature} ({count} tool(s))
=======================================

Tools implemented:
  1. {tool_name} ({DomainTools}) — {completed}/{total} scenarios — contract: {snapshot updated + changelog | not configured}

Tools skipped (demotion declined or stopped in Step 2):
  {tool} — {reason}, or "(none)"

Files created:
  {list}

Files modified:
  {list}

Build file: {the agent's testLogging item — added to {file} | already present, unchanged}

Build: {PASS / FAIL}
```

If the build failed, suggest `/backend-mcp-plugin:mcp-verify --fix`.

### Step 7: Update Pipeline State

For each tool in `confirmedTools` (or the single tool), update `{workDocDir}/.progress/{feature}.json`:

1. Read the progress file
2. `pipeline.scenarios.completed` = the count of `- [x]` items in that tool's own work document
3. `pipeline.status`:
   - All scenarios complete + build passes → `"implemented"`
   - All scenarios complete + build fails → `"implementing"` (code that does not build is not implemented)
   - Some scenarios remain → `"implementing"`
4. Update `updatedAt`
5. Write back (read-modify-write)

Then release the lock with `bash "{pluginRoot}/scripts/pipeline-state.sh" lock release "{workDocDir}" mcp-code {runId}` (`{pluginRoot}/templates/pipeline-protocol.md` § The Lock — it also removes a validated agent snapshot directory).

Suggest next step:
- **Implemented + build passes**: `/backend-mcp-plugin:mcp-verify {feature}` for each tool
- **All scenarios done, build fails**: `/backend-mcp-plugin:mcp-verify --fix`
- **implementing**: resume with `/backend-mcp-plugin:mcp-code {workDoc}`

### Error Handling

- **3 consecutive test failures**: the implement agent stops; Step 4 § Agent stopped by its 3-failure rule decides — relaunch (lock kept) or stop (Steps 5–7 run; Step 7 releases the lock and leaves `implementing`)
- **Unexplained contract drift** reported by the agent: nothing was copied into the snapshot. Report the unexpected entries; the user decides (a change made elsewhere, or a missing tool class in the manifest)
- **Compilation errors during TDD**: the agent fixes stubs, not tests
- **User cancellation**: completed scenarios stay `- [x]`; refresh `updatedAt`; release the lock before stopping
- **Agent fails unexpectedly, or the Step 5 build errors out** (crash/timeout, not a reported `FAIL`): release the lock immediately; leave every affected tool `implementing` with a refreshed `updatedAt`; report which tools finished before the failure; do not report Step 6 as complete
- **`plan.json` or the work document is malformed/unreadable**: stop before Step 3.6 (the lock is never taken) and report the parse error with the file path. Never guess values

## Example: Manual Mode, New Tool

Invocation: `/backend-mcp-plugin:mcp-code get_channel_qps --class ChannelTools`

1. **Step 1**: `get_channel_qps` matches the tool-name rule; no plan contains it → manualMode, `feature-name = get-channel-qps`.
2. **Step 2**: `ChannelTools` exists (with `list_channels`, `get_channel`); `get_channel_qps` is not declared → a new tool. `config.contractTest = ToolContractSnapshotTest`; `readOnly: true` and the endpoint is a read.
3. **Step 3**: the user answers the six questions (upstream `POST /mcp/v1/comp/seller/qps`, never cached — live window; permission aliases `get_channel`). The drafted description:
   ```
   <tool_scope>Seller QPS limits: configured limit and the limit enforced now, per seller. Live values — not cached. Read-only.</tool_scope><input>sellerCompCode required (see list_channels).</input>
   ```
   Scenarios: missing sellerCompCode → INVALID_INPUT; returns configured and current QPS; caller without get_channel is denied; upstream timeout → UPSTREAM_UNAVAILABLE; response is not cached; contract scenario. Approved and saved.
4. **Steps 3.6–3.7**: lock taken; `work/features/.progress/get-channel-qps.json` created as `implementing`, 6 scenarios.
5. **Step 4**: the implement agent adds the `@Tool` method, the client method, registration (spec-list: `ChannelTools` is already in `McpToolConfig`), and tests; the contract scenario shows drift of exactly one new entry, `get_channel_qps` → snapshot updated, changelog entry added.
6. **Step 5**: `./gradlew build` exits 0.
7. **Step 6–7**: report grounded in `git status`; status `implemented`; lock released; next: `/backend-mcp-plugin:mcp-verify get-channel-qps`.
