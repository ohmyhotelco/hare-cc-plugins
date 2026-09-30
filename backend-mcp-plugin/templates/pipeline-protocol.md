# Pipeline Protocol

The rules every skill and agent that touches `{workDocDir}/.progress/` follows. Read this file
(`{pluginRoot}/templates/pipeline-protocol.md`) wherever a skill or agent says "per the pipeline
protocol". The plugin's own `CLAUDE.md` is maintainer documentation — Claude Code never loads it,
so nothing load-bearing lives there.

## The Lock

One cross-skill lock, `{workDocDir}/.progress/.lock`, guards every progress-file write. It is
**mechanism, not prose**: only `scripts/pipeline-state.sh` creates, refreshes, extends or removes
it. Never write, rewrite or delete the lock file by hand — not even to "fix" a stale one.

| Step | Command (from the project root) | Exit codes |
|------|---------------------------------|------------|
| Acquire | `runId=$(bash "{pluginRoot}/scripts/pipeline-state.sh" lock acquire "{workDocDir}" {operation} {feature})` | `0` acquired — keep the printed `runId` for every later call; `75` another run holds a live lock (holder on stderr): tell the user and **stop**; `64` invalid operation/feature; `2` tooling error: report and stop |
| Refresh | `bash "{pluginRoot}/scripts/pipeline-state.sh" lock refresh "{workDocDir}" {runId}` | `0` refreshed; `1` the lock is no longer this run's (removed as stale, then taken by another run): **stop editing** and report — the run lost its exclusivity |
| Snapshot dir | `bash "{pluginRoot}/scripts/pipeline-state.sh" lock snapshot "{workDocDir}" {runId}` | `0` prints this run's revert-snapshot directory (created on first call, same path afterwards); `1` as for refresh |
| Release | `bash "{pluginRoot}/scripts/pipeline-state.sh" lock release "{workDocDir}" {operation} {runId}` | `0` released (or nothing to release); `1` the lock belongs to another run — it was left alone; say so |

- `{operation}` is the skill's name: `mcp-code`, `mcp-verify`, `mcp-review`, `mcp-fix`,
  `mcp-debug`, `mcp-commit`. `{feature}` is the validated feature name, or omitted when the run has
  none.
- **Staleness**: a lock not refreshed for 30 minutes is stale, and the next `acquire` removes it.
  Any holder that can run longer refreshes it: the implement, review-fixer, debugger and
  build-doctor agents run **Refresh** after every Gradle run (the skill that took the lock is
  blocked on the agent); `mcp-verify` refreshes before each Gradle row; a skill waiting on the user
  refreshes when the user answers.
- **Release on every exit** after a successful acquire — success, failure, cancellation, an agent
  that errored or timed out. A lock left behind blocks every other skill for 30 minutes.
- **Snapshot directories**: an agent that edits code keeps its revert copies in the directory
  **Snapshot dir** prints (one per run, outside the repository): each file stored under its
  repository-relative path in a per-attempt subdirectory, the subdirectory removed once its attempt
  is settled. `release` (and a stale-lock removal) deletes the directory itself, and only after
  checking that its canonical path is directly under the temp dir, is named `mcp-snapshot.*`, and
  holds the marker `.mcp-snapshot` with the lock's `runId` — the lock file is project-writable text,
  and an unchecked path would be an `rm -rf` of anything it names. Never `rm -rf` a snapshot
  directory yourself.
- The lock guards against a forgotten, crashed or concurrent run on one project: acquisition is
  atomic (an exclusive create), so two sessions cannot both hold it.

Lock file format (written only by the script):

```json
{ "lockedAt": "{ISO 8601}", "operation": "mcp-code", "feature": "{feature}", "runId": "{random, per run}", "snapshotDir": "{optional}" }
```

## Progress Files

`{workDocDir}/.progress/{feature}.json` — schema and status transitions in
`templates/progress-schema.md`. Every write is **read-modify-write** under the lock: read the
current file, change only the fields the step names, write the whole object back. Never recreate
a progress file from memory.

## Demotion Warning

Running a skill from an earlier pipeline stage demotes the status. Skills must warn the user and
obtain confirmation before demotion. For example, running `mcp-code` when status is `verified`
resets the pipeline to `implementing`, discarding verification and review progress.

## Tree Hash

**A status is only as good as the tree it was earned on.** `mcp-verify` records
`scripts/source-tree-hash.sh` (src/, build and settings files, lockfile-adjacent gradle/, config/)
as `pipeline.verification.tree`; `mcp-review` recomputes it and refuses a `verified`/`reviewed`/
`done` status on a different tree — the code goes back through `mcp-verify`; `mcp-commit` compares
the **staged** tree: a match marks the record `committed`; a mismatch the user confirms committing
demotes that tool to `resolved`, so it re-enters verification. Editing source after verification
never demotes the status by itself; the hash is what makes the edit visible. Scripts are always run
as `bash "{pluginRoot}/scripts/<name>.sh"`, so a checkout that lost the executable bit (Windows)
still works.
