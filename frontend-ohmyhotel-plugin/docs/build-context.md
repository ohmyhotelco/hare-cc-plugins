# Build context

History and rationale that would otherwise end up inside agent or skill instructions. Instructions keep
the rule and a one-line reason; the story behind the rule goes here (design document §7, rule 5).

## 2026-10-03 — v0.1.0 skeleton

### Dry run: plugin agents through the workflow runtime

Question (design §5, §11 Q1): can a workflow shipped in the plugin's `workflows/` start the plugin's own
agents (`agentType: "frontend-ohmyhotel-plugin:<agent>"`) with a `schema`, and do those agents receive
the `fo-shared` preload? The fallback, had it failed, was a skill that starts one agent per turn and
advances on completion notifications.

1. Inline workflow from an interactive session (vault repo), one `agent()` call with
   `agentType: "frontend-react-plugin:spec-reviewer"` (an installed plugin's agent), `schema`, `effort: low`.
   Result: resolved; the agent described itself in that agent's role; schema output validated.
   Run `wf_154d4d31-9d6`, 1 agent, 26.7k subagent tokens, 9.4 s.
2. Headless, from the product repo clone:
   `claude -p --plugin-dir ./frontend-ohmyhotel-plugin --allowedTools "Read,Glob,Grep,Workflow,Agent"` asked
   to run the workflow named `frontend-ohmyhotel-plugin:fo-probe` with `{"agents":["spec-reviewer"],"file":"README.md"}`.
   Result: `{"ok":true,...,"sawSharedConventions":true}` — the plugin-shipped workflow resolved by name,
   `frontend-ohmyhotel-plugin:spec-reviewer` resolved, the `skills: [fo-shared]` preload was present in the
   agent's context, and `modelUsage` showed the agent on `claude-opus-5-5` (the agent's `model: opus`) while
   the main loop ran Fable. Run `wf_0c46ac01-442`, 1 turn, ~$0.68.

Consequence: P4 stands without the fallback. `fo-probe` stays in the plugin as the smoke test to re-run
after agent changes or Claude Code upgrades.

### Why `bin/fo-tree-hash` is a byte-for-byte port

`frontend-migration-plugin/scripts/gate-tree-hash.sh` encodes three rules learned from past evidence
defects (resolve from git's object model, decide on explicit discriminators, fail loudly on anything
unresolved). The port changes only the header and usage line so evidence recorded by either plugin
compares; the algorithm's own history is in that script's header comments.

### Why the plugin root `CLAUDE.md` exists although agents never see it

`claude plugin validate` warns that a plugin-root `CLAUDE.md` is not loaded as project context. It is kept
on purpose as maintainer notes (design §11 Q6) and says so in its first paragraph; agent-facing rules are
in `skills/fo-shared/SKILL.md`.

### fo-init headless test (scratch clone of the product repo, README only)

`claude -p --plugin-dir … "Run /frontend-ohmyhotel-plugin:fo-init …"` — 22 turns, ~$1.59. Wrote the config
and the full scaffold, installed nothing, and reported two reconciliations worth keeping: the README's
mobile breakpoint is 390 (the config default was 360 → changed to 390), and the README on `main` still
names the pre-rename design-system packages (`@omh/*`) — fixed by the product repo's README PR #2, not
by the plugin. `bin/fo-spec-import` was exercised against the real attachments: the recorded sha256
values match the vault ledger (`a851af14492c`, `f07628af238e`), Windows-separator entries normalise,
re-importing the same zip reports `changed: false`.

### Importer fixes found by the real import (product repo branch `chore/fo-init-scaffold-20261003`)

Zia's attachments differ from Lexi's and the planning-plugin originals: one wrapper folder
(`spec_b2c-<screen>/`) above `ko/ en/ vi/`, a `.progress/` state folder, generic file names
(`screens.md`, `test-scenarios.md`), `Status: DRAFT v0.4.1 (…)` with the version inside the status,
`Last Updated` sharing a line with `Created`, and `- 상태: 확정 (date)` for the admin extension.
`fo-spec-import` now hoists a single wrapper folder, splits status/version, keeps the date only, and
accepts the Korean bullet header. Package-level versions (`v0.2` in the zip name, no header version)
stay in the manifest note. The product repo gained `.gitattributes` (`specs/** -text`) because git
reported a CRLF conversion on the city-landing CSV — a converted file would no longer match its sha256.

### fo-plan headless test on the real 01-main-page spec (scratch clone of the scaffold branch)

10 turns, 1 planner agent, ~$2.79; wrote a 561-line `implementation-plan.json` and a 179-line
`MainPage.spec.md` from the v1.9 spec (ko primary, en for naming), the OMH-744 SEO reference, empty rule
lists, no Figma entry, no analysis, DS not installed. It ended at the approval question as designed.

