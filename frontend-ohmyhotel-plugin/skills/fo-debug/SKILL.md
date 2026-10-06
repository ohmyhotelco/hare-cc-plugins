---
name: fo-debug
description: Debug a failing test, gate or runtime error on a screen with the debugger agent — reproduce, one hypothesis at a time with evidence, fix the confirmed cause with a regression test, escalate after three refuted hypotheses. Use when fo-verify, fo-e2e or a dev run fails for a reason the evidence does not make obvious.
argument-hint: "--app <name> --screen <id> [--from verify|e2e|visual|contract|seo] [--symptom \"<command or error>\"]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# fo-debug — find the cause before fixing

Conventions: `${CLAUDE_PLUGIN_ROOT}/skills/fo-shared/SKILL.md`.

1. Config, `--app`/`--screen`. The symptom: from `--from` (the gate's evidence file — the failing
   check's `command` and `tail`, or the failed scenario's `trace`), or `--symptom` as given, or ask
   for the failing command. Collect the `scope` files the evidence names. Lock `debug.lock`.
2. Start one `Agent` with `subagent_type: frontend-ohmyhotel-plugin:debugger` and the inputs; wait
   for the completion notification.
3. Release the lock. Report the reproduction, each hypothesis with its result, the cause, the fix
   and regression test (or, when escalated, what is known and what the next person should look at).
   Suggest the commit (`fix(<screen>): <cause>`). Next: `/frontend-ohmyhotel-plugin:fo-verify --app <app> --screen <screen>`,
   then the gate that failed.

Done when the agent has returned and the report names the next command.
