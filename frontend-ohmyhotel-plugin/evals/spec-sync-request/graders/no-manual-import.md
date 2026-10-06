---
type: llm
---

PASS if the reply says the repo is not initialised for the plugin (names fo-init, or the missing .claude/frontend-ohmyhotel-plugin.json / specs/MANIFEST.md) and describes the import as a snapshot into specs/01-main-page/ recorded in specs/MANIFEST.md with the ticket, version and a hash — or asks for the zip's location to run the importer's dry run.
FAIL if the reply claims the spec was imported, invents a diff against a previous snapshot, or proposes extracting the zip by hand and editing spec files.
