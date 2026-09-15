---
name: be-commit
description: "Create a commit from staged changes with validated message."
argument-hint: "[topic: <hint>] [short]"
user-invocable: true
allowed-tools: Read, Edit, Write, Glob, Bash
---

# Smart Commit

Create a git commit from already-staged changes with a validated commit message following project conventions.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, tell the user to run `/backend-webflux-plugin:be-init` first and stop
3. `pluginRoot`: the one line of `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/data/backend-webflux-plugin/pluginRoot` (plugin CLAUDE.md § Configuration) — every `templates/…` path in this document is `{pluginRoot}/templates/…`; missing → stop: start a new session so the hook writes it.

### Step 1: Check Staged Changes

Run `git diff --staged` to see what is staged.

- If nothing is staged, inform the user:
  > "No staged changes found. Stage your changes with `git add` first."
- Stop if nothing is staged

### Step 1.5: Pipeline Status Warning

Check if any feature progress files exist in `{workDocDir}/.progress/`:

1. Glob `{workDocDir}/.progress/*.json` — exclude files matching `review-report-*.json` or `fix-report-*.json` (only keep entity progress files)
2. For each progress file, read `pipeline.status`
3. If any feature has a status other than `reviewed` or `done` (i.e., `scaffolded`, `implementing`, `implemented`, `verified`, `verify-failed`, `review-failed`, `fixing`, `resolved`, `escalated`):
   > "Warning: Feature '{feature}' is in '{status}' status — review/verification may not be complete."
   > "Continue with commit?"
   If the user declines, stop here.
4. Compute `{pluginRoot}/scripts/source-tree-hash.sh --staged` once — the index is what this commit will contain (exit 0 and a 40-hex id, else a tooling error: report it and stop — an empty value must not be compared). For each `reviewed`/`done` feature that has not been committed since it was verified (`pipeline.verification.committed` is not `true`; Step 6.5 sets it), it must equal `pipeline.verification.tree`; different (or the field missing) — an unstaged edit, an untracked new file, or a change made after `be-verify` ran:
   > "Warning: the staged tree is not the tree feature '{feature}' was verified on — the review describes different code. Stage everything under src/ and the build files, or re-run be-verify and be-review."
   > "Continue with commit?"
   If the user declines, stop here. A feature already committed on the tree it was verified on is not re-checked: later tickets change the tree without invalidating its record.
5. If all features are `reviewed`, `done` with a matching (or already committed) tree, or no progress files exist: proceed without warning

### Step 2: Parse Arguments

- `topic: <topic>` -- optional topic hint for the commit message (inferred from diff if omitted)
- `short` -- if present, generate subject line only (skip body)

### Step 3: Security Scan

Run `{pluginRoot}/scripts/pre-commit-check.sh security` to scan staged changes for secrets and dangerous files (the scan is not optional).

- If the script reports issues, show the findings and **abort the commit**
- Do not proceed to message drafting until the security scan passes

### Step 4: Analyze Changes

From the staged diff, determine:

1. Which files were changed, added, or deleted
2. The nature of the change: new feature, enhancement, bug fix, refactoring, test, configuration
3. The domain/module affected
4. If a topic hint was provided, use it to guide the message focus

### Step 5: Draft Commit Message

Follow CLAUDE.md commit standards:

1. **Subject line** (mandatory):
   - English, present tense, imperative mood ("Add", "Fix", "Update", not "Added", "Fixes")
   - Maximum 50 characters
   - Start with uppercase letter (exception: lowercase identifiers like function names)
   - No prefix (no `fix:`, `feat:`, `docs:`, etc.)
   - Focus on "why" rather than "what"

2. **Body** (skip if `short` argument):
   - Blank line after subject
   - Maximum 72 characters per line
   - Only break within paragraphs when exceeding 72 characters
   - Describe the motivation and context
   - Do not mention test code
   - Do not list file names
   - Do not include tool advertisements or branding

**Worked example 1 — new feature:**

Staged diff summary: adds `command/CreateEmployee.java`, `commandmodel/CreateEmployeeCommandExecutor.java`, `domain/api/EmployeeRouter.java`; wires a new `POST /hr/employees` route.

```
Add employee creation endpoint

Introduce the command executor and router wiring needed to
create an employee via POST /hr/employees. The executor
validates the email is unique before persisting, matching the
duplicate-check pattern used by the existing customer domain.
```

**Worked example 2 — bug fix, with an edge case:**

Staged diff summary: changes `data/EmployeeRepository.java` and `commandmodel/UpdateEmployeeCommandExecutor.java` only — a one-line fix plus a null check. Small diffs are still expected to explain *why*, not just restate the diff:

