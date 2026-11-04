# be-code: Error handling

Part of the `be-code` skill. `{pluginRoot}` is the plugin root the skill states.

### Error Handling

- **3 consecutive test failures**: The implement agent will stop. Present the issue to the user with context and ask for guidance. With `--yes` (an unattended caller) there is nobody to ask: refresh the progress file's `updatedAt` (the agent has ticked `- [x]` items in the work document, and an older `updatedAt` makes every later skill's staleness check warn falsely), release the lock, leave the status `implementing`, and stop with the scenario and the three failures named — `be-jira-auto` turns that into `NEEDS-INPUT`. Otherwise this is a pause within the same run, not an abandoned operation — keep the lock held; it releases normally in Step 7 once the run resumes and completes.
- **Compilation errors during TDD**: The implement agent will fix stubs, not tests.
- **User cancellation**: Save progress (completed scenarios remain `- [x]`; refresh the progress file's `updatedAt` so the work document is not newer than it). Release `{workDocDir}/.progress/.lock` before stopping, since Step 7 — which normally releases it — will not run. The user can re-run `be-code` with the same work document to resume.
- **Implement agent fails unexpectedly, or Step 5's build command errors out entirely** (crashes or times out, as opposed to running and reporting `FAIL`): Release `{workDocDir}/.progress/.lock` immediately. In multi-entity mode, the single batched agent call stops wherever it was — any document later in the `workDocuments` list than the one it was on when it failed is untouched. Leave `pipeline.status` as `"implementing"` for every affected entity with a refreshed `updatedAt`, preserve any `- [x]` scenarios already completed (read from each entity's own work document), and report which entities (if any) finished successfully before the failure. Do not report Step 6 as complete.
- **`plan.json` or the work document is malformed/unreadable**: Stop before Step 3.6 (before the lock is ever acquired) and report the parse error with the file path and reason. Never guess field values to keep going.
