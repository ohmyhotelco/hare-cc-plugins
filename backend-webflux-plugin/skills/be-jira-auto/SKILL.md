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
`be-commit` in sequence (see `CLAUDE.md` § Pipeline).

**A skill, not a subagent, on purpose.** `be-code`, `be-build`, `be-review` and `be-fix` each
launch an agent (`implement`, `build-doctor`, `code-reviewer`, `review-fixer`) with the `Agent`
tool, and a Claude Code subagent has no `Agent` tool — it cannot spawn subagents. Run as an agent,
four of the seven pipeline steps below could not execute as written. As a skill it runs in the
main session, where `Skill` and `Agent` both exist.

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
  small -- CLAUDE.md § Verification Philosophy explicitly rejects "the
  change is small, no need to verify" as a rationalization, and this
  agent is bound by the same rule. Tiering (see Step 1) only scales
  whether the parallel `be-security` gate runs alongside `be-review` --
  it never skips `be-verify` or `be-review` themselves.
- Never push, open a pull request, or comment on / transition the Jira
  issue. The plugin's own pipeline (`CLAUDE.md` § Pipeline) ends at
  `be-commit` -- stay there. Push/PR/Jira-status is a manual decision for
  the user, made outside this skill.
- Report in the working language read from
  `.claude/backend-webflux-plugin.json` (`workingLanguage`), matching the
  language every other skill in this plugin already reports in.

## Input Parameters

The caller (a slash-command invocation, or the top-level session) provides
these in the prompt:

- `jiraKey` -- Jira issue key, e.g. `OMH-1234`, `ELS-3225` (required): the first token of the argument
- `projectRoot` -- project root path: the current working directory unless the caller names another
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
4. `pluginRoot`: the one line of `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/data/backend-webflux-plugin/pluginRoot` (plugin CLAUDE.md § Configuration) — every `templates/…` path in this document is `{pluginRoot}/templates/…`; missing -- stop with `NEEDS-INPUT`: start a new session so the hook writes it.

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

Read `agents/backend-planner.md` first -- this step and Step 1.5 apply its
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
     `templates/entity-conventions.md` already standardizes). Skip Step
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
     per `templates/test-scenario-template.md`.
   - **Tier** -- classify the ticket to scale the Step 7 gate:
     - `easy`: no new entity, no new public endpoint -- a logic/bug fix on
       code that already exists.
     - `normal`: exactly one new entity scaffolded (one `be-crud` call),
       one domain.
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
   `be-build` may edit the build), the tree is this
   pipeline's own in-progress work left by a `NEEDS-INPUT` exit (a
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
   re-enters at Step 6 instead whenever `{pluginRoot}/scripts/
   source-tree-hash.sh` (exit 0 and a 40-hex id, else `NEEDS-INPUT`: the
   tooling is broken, or the `{pluginRoot}` file is missing -- start a new session)
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
   then `master`), `GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" git fetch` (an expired credential, a passphrase or an unknown host key must fail, not prompt an unattended run — `GIT_TERMINAL_PROMPT` covers git's own credential prompt only, `BatchMode` covers SSH's), then
   `git checkout -b {jiraKey}-{slug} origin/{default}` -- with the start
   point spelled out; without it the branch forks from whatever HEAD is. `{slug}` is a short kebab-case form of the Jira summary (up to
   ~5 meaningful words).
4. Confirm the working tree is on the right branch and clean -- or, on a
   resume, dirty only under item 1's locations -- before Step 3.

### Step 3: Scaffold (conditional) -- `be-crud`

Only for entities Step 1/1.5 marked as brand-new, in dependency order:

```
Skill(skill: "backend-webflux-plugin:be-crud", args: "{EntityName} field1:Type1[:unique][:max=N][:pattern=email|phone|url] ... --domain {domain} --profile {r2dbc|mybatis}")
```

- Before the call, look for `{workDocDir}/.progress/{kebab-case-entity}.json`: present in any
  status → `be-crud`'s Step 2.5 would ask "Continue?" — stop with `NEEDS-INPUT` naming the
  entity, unless `notes` says to start it over, in which case add `--yes`.
