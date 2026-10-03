---
name: fo-spec-sync
description: Import a planning-spec attachment (Jira zip or extracted folder) into specs/<screen>/ as an immutable snapshot, update specs/MANIFEST.md (ticket, version, status, sha256, content hash, date), and report which screens now have a plan older than their spec. Use when the planning team delivers a new or updated spec.
argument-hint: "<screen> <zip-or-dir> --ticket <OMH-nnn> [--app <name>] [--extra <path>]... [--note \"...\"]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# fo-spec-sync — bring a spec snapshot into the repo

The planning team's attachments are the functional source of truth for a screen. This command places
one of them under `specs/<screen>/` exactly as delivered, records it in the ledger, and tells you which
plans are now stale. It never edits a spec and never merges two versions — a new version replaces the
folder, and git history keeps the old one.

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`.

## Step 1 — Arguments and preconditions

- `<screen>` — the screen id used across the repo (`01-main-page`, `02a-admin-hotel-recommendation`, …);
  a directory under `screensDir` when the code exists, otherwise a new id (the spec arrives before the
  code). `--app` selects the app (the only one when there is one) — its `answerKeys.spec.dir` is the
  specs folder and its `progress.json` records stale plans.
- `<zip-or-dir>` — the attachment as downloaded from Jira (`*-spec_v<ver>_<yyyymmdd>.zip`) or an
  extracted folder with `ko/ en/ vi/` at its top.
- `--ticket` — the Jira issue the attachment came from. Required: the ledger is only useful if a row can
  be traced back to the comment it was taken from. Ask for it when it is missing.
- `--extra` — a second attachment to place inside the snapshot (a prototype delivered separately).
- `--note` — free text for the ledger row (e.g. "afternoon re-upload; FR-012 modal rules").

Read `.claude/frontend-ohmyhotel-plugin.json`; stop with the `fo-init` hint if it is missing. Confirm
`specs/MANIFEST.md` exists (`fo-init` creates it).

## Step 2 — Dry run and show the delta

Run the importer once with `--dry-run`:

```bash
fo-spec-import --screen <screen> --from <path> --ticket <ticket> --specs-dir <answerKeys.spec.dir> [--extra ...] [--note "..."] --dry-run --stage-dir .claude/frontend-ohmyhotel/stage/<screen>
```

It prints a JSON object: header metadata read from the spec (`status`, `version`, `lastUpdated` —
a version embedded in the status line is split out; attachments that wrap `ko/ en/ vi/` in one folder
are hoisted; a package-level version that only appears in the zip name goes into `--note`), the
attachment `sha256`, the markdown `contentHash`, `previousContentHash` for the current snapshot, and
`changed`. Show the user the prospective ledger row and, when a previous snapshot exists:

- `changed: false` → say the content is identical (only the attachment or its name differs); still
  record the row if the ticket or file name is new, otherwise stop here.
- `changed: true` → list what differs at file level (`diff -rq <stage-dir> specs/<screen>` — the
  staged tree is kept at `--stage-dir`, already normalised and hoisted), and run a quick comparison of
  the `ko/*-spec_ko.md` headers and section headings so the user sees whether this is a re-upload or a
  real revision. Do not attempt a semantic diff of requirements here; that is `fo-plan`'s delta step.

A `status` other than `FINALIZED` (e.g. `DRAFT`) is imported like any other but flagged in the report:
plans built on a draft are expected to change.

## Step 3 — Import

Run the same command without `--dry-run`. The importer replaces `specs/<screen>/` wholesale and
rewrites the screen's row in `specs/MANIFEST.md` (rows sorted by screen id).

Then stage the result for the user to commit — do not commit on their behalf:

```bash
git add specs/<screen> specs/MANIFEST.md
```

## Step 4 — Stale plans

For the screen just imported, read `<screensDir>/<screen>/implementation-plan.json` if it exists and
compare its `spec.contentHash` (the 12-hex prefix the manifest records) with the first 12 characters
of the new `contentHash`. Different → the plan is stale: record
`specStale: true` with both hashes in `<gates.evidenceDir>/<app>/progress.json` under the screen, so
`fo-progress` shows it and `fo-plan` knows to produce a delta instead of a fresh plan.

Also check every other screen in the manifest the same way (cheap: hashes only) so a backlog of
un-synced specs surfaces here rather than at gate time.

## Step 5 — Report

In the user's language: the ledger row as written, whether content changed, draft/final status, the
list of stale plans, the suggested commit message
(`specs: <screen> v<version> (<ticket>) — <note>`), and the next command:

- plan exists and is stale → `/frontend-ohmyhotel-plugin:fo-plan --app <app> --screen <screen>` (delta)
- no plan yet → the same command (fresh plan)
- content unchanged → nothing to do

Tagging the snapshot set (`specs/<date>`) at the start of a screen group is the team's release
convention, not this command's job; mention the tag command when the user asks.

Done when the snapshot and the manifest are written and staged, `progress.json` records stale flags,
and the report names the next command.
