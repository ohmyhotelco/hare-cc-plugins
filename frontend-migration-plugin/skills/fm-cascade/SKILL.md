---
name: fm-cascade
description: "Use after fm-verify and before fm-e2e to diff legacy's global stylesheet against the migrated app's, node by node, on the page's real markup — catching rule-level divergences (reset collisions, dropped global rules) that element-indexed style specs and jsdom DOM tests structurally cannot see. Needs legacy's compiled CSS, not a running legacy host."
argument-hint: "<page> [--app pc|mobile|hana] [--legacy-css <url|path>] [--keep-fonts] [--props <a,b,c>]"
user-invocable: true
allowed-tools: Read, Write, Glob, Grep, Bash, Agent
---

# Diff a Page's Stylesheet Cascade Against Legacy

Runs the `cascade-differ` agent to produce `cascade-diff.json` — every computed-style divergence
between legacy's global stylesheet and the migrated app's, measured on the page's own markup with the
stylesheet as the **only** variable. All user-facing output in `workingLanguage` (default `ko`). See
`templates/cascade-diff.md`.

**What this stage exists for.** `fm-style-spec` is element-indexed: it probes the elements
`analysis.json.styleSurface` names. A page that injects foreign markup — CMS rich text, an i18n value
containing HTML, editor output, anything through `innerHTML` / `dangerouslySetInnerHTML` — has
hundreds to thousands of nodes that no index can enumerate, because they are unknown at analysis
time. The golden DOM test cannot see it either: it runs in jsdom, which applies no CSS, so identical
markup rendering differently is invisible to it by construction. `fm-parity` is the only existing
gate that covers this, and it needs both hosts live. This stage covers it with legacy's CSS alone.

## Instructions

### Step 0: Config
Read `.claude/frontend-migration-plugin.json` (absent → run `fm-init`; stop). Resolve `app`
(`--app`/`currentApp`), `legacyDir`, `targetDir`, `appDir`, the app's `legacyPort` / `port`,
`pluginRoot` (absolute; where `scripts/cascade-diff.mjs` lives — absent → stop: the differ cannot
run, and an unrun diff is `not-run`, never a pass), and `workingLanguage`. Resolve `viewport` as
`{width}x{height}` from the page's `style-spec.json` → `legacySource.provenance.viewport` when the
file exists **and** carries it (a source-fallback spec may omit it — capture-provenance records
dimensions, never a device name); otherwise leave it unset and the differ uses its default device
(`Pixel 7`). Say in the report which was used.

**Confirm `apps[app]` before using it** (CLAUDE.md → Configuration): the app entry must exist and
carry the keys this stage reads. Config-file presence is not app presence — a `--app` naming an
unconfigured app must stop here with a clear message rather than fail deep inside an agent on an
unresolved path.

### Step 1: Require a built page
Check `tracker.json`: the page must be at `verified` or beyond. Below that the target app's CSS has
not been proven to compile and any diff describes a moving target. If lower:
> "Run /frontend-migration-plugin:fm-verify {page} first."
Stop.

### Step 1a: Refuse a flipped, done, or flip-in-flight page
Same rule as every writing stage (CLAUDE.md → Per-page State Machine). `flipped` → point at
`fm-route {page} --revert`. `done` → refuse, require manual intervention, do **not** point at
`--revert`. `flipPrOpenedAt` present → refuse and point at `fm-route --revert`.

### Step 2: Resolve the two stylesheets
Both must be **compiled** output, never source — `@import`, nesting and the build's own reset must
already be resolved.

- **legacy CSS:** `--legacy-css` if given. Else fetch the main stylesheet from the legacy dev server
  on `legacyPort` (read its `<link rel=stylesheet>` from `/`). Else read the newest compiled sheet
  from `{legacyDir}`'s build output. If none resolves, **stop with the reason** — do not fall back to
  raw SCSS, which would compare an uncompiled cascade and report fiction.
- **target CSS:** fetch from the target dev server on `port`. Under Vite it arrives wrapped as a JS
  module (`const __vite__css = "…"`); the agent unwraps it.

Legacy does **not** need to be serving the page — only its stylesheet. Say so in the report when the
legacy host is otherwise down, because that is the case this stage was built for.

### Step 2a: Ensure probe run permission
The agent runs the probe as a **sub-agent**, so session approvals do not transfer. The probe is
three plain commands (`agents/cascade-differ.md` Step 3): `cp` the differ script to
`{appDir}/.cascade-diff.tmp.mjs`, `node {appDir}/.cascade-diff.tmp.mjs …` with absolute arguments
(no `cd`, no `&&` — a compound command would not match a `node`-prefixed allow rule), `rm` the
copy. Ensure `.claude/settings.json` `permissions.allow` covers the `node` call with `appDir`
expanded (e.g. `Bash(node /abs/path/apps/web-mobile/.cascade-diff.tmp.mjs *)`); if missing, add it
(Read-Modify-Write) and note it in the report. Without it the probe cannot launch and there is no
partial-credit fallback here — an unrun cascade diff is `not-run`, never a pass.

### Step 3: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale only when its holder is gone — CLAUDE.md → Lock
file; age alone never breaks a live holder's lock).

