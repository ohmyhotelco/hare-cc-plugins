---
name: be-recall
description: "Recall development rules and check for violations."
argument-hint: "[commit | tdd | build | coding | api | data]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# Recall Rules

Display development rules from the plugin CLAUDE.md and scan recent work for
concrete violations of them. Every check below names an exact scope (a git
range, a directory, a file glob) — report results against that scope only,
never as a claim about the whole codebase.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`.
2. If missing: show general rules from the plugin CLAUDE.md only, and skip
   Step 3 entirely. Report: "not verified: no
   `.claude/backend-webflux-plugin.json` found, so project-specific checks
   (webLayer, dataProfile) cannot be scoped correctly. Showing rules only."
   Guessing a profile instead of declaring it missing would risk scanning
   the wrong file shapes (see the `api`/`data` branching below).
3. If present, read and hold onto two values — Step 3 branches on them so the
   scan targets match what this project actually contains:
   - `webLayer` (default `"functional"` if absent)
   - `dataProfile` (default `"both"` if absent)

### Step 1: Parse Argument

Map argument to section:

| Argument | Section | Source |
|----------|---------|--------|
| (none) | All rules summary | CLAUDE.md (all sections) |
| `commit` | Commit Standards | CLAUDE.md § Commit Standards |
| `tdd` | TDD Process + Test Scenario Writing | CLAUDE.md § TDD + Scenario Rules |
| `build` | Build Standards | CLAUDE.md § Build Standards |
| `coding` | Coding Standards + Entity/DTO Conventions | CLAUDE.md § Coding Standards |
| `api` | API Conventions + Naming | CLAUDE.md § API Conventions + Naming Conventions |
| `data` | Entity/Repository/Mapper Conventions | templates/entity-conventions.md (shared) + templates/entity-conventions-r2dbc.md / -mybatis.md (profile-specific) |

### Step 2: Display Rules

Read the relevant section(s) from the plugin CLAUDE.md and display them
clearly in the working language.

For each rule, show:
- The rule statement
- Why it exists (one line — this is what lets the reader apply the rule to a
  case the examples below don't cover)
- A brief example (if applicable)

### Step 3: Check for Violations

Before scanning, state the scope you're about to scan (the exact command or
directory). If a scan cannot run at all (not a git repo, directory missing,
fewer commits than the range needs), report "not verified: <reason>" for
that check instead of skipping it silently or reporting zero violations —
zero violations and "couldn't scan" look identical to the user unless you
say which one happened.

#### `commit` violations:
- Scope: `git log --oneline -5`.
- If the command fails (not a git repo, no commits yet): "not verified: no
  git history available."
- For each message, check: wrong tense, prefix usage (`fix:`, `feat:`, etc.),
  exceeds 50 characters, lowercase start, missing blank line before body,
  body lines exceeding 72 characters.

#### `tdd` violations:
- Scope: all test files under `{testDir}`.
- If `{testDir}` doesn't exist: "not verified: {testDir} not found."
- For each test file, check:
  - Test methods not using `snake_case` (method name doesn't match the
    convention shown in Coding Standards, e.g.
    `duplicate_email_returns_409_Conflict`)
  - Missing assertions: a `@Test`/`@ParameterizedTest` method whose body
    contains none of `StepVerifier`, `assertThat`, `Assertions.`, or a
    `.verify*()` call
  - Test scenario format issues: a scenario list in a work document that
    doesn't follow the Given/When/Then shape in
    `templates/test-scenario-template.md`

#### `build` violations:
- Scope: `build/` directory presence/freshness and `build.gradle(.kts)`
  plugin configuration.
- If `build/` doesn't exist: "not verified: no build output found — run
  be-build or the configured build command, then re-run `be-recall build`."
  This is not itself a violation; it means the check couldn't run.
- If `build/` exists, check:
  - `build/` older than the newest file under `{sourceDir}` (stale build —
    suggests the last build predates the current code)
  - `build.gradle(.kts)` missing the JaCoco plugin block when `coverage:
    true` in config
  - `build.gradle(.kts)` missing the Checkstyle plugin block when
    `checkstyle: true` in config

#### `coding` violations:
- Scope: Java files from `git diff --name-only HEAD~3`.
- If the repo has fewer than 3 commits: "not verified: fewer than 3 commits
  available; falling back to `git diff --name-only HEAD` (uncommitted
  changes only)." Use that fallback scope rather than reporting nothing.
- For each file, check:
  - Missing final newline
  - Class where `record` should be used (DTOs — Command/Query/View)
  - Non-standard naming (check against the Naming Conventions table)

#### `api` violations:
Branch on the `webLayer` value read in Step 0 — a check written for one web
layer style finds nothing when run against the other, which reads as "no
violations" even when the code is riddled with them. Run exactly one branch.

- If `webLayer == "functional"` (the plugin default — see CLAUDE.md § Web
  Layer): scan `*Router.java` / `*Handler.java` under each domain's `api/`
  directory for:
  - Non-kebab-case path strings in `RequestPredicates.path(...)` / route
    builder calls
  - Singular resource names in route paths (plural expected: `/employees`,
    not `/employee`)
  - `ServerResponse.status(...)` codes that don't match the API Conventions
    table (e.g. a POST handler returning `200` instead of `201`)
  - Missing router-level `onErrorResume` mapping for a domain exception
- If `webLayer == "annotated"` (the named exception — a domain deliberately
  mirroring an existing annotated-controller module): scan `*Controller.java`
  files for:
  - Wrong `@GetMapping`/`@PostMapping`/etc. for the action performed
  - Non-kebab-case `@RequestMapping` paths
  - Missing `@ResponseStatus`
  - Singular resource names in URLs
- Do not run the `@ResponseStatus`/`*Controller.java` checks when
  `webLayer == "functional"` — functional endpoints have no controller
  classes at all, so that scan is a guaranteed false "no violations."

#### `data` violations:
Branch on the `dataProfile` value read in Step 0 — same reasoning as `api`:
a profile-specific check run against the wrong profile finds nothing to
scan and silently reports a clean result.

- If `dataProfile` is `"r2dbc"` or `"both"`: scan R2DBC entity classes under
  `data/` for:
  - Missing `sequence` + `id` dual key pattern
  - Missing `@Table` annotation, non-snake_case table names
  - Missing explicit `@Column` mapping
- If `dataProfile` is `"mybatis"` or `"both"`: scan call sites of `*Mapper`
  methods for:
  - A mapper method invoked directly inside a `Mono`/`Flux` chain without
    `.subscribeOn(Schedulers.boundedElastic())` or an enclosing
    `Mono.fromCallable(...)`
- If `dataProfile == "r2dbc"`, skip the MyBatis mapper check — there are no
  mappers in this project. If `dataProfile == "mybatis"`, skip the R2DBC
  entity check — there are no R2DBC entities. Only `"both"` runs both
  branches.

### Step 4: Report

Lead with evidence, not the verdict: state what was scanned (the exact
command/directory from Step 3, or the "not verified: <reason>" line) before
stating whether violations were found.

Display each violation found with:
- File path and line number
- Rule violated
- Suggested fix

If a check could not run, report it as its own line rather than omitting
the section or folding it into "no violations":
> "not verified: {reason}"

If no violations found within the scanned scope:
> "No violations detected in {the stated scope, e.g. 'the last 5 commits'}."

Never report the unscoped "All rules are being followed" — Step 3's checks
only cover the named scope (5 commits, 3 commits of diff, one directory),
not the project's full history or every file, so a blanket compliance claim
overstates what was actually scanned.

If violations can be auto-fixed (e.g., missing final newline):
> "Auto-fixable violations found. Apply fixes? (y/n)"

Apply fixes only with user confirmation.

## Examples

**Example 1 — clean run, scope stated**

Input: `/backend-webflux-plugin:be-recall commit`

1. Step 0 reads config (found; `webLayer`/`dataProfile` unused for this arg).
2. Step 2 displays the Commit Standards section.
3. Step 3 runs `git log --oneline -5`, gets 5 messages, checks each against
   the commit rules.
4. Step 4 reports:
   > Scanned: last 5 commits (`git log --oneline -5`).
   > No violations detected in the last 5 commits.

**Example 2 — webLayer branching catches a real violation**

Input: `/backend-webflux-plugin:be-recall api`, config has
`"webLayer": "functional"`.

1. Step 0 reads config: `webLayer: "functional"`.
2. Step 3 (`api` branch) scans `*Router.java` / `*Handler.java` under
   `employee/api/` — not `*Controller.java`, which would be the wrong style
   for this project and would always report zero violations regardless of
   the actual code.
3. Finds `EmployeeHandler.java:42` returning `ServerResponse.status(200)`
   from the `createEmployee` handler.
4. Step 4 reports:
   > Scanned: `EmployeeRouter.java`, `EmployeeHandler.java` under
   > `employee/api/`.
   > 1 violation found:
   > - `EmployeeHandler.java:42` — POST handler returns `200 OK`; API
   >   Conventions require `201 Created` for create. Fix:
   >   `ServerResponse.status(HttpStatus.CREATED)`.

**Example 3 — scan can't run, declared instead of skipped**

Input: `/backend-webflux-plugin:be-recall build`, no `build/` directory
exists yet.

Step 4 reports:
> not verified: no `build/` directory found — run `be-build` or the
> configured build command first, then re-run `be-recall build`.
