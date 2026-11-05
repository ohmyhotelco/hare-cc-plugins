# Gate Record

What a passing gate records, so `v2-progress` can tell when the code has moved since. Producers:
`v2-verify` (gate `verify`), `v2-e2e` (gate `e2e`). Consumer: `v2-progress`. Script:
`${CLAUDE_PLUGIN_ROOT}/scripts/gate-record.sh` (it calls `gate-tree-hash.sh`).

## Watch paths

The files the gate actually covered — never fewer:

- **Change plan** (`changeKind: "change"`): every file `changed-lines.sh {plan.baseCommit} {owner dirs}`
  lists (each app's `appDir` and each `plan.packages` entry; untracked files included; drop `(deletion)` entries and any path that no longer exists), plus every
  `files[]` / `tests[]` entry that exists, plus each `plan.packages` directory, plus `plan.json`.
  Files whose plan `op` is `remove` and that no longer exist are left out and named in the report.
- **New-screen plan**: every `file` value in `plan.json` (items, `tests[]`, `e2eTests`), the
  feature-module folder `{baseDir}/features/{feature}` when the app has no `layout`, `apiPackage.dir`
  under `workspace-package`, plus `plan.json`.
- `verify` leaves out e2e spec files; `e2e` includes them.

**Shared paths** (`--shared`, repo-relative): files many features edit — the app's route registry
(`{appDir}/{layout.routeRegistry}`, else `{baseDir}/routes.ts` / the central route file), the i18n resource files
(`i18nHook.resourcesDir` or the locales dir), and the global mock-handler aggregator. A change there
alone makes the record `shared-stale`, not `stale`.

## Record (on pass)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gate-record.sh record {runsDir}/{feature}/gate-tree/{gate}.tsv \
  --shared <path> ... -- <watch path> ...
```

- Exit 0 → write the printed hash as `implementation.{verification|e2e}.tree` and the record path as
  `…treeFile`.
- Exit 2 with `missing <path>` lines → record nothing; report each missing path by name and keep the
  pass unrecorded (`tree: "unverifiable"`, `treeMissing: [...]`). A missing watch path means the plan
  and the code disagree — fix the plan or the code, then re-run the gate.
- Exit 1 → report the error; record nothing.

The `.tsv` stores the watch paths and the shared paths it was recorded with (`# watch` / `# shared`
lines); `check` uses the stored shared paths, so a later config change does not change the verdict.
It is committed with the rest of `{runsDir}/{feature}/`.

## Check (v2-progress)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gate-record.sh check {runsDir}/{feature}/gate-tree/{gate}.tsv
```

- `fresh` → the pass holds.
- `stale <files>` → the gate's own files moved: show the pass as **stale** with the files; re-run the
  gate before trusting it.
- `shared-stale <files>` → only shared files moved (often another feature's edit): show
  **shared-stale** with the files; a re-run is advised, not required.

**Change plan:** also run `changed-lines.sh {plan.baseCommit}` over the owners and report any changed
file that the record does not hold as `stale (new files)` — a file written after the pass is not in
the record.

A stale pass is not a failure — it means "re-run before trusting".