- `--domain` and `--profile` are the answers `be-crud` would otherwise ask
  for; passing them is what keeps this run unattended -- both were already
  decided in Step 1. The field flags carry what Step 1 read off the ticket:
  a field the ticket calls unique gets `:unique` (that is the only thing that
  makes `be-crud` emit the `existsBy` pre-check, the named constraint mapping
  and `Duplicate{Field}Exception`), a bounded one `:max=N`, an email/phone/
  url one `:pattern=…`. A flag left off is a validator that does not exist. If `config.dataProfile == "both"` and the skill still
  prompts, answer with the value decided in Step 1 (default `r2dbc` unless
  Step 1 found a reason to match an existing `mybatis` module).
- Entity already exists (extend, not create): do **not** call `be-crud` --
  see Step 3.5 instead.
- No entity involved at all (pure logic/bug-fix ticket on an existing
  endpoint): note "Step 3: skipped -- no new entity" and continue to Step 4.

### Step 3.5: Extend an Existing Entity (conditional) -- this skill's own tools

For every entity Step 1/1.5 marked "extend, not create", performed by
this skill directly (`Write`/`Edit`/`Bash`), **before** Step 4 authors the
work document -- schema, entity field and mapping are scaffold, the same
kind of untested output `be-crud` produces for a new entity (behavior is
still written RED → GREEN by `be-code` in Step 5); there is no "alter"
skill in this plugin, so this is not
`be-crud`'s job and not `implement`'s job either; `implement` only ever
sees a scenario list, never "this entity needs a new column" as a task in
its own right:

1. Determine `{next}` the same way `skills/be-crud/SKILL.md`'s Shared
   Derivation Rules do (glob `src/main/resources/migration/V*__*.sql`,
   take the max version + 1), and write
   `src/main/resources/migration/V{next}__alter_{snake_case_table}_add_{field}.sql`
   with the new column(s) -- one migration per entity, even when it gains
   more than one field.
2. Edit the entity class (R2DBC: `@Column`-annotated field; MyBatis: plain
   field + the corresponding `<result>` mapping in `{EntityName}Mapper.xml`)
   directly, following `templates/entity-conventions-r2dbc.md` or
   `templates/entity-conventions-mybatis.md` conventions matching the entity's
   profile (Lombok `@Getter`/`@Setter` when `config.lombokEnabled == true`) -- so
   the class already compiles with the new field before `be-code`'s TDD
   cycle starts.
3. Add a repository/mapper query method only if a scenario in Step 1/1.5
   actually needs one (e.g. `existsBy{NewField}` for a uniqueness check);
   otherwise leave the repository/mapper untouched. A field the ticket calls
   **unique** gets the same three parts `be-crud` emits for one: the ALTER
   migration adds `CONSTRAINT uk_{table}_{column} UNIQUE ({column})` (the
   `existsBy` pre-check alone is a race -- two concurrent creates both pass
   it, and only the constraint stops the second row), the executor maps a
   `DataIntegrityViolationException` naming that constraint to
   `Duplicate{Field}Exception`, and the web layer maps that to 409.
4. Do not touch command/query/view DTOs or router/handler code here --
   that is ordinary TDD scope and belongs to `be-code` in Step 5, exactly
   like any other scenario.

### Step 4: Author the Work Document Before Calling `be-code`

Mandatory, even when Step 3 already generated
`{workDocDir}/{kebab-case-entity}.md` via `be-crud` -- this skill cannot
answer `be-code`'s "review and confirm to proceed" prompt (`skills/be-code/SKILL.md`
Step 3), so the work document must already exist and be final before Step
5 runs.

1. If `{workDocDir}/{feature}.md` already exists (from `be-crud`): merge
   in any scenario from Step 1 that the default scaffold does not cover
   (a ticket-specific business rule, a non-CRUD action).
2. If it does not exist (editing an existing entity, no scaffold run):
   create `{workDocDir}/{feature}.md` from
   `templates/work-document-template.md` with the scenario list decided
   in Step 1, `- [ ]` format, no `?` markers -- every uncertain scenario
   must already have been resolved in Step 1; nothing marked `?` reaches
   this file, since nobody is present to confirm or drop it.
3. `feature` = kebab-case of the primary entity name, or kebab-case of
   `{jiraKey}` when the ticket is not centered on one entity.
