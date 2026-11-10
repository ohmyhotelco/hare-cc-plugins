# Maintaining this repository

How to change a plugin safely and get it to the people who install it. To build a new plugin, use the plugin-building guide attached to Jira ticket ELS-4167. It is not committed here because its appendices describe company codebases.

## Access and merging

- Organization owners have admin on this repository. Other members have write: they can push a branch and open a pull request.
- The `main protection` ruleset covers `main`: a pull request is required, with one approval, and force pushes and deletion are blocked.
- Admins can bypass the ruleset. A bypass merges with no approval on record, so ask for a review when a change touches gates, evidence or locks.
- A Claude Code session may be refused when it opens or merges a pull request on this public repository. Pushing the branch still works. Run `gh pr create` or `gh pr merge` yourself.

Do not use the legacy branch-protection API to check `main`. It cannot see rulesets and reports that the branch is unprotected.

## Before every pull request

Follow [Public Repository](CLAUDE.md#public-repository) first: anything you commit is readable by anyone. Then run these from the repository root:

```bash
scripts/check-plugin-consistency.py          # wiring between skills, agents, templates and versions
scripts/check-public-repo.sh                 # patterns that never belong in a public repository
claude plugin validate .                     # the marketplace file
claude plugin validate <plugin>-plugin       # each plugin you changed
```

The `checks` workflow runs the same commands on every pull request and every push to `main`. It needs no secrets and spends nothing. It does not run evals or real sessions. It is not a required status check, so read its result before you merge.

## Changing a plugin

1. Branch as `<plugin>/<topic>`, and write commits as `feat(<plugin>): …` or `fix(<plugin>): …`.
2. If an installer would receive the change, raise `version`. `plugin.json`, the root `.claude-plugin/marketplace.json` and the `vX.Y.Z` label in the root `README.md` must change in the same commit. See [Version Sync Rule](CLAUDE.md#version-sync-rule).
3. Run the plugin for real at least once. `claude -p --plugin-dir <plugin>-plugin "<request>"` loads your working copy instead of the installed version.
4. If you edit a skill's `description`, measure routing before and after with its evals. See [Evals](CLAUDE.md#evals) for the commands and the cost.
5. Where the plugin keeps `docs/build-context.md`, record what you ran and what it showed. Do not paste transcripts or the target project's code.
6. Keep LF line endings. Entry points under `bin/` and `scripts/` must stay `100755`: check with `git ls-files -s`. A Windows checkout does not record the bit.

The checker validates wiring, not meaning. A clean run says the instructions refer to things that exist, not that they are right.

## Names are a contract

Plugin names, skill names and the keys of each plugin's `.claude/<plugin>.json` are read outside this repository: by projects that installed the plugin, and by tooling that reads `.claude-plugin/marketplace.json` from `main` to recognise these plugins. Renaming or removing one changes what those readers see, so tell the people who depend on it first.

## Where the reasoning lives

| Plugin | Read first |
|---|---|
| `planning-plugin` | `CLAUDE.md` |
| `frontend-react-plugin` | `CLAUDE.md`, `docs/design/` |
| `homepage-plugin` | `CLAUDE.md` |
| `backend-springboot-plugin` | `CLAUDE.md` |
| `backend-webflux-plugin` | `CLAUDE.md`, `docs/decisions.md` |
| `frontend-migration-plugin` | `CLAUDE.md`, `docs/build-context.md`, `docs/design/` |
| `frontend-ohmyhotel-plugin` | `CLAUDE.md`, `docs/build-context.md`, `docs/design/plugin-design.md` |
| `frontend-v2-plugin` | `CLAUDE.md`, `docs/build-context.md` |
| `cc-usage-plugin` | `CLAUDE.md`, `docs/decisions.md`, `docs/design/plugin-design.md`, `docs/build-context.md` |

A plugin-root `CLAUDE.md` holds notes for maintainers and is not loaded into agents. A rule an agent must follow belongs in a preloaded skill or a file the agent is told to read.

## After a Claude Code release

Plugin behaviour can change with Claude Code. The `checks` workflow installs the latest version, so a failure on an unchanged branch may come from the release. If skills stop starting or agents stop launching, run `claude plugin validate` and one eval tag for the affected plugin before you change its instructions.

## If something sensitive is committed

Treat it as public from the moment it was pushed. Rotate a leaked secret first, then remove it from history.
