# Cutover Ledger

`docs/migration/cutover-ledger.json` — one file for the whole migration, the **machine-readable
registry of deferred items and flip-preconditions** across every page. Fixed path (like
`tracker.json`), not a config key.

## Why it exists

The recurring approved-round finding is: *"the deferral set is not recorded anywhere the repo or the
deployment can look it up"* (OMH-937/PR #329; OMH-936/PR #294 M3; OMH-938/PR #302). A page's
`migration-plan.json.openApprovals[]` records a coverage reduction **at plan time, per page** — but
nothing aggregates the items that must be closed **before the flip** into one list the (big-bang)
cutover batch can enumerate. When the flip is one big-bang cutover of all ready pages
(`templates/pr-body.md` → Grading standard), "before the flip" means "before the batch", and the batch
needs a single readiness view. This file is that view. It does not replace `openApprovals[]` — it is
the batch-scoped projection of every unresolved item that gates a flip.

## Shape

```jsonc
{
  "updatedAt": "2026-09-15T10:00:00+09:00",
  "entries": [
    {
      "app": "pc",
      "page": "hotel-map-integration",
      "item": "last-selected-hotel restore drops the card on return",   // one line, human-readable
      "kind": "flip-precondition",                 // "deferred" | "flip-precondition"
      "blocksCutover": true,                        // true → an unresolved entry blocks the flip of this page
      "sourceApproval": "openApprovals[restore-selection-drop]",  // where the decision lives on the page
      "owner": "OMH-935",                           // the ticket/person that owns closing it — never "TBD"
      "ticket": "OMH-935",
      "evidence": "hotel-map.tsx:550 forces setShowCard(false); legacy .component.ts:596-604 opens the card",
      "status": "open",                             // "open" | "approved" | "resolved"
      "recordedAt": "2026-08-27T14:00:00+09:00",
      "resolvedAt": null,                           // set when status leaves "open"; approved carries by/when too
      "by": null                                    // who approved/resolved (required once status != open)
    }
  ]
}
```

## Field rules

- `kind` — `flip-precondition` is something OMH-938-style gate items require *before* the path flips
  (internal-link conversion complete, a sitemap decision, a style gate that must run on the real
  route). `deferred` is work explicitly handed to a successor ticket that is **not** a flip blocker.
  Only `blocksCutover: true` entries gate a flip.
- `blocksCutover` — the one field `fm-route --flag-on` reads. `true` + `status: "open"` **blocks** the
  flip of that page, surfaced exactly like an unresolved Codex `high` or an unapproved cascade `real`
  row. `false` is disclosed but does not block.
- `owner` / `ticket` — never `TBD`. An entry with no owner is itself the defect the reviews flag ("no
  ticket owns work that the gate item requires"). If no ticket exists yet, that is the blocker to
  record, not a blank.
- `status` — `open` blocks (when `blocksCutover`). `approved` = an owner signed off deferring it past
  this page's flip (carries `by` + `resolvedAt`); it stops blocking this page but stays visible to the
  batch. `resolved` = the work landed. `approved`/`resolved` **require** `by` and `resolvedAt` — the
  same standard as an `owner-decisions.md` approval.
- `sourceApproval` — the pointer back to the page's `migration-plan.json.openApprovals[]` topic (or a
  `decisions.md`/`owner-decisions.md` ref). Keeps the batch view traceable to the per-page decision;
  the ledger is a projection, never an independent second source of truth.

## Read-Modify-Write & lock

The ledger is an app-wide file. Every write takes `docs/migration/.app.lock` then `.tracker.lock`
around the read-modify-write, in that order (CLAUDE.md → State Files & Lock Convention), and merges —
never overwrites — existing entries, keyed on `app` + `page` + `item`.

## Producers and consumers

- **`fm-route --flag-off`** (producer) — when it prepares a page's code PR, it projects that page's
  unresolved flip-preconditions into the ledger: every `migration-plan.json.openApprovals[]` entry
  carrying `blocksFlip: true`, plus any deferred gate item the plan/reports record. It sets `owner`,
  `ticket`, `evidence`, `status` from the approval, and it never invents an owner.
- **`fm-route --flag-on`** (consumer, hard block) — reads this file for the page and refuses the flip
  while any `blocksCutover: true` entry for that page is `status: "open"`. An `approved` entry proceeds
  (the owner's call), the same handling as an approved cascade divergence.
- **`fm-progress`** (consumer, read-only) — renders the batch readiness: per app, the count of pages
  with open blocking entries, and the full list of open `flip-precondition` rows with owner/ticket, so
  the cutover batch has one place to read what is not yet ready.
- **`fm-plan`** — marks an `openApprovals[]` entry a flip-precondition with `blocksFlip: true` when the
  deferred coverage must be closed before the path flips, so `fm-route --flag-off` can project it. A
  plan-time reduction that is not a flip blocker stays a plain `openApprovals` entry.
