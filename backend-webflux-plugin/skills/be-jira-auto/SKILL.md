---
name: be-jira-auto
description: "Jira-to-commit orchestrator that implements a ticket's own stated Technical Approach directly when present, or drafts a Proposed Solution and stops for user confirmation when not, classifies the ticket into a tier (easy/normal/extreme) to scale the review gate, and drives the full be-crud -> be-code -> be-verify -> (be-review + be-security) -> be-fix -> be-commit pipeline end to end via the Skill tool, instead of the user running each be-* skill one at a time"
argument-hint: "<JIRA-KEY> [notes: <text>]"
user-invocable: true
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Skill, Agent, ToolSearch
---

# be-jira-auto — Jira Auto Orchestrator

Orchestrator skill. Given a Jira issue key, it derives the same inputs a
human would type into `be-crud`/`be-code`, then delegates every actual
step to the plugin's own `be-*` skills via the `Skill` tool -- it never
reimplements scaffold generation, TDD, verification, review, or fix logic
itself. This skill is the automated counterpart of manually running
`be-crud` -> `be-code` -> `be-verify` -> `be-review` -> `be-fix` ->
`be-commit` in sequence (see `${CLAUDE_PLUGIN_ROOT}/CLAUDE.md` § Pipeline).

**A skill, not a subagent, on purpose.** `be-code`, `be-build`, `be-review` and `be-fix` each
launch an agent (`implement`, `build-doctor`, `code-reviewer`, `review-fixer`) with the `Agent`
tool, and a Claude Code subagent has no `Agent` tool — it cannot spawn subagents. Run as an agent,
four of the seven pipeline steps below could not execute as written. As a skill it runs in the
main session, where `Skill` and `Agent` both exist.

Files under `references/` write the plugin root as `{pluginRoot}`, which is `${CLAUDE_PLUGIN_ROOT}`.

## Golden Rules

- One skill owns each step (`be-crud`, `be-code`, `be-verify`, `be-build`,
  `be-review`, `be-fix`, `be-commit`). Call it through `Skill`, read its
  output, then move on -- never skip a step, never reorder, never
  reimplement a skill's job inline (the one exception is Step 3.5's
  scaffold-level extension of an existing entity, for which no skill exists;
  it follows `be-crud`'s templates).
- This skill runs unattended: it cannot answer a skill's interactive
  confirmation prompts mid-run. Resolve every input a skill would
  otherwise ask for (data profile, domain, fields, scenarios) *before*
  calling that skill, and pass it explicitly. When a question genuinely
  cannot be answered from the ticket, stop with `NEEDS-INPUT` rather than
  guessing.
- **The ticket's own Technical Approach outranks this skill's judgment.**
  When the Jira issue already states a technical approach/solution, that
  is the design -- extract from it and implement directly, do not
  re-derive or second-guess it (see Step 1). Only when the ticket has no
  stated approach does this skill draft one itself, and a self-drafted
  design must be confirmed by the user before implementation starts (see
  Step 1.5) -- a self-drafted design is a proposal, not a mandate.
- Never skip `be-verify` or `be-review`, even for a ticket that looks
  small. Tiering (see Step 1) only scales
  whether the parallel `be-security` gate runs alongside `be-review` --
  it never skips `be-verify` or `be-review` themselves.
- Never push, open a pull request, or comment on / transition the Jira
  issue. The plugin's own pipeline (`${CLAUDE_PLUGIN_ROOT}/CLAUDE.md` § Pipeline) ends at
  `be-commit` -- stay there. Push/PR/Jira-status is a manual decision for
  the user, made outside this skill.
- Report in the working language read from
  `.claude/backend-webflux-plugin.json` (`workingLanguage`), matching the
  language every other skill in this plugin already reports in.

## Input Parameters

The caller (a slash-command invocation, or the top-level session) provides
these in the prompt:

- `jiraKey` -- Jira issue key, e.g. `OMH-1234`, `ELS-3225` (required): the first token of the argument
- `projectRoot` -- the current working directory: every delegated skill, git command and script runs there, so another directory cannot be named
- `notes` -- (optional) everything after `notes:` in the argument (`/backend-webflux-plugin:be-jira-auto OMH-1234 notes: jira-mcp: mcp__atlassian__…; start over`): extra constraints or a preferred approach from the
  user, carried verbatim into Step 0.5, Step 1, and Step 2 -- this is also
  where a Jira MCP preference from a prior `NEEDS-INPUT` round comes back
  in (see Step 0.5)

If `jiraKey` is missing from the prompt, stop immediately with status
`NEEDS-INPUT` and a single-sentence request for the key -- do not guess a
ticket.

## Pipeline

### Step 0: Repo Guard

