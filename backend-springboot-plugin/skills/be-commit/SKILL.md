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

### Step 2: Parse Arguments

- `topic: <topic>` -- optional topic hint for the commit message (inferred from diff if omitted)
- `short` -- if present, generate subject line only (skip body)

### Step 3: Analyze Changes

From the staged diff, determine:

1. Which files were changed, added, or deleted
2. The nature of the change: new feature, enhancement, bug fix, refactoring, test, configuration
3. The domain/module affected
4. If a topic hint was provided, use it to guide the message focus

### Step 4: Draft Commit Message

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

### Step 5: Validate

Check the draft message against all 13 commit rules from CLAUDE.md:

- [ ] English
- [ ] Present tense imperative
- [ ] Subject <= 50 characters
- [ ] Blank line between subject and body
- [ ] Body lines <= 72 characters
- [ ] No test code mentions
- [ ] No prefix
- [ ] Starts with uppercase (or justified lowercase identifier)
- [ ] No branding/promotional content
- [ ] No file name listing
- [ ] Describes "why" not "what"

If validation fails, revise the message.

### Step 6: Execute Commit

```bash
git commit -m "{message}"
```

### Step 7: Report

> "Committed: `{short hash}` {subject line}"

### Constraints

- **Never run `git add`** -- only operate on already-staged changes
- **Never modify the staging area** -- the user controls what is staged
- If the diff is too large to summarize in 50 characters, focus on the primary change
