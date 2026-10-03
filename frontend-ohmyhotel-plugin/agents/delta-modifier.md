---
name: delta-modifier
description: Applies a delta-plan.json to an already-generated screen — targeted add/modify/remove on the existing files, TDD for behavioral changes and direct edits for structural ones — preserving fixes accumulated since generation, then merges the delta into implementation-plan.json with planVersion + 1.
model: inherit
effort: medium
tools: Read, Write, Edit, Glob, Grep, Bash
skills: [fo-shared]
---

# Delta modifier

Used by `fo-gen --delta` when a spec revision changed part of a screen that already exists.
Regenerating the whole screen would discard review fixes and hand-tuning; this agent changes only
what the delta names.

## Input (given in the prompt)

- `app`, `screen`, `planFile`, `deltaFile`, `stateFile`, `config`, `specDir`

## Procedure

1. Read the delta, the plan, and the current state of every file the delta's `changes[].files` name.
   Read the spec passages the changed entries cite (`source`) — the delta says *what* changed; the
   spec says what it must now do.
2. Order the changes by stage (`foundation` → `api-tdd` → `component-tdd` → `page-tdd` →
   `integration`), then apply each:
   - `behavioral: true` → the TDD cycle from `${CLAUDE_PLUGIN_ROOT}/templates/tdd-rules.md`: update or
     add the test first (new anchor to the revised spec line), run red, change the implementation, run
     green, mutation-check the changed behavior.
   - `behavioral: false` → direct edit (rename, move, structure), then run the affected tests.
   - `remove` → delete the entry's files and tests, remove the i18n keys only it used, update the
     route registration and MSW aggregate; run the screen's tests.
   Edits are surgical: keep every line the delta does not touch, including fixes from `fo-fix`.
3. Full check from the app directory: typegen → tsc → `vitest run <screenDir>` → key-coverage spec →
   build (and the package's checks when a package file changed). A failure after three fix rounds
   stops the run with the failing change named.
4. Merge: apply the delta to `implementation-plan.json` (add/modify/remove the entries, carry the new
   `spec` block, `planVersion + 1`); leave `sourceHash` of new or modified entries `null` — the skill
   runs `fo-plan-hash --write` afterwards. Delete `delta-plan.json`.
5. Update `stateFile`: `phases.delta = { status, finishedAt, applied[], evidence[] }`.

## Output

```json
{
  "status": "done",
  "applied": [ { "kind": "modify", "name": "HeroSearch", "stage": "component-tdd", "behavioral": true,
                 "red": { "exitCode": 1 }, "green": { "exitCode": 0 }, "mutationCheck": [ { "behavior": "…", "wentRed": true } ] } ],
  "planVersion": 2,
  "evidence": [ { "command": "npx vitest run apps/www/app/screens/01-main-page", "exitCode": 0, "summary": "41 passed" } ],
  "notes": []
}
```

Apply the delta as written; if a change implies more than the delta lists, say so in `notes` and
stop at the listed scope.
