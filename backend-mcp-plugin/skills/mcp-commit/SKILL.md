---
name: mcp-commit
description: "Create a commit from already-staged changes with a validated message: pipeline-status and staged-tree checks, a secret scan, and a tool-contract pairing check (snapshot staged without its changelog entry, or the reverse)."
argument-hint: "[topic: <hint>] [short]"
user-invocable: true
disable-model-invocation: true
allowed-tools: Read, Edit, Write, Glob, Bash(bash *scripts/detect-project.sh*), Bash(bash *scripts/pipeline-state.sh *), Bash(bash *scripts/source-tree-hash.sh*), Bash(bash *scripts/pre-commit-check.sh *), Bash(git status*), Bash(git diff *), Bash(git add *), Bash(git commit *), Bash(git rev-parse *)
---

# Smart Commit

Create a git commit from already-staged changes with a validated commit message following the plugin's commit standards. Always show the drafted message and ask for confirmation before committing.

**Done when:** `git commit` exited 0 and `git rev-parse --short HEAD` is reported with the subject line; every `reviewed`/`done` progress file is either marked (`fix.round` 0, `verification.committed: true` on a matching tree) or demoted to `resolved` (confirmed mismatch), and the lock is released. A non-zero commit exit leaves no Step 6.5 change behind.

## Instructions

### Step 0: Validate Configuration

1. `pluginRoot`: `${CLAUDE_PLUGIN_ROOT}` — Claude Code substitutes the plugin's install directory here when it loads this skill (the variable is not in the Bash environment, so always use this substituted value) — every `scripts/…` path in this document is `{pluginRoot}/scripts/…`; not an absolute path (the substitution did not happen) → stop: this Claude Code version does not substitute plugin paths in skill content — upgrade Claude Code.
2. `config`: run `bash "{pluginRoot}/scripts/detect-project.sh"` (`{pluginRoot}/templates/configuration.md`). Exit 0 → its stdout JSON is `config`; show each `config.warnings` entry once. Any other exit → show its stderr and stop (not a Spring AI MCP server Gradle project).

### Step 1: Check Staged Changes

Run `git diff --staged --stat` (and read the diff itself in bounded pieces).

- Nothing staged → "No staged changes found. Stage your changes with `git add` first." and stop

### Step 1.5: Pipeline Status Warning

1. Glob `{workDocDir}/.progress/*.json`, excluding `review-report-*.json`, `fix-report-*.json` and `audit-*.json`
2. For each progress file, read `pipeline.status`
3. Any tool with a status other than `reviewed` or `done`:
   > "Warning: tool '{feature}' is in '{status}' status — review/verification may not be complete. Continue with commit?"
   Decline → stop.
4. Compute `bash {pluginRoot}/scripts/source-tree-hash.sh --staged` once — the index is what this commit contains (exit 0 and a 40-hex id, else a tooling error: report it and stop). For each `reviewed`/`done` tool whose `pipeline.verification.committed` is not `true`, it must equal `pipeline.verification.tree`; different or missing:
   > "Warning: the staged tree is not the tree tool '{feature}' was verified on — the review describes different code. Stage everything under src/ and the build files, or re-run mcp-verify and mcp-review. Continue with commit?"
   Decline → stop. Confirm → add the tool to `mismatchedTools`: Step 6.5 demotes it to `resolved`, so it re-enters verification instead of warning on every later commit. A tool already committed on its verified tree is not re-checked.
5. All `reviewed`/`done` with a matching (or already committed) tree, a confirmed mismatch, or no progress files → proceed

### Step 2: Parse Arguments

- `topic: <topic>` — optional topic hint for the message
- `short` — subject line only

### Step 3: Security Scan

Run `bash {pluginRoot}/scripts/pre-commit-check.sh security` (not optional).

Decide on the exit code alone:

- Exit 0 → clean, continue
- Exit 1 → findings: show the report as printed (each finding is `file: line` with its value already masked — never print, `git show` or quote the staged secret yourself) and **abort the commit**
- Exit 2 → the scan did not run (`NOT_GIT_REPO`, `PATTERN_ERROR`, `GIT_DIFF_FAILED`): abort and say so — an unperformed scan is not a clean one
- Any other exit → tooling error: abort and report it

### Step 3.5: Contract Pairing Check

When `config.contractSnapshot` is set, from `git diff --cached --name-only`:

- The snapshot is staged but `config.contractChangelog` (when set) is not:
  > "The tool contract snapshot is staged without a contract changelog entry. Every contract change records its changelog entry in the same commit. Stage the changelog entry, or continue anyway?"
- The changelog is staged but the snapshot is not, while staged `@Tool`/`@ToolParam` edits exist under `config.toolsPackage`:
  > "Tool annotations and the changelog are staged but the contract snapshot is not — the build's snapshot test will fail on this commit. Continue anyway?"

Decline → stop.

### Step 4: Analyze Changes