### Step 4: Diff
Before launching, compute the **pre-run** `tree` hash over the page's watch-path union — same
script and union as the gates (CLAUDE.md → Gate Result Accounting F). Step 6 compares against it.

Launch `cascade-differ` (Agent) with only its params: `app`, `page`, `legacyCssPath`,
`targetCssPath`, `markupSource` (the page's captured documents if it has them — golden fixtures, MSW
response fixtures — else the target-app URL to scrape the rendered container from), `viewport`,
`propsOverride` (`--props`), `keepFonts` (`--keep-fonts`), `pluginRoot` (where
`scripts/cascade-diff.mjs` lives), `outPath` =
`docs/migration/{app}/{page}/cascade-diff.json`, `appDir`, `workingLanguage`.

### Step 5: Classify every divergence
Read the agent's report and put **each** row in exactly one bucket — this is the stage's actual work,
not the measurement:

- **real** — a rule on one side and not the other. Fix it (`templates/cascade-diff.md` → *Fixing what
  it finds*: port the legacy rule, or scope a `revert`).
- **consequence** — caused by another row (a border-width change shifts every `width` in that table).
  Do not fix separately; re-run after the cause is fixed and confirm it is gone.
- **artifact** — the harness leaked a second variable. A whole document diverging on `fontFamily` is
  the signature. **Not a finding.** Fix the harness, re-run, and say in the report that you did.

Never report a count without this classification: "37 divergences" where 23 are consequences and 14
are a font artifact is a misleading number, and the misleading number is what makes someone port an
innocent rule.

If any **real** row was fixed, re-run Step 4 after the fixes land: "fixed" means **absent from the
latest run** — that is what `fm-route` reads — and the consequence rows attributed to it must be
gone from the same run. `cascade-diff.json` and the tracker record always describe the latest run.
If the re-run itself fails (probe exit non-zero), the stage is `not-run` for the changed tree:
record it that way in Step 6 and in the report. The stale artifact stays only as history — its
unresolved rows keep blocking `fm-route`, which is the safe direction — but never present it as
current.

### Step 6: Record

**Tracker lock.** Take `docs/migration/.tracker.lock` around the `tracker.json` write below — after
the page lock this stage already holds, released right after the write (CLAUDE.md → Lock file).

1. Recompute the `tree` hash and compare with Step 4's pre-run hash. If they differ, the tree
   moved while the diff ran (a package rewrite, a concurrent fix): the measurement describes a
   tree that no longer exists — record the stage `not-run`, do **not** publish this report as
   current, and re-run from Step 4. A stale-but-clean report published after a concurrent clear
   would silently vouch for styles nobody measured.
2. Verify `cascade-diff.json` exists and parses (`jq empty`).
3. Update `tracker.json` (Read-Modify-Write): `apps[app].pages[page].cascade` =
   `{ runAt, nodesCompared, propsCompared, languages, real, consequence, artifact, unresolved }`,
   and `updatedAt`. **Never advance `status`.** A run that changed **no** file leaves the page's
   state untouched — evidence only. A run that **did** change files (a ported rule, a scoped
   revert, a new regression test) applies the same rule as `fm-fix`: set `status` to `generated`
   and clear `gateEvidence` (all gates), the legacy `verifiedAt`/`e2ePassedAt`/`parityPassedAt`,
   and `routePrepared`/`flagKey` — this skill changed code, so every prior gate PASS rests on a
   tree that no longer exists. Also **refresh `sourcePaths`** with any file this stage created or
   removed (the same refresh `fm-fix` performs): a new stylesheet outside the watch union would let
   later edits to it pass every freshness check unnoticed. The `cascade` record itself stays: it
   describes the latest run of this stage.
4. Every **real** divergence left unfixed goes to `owner-decisions.md` as an explicit-approval item
   with the values and the node count. An intended divergence is a decision, and a decision is
   recorded, not assumed. `fm-route --flag-on` reads these.
5. Release the lock.

### Step 7: Turn the fix into a gate
A diff run is evidence at a point in time. For each **real** divergence fixed, add a regression
assertion to the page's e2e suite, written from the **invariant** rather than the observed number
(`templates/cascade-diff.md` → *Turning a finding into a gate*). Then prove it is not vacuous:
disable the fix → the test must fail → restore → it must pass. Record both outcomes. A test that
passes with the fix removed protects nothing, and the pipeline has no other way to know that.

Then merge the new spec files into `sourcePaths` (same Read-Modify-Write under `.tracker.lock` as
Step 6) — Step 6's refresh ran before these files existed, and a spec outside the watch union goes
stale silently.

### Step 8: Report
In `workingLanguage`: nodes and properties compared, languages/documents covered, the three bucket
counts, each **real** divergence as `tag · property · legacy → target · node count` with its
disposition (fixed / recorded for approval), any harness artifact found and what was done about it,
the negative-control result for each new test, and whether legacy was reached by CSS only or was
serving. Next step: if this stage changed any file — a ported rule, a scoped revert, a new
regression test — the page's verify evidence is stale (the tree changed):
`/frontend-migration-plugin:fm-verify {page}`. Only a run that changed nothing (every real row
recorded, none fixed) proceeds straight to `/frontend-migration-plugin:fm-e2e {page}`.