```
Fix duplicate-email race on concurrent update

Two concurrent updates to the same email could both pass the
uniqueness check before either write committed. Wrap the check
and update in TransactionalOperator so the second writer sees
the first writer's row and fails the uniqueness constraint
instead of silently overwriting it.
```

Edge case: if the diff is a one-line change with no obvious "why" recoverable from the diff alone (e.g. a config value bump), keep the body short rather than inventing a rationale — a single sentence stating what changed and, if known from the topic hint, why is acceptable; never fabricate a motivation the diff doesn't support.

### Step 6: Validate

Check the draft message against commit message rules from CLAUDE.md:

- [ ] English (#1)
- [ ] Present tense imperative (#2)
- [ ] Subject <= 50 characters (#3)
- [ ] Blank line between subject and body (#4)
- [ ] Body lines <= 72 characters (#5)
- [ ] Only break within a paragraph when exceeding 72 characters (#6)
- [ ] No test code mentions (#7)
- [ ] No prefix (fix:, feat:, docs:, etc.) (#8)
- [ ] Starts with uppercase (or justified lowercase identifier) (#9)
- [ ] No branding/promotional content (#10)

If validation fails, revise the message.

Note: CLAUDE.md rules #11-13 (staged-only, ensure staging, separate git commands) are workflow constraints enforced in Step 1 and the Constraints section, not message format rules.

### Step 6.5: Close the Fix Cycle

Before the commit, for every feature progress file whose status is `reviewed` or `done`, set
`pipeline.fix.round` to `0` — and, when its `pipeline.verification.tree` equals the staged hash Step 1.5
computed, `pipeline.verification.committed` to `true` (this commit consumes that verification; Step 1.5
stops comparing it to later trees) — (read-modify-write, preserving everything else) under
`{workDocDir}/.progress/.lock` (`operation: be-commit`, a fresh `runId`), taken and released (per CLAUDE.md § State File Safety) around the writes exactly as every other
progress-file writer does (CLAUDE.md § State File Safety); if the lock is held by a live operation,
skip the reset and say so rather than wait. The counter bounds fix attempts within one review cycle;
a commit ends that cycle. Left as is, a feature committed at `reviewed` with `round: 2` makes the
next ticket's first `be-fix` round 3 — and `be-fix` Step 3 blocks on a prompt an unattended
`be-jira-auto` run cannot answer.

This runs before Step 7, not after: a progress file that is tracked and staged would otherwise be
committed with the old round and dirty again the moment the commit lands. For such a file — listed by
`git diff --cached --name-only` and, before this step's write, carrying no unstaged edit
(`git diff --quiet -- {file}`) — refresh its staged copy with `git add -- {file}`: the one `git add`
this skill makes, on a path the user already staged, adding only this step's own fields. A tracked
but unstaged progress file, or one that had unstaged edits of the user's, stays as it was (say so).

### Step 7: Execute Commit

A multi-paragraph body passed via `-m "{message}"` is fragile (shell quoting can mangle or
truncate it). Pass the drafted message through stdin with `git commit -F -` inside a
heredoc instead:

```bash
git commit -F - <<'EOF'
{subject line}

{body}
EOF
```

If the `short` argument was passed (Step 2), the heredoc contains only `{subject line}` —
omit the blank line and body.

Check the command's exit code:

- **Non-zero exit** (for example a pre-commit hook rejected the commit): the commit did
  **not** happen. Undo Step 6.5 entirely — under `{workDocDir}/.progress/.lock` again, re-reading each file
  first and restoring only the two fields it wrote, each to the value kept in memory from before
  Step 6.5 (`pipeline.fix.round`; `pipeline.verification.committed` — removed only where Step 6.5
  added it, a mark an earlier commit set stays; the verification was not consumed and the fix
  cycle did not end), re-staging the same files Step 6.5 re-staged. Show the command's output to the user verbatim, explain that no commit
  was created, and **stop** — do not proceed to Step 8.
- **Zero exit**: proceed to Step 8.

### Step 8: Report

Only report a commit after Step 7 exited zero. Get the actual hash from the repository —
never assume or construct it:

```bash
git rev-parse --short HEAD
```

Report using the hash this command printed:

> "Committed: `{short hash from git rev-parse output}` {subject line}"

### Constraints

- **Never run `git add`** on a path the user has not staged -- only operate on already-staged changes (Step 6.5 refreshes an already-staged progress file, nothing else)
- **Never add to or remove from the staging area** -- the user controls what is staged
- If the diff is too large to summarize in 50 characters, focus on the primary change