What the test changed in the plugin:
- **Hashing moved out of the agent.** The planner has no shell, so every `sourceHash` came back `null`.
  `bin/fo-plan-hash` now resolves ids to passages (FR/TS heading section, BR bullet under its FR,
  `screen:` section of `*screens*.md`) and fills the hashes after the agent returns (`--write`); delta
  mode seeds the planner with `--check` output so both sides use one resolver. On the generated plan:
  41/41 resolved after accepting `|` as a separator (the planner copied the react template's `a | b` form).
  An FR-003 text edit on a spec copy flagged the 13 entries citing FR-003 — coarse, deterministic.
- The planner's `source` convention is now `FR-003 BR-004` (BR numbers restart under every FR).

What the test said about the project (kept here so it is not lost; owners decide, not the plugin):
12 open approvals — most are "repo not scaffolded yet" (DS inventory unavailable, shared-data absent,
rule lists empty, frozenCommit TBD); the rest are spec gaps (SNS URLs, cross-screen paths, redirect
storage, currency conversion, banner admin). 5 conflicts between the main-page spec and the OMH-744 SEO
spec: date overlay apply button, hero copy lines, home canonical `/` vs `/hotel`, cookie locale vs
per-locale URLs, search path `/search` vs `/hotel?keyword=`.

### Step 4 — fo-gen workflow, fo-verify script, generation agents (2026-10-03)

- `fo-verify` became a script rather than a workflow: every check is a command with an exit code
  (typegen+tsc, package tsc/vitest, eslint, screen vitest, key-coverage spec), so `bin/fo-verify-run`
  runs them in parallel, applies the pass/fail/skipped/not-run taxonomy from the migration plugin and
  writes `verify.json` with a tree hash. No agent, no cost, same output every time. Smoke test on the
  un-scaffolded repo: `typecheck`/`package` → not-run (no tsconfig, no package), `lint`/`i18n` →
  skipped, `unit` → fail (no tests) — the taxonomy keeps "could not check" apart from "nothing to check".
- `workflows/fo-gen.js` runs the five stages sequentially and stops at the first failed stage; the
  skill passes `stages[]` (enabled from `buildOrder`) and `resumeFrom`, the agents write their own
  stage entry into `generation-state.json` (the workflow has no filesystem). The workflow cannot be
  exercised end to end until the app exists (`apps/www/app/root.tsx`, DS installed, vitest) — Phase 0-B
  of the V3 plan; `fo-gen` Step 1 stops with that reason, which is the intended behaviour today.
- Generation agents are rewritten from the react plugin: the mutation check and the red/green runs
  stay (they produce evidence), the Iron Law / rationalisation tables are gone; `tdd-rules.md` now
  explains why each step records something. `tdd-cycle-runner` runs on the session model
  (`inherit`), foundation/integration on `sonnet` at `medium`.
- Templates copied from the react plugin and rewritten for the fixed stack: `i18n-key-coverage`,
  `e2e-playwright`, `form-adapters`, `server-state` (knob names → config paths, `fe-*` → `fo-*`).

### Step 5 — gate skills (2026-10-03)

- One evidence writer for every gate: `bin/fo-evidence` adds gate/app/screen/planVersion/recordedAt/
  treeHash/result around the gate's own payload, writes `<gate>.json` and the `gates.<gate>` entry in
  `progress.json`; `--register` only indexes a file a gate wrote itself (`fo-verify-run`). Tested on
  the scratch clone (visual not-run payload, verify register).
- `fo-visual` captures once (a generated Playwright spec per screen, breakage checks in the same
  test) and compares each Figma frame in parallel; breakage-only when the manifest has no frames
  (decision 10). `fo-contract` and `fo-seo` start one worker per rule list / aspect; an empty rule
  list is reported as a gap, never folded into a pass (P3: the lists belong to the product repo).
  `fo-e2e` is a single agent because its scenarios share one harness run.
- None of the four can run end to end before the app scaffold exists (same dependency as `fo-gen`);
  the workflows are syntax-checked with the runtime's async-body semantics (`node --check` on a wrapped
  copy, because top-level `return` is a workflow feature).

### Step 6 — review, fix, progress (2026-10-03)

- `fo-review.js` runs spec/quality/test/security reviewers in parallel and merges in code: every
  finding normalised to one shape, clustered by file, clusters ordered by worst severity. The reviewers
  are told to report everything (P6-3); the decision about what to fix is a multi-select question in
  the skill, and the chosen cluster ids are recorded in `progress.json` so `fo-fix` reads them rather
  than re-deciding.
- `fo-fix.js` runs one `review-fixer` per cluster strictly in sequence (fixers edit the same screen;
  parallel runs would race on files) and stops at the first failed cluster; the skill re-runs
  `fo-verify-run` before reporting, because a fix the technical gate has not seen is not finished.
- `fo-progress` is a script (`bin/fo-progress-report`) plus rendering: it recomputes each screen's
  tree hash and marks evidence recorded against other content as stale (`⟳`), which is a different
  state from failed. Tested on the scratch clone: 13 screens, 01-main-page `next = fo-plan (approve)`
  with 12 pending approvals, the rest `fo-plan`.
- `test-reviewer` follows every spec anchor into the snapshot and reports a cited line that
  disagrees with the test as `critical` — the one review that can see a shared misreading between
  test and implementation.
