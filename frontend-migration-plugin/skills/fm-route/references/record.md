# fm-route: Ledger entries, audit and staging

Part of the `fm-route` skill. `{pluginRoot}` is the plugin root the skill states.

### Step 4a: Project cutover-ledger entries (--flag-off only) — see `{pluginRoot}/templates/cutover-ledger.md`
The code PR is where a page's deferrals become knowable to the cutover batch, so project them into
`docs/migration/cutover-ledger.json` now. Read the page's `migration-plan.json` `openApprovals[]`;
for every entry carrying `blocksFlip: true` (a coverage reduction that must close before the path
flips), plus any deferred gate item the plan or the gate reports record as a flip precondition, write
or update a ledger entry keyed on `app` + `page` + `item`: `kind: "flip-precondition"`,
`blocksCutover: true`, `owner`/`ticket`/`evidence`/`status` carried from the approval,
`sourceApproval` pointing back at the `openApprovals` topic. **Never invent an `owner`** — an approval
with `owner: "TBD"` projects an entry whose owner is `TBD`, which is itself the blocker to surface, not
a value to fill in. A plan with no `blocksFlip` approvals writes nothing.

**Also project not-yet-ready consumed clusters ({pluginRoot}/CLAUDE.md → Component Clusters).** Scan `tracker.json`
for entries with `kind: "cluster"` whose `consumedBy` contains this page and that are **not ready**. A
cluster is ready when its status is `cluster-ready` **and** every gate its `gateEvidence` marks
`notApplicable` still has an approved entry whose `grantedTree` equals that gate's `tree` (Step 1's
exemption test). For each cluster that is not ready, write a ledger entry `kind: "flip-precondition"`, `blocksCutover: true`,
`item: "cluster <name> not yet cluster-ready"`, `owner`/`ticket` from the cluster's tracker record (or
`TODO(owner):` when it has none — an unowned unready cluster is the blocker to surface). A page must
not flip on a cluster that has not passed its own gates. A ready cluster writes
nothing (and a prior entry for it moves to `resolved`).

This is an app-wide file:
take `docs/migration/.app.lock` then `.tracker.lock` (in that order, under the page lock already held —
{pluginRoot}/CLAUDE.md → State Files & Lock Convention), Read-Modify-Write merging on the key, release both.
Step 4c stages it with the rest of PR1's evidence.

### Step 4b: Codex audit (advisory; --flag-off only) — see {pluginRoot}/CLAUDE.md → "Codex Independent Audit"
After preparing the code PR (`--flag-off`), if `codexAudit` is enabled and `route` is in
`codexAuditStages` (**absent → all seven**; the key narrows coverage, it never means "none" — and
this is the sign-off before the irreversible flip, so a silent skip here is the costliest of the
seven),
spawn `codex-auditor` (`subagent_type: "frontend-migration-plugin:codex-auditor"`) for the `route` stage (params: `app`, `page`, `stage="route"`,
`appDir`, `legacyDir`, the full PR diff + all gate reports + `codex-audit.json`,
`outPath = docs/migration/{app}/{page}/codex-audit.json`, `workingLanguage`) — Codex's final
independent sign-off of the whole page. Advisory; its high-severity findings are what the
`--flag-on` acknowledgement (Step 1b) will surface.

### Step 4c: Stage the evidence (every action)
Every action wrote `tracker.json` in Step 4, and the PR that action prepares carries it — PR1, the
PR2 (the flip unit), the rollback PR — or `flipPrOpenedAt` / `flipped` / `revertedAt` exist in one working
tree only and every other checkout re-arms the flip. Stage it. `--flag-off` additionally stages the
page's evidence, after Step 4b — the route audit is part of the record PR1 must carry:

```sh
REPO=$(git rev-parse --show-toplevel)
git add -- "$REPO/docs/migration/tracker.json"
# --flag-off only:
for l in .lock '.*.lock' '*.tmp' '*.next.json'; do   # the ignore file fm-init writes; older projects lack it
  grep -qxF -- "$l" "$REPO/docs/migration/.gitignore" 2>/dev/null || printf '\n%s\n' "$l" >> "$REPO/docs/migration/.gitignore"
done
git add -- "$REPO/docs/migration/.gitignore" "$REPO/docs/migration/{app}/{page}"
[ -f "$REPO/docs/migration/cutover-ledger.json" ] && git add -- "$REPO/docs/migration/cutover-ledger.json"   # Step 4a's projection (a bare `git add` on a missing path errors)
```

The ignore file (appended with a leading newline — a file that ends without one would glue the
rule onto its last line) is what keeps a live lock, a pre-run manifest or `fm-delta`'s proposed baseline out
of the directory add (an `:(exclude)` pathspec naming an ignored file makes `git add` exit 1 with
the ignored-path advice, so the ignore rule is the mechanism, not a pathspec), and it ships with PR1
so every later checkout has it. The gate skills staged the tracker as of their pass; this write
supersedes that index entry. Staging here leaves nothing for Step 1a's evidence check to find but a
later change.