4. **Every entity Step 3 scaffolded is a feature of its own**: `be-crud`
   wrote `{workDocDir}/{kebab-case-entity}.md` for each, so do items 1-2
   for each of them, not only for the primary -- a secondary entity whose
   document is left at the scaffold's defaults never reaches `be-code`,
   `be-verify` or `be-review`. Keep the list (`features`, in Step 1's
   dependency order); Steps 5-8 iterate it.

### Step 5: Implement (TDD) -- `be-code`

For each entry of `features` (Step 4 item 4), in dependency order:

```
Skill(skill: "backend-webflux-plugin:be-code", args: "{workDocDir}/{one feature}.md --yes")
```

- Because the work document already exists, `be-code` enters file-path
  mode directly (its Step 1 -> Step 3.5) and skips the interactive
  approval flow entirely. `--yes` answers its demotion prompt: a second
  ticket on an existing entity finds `.progress/{feature}.json` at `done`
  from the first, and re-implementing it is exactly what this ticket asks
  for — the prompt is the operator's, and here the operator is Step 1.
- The skill runs RED -> GREEN per scenario and writes its own tests --
  there is no separate "write unit tests" step in this plugin's pipeline.
- If `be-code`'s own report leaves `pipeline.status` at `"implementing"`
  with a scenario unfinished (3 consecutive failures) -- stop with
  `NEEDS-INPUT`, naming exactly which scenario is unfinished and the
  reason the skill reported. If every scenario is `- [x]` and only its
  final full build failed (checkstyle first runs there, never in the
  per-class cycles) -- go to Step 6.1: that is what `be-build` is for.

Steps 6–8 run **per entry of `features`** (Step 4 item 4): `{feature}` below is the one being
processed, and a FAIL on any entry stops the run at that entry (later entries depend on it).

### Step 6: Verify -- `be-verify`

```
Skill(skill: "backend-webflux-plugin:be-verify", args: "{feature} --yes")
```

- `--yes` answers `be-verify`'s demotion/staleness confirmations (a resume re-entering here from `reviewed`/`done`/`escalated`) — this run decided the re-entry; the report is still read in full.
- Read the 5-row report (Compilation/Checkstyle/Tests/Build/Coverage).
- The coverage percentage is report-only (`docs/decisions.md` Decision 6)
  -- carry it into the final report, never treat the number as a failure
  condition. A Coverage row that FAILS (no report produced) is part of
  `Overall`, like any other row.
- Overall PASS -- go to Step 7.
- Overall FAIL -- go to Step 6.1.

#### Step 6.1: Auto-fix the build -- `be-build` (at most one call)

```
Skill(skill: "backend-webflux-plugin:be-build", args: "")   # be-build takes no argument: it builds the project, not a feature
```

`be-build` already retries internally up to 3 times -- call it **once**,
never wrap it in an outer retry loop of this skill's own. Then re-run
`be-verify {feature} --yes` once to confirm:

- PASS -- go to Step 7.
- Still FAIL -- stop with status `ABORTED`, listing the exact FAIL rows
  from the latest `be-verify` report.

### Step 7: Gate -- `be-review` (always) + `be-security` (tiered)

