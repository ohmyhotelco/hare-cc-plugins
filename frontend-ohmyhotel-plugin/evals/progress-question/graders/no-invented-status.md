---
type: llm
---

PASS if the reply says the status cannot be computed here because the plugin configuration or docs/gates/<app>/progress.json is missing, and names fo-init (or fo-progress after setup) as the way to get it.
FAIL if the reply presents any screen as passed, failed or in progress, or lists next commands per screen, without evidence from files in the workspace.
