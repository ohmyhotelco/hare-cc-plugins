# docs/rules — product rules the plugin checks

<!-- scaffolded by /frontend-ohmyhotel-plugin:fo-init — edit freely; the plugin reads, never writes, these files -->

Rules about this product that the planning spec does **not** state: decisions taken by development or
the CTO, contracts with the native apps, with transactional e-mail, with partners and with the backend.
Rules the spec does state stay in `specs/` and are read from there — do not copy them here.

Two kinds of file:

| Kind | Form | Read by |
|---|---|---|
| Machine-checked lists | `*.json` with the shapes in `frontend-ohmyhotel-plugin/templates/rule-lists.md` (`externalUrls`, `sensitiveQueryKeys`, `webviewContract`, `requestConventions`) | `fo-contract`, `fo-security`, `fo-plan` |
| Human-readable rules | Markdown in this directory, one topic per file, each pointing at the ADR that decided it | every agent, through the repo `CLAUDE.md` |

A change here is a product decision: it goes through a PR, references its ADR (`docs/adr/`), and is
dated in the list's `updatedAt`. The plugin does not need a release for it.
