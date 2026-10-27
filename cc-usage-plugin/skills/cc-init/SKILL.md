---
name: cc-init
description: Set up cc-usage-plugin after installing it — show which options are set and what the hooks have recorded, save your developer id and team, and print the terminal command that stores the receiver URL and token outside the chat. Run once after install, again to change the id or team or to check uploads.
argument-hint: "[developer] [team]"
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash(node "${CLAUDE_PLUGIN_ROOT}/scripts/init.js":*)
---

# cc-init — set up cc-usage-plugin

`scripts/init.js` saves the plugin's options through `claude plugin configure`: the developer id and
team go to `settings.json`, the receiver URL and token to Claude Code's secure storage. The URL and
token are never handled in this conversation, because anything typed here stays in the session
transcript (`docs/decisions.md` D12).

## Step 1 — Current state

Run:

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/init.js" status
```

Show the output to the user as it is. If the command exits non-zero, show its message and stop; the
message says what to do (for example, install the plugin from its marketplace first).

## Step 2 — Developer id and team

- **Developer**: the first argument, if one was given. Otherwise ask the user for the id assigned to
  them in the install guide. Do not suggest one, and do not use the OS login name or the account
  email. If Step 1 shows a developer already and no argument was given, ask whether to keep it; if
  the user keeps it, go to Step 3.
- **Team**: the second argument, if given. Otherwise ask, and accept an empty answer, which keeps the
  current team.
- A value that contains a single quote or a line break: ask for it again.

Then run, with each value in single quotes and `--team` only when the user gave a team:

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/init.js" set --developer '<developer>' --team '<team>'
```

Show the output. If the saved id differs from what the user typed, point it out: the saved id is the
one the receiver sees.

## Step 3 — Receiver URL and token

Never ask for the receiver URL or the token, and never put either in a command. If Step 1 shows
either as not set and the user has been given them, tell the user to run the `node … secrets`
command printed by Step 1 or Step 2 in a terminal outside Claude Code, exactly as printed (its
`--plugin` and `--config-dir` name this install): it asks for both without showing them and checks
the URL and token before saving. If the user pastes a URL or token into the chat anyway,
do not repeat it and do not save it; tell them it is now in this session's transcript and that the
terminal command is still the way to save it.

## Step 4 — Finish

Tell the user that the changes apply from the next Claude Code session, and that running
`/cc-usage-plugin:cc-init` again shows the state, including uploads once an endpoint is set.