1. Read `.claude/backend-webflux-plugin.json` from `projectRoot`.
2. Missing -- stop with status `ABORTED`: "backend-webflux-plugin is not
   initialized in `{projectRoot}` -- run `/backend-webflux-plugin:be-init`
   first." Do not guess config values, do not run any git/gradle command
   after this.
3. Record `buildCommand`, `testCommand`, `basePackage`, `sourceDir`,
   `testDir`, `workDocDir`, `dataProfile`, `webLayer`, `workingLanguage`
   for use in every later step.

### Step 0.5: Discover the Jira MCP Tool

This skill does not hardcode which Jira integration is wired up -- a
project may have a cloud Atlassian connector, a local/self-hosted MCP
gateway, or both, and the exact tool name differs per setup (e.g.
`mcp__claude_ai_Atlassian__getJiraIssue` vs.
`mcp__MCP_DOCKER__getJiraIssue`). Resolve it once, at the start:

1. If `notes` already states a Jira MCP preference from a prior
   `NEEDS-INPUT` round (see below), use it directly and skip to Step 1 --
   never re-discover once the user has already picked one for this run.
2. Otherwise call `ToolSearch` with a keyword query such as
   `"jira issue get"` (and, if that returns nothing, a broader `"jira"`)
   to enumerate every connected MCP tool that can fetch a single issue by
   key -- look for names ending in something like `getJiraIssue` /
   `get_issue` under any `mcp__<server>__...` prefix.
