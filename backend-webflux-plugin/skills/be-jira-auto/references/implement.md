# be-jira-auto: Scaffold, implement and verify

Part of the `be-jira-auto` skill. `{pluginRoot}` is the plugin root the skill states.

### Step 3: Scaffold (conditional) -- `be-crud`

Only for entities Step 1/1.5 marked as brand-new, in dependency order:

```
Skill(skill: "backend-webflux-plugin:be-crud", args: "{EntityName} field1:Type1[:unique][:nullable][:max=N][:pattern=email|phone|url] ... --domain {domain} --profile {r2dbc|mybatis}")
```

- Before the first call, look for `{workDocDir}/.progress/{kebab-case-entity}.json` for **every**
  entity to scaffold: one at `implementing` or later (`scaffolded` does not prompt) → `be-crud`'s
  Step 2.5 would ask "Continue?" — stop with `NEEDS-INPUT` naming the entity before anything is
  written, unless `notes` says to start it over, in which case add `--yes`.
- `--domain` and `--profile` are the answers `be-crud` would otherwise ask
  for; passing them is what keeps this run unattended -- both were already
  decided in Step 1. The field flags carry what Step 1 read off the ticket:
  a field the ticket calls unique gets `:unique` (that is the only thing that
  makes `be-crud` emit the `existsBy` pre-check, the named constraint mapping
  and `Duplicate{Field}Exception`), a bounded one `:max=N`, an email/phone/
  url one `:pattern=…`. A field the ticket calls optional gets `:nullable` — without it the column is `NOT NULL` and a "request without {field}" scenario fails at the database. A flag left off is a validator (or a nullability) that does not exist. If `config.dataProfile == "both"` and the skill still
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
   directly, following `{pluginRoot}/templates/entity-conventions-r2dbc.md` or
   `{pluginRoot}/templates/entity-conventions-mybatis.md` conventions matching the entity's
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
   `{pluginRoot}/templates/work-document-template.md` with the scenario list decided
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

- `--yes` answers `be-verify`'s demotion/staleness confirmations (a resume re-entering here from `reviewed`/`done`/`escalated`) — this run decided the re-entry; the report is still read in full. A `be-verify`/`be-review` stop on unfinished `- [ ]` scenarios (a work document edited during a pause) is `NEEDS-INPUT` naming them: the scenario has to go through Step 5 first.
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
