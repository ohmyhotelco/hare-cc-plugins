# Existing e2e, base vs HEAD (change plan, optional)

Used only for an app whose change-plan e2e result is `skipped: no e2e in plan` and that has a Playwright harness. Offer it; do not run it unasked, because it runs the app's suite twice. In a repo where many existing e2e tests already fail, this is what shows the change broke none of them.

1. Ask the user which spec files or folder to run (default: the app's whole e2e folder minus `excludePaths`).
2. Create a temporary worktree at `plan.baseCommit` (`git worktree add --detach <scratch dir> {baseCommit}`), install dependencies there the way the repo's own setup does, and, under the same feature lock as the change-plan e2e run, run the same command in both trees, one after the other (never in parallel — both harnesses own the same dev-server port).
3. Compare per test, not by totals: list tests that pass on base and fail on HEAD (regressions), and those that fail on base and pass on HEAD. Equal totals with different failing tests is not "no change".
4. Record under `implementation.e2e.apps.{app}.baseComparison` `{ baseCommit, command, base: {passed, failed, skipped}, head: {...}, regressions: [names], fixed: [names] }`. The app's e2e result stays `skipped: no e2e in plan` — a comparison with no regressions is evidence for the PR body, not a pass. Any regression → remove the worktree (item 5), release the lock, report it and stop for the user.
5. Remove the temporary worktree (`git worktree remove`) before every stop, including a failed run.
