# Evals — standalone review attribution

Behaviour tests for `v2-clean-code`, `v2-test-review` and `v2-security` when they split findings
into the change under review (`[introduced]`) and older code (`[pre-existing]`, `[touched]`).

Each case builds the same small git repo in the empty eval workspace (`_shared/build-fixture.sh`):
a stale local `master`, an already-merged commit tagged `pr-base`, and the change on top. See the
script header for what each file is meant to trigger.

| Case | Checks |
|---|---|
| `clean-code-format` | Attribution SHAs, 0 introduced on clean changed lines, old issues tagged, report shown verbatim |
| `security-touched` | old CSS `url()` interpolation on a changed line → `[touched]`; new `dangerouslySetInnerHTML` → `[introduced]` (also in the agent's own report, via the trace) |
| `test-review-convention` | new `querySelector` tests that follow the file's convention are lowered and noted; no `img` role query for `alt=""` thumbnails |
| `test-review-no-base` | no `--base` → `not-checked`, no tags, no branch guessed |
| `base-local-branch-refused` | `--base master` (local branch) stops before any review |

Run from the plugin root (scaffold scripts need `--scaffold`; the skills need Bash):

```bash
claude plugin eval . --ablation none --scaffold --allow-tools Bash SendMessage --trust-plugin --no-publish
# one case, one run, keep the sandbox for its trace:
claude plugin eval . --case security-touched --runs 1 --ablation none --scaffold \
  --allow-tools Bash SendMessage --trust-plugin --keep-temp --no-publish
```

A full run (5 cases × 3 runs) takes about 2.5 minutes and costs about $3 at list price.
`--ablation none` skips the no-plugin arm, which cannot run these skills at all.