3. **Exactly one candidate** -- load it, use it for the rest of this run,
   and record which server it came from for the final report ("Jira
   source: {server}"). Also resolve that same server's JQL-search
   counterpart (e.g. `searchJiraIssuesUsingJql` / `search_issues`) the
   same way, for the related-ticket check in Step 1 -- it is optional, so
   proceed without it if the server does not expose one.
4. **Zero candidates** -- stop with status `NEEDS-INPUT`: no Jira MCP tool
   is connected in this session; ask the user to connect one (cloud
   Atlassian connector or a local MCP gateway) and re-invoke.
5. **More than one candidate** -- stop with status `NEEDS-INPUT`, listing
   every candidate found (server name + tool name), and ask the user to
   pick one. On the next invocation, expect the choice back via `notes`
   (e.g. `"jira-mcp: mcp__claude_ai_Atlassian"`) and use point 1 above --
   never guess between two connected Jira sources, since they can point
   at different Jira instances entirely.

### Step 1: Understand the Ticket

Read `${CLAUDE_PLUGIN_ROOT}/agents/backend-planner.md` first -- this step and Step 1.5 apply its
Phase 1 (existing-code scan) and Phase 2 (spec-to-CQRS mapping) rules by
reference throughout; without reading it here those rules are not actually
in context when this step needs to apply them, since a fresh agent
invocation does not inherit any other agent's file reads.

Call the issue-lookup tool resolved in Step 0.5 with `{jiraKey}`.

1. Read summary, description, acceptance criteria, comments, linked
   issues. If a JQL-search counterpart was also resolved in Step 0.5, use
   it to check for related tickets already in flight if the description
   references one -- skip this check when no search tool was found.

2. **Check whether the ticket already states a technical approach.**
   Look at the description and comments for an explicit
   approach/solution section -- a heading or clearly-labeled block such
   as "Technical Approach", "Solution", "Technical Design",
   "Implementation Approach", or the Vietnamese equivalents ("Giải pháp
   kỹ thuật", "Giải pháp", "Hướng triển khai") -- typically written by a
   tech lead/architect as part of grooming, not just a passing mention of
   a class name in a comment.

   - **Found**: this is the binding design. Extract the entity list,
     `field:Type` pairs, endpoints, exceptions, and the extend-vs-new-entity
     call directly from what it states -- do not re-derive or replace a
     product/design decision the approach already made. Apply
     `agents/backend-planner.md` Phase 2's mapping rules only to fill in
     mechanical detail the approach left implicit (e.g. it says "add a
     `status` field" without naming a column type that
     `${CLAUDE_PLUGIN_ROOT}/templates/entity-conventions.md` already standardizes). Skip Step
     1.5 -- go straight to Step 2 once the extraction below is complete.
   - **Not found**: investigate the existing codebase yourself -- scan
     `{sourceDir}/{basePackage}/data/` for entities that already exist,
     scan `{sourceDir}/{basePackage}/` for existing domain packages, and
     glob `src/main/resources/migration/` for the next migration version
     (mirror `agents/backend-planner.md` Phase 1's scan). Draft a
     **Proposed Solution** using Phase 2's mapping rules from the
     summary/description/AC alone. This proposal is not authoritative --
     Step 1.5 must confirm it with the user before Step 2 touches
     anything.

3. Either way, resolve and write down before moving on (from the stated
   approach when found, from the draft otherwise):
   - Whether this ticket needs a brand-new entity (`be-crud` applies) or
     only extends an existing one (`be-crud` does not apply -- see Step
     3.5).
   - The domain (one lowercase package segment, `[a-z][a-z0-9]*` — no hyphen, it
     is spliced into `package …{domain}.api;`; used for the `{domain}/api` package and the
     URL prefix).
   - The entity list, in FK-dependency order if more than one (referenced
     entity first) -- same rule as `agents/backend-planner.md` § 2.8.
   - Per entity: `field:Type` pairs, validation rules, exceptions with
     their HTTP status, endpoints (method, path, status code).
   - Test scenarios: single sentence, present tense, lowercase first word
     (usable as a snake_case test method name), `- [ ]` checkbox format,
     per `${CLAUDE_PLUGIN_ROOT}/templates/test-scenario-template.md`.
   - **Tier** -- classify the ticket to scale the Step 7 gate:
     - `easy`: no new entity, no new public endpoint -- a logic/bug fix on
       code that already exists.
     - `normal`: one new entity scaffolded (one `be-crud` call), or one or
       more new public endpoints on existing entities, within one domain.
     - `extreme`: more than one new entity, or the change spans more than
       one domain/module.
     Tier never changes whether `be-verify`/`be-review` run (see Golden
     Rules) -- it only decides whether the parallel `be-security` gate in
     Step 7 is mandatory. Regardless of tier, force `be-security` to run
     if the ticket description/AC mentions anything security-sensitive
     (auth, permission, PII, payment, token, secret) -- tier is a
     complexity signal, not a security override.

4. **Gap inside a stated approach**: if a found Technical Approach leaves
   something genuinely unresolved (a field with no declared type, a
   business rule with no stated behavior) -- stop with status
   `NEEDS-INPUT`, quoting the exact gap. Never fill it with a guess just
   because "most of the approach" was already clear.

### Step 1.5: Confirm the Proposed Solution (only when Step 1 found no stated approach)

Skip this step entirely when Step 1 extracted from a stated Technical
Approach -- re-confirming the ticket author's own design back to them is
redundant, and the Golden Rule above says implement it directly.

When Step 1 had to draft its own Proposed Solution:

1. Stop the run here with status `NEEDS-INPUT`, before Step 2 touches git
   or anything else. Report the full Proposed Solution exactly as Step
   3/3.5/4 would consume it (entity list, fields/types, endpoints,
   exceptions, extend-vs-new-entity call per entity, migration strategy
   for any "extend" entity, tier), plus up to 3-5 open questions -- points
   the draft had to guess where a wrong guess would change the design.
2. On the *next* invocation, the caller passes the user's confirmation or
   corrections back via the `notes` input parameter. Treat `notes` as
   amending the Proposed Solution (apply corrections literally, do not
   reinterpret them) and proceed straight through to Step 2 -- do not
   re-enter Step 1.5 for the same ticket. If `notes` itself leaves a point
   unresolved, that is an ordinary Step 1 point 4 gap, not a reason to
   loop back into another proposal-and-confirm round.

### Step 2: Prepare the Branch

1. `git status --porcelain -z` (NUL-separated, the form Step 9 diffs against). Paths under `{workDocDir}/.progress/` and `.claude/backend-webflux-plugin.json` are this plugin's own bookkeeping and never count as dirty (the run state above is written before any branch exists). Not clean otherwise -- stop with `NEEDS-INPUT`: ask the
   user to commit or stash their own in-progress work first. Never run
   `git stash` or `git checkout .` to clear it yourself. **Exception -- a
   resume of this ticket:** when the current branch already carries
   `{jiraKey}` (item 2) and every dirty path lies under `{sourceDir}`,
   `{testDir}`, `src/main/resources/`, `config/`, `gradle/`, `buildSrc/`,
   `{workDocDir}`, or is a `build.gradle(.kts)` / `settings.gradle(.kts)` /
   `gradle.properties` / `gradlew` file (be-crud edits `application.yml`,
   `be-build` may edit the build) **and is in the run state's `dirty`
   list** (a path that is not was edited during the pause: stop with
   `NEEDS-INPUT` naming it — two exceptions: the security fix a Step 7 stop
   asked for, when its paths lie under `{sourceDir}`, `{testDir}` or
   `src/main/resources/` (be-security's credential rules point at
   `application*.yml`), and a resume with no run state or after a crash,
   when `notes` says `own-dirty` — the user vouching that every dirty path
   is this pipeline's), the
   tree is this pipeline's own in-progress work left by a `NEEDS-INPUT` exit (a
   three-failure pause, a security finding, an escalation); keep it and
   continue from the step and feature `{workDocDir}/.progress/jira/{jiraKey}.json`
   names (written at every early stop and after the commit -- see Gates;
   absent → `NEEDS-INPUT` asking which step; `committed`/`DONE` → the
   ticket is finished: stop and say so, a fresh run on the same branch
   starts over at Step 3 only when the user asks for it in `notes`). The
   feature's own progress file wins over an older state: a step the state
   names that the feature has already passed by hand (`done` on the current
   tree, `verification.committed`) is skipped, not replayed. Then,
   **capped at Step 6 when
   the code changed since it was verified**: a report naming Step 7, 8 or 9
   re-enters at Step 6 instead whenever `${CLAUDE_PLUGIN_ROOT}/scripts/
   source-tree-hash.sh` (exit 0 and a 40-hex id, else `NEEDS-INPUT`: the
   tooling is broken)
   differs from the feature's
   `pipeline.verification.tree` (a manual security fix, an escalation
   resolved by hand: the review that may already have written `done`
   describes the old tree). A report naming Step 3, 4 or 5 resumes there
   regardless -- the work is not finished, and verifying it would only
   certify a subset. Any dirty path outside those locations is still
   someone else's work: stop.
2. If the current branch name already starts with `{jiraKey}` followed by
   a `-` or `_` (case-insensitive) -- not merely *contains* it, since
   `jiraKey = "OMH-10"` is a substring of an unrelated branch named
   `OMH-100-refactor-pricing` -- stay on it -- skip branch creation, note
   this in the final report, and read the run state (item 1) even when the
   tree is clean: a `committed`/`DONE` ticket is not implemented twice.
3. Otherwise: resolve the default branch
   (`git symbolic-ref refs/remotes/origin/HEAD`, falling back to `main`
   then `master`); with no `origin` remote (`git remote get-url origin`
   fails — a local-only checkout) skip the fetch and branch from the local
   default branch, saying so in the report; otherwise `GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" git fetch` (an expired credential, a passphrase or an unknown host key must fail, not prompt an unattended run — `GIT_TERMINAL_PROMPT` covers git's own credential prompt only, `BatchMode` covers SSH's), then
   `git checkout -b {jiraKey}-{slug} origin/{default}` -- with the start
   point spelled out; without it the branch forks from whatever HEAD is. `{slug}` is a short kebab-case form of the Jira summary (up to
   ~5 meaningful words).
4. Confirm the working tree is on the right branch and clean -- or, on a
   resume, dirty only under item 1's locations -- before Step 3.

### Step 3: Scaffold (conditional) -- `be-crud`

Read `${CLAUDE_PLUGIN_ROOT}/skills/be-jira-auto/references/implement.md` and follow this section there.

### Step 3.5: Extend an Existing Entity (conditional) -- this skill's own tools

Read `${CLAUDE_PLUGIN_ROOT}/skills/be-jira-auto/references/implement.md` and follow this section there.

### Step 4: Author the Work Document Before Calling `be-code`

Read `${CLAUDE_PLUGIN_ROOT}/skills/be-jira-auto/references/implement.md` and follow this section there.

### Step 5: Implement (TDD) -- `be-code`

Read `${CLAUDE_PLUGIN_ROOT}/skills/be-jira-auto/references/implement.md` and follow this section there.

### Step 6: Verify -- `be-verify`

Read `${CLAUDE_PLUGIN_ROOT}/skills/be-jira-auto/references/implement.md` and follow this section there.

### Step 7: Gate -- `be-review` (always) + `be-security` (tiered)

Read `${CLAUDE_PLUGIN_ROOT}/skills/be-jira-auto/references/gate-and-commit.md` and follow this section there.

### Step 8: Fix Loop (conditional, at most 2 rounds) -- `be-fix` -> `be-verify` -> `be-review`

Read `${CLAUDE_PLUGIN_ROOT}/skills/be-jira-auto/references/gate-and-commit.md` and follow this section there.

### Step 9: Stage and Commit -- `be-commit`

Read `${CLAUDE_PLUGIN_ROOT}/skills/be-jira-auto/references/gate-and-commit.md` and follow this section there.

## Gates (fail fast)

Before any `NEEDS-INPUT` or `ABORTED` stop, read this section in `${CLAUDE_PLUGIN_ROOT}/skills/be-jira-auto/references/gate-and-commit.md`: every stop writes the run state it defines.

## Anti-patterns

Read this section in `${CLAUDE_PLUGIN_ROOT}/skills/be-jira-auto/references/gate-and-commit.md` before Step 3.

## Output

At the end of the run, read this section in `${CLAUDE_PLUGIN_ROOT}/skills/be-jira-auto/references/gate-and-commit.md` and follow it.
