---
name: fo-security
description: Standalone client-side security audit of any path (screen, package, route modules, telemetry) with security-auditor — XSS sinks, token handling, secrets, sensitive query keys against the repo's rule list, open redirects, SSR exposure, headers. Read-only. Use before cutover on shared modules and on any code touching tokens or URLs.
argument-hint: "<path>"
user-invocable: true
allowed-tools: Read, Glob, Grep, Agent
---

# fo-security — security audit of a path

Read the config (the auditor applies `config.rules.lists.sensitiveQueryKeys` and the prose rules
under `rules.rulesDir`, so the product's own decisions about tokens in URLs are respected). Resolve
`<path>`; empty → not a pass, stop.

Start one `Agent` with `subagent_type: frontend-ohmyhotel-plugin:security-auditor`, `mode: standalone`,
`targetPath`, `config`; wait for the completion notification. Show findings critical-first with
file:line and fix hints. Nothing is written; a `critical` on a shared module is worth a cutover
ledger item (`fo-cutover add`).
