# v2-gen: Resume support

Part of the `v2-gen` skill. `{pluginRoot}` is the plugin root the skill states.

### Resume Support

When Step 1.6 detects an existing `.implementation/frontend/generation-state.json`:

1. Read the state file
2. **All-completed check** — if every phase has `status: "completed"` or `"skipped"` with
   `skipKind: "auto"`:
   - **If `delta-plan.json` exists**: do not start fresh — proceed to Step 1 item 3 (**Delta
     detection**); the pending delta is the reason this run exists.
   - Otherwise:
     > "Previous generation completed successfully. Re-running will start fresh."
     - Delete generation-state.json and proceed to Step 3 (fresh start).
3. **Plan freshness check** — compare `.implementation/frontend/plan.json` modification time against phase-level `completedAt` timestamps:
   - Get plan.json mtime (use `stat` or file system check)
   - For each completed phase (in order), compare plan.json mtime against `completedAt`:
     - If plan.json was modified after a specific phase's `completedAt`:
       > "plan.json has been modified after '{phase}' was completed."
       > "Options:"
       > "1. Continue from the next incomplete phase"
       > "2. Re-run from '{phase}' onward"
       > "3. Restart generation from scratch"
       - Option 1: continue from next incomplete phase as-is
       - Option 2: reset the affected phase and all subsequent phases to `"pending"` (clear `completedAt`), resume from that phase
       - Option 3: delete generation-state.json and proceed to Step 3 (fresh start)
   - If plan.json mtime is older than all completed phases' `completedAt` (or no `completedAt` recorded — legacy state):
     - Fall back to `startedAt` comparison: if plan.json is newer than `startedAt`:
       > "Warning: plan.json has been modified since generation started ({startedAt})."
       > "Resuming may create inconsistencies between already-generated and new code."
       > "Options: 1. Continue anyway  2. Restart generation from scratch"
       - If user chooses restart: delete generation-state.json and proceed to Step 3 (fresh start)
4. Find the first phase with `status` not `"completed"`
5. Display:
   ```
   Resuming code generation for '{feature}':
     Completed: {list of completed phases}
     Resuming from: {phase name}
   ```
6. Ask user to confirm resume
7. Continue from the incomplete phase (skip completed phases)