A `Skill` call loads that skill's steps into this same session -- nothing
runs in parallel, and two multi-step procedures loaded in one turn
interleave their stops and lock handling. Run them one after the other,
`be-security` first (read-only, no lock, no report file -- its findings
are read from its own output before `be-review`'s steps begin):

```
Skill(skill: "backend-webflux-plugin:be-security", args: "")   # no argument = its default scope: the whole base package plus src/main/resources (a dotted basePackage is not a path)
Skill(skill: "backend-webflux-plugin:be-review", args: "{feature} --yes")
```

Run `be-security` when tier is `normal` or `extreme`, or when Step 1's
security-sensitive override fired regardless of tier. At `easy` tier with
no override, skip it -- note "Step 7: be-security skipped -- easy tier, no
new entity/endpoint surface" and treat this step as `be-review`-only.

**`be-review` branch:**
- Read `review-report-{feature}.json` (path returned by
  `skills/be-review/SKILL.md` Step 4): verdict, critical/warning/
  suggestion counts.
- Verdict PASS -- with or without warnings/suggestions -- and no security
  block (below): skip Step 8, go straight to Step 9. A PASS with warnings
  leaves the feature `reviewed`, and `be-fix` on a `reviewed` feature asks
  "Continue?" (its Step 2.5 demotion check) -- a prompt this run cannot
  answer. Carry the warnings into the Step 10 summary instead.
- Verdict FAIL -- go to Step 8.

**`be-security` branch (when run):**
- `be-security` has no persisted report file and no `be-fix` integration
  in this plugin -- read its findings directly from the skill's own
  report text (Critical / Warnings / Suggestions, per
  `skills/be-security/SKILL.md` Step 4).
- **Any Critical finding blocks the pipeline.** There is no automated
  security-fix skill in this plugin, so do not attempt to route these
  into `be-fix` or fix them inline yourself. Stop with status
  `NEEDS-INPUT`, quoting every Critical finding verbatim (`file:line`,
  description, suggestion) and asking the user to fix them manually (or
  via a manual `be-code`/`implement` edit), then re-run
  `/backend-webflux-plugin:be-security` to confirm before resuming this
  agent — the resume re-enters at Step 6, not here: the fix changed the
  tree, and the `be-review` that ran alongside may already have written
  `reviewed`/`done` for code that no longer exists (Step 2's tree rule).
- Warnings/Suggestions are non-blocking -- carry them into the Step 9/final
  report as-is; they do not gate progression to Step 8/9.

### Step 8: Fix Loop (conditional, at most 2 rounds) -- `be-fix` -> `be-verify` -> `be-review`

```
Skill(skill: "backend-webflux-plugin:be-fix", args: "{feature}")
```

then -- a fix changed code, and `be-review` refuses a `fixing` feature until it is re-verified:

```
Skill(skill: "backend-webflux-plugin:be-verify", args: "{feature} --yes")
```

(`Overall: FAIL` here → one `be-build` + re-verify exactly as Step 6.1; still FAIL → `ABORTED`.) Then

```
Skill(skill: "backend-webflux-plugin:be-review", args: "{feature} --yes")
```

- **Read `pipeline.fix.round` before every `be-fix` call**, not only the
  first. The counter persists across runs (be-review zeroes it only on a
  clean PASS, be-commit only before a commit); if it is already >= 2, one
  more call reaches round 3 and `be-fix` Step 3's "Continue anyway?"
  prompt -- stop with `NEEDS-INPUT` instead of calling. (A feature
  entering at round 1 passes the first check and would reach round 3 on
  the second call without this.)
- **Read `{workDocDir}/.progress/fix-report-{feature}.json` (the path
  `pipeline.fix.reportFile` records) and `pipeline.status` before calling
  `be-verify`/`be-review`.** If `escalated[]` is non-empty, or the status
  is `escalated` (the post-fix build failed even with every issue marked
  fixed -- `be-verify` would prompt on it) -- stop with `NEEDS-INPUT` and
  list the escalated issues, or the build failure, verbatim. A partially escalated fix is a known unresolved issue;
  re-verifying and re-reviewing around it can PASS-with-warnings and reach
  the commit with that issue still open. (`be-review` refuses `escalated`
  outright, and `be-verify` would re-admit the partial fix silently.)
- **Hard bound: call `be-fix` at most 2 times** for a given feature.
  Reason: `skills/be-fix/SKILL.md` Step 3 blocks on a "Continue anyway?
  (y/n)" prompt once `pipeline.fix.round >= 3` -- a third call would hang
  on a prompt this unattended agent cannot answer, so it must never be
  made.
- If review is still FAIL, or still has a `critical` issue, after 2
  rounds -- stop with status `ABORTED`, listing the remaining issues
  verbatim (severity, `file:line`, message) from the latest
  `review-report-{feature}.json`. Never assume issues are resolved without
  a report confirming it.
- Review PASS (even with non-critical suggestions) after round 1 or 2 --
  stop the loop, go to Step 9.

### Step 9: Stage and Commit -- `be-commit`

0. Settle the tree first: Steps 6–8 ran per feature, and a later feature's
   `be-fix`/`be-build` changed the tree every earlier feature was verified
   on. For each feature (in `features` order) whose
   `pipeline.verification.tree` differs from the current
   `{pluginRoot}/scripts/source-tree-hash.sh`, run
   `be-verify {feature} --yes` then `be-review {feature} --yes`; a FAIL goes
   through Step 8 for that feature (its bounds apply). A pass that changed
   nothing settles the tree; a pass in which a fix changed it is followed by
   at most **one** more pass -- two features whose fixes keep invalidating
   each other do not converge, so a third pass is `NEEDS-INPUT` naming both.
1. Diff the current `git status --porcelain -z` (NUL-separated: a quoted
   or renamed record is otherwise misread) against the Step 2 baseline
   (captured before any implementation work) to get the exact set of
   files this feature touched. On a resume, the baseline already held this
   pipeline's own dirty files (Step 2's exception) -- add every dirty path
   under the Step 2 locations too, or the migration and entity from the
   first run are never staged and the commit is a partial feature.
2. `git add <file1> <file2> ...` -- name every file explicitly. Never
   `git add -A` or `git add .`.
2a. `be-commit` Step 1.5 asks "Continue with commit?" whenever ANY other
   feature under `{workDocDir}/.progress/` is not `reviewed`/`done` -- a
   prompt this run cannot answer. Read every progress file first; if one
   belongs to another feature and is in any other status, stop with
   `NEEDS-INPUT` naming it instead of calling `be-commit`. Its Step 1.5
   also prompts when a `reviewed`/`done` feature not yet
   `pipeline.verification.committed` has a `pipeline.verification.tree`
   that differs from `{pluginRoot}/scripts/source-tree-hash.sh
   --staged` -- compute that once after item 2 and compare; after item 0 a
   mismatch here means item 2 missed a file: stage it (a file outside the
   Step 2 locations is not this feature's -- stop with `NEEDS-INPUT`).
3. ```
   Skill(skill: "backend-webflux-plugin:be-commit", args: "topic: {jiraKey} <one-line summary>")
   ```
4. Read `be-commit`'s own report; take the short hash from the
   `git rev-parse --short HEAD` output it printed -- never fabricate one --
   and write it to the run state at once (`status: committed`, `commit`).
5. **Do not push, do not open a pull request, do not transition or
   comment on the Jira issue.** This is the pipeline's final step, exactly
   as `CLAUDE.md` § Pipeline defines it (`be-plan -> be-crud -> be-code ->
   be-verify -> be-review <-> be-fix -> be-commit`, no push/PR step).

## Gates (fail fast)

| Gate | Condition to proceed | On failure |
|---|---|---|
| Step 0 | `.claude/backend-webflux-plugin.json` exists | `ABORTED` -- tell the user to run `be-init` |
| Step 0.5 | Exactly one Jira MCP tool resolved (or one already confirmed via `notes`) | `NEEDS-INPUT` -- report zero or multiple candidates found, ask the user to connect/pick one |
| After Step 1 | Stated approach has no gap, or a Proposed Solution was fully drafted | `NEEDS-INPUT` -- quote the exact gap in the stated approach |
| Step 1.5 | Only when Step 1 drafted its own proposal (no stated approach): user has confirmed/corrected it | `NEEDS-INPUT` -- report the full proposal + open questions, stop before any git/scaffold action |
| Step 2 | Working tree clean before branching | `NEEDS-INPUT` -- ask the user to handle their own uncommitted work |
| After Step 5 | `be-code` reports every scenario `- [x]` | `NEEDS-INPUT` -- name the unfinished scenario/entity (a failed final build with every scenario done goes to Step 6.1 instead) |
| After Step 6/6.1 | `be-verify` Overall PASS (one `be-build` attempt allowed) | `ABORTED` -- list the FAIL rows |
| Step 7 (`be-security` branch) | Zero Critical findings (when the gate ran) | `NEEDS-INPUT` -- quote every Critical finding, ask for a manual fix |
| After Step 8 | `be-review` verdict PASS (at most 2 `be-fix` rounds) | `ABORTED` -- list remaining critical/warning issues |
| Step 9 | `be-commit` exits 0 with a confirmed short hash | Report the commit failure verbatim, stop -- no retry |

Every early stop (`NEEDS-INPUT`/`ABORTED`) writes the run state to
`{workDocDir}/.progress/jira/{jiraKey}.json` (`mkdir -p` first; a stop
before Step 0 resolved `workDocDir` or `jiraKey` writes nothing — there is
nothing to resume; a field not known yet is `null`, `features` `[]`) — a
subdirectory, so the
`.progress/*.json` scans of be-commit and the other skills never read it
as a progress file — `{ "step": "{N}", "status": "NEEDS-INPUT|ABORTED|
committed|DONE", "feature": "{the entry being processed}", "features":
[...], "commit": "{short hash, once be-commit returned it}", "timestamp":
"{ISO 8601 Z}" }`. Step 9 item 4 writes `committed` with the hash the
moment be-commit reports it (a crash before `DONE` must not replay the
commit); the Output section writes `DONE`. Step 2 reads it whenever the
branch carries `{jiraKey}` (a resume with no file stops with `NEEDS-INPUT`
asking which step to resume at) — and every stop must report which
pipeline step it stopped at and the current `pipeline.status` for each affected feature
(read from `{workDocDir}/.progress/{feature}.json` when it exists), so the
user knows exactly which `be-*` skill to resume with by hand. Never stop
silently.

## Anti-patterns

- Assuming a specific Jira MCP server name instead of resolving it via
  `ToolSearch` in Step 0.5 -- the tool that exists in one project's
  session (cloud connector, local gateway, or something else entirely)
  is not guaranteed to exist, or be the right one, in another's.
- Guessing which Jira MCP tool to use when `ToolSearch` returns more than
  one candidate -- two connected Jira sources can point at two different
  Jira instances; stop and ask instead of picking one silently.
- Re-deriving a design the ticket's own Technical Approach already states
  -- extract from it, do not second-guess a decision the ticket already
  made.
- Implementing a self-drafted Proposed Solution (Step 1.5) without
  stopping for confirmation first -- a self-drafted design is a
  proposal, not a mandate, and this skill has no way to detect the user
  silently disagreed with it once code already exists.
- Calling `be-crud` on an entity that already exists (discards its
  pipeline history -- see `skills/be-crud/SKILL.md` Step 2.5).
- Letting `be-code` draft scenarios and wait for interactive approval
  instead of authoring the work document up front in Step 4.
- Calling `be-fix` a third time on the same feature (hangs on the
  round-3 confirmation prompt).
- Skipping `be-verify` or `be-review` because the ticket looks small (tier
  only scales the `be-security` gate, never these two).
- Routing a `be-security` Critical finding into the `be-fix` loop, or
  fixing it inline -- there is no automated security-fix contract in this
  plugin; stop with `NEEDS-INPUT` instead.
- Loading `be-review` and `be-security` in the same turn "to run them
  concurrently" -- a `Skill` call runs inline in this session; two loaded
  at once interleave their stops and lock handling. `be-security` first,
  then `be-review`.
- Running `git add -A`/`git add .`, or `git stash`/`git checkout .` to
  discard the user's own uncommitted work without asking.
- Pushing, opening a pull request, or commenting on / transitioning the
  Jira issue -- none of that is part of this plugin's pipeline, and none
  of it has this skill's explicit authorization to act on the user's
  behalf.
- Reporting `DONE` without a real short hash confirmed via
  `git rev-parse --short HEAD`.

## Output

Write `{workDocDir}/.progress/jira/{jiraKey}.json` with the final status (`DONE` closes the
resume path: a later run on the same branch starts over at Step 3 only with the user's say-so),
then report, in `workingLanguage`, starting with a status line:

```
Status: DONE | NEEDS-INPUT | ABORTED (stopped at Step N)

Jira: {jiraKey} -- {summary}
Jira source: {mcp server resolved in Step 0.5}
Approach: {"ticket-stated" | "proposed, confirmed via notes on {date}"}
Tier: {easy|normal|extreme}
Branch: {branch}
Entities/features: {list}
Files changed: {count}
Verify: {PASS/FAIL per row}
Review: {overallScore}/10, {critical} critical fixed over {round} be-fix round(s)
Security: {"not run (easy tier)" | "PASS, N warning(s)" | "BLOCKED, N critical"}
Coverage: {linePercent}% (report-only)
Commit: {short hash, or "none"}

Not pushed, no pull request opened -- push/PR/Jira transition is a manual
next step for the user.
```

For `NEEDS-INPUT`, the report must contain the exact questions the user
needs to answer before re-invoking this skill.
