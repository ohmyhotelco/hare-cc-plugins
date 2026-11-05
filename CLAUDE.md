# hare-cc-plugin

Claude Code plugin monorepo.

## Repository Structure

```
planning-plugin/              - Functional spec generation plugin (see planning-plugin/CLAUDE.md — maintainer notes)
frontend-react-plugin/        - Frontend React development plugin (see frontend-react-plugin/CLAUDE.md — maintainer notes; agent rules live in skills/fe-shared)
frontend-migration-plugin/    - Angular 15 → React Router v7 migration plugin (see frontend-migration-plugin/CLAUDE.md — read on demand; not loaded into agents)
frontend-ohmyhotel-plugin/    - Repo-scoped plugin for ohmyhotelco/ohmyhotel-frontend (see frontend-ohmyhotel-plugin/CLAUDE.md — maintainer notes; agent rules live in skills/fo-shared)
homepage-plugin/              - Marketing homepage generation plugin (see homepage-plugin/CLAUDE.md — maintainer notes; agent rules live in skills/hp-shared)
backend-springboot-plugin/    - Backend Spring Boot development plugin (see backend-springboot-plugin/CLAUDE.md — maintainer notes; agent rules live in skills/be-spring-shared)
backend-webflux-plugin/       - Backend Spring WebFlux development plugin (see backend-webflux-plugin/CLAUDE.md — read on demand; not loaded into agents)
cc-usage-plugin/              - Hook-only Claude Code usage ledger with batched upload (see cc-usage-plugin/CLAUDE.md — maintainer notes; hooks plus one user-invoked setup command, no agents)
.claude-plugin/                - Root marketplace manifest
scripts/                       - Repository checks (consistency, public-repo scan)
.github/workflows/checks.yml   - Runs those checks and `claude plugin validate` on every pull request and push to main
MAINTAINING.md                 - How to change a plugin, what to run before a pull request, and how merging works
```

## Public Repository

This repository is public on purpose, as a showcase of the company's engineering. Everything that enters it is readable by anyone: instructions, templates, examples, docs, commit messages and pull request text. Nothing in it may be company information or security-relevant:

- no secret, key, token or licence, and no pointer to where one is kept;
- no internal hostname, URL, IP, bucket, queue, database or environment name, and no production path or deploy layout;
- no customer, partner or employee data;
- no business rule or product fact: those live in the product repository, and a plugin says "the product repo's `docs/rules`", not what the rules are;
- no copied ticket, spec or design text, and no finding about a weakness in a company system.

Keep surveys of a target codebase, fit tables and ticket text outside this repository. Citing a Jira key as a source is fine; quoting the ticket is not. Public service domains and invented example values are fine.

Before every pull request, run `scripts/check-public-repo.sh`, then run this wider scan on the plugin you changed and read every hit. The pattern list is a net, not the rule.

```bash
git grep -n -I -E 'ohmyhotel\.com|s3://|amazonaws|\.internal\b|[0-9]{1,3}(\.[0-9]{1,3}){3}|api[_-]?key|secret|token|password|licen[cs]e[_-]?key' -- <plugin>/
```

If a secret is committed, rotate it first and remove it from history second.

## Documentation Language

All plugin instruction documents (CLAUDE.md, agents/*.md, skills/*/SKILL.md, templates/*.md) must be written in English.

## Consistency Check

`scripts/check-plugin-consistency.py` validates the cross-file wiring every plugin depends on:
agent input parameters vs. what launchers pass, tool permissions vs. what a skill's body runs,
`proceed to Step N` jumps that skip a Lock Acquire, variables derived before they are bound or
defaulted, command arguments that are repo-relative when the command runs from `appDir`, ordered-list
numbering, dangling `templates/*.md` / `agents/*.md` / `CLAUDE.md § Heading` references, and what a
workflow starts, and that each agent declares `model` and `effort`.

A skill over 20,000 characters comes back cut after auto-compaction, so the checker limits its size. Move a
rarely used section to `skills/<skill>/references/`, keep its heading in `SKILL.md` with a pointer, and write
the plugin root there as `{pluginRoot}`: `${CLAUDE_PLUGIN_ROOT}` is not substituted in a file read with Read.
The skill binds `{pluginRoot}` above its first section.

**Run it after editing any plugin's agents, skills, or CLAUDE.md** — a plugin is a corpus of
instructions nothing compiles, so an edit that reads fine can still be unexecutable:

```bash
scripts/check-plugin-consistency.py                    # every plugin
scripts/check-plugin-consistency.py frontend-react-plugin
```

It validates wiring, not meaning. A clean run does not mean the instructions are correct — only that
they refer to things that exist and can be reached.

## Evals

Each plugin's `evals/` checks that a natural request reaches the right skill. A case with a `fixture.sh` needs `--scaffold`, and a case about a request for existing work needs one, because in an empty workspace Claude stops before it would choose a skill. A case for a skill that runs commands or edits files lists `Bash`, `Write` and `Edit` in `allowed_tools` and runs with `--allow-tools Bash Write Edit`: without them Claude cannot do the work itself, so a pass means little.

```bash
cd backend-webflux-plugin && claude plugin eval . --tag routing-audit --scaffold --ablation none --no-publish --threshold 0
cd backend-webflux-plugin && claude plugin eval . --tag routing-exec --scaffold --allow-tools Bash Write Edit --ablation none --no-publish --threshold 0
```

Both tags together cost about $3 to $6 per plugin on Sonnet, and only `routing-exec` takes `--allow-tools`. Older cases carry only `routing`. Set `max_turns` to 5 for a skill Claude may reach after reading the code: at 3, `be-code` looked like a miss.

Measure a description before and after editing it. When-to-use text neither predicts a miss nor always fixes one: it took four `backend-springboot` skills from 0/3 to 3/3, and changed nothing for `fe-verify`, `fo-verify` and webflux `be-debug`, so those three edits were reverted. A missed route is not proven worse output: on `quality-recall`, Claude alone found as many seeded defects as `fe-clean-code` (0.967 on both, five runs each) for about 57% of the cost.

`frontend-react-plugin/evals/quality-recall` seeds defects for `quality-reviewer`, for tuning a reviewer's effort. Agents run at `medium` and debuggers at `high`: on that case `high` found no more seeded defects than `medium` and cost about 22% more (five runs per arm).

## Version Sync Rule

Each plugin's `plugin.json` and the root `.claude-plugin/marketplace.json` must always stay in sync.

**Rule**: When changing `version`, `keywords`, or `description` in a plugin's `.claude-plugin/plugin.json`, the corresponding entry in the root `.claude-plugin/marketplace.json` must also be updated **in the same commit**.

Fields to synchronize:
- `version` — must match exactly, **including the root `README.md` plugin-list label** (`` `vX.Y.Z` `` beside each plugin heading) — the label sat outside this rule and rotted silently until `scripts/check-plugin-consistency.py` gained a `version-sync` rule that now enforces all three locations
- `keywords` — must match exactly
- `description` — must match exactly
