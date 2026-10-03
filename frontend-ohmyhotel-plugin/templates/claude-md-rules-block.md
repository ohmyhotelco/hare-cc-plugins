
## Product rules and specs (frontend-ohmyhotel-plugin)

- Planning specs are snapshots under `specs/<nn>-<screen>/` (ledger: `specs/MANIFEST.md`). Read the
  spec for the screen you work on; do not rely on a summary.
- Product rules the spec does not state — native app contract, external URL contract, request
  conventions, sensitive query keys, host rules, payment flow — live in `docs/rules/` (machine-checked
  lists as `*.json`, prose as `*.md`) and are decided in `docs/adr/`. Read them before changing routes,
  requests, URLs or anything the apps call.
- Gate evidence for each screen is committed under `docs/gates/<app>/<screen>/`; the screen × gate
  matrix is `docs/gates/<app>/progress.json`.
- Plugin configuration: `.claude/frontend-ohmyhotel-plugin.json`.