From the staged diff determine: files changed/added/deleted; the nature (new tool, contract change, security hardening, upstream client change, fix, refactor, configuration, dependency/lockfile update); the domain affected; the topic hint, if any.

### Step 5: Draft Commit Message

Follow `{pluginRoot}/templates/commit-standards.md` (read it now — the rules below summarize it):

1. **Subject line**: English, imperative present tense, ≤ 50 characters, uppercase start (a lowercase identifier such as a tool name is allowed with justification), no prefix (`fix:`, `feat:`…), focused on why
2. **Body** (skip with `short`): blank line after the subject, ≤ 72 characters per line, breaks only when a paragraph exceeds 72 characters, motivation and context, no test-code mentions, no file lists, no branding. A contract change says what changed for clients (new tool, new optional parameter, description clarified)

**Worked example — new tool:**

```
Add seller QPS lookup tool

Operators asked the assistant for a seller's live request limit
and had no tool for it. get_channel_qps reads the configured and
currently enforced limits for one seller; it bypasses the cache
because the window is live, and it is gated by the same access
as the seller detail tool.
```

**Worked example — security fix:**

```
Sanitize seller names in channel results

Seller names come from the upstream as free text and reached the
model unfiltered, so invisible characters could smuggle text past
a human reviewer. Route them through the shared sanitizer like
every other free-text field.
```

Never fabricate a motivation the diff and topic hint do not support — a one-line change with no recoverable why gets a short, factual body.

### Step 6: Validate

- [ ] English (#1)
- [ ] Present tense imperative (#2)
- [ ] Subject <= 50 characters (#3)
- [ ] Blank line between subject and body (#4)
- [ ] Body lines <= 72 characters (#5)
- [ ] Only break within a paragraph when exceeding 72 characters (#6)
- [ ] No test code mentions (#7)
- [ ] No prefix (#8)
- [ ] Starts with uppercase (or justified lowercase identifier) (#9)
- [ ] No branding, promotional content, or attribution trailers (#10)

Revise until every item passes. Then show the final message and ask:
> "Commit with this message?"
Decline → stop without committing.

### Step 6.5: Close the Fix Cycle

Before the commit, under the pipeline lock — acquired with `bash "{pluginRoot}/scripts/pipeline-state.sh" lock acquire "{workDocDir}" mcp-commit` (exit 75 → another operation holds it: stop before committing) and released with `bash "{pluginRoot}/scripts/pipeline-state.sh" lock release "{workDocDir}" mcp-commit {runId}` (`{pluginRoot}/templates/pipeline-protocol.md` § The Lock — it also removes a validated agent snapshot directory) on every path — update every progress file whose status is `reviewed` or `done` (read-modify-write, preserving everything else):

- **In `mismatchedTools`** (Step 1.5 item 4): set `pipeline.status` to `"resolved"` and `pipeline.build` to `{ "timestamp": "{ISO 8601}", "previousStatus": "{reviewed|done}", "by": "mcp-commit", "filesModified": [the staged paths] }` (`templates/progress-schema.md`) — the committed code is not the code that earned the status
- **Otherwise**: set `pipeline.fix.round` to `0` and, when its `pipeline.verification.tree` equals the staged hash from Step 1.5, `pipeline.verification.committed` to `true`

If the lock is held by a live operation, skip these writes and say so rather than wait (the mismatched tools then warn again on the next commit).

A progress file that is tracked and staged (listed by `git diff --cached --name-only` and, before this step's write, carrying no unstaged edit — `git diff --quiet -- {file}`) is re-staged with `git add -- {file}`: the one `git add` this skill makes, on a path the user already staged, adding only this step's own fields. A tracked but unstaged progress file stays as it was (say so).

### Step 7: Execute Commit

Pass the message through stdin (quoting-safe):

```bash
git commit -F - <<'EOF'
{subject line}

{body}
EOF
```

With `short`, the heredoc holds only the subject line.

- **Non-zero exit** (a hook rejected the commit): no commit happened. Undo Step 6.5 under the lock again — restore only the fields it wrote (`fix.round`, `verification.committed`, and for a demoted tool `status` and `build`), each to the value kept in memory from before Step 6.5 (a field removed where Step 6.5 added it), re-staging the same files Step 6.5 re-staged. Show the command's output verbatim and **stop**
- **Zero exit**: proceed to Step 8

### Step 8: Report

Only after Step 7 exited zero:

```bash
git rev-parse --short HEAD
```

> "Committed: `{short hash}` {subject line}"

### Constraints

- **Never run `git add`** on a path the user has not staged — Step 6.5 refreshes an already-staged progress file, nothing else
- **Never add to or remove from the staging area** otherwise — the user controls what is staged
- Never push, open a pull request, or touch any external system
- Never add a `Co-Authored-By` or any attribution trailer
- If the diff is too large to summarize in 50 characters, focus on the primary change
