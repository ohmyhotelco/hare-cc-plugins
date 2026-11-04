# be-jira-auto: Gate, fix and commit

Part of the `be-jira-auto` skill. `{pluginRoot}` is the plugin root the skill states.

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
- **First, confirm `be-review` wrote a verdict in this call**: read
  `{workDocDir}/.progress/{feature}.json` — `pipeline.status` must now be
  `reviewed`, `done` or `review-failed` (be-review sets one of them only
  after saving the report). Still `verified`: be-review stopped without
  writing (its Step 3.5 validation failed), and the
  `review-report-{feature}.json` on disk is a previous round's or ticket's
  — nothing removes old reports. Stop with `NEEDS-INPUT` quoting be-review's
  own stop message; never read the report in that case.
- Then read `review-report-{feature}.json` (path returned by
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

(the same freshness check as Step 7: `pipeline.status` must have left
`verified`, or the report on disk is stale — `NEEDS-INPUT`.)

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
   `be-verify {feature} --yes` then `be-review {feature} --yes` (Step 7's
   freshness check applies); a FAIL goes
   through Step 8 for that feature (its bounds apply). A pass that changed
   nothing settles the tree; a pass in which a fix changed it is followed by
   at most **one** more pass -- two features whose fixes keep invalidating
   each other do not converge, so a third pass is `NEEDS-INPUT` naming both.
1. Diff the current `git status --porcelain -z -uall` (NUL-separated: a quoted
   or renamed record is otherwise misread) against the Step 2 baseline
   (captured before any implementation work) to get the exact set of
   files this feature touched. On a resume, the baseline already held this
   pipeline's own dirty files (Step 2's exception) -- add the paths in the
   run state's `dirty` list that the current status still lists as well, or the migration and entity from the first run are
   never staged and the commit is a partial feature. A dirty path under
   the Step 2 locations that is in neither set was edited by someone
   during the pause: stop with `NEEDS-INPUT` naming it rather than commit
   it as this ticket's work — unless Step 2 admitted it (a security fix,
   or `notes: own-dirty`), in which case it is staged with the rest.
2. `git add <file1> <file2> ...` -- name every file explicitly. Never
   `git add -A` or `git add .`.
2a. `be-commit` Step 1.5 asks "Continue with commit?" whenever ANY other
   feature under `{workDocDir}/.progress/` is not `reviewed`/`done` -- a
   prompt this run cannot answer. Read every progress file first — this
   feature's included: it must be `reviewed` or `done`, and any file in
   any other status stops the run with `NEEDS-INPUT` naming it instead of
   calling `be-commit`. Its Step 1.5
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
   as `{pluginRoot}/CLAUDE.md` § Pipeline defines it (`be-plan -> be-crud -> be-code ->
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
`{workDocDir}/.progress/jira/{jiraKey}.json` (`mkdir -p` first; no lock — the file is this run's alone, not a feature's
progress file; a stop before Step 0 resolved `workDocDir` or `jiraKey`
writes nothing — there is nothing to resume; a stop at or before Step 2 leaves an existing file as it is and otherwise writes `dirty` as `[]`; a field not known yet is
`null`, `features` `[]`) — a
subdirectory, so the
`.progress/*.json` scans of be-commit and the other skills never read it
as a progress file — `{ "step": "{N}", "status": "NEEDS-INPUT|ABORTED|
committed|DONE", "feature": "{the entry being processed}", "features":
[...], "dirty": ["{every path `git status --porcelain -z -uall` lists under the
Step 2 locations at this stop}"], "commit":
"{short hash, once be-commit returned it}", "timestamp": "{ISO 8601 Z}" }`. Step 9 item 4 writes `committed` with the hash the
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

On `DONE`, write that status to `{workDocDir}/.progress/jira/{jiraKey}.json` (it closes the
resume path: a later run on the same branch starts over at Step 3 only with the user's say-so).
Then report, in `workingLanguage`, starting with a status line:

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
