# cutover-ledger.json — what must be closed before the big-bang switch

Lives at `<gates.evidenceDir>/<app>/cutover-ledger.json`, owned by the product repo; `fo-cutover`
adds, updates and checks items but never flips anything — the ALB/CloudFront switch is an operations
step outside this plugin (V3 plan D7/D9). The ledger exists so "ready" is a list of closed items with
evidence, not an impression.

```jsonc
{
  "app": "www",
  "mode": "big-bang",                    // from config apps[].cutover
  "updatedAt": "2026-12-20T08:00:00Z",
  "items": [
    { "id": "screens-all-gates", "kind": "computed", "title": "every screen: verify, visual, e2e, contract, seo pass and current; designer review and planning acceptance recorded",
      "status": "open", "evidence": "fo-progress-report", "checkedAt": "…" },
    { "id": "rule-lists-populated", "kind": "computed", "title": "no rule list under docs/rules has an empty entries array", "status": "open" },
    { "id": "integrated-qa", "kind": "manual", "title": "v3-stg integrated QA: 5 languages × 4 viewports × all screens", "status": "open",
      "owner": "QA", "evidence": null, "closedAt": null },
    { "id": "payment-staging", "kind": "manual", "title": "payment flow verified on the staging gateway with a real transaction", "status": "open", "owner": "Dev" },
    { "id": "app-contract", "kind": "list", "title": "native app contract items confirmed with the app team",
      "source": "docs/rules/webview-contract.json", "status": "open" },
    { "id": "external-urls", "kind": "list", "title": "every external URL contract entry resolves on the staging host",
      "source": "docs/rules/external-urls.json", "status": "open" },
    { "id": "frozen-hotfixes", "kind": "list", "title": "every monorepo hotfix since the freeze has a V3 PR or a recorded 'not applicable'",
      "source": "docs/cutover/frozen-hotfixes.json", "status": "open" },
    { "id": "rollback-rehearsal", "kind": "manual", "title": "ALB/CloudFront switch and revert rehearsed on staging", "status": "open", "owner": "Ops" },
    { "id": "archive-pointers", "kind": "manual", "title": "monorepo README, Jira components and plugin configs point at this repo", "status": "open" },
    { "id": "hana-termination", "kind": "manual", "title": "Hana Card white-label termination items handled (cutover day)", "status": "open", "owner": "Business" }
  ]
}
```

`kind`: `computed` (the check script decides from evidence), `list` (every entry of the named list
file must carry `status: "confirmed"` or `"verified"` with a date), `manual` (a named owner closes it
with an evidence link). `fo-init` does not create this file; `fo-cutover init` writes it with the
items above — and `docs/cutover/frozen-hotfixes.json` (same envelope as the rule lists, entries
`{ id, ticket, monorepoCommit, v3Pr | "not-applicable", reason, status }`) — and the user edits owners
and adds items.
