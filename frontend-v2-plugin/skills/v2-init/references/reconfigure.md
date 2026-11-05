# v2-init: reconfiguration guard and Step 3 key notes

Part of the `v2-init` skill. `{pluginRoot}` is the plugin root the skill states.

### Structural-change guard (Step 1 item 4)

4. **Structural-change guard — evaluated AFTER the new answers exist.** Step 1 only **snapshots
   the old config**; the comparison below runs **after Step 2l (all knobs collected) and before
   Step 3 writes the file** — at Step 1 the new values do not exist yet, so "changes a structural
   knob" cannot be evaluated here, and a guard run here either never fires or warns about a change
   it cannot name. Before overwriting, glob `{runsDir}/*/progress.json` for any
   feature whose `implementation.status` is beyond `planned`. If any exist AND the reconfiguration
   changes a **structural** knob (`baseDir`, `appDir`, `routerMode`, `appProfile`, `serverState`,
   `formStack`, `componentLibrary`, `apiLayer`, `i18nBinding`, `clientStore`), list the affected features and warn:
   > "{N} generated feature(s) were built against the current settings. Changing {knob} leaves
   > their plan.json and generated code pointing at the old {directory/router shape}, while
   > v2-gen/v2-verify will use the new one — builds split across directories or framework commands
   > run against Vite-mode plans. Each listed feature needs a full re-plan and re-generation
   > (`v2-plan` → `v2-gen`) after this change."
   - Require an explicit second confirmation naming the consequence; if declined, keep the old
     config and stop. Non-structural knobs (`mockFirst`, `eslintTemplate`, `prettierTemplate`,
     `i18n`) reconfigure without this guard — `i18n` changes surface through the key-coverage
     spec's fingerprint instead.
   - **`e2eTool` sits in between**: switching to `playwright` with generated features leaves no
     harness (`playwright.config.ts` / `e2e/fixtures.ts` are scaffolded by foundation-generator,
     which only runs inside `v2-gen`), so the next `v2-e2e` stops with "run v2-gen first" — a
     guided stop, not a dead end, but a surprise. Warn at reconfiguration time:
     > "Switching e2eTool to playwright: the Playwright harness does not exist yet. The next
     > `v2-gen` run for any feature scaffolds it (a preflight that runs in full, delta, and resume
     > modes alike — v2-gen Step 1.9); `v2-e2e` will refuse until then."
     No second confirmation required — the consequence is one guided re-run, not split state.

### Step 3 key notes

- `devPort` (written in the ota example above): the dev-server port v2-e2e uses and Playwright's scaffolded `webServer` bakes in — default `5173`, edit it in the config file when that port is taken. Changing it after the harness exists does **not** rewrite `playwright.config.ts`; v2-gen's preflight detects the mismatch and says what to align.
- `renderingDefault` is written only in framework mode (default `ssr`); it is the fallback rendering for a
  page whose plan does not specify one. Absent keys fall back to admin defaults on read
  (`appProfile=admin`, `routerMode` as written, `serverState=zustand-only`, `formStack=native`,
  `e2eTool=agent-browser`, `prettierTemplate=true`).
- `componentLibrary` / `apiLayer` / `i18nBinding` / `clientStore` (Phase 2) are written only when they differ from their defaults (`shadcn` / `feature-local` / `react-i18next` / `zustand`); their companion objects (`externalComponents` / `apiPackage` / `i18nHook`) are written only alongside the non-default value that needs them. Absent → defaults on read, and every Phase 2 branch stays inactive.
- `i18n` is written only when Step 2d-3 produced one. Absent → no key-coverage spec is generated and
  `v2-verify` reports that axis as `skipped`. It is the one key with **no default**: guessing the
  supported language set would make coverage claims about languages nobody confirmed.
