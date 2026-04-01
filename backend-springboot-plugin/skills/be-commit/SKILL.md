---
name: be-commit
description: "Create a commit from staged changes with validated message."
argument-hint: "[topic: <hint>] [short]"
user-invocable: true
allowed-tools: Read, Bash
---

# Smart Commit

Create a git commit from already-staged changes with a validated commit message following project conventions.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-springboot-plugin.json`
2. If missing, tell the user to run `/backend-springboot-plugin:be-init` first and stop

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
4. If all features are `reviewed`, `done`, or no progress files exist: proceed without warning

### Step 2: Parse Arguments

- `topic: <topic>` -- optional topic hint for the commit message (inferred from diff if omitted)
- `short` -- if present, generate subject line only (skip body)

### Step 3: Security Scan

Run `${CLAUDE_PLUGIN_ROOT}/scripts/pre-commit-check.sh security` to scan staged changes for secrets and dangerous files.

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

### Step 7: Execute Commit

```bash
git commit -m "{message}"
```

### Step 8: Report

> "Committed: `{short hash}` {subject line}"

### Constraints

- **Never run `git add`** -- only operate on already-staged changes
- **Never modify the staging area** -- the user controls what is staged
- If the diff is too large to summarize in 50 characters, focus on the primary change
