# v2-shared: deliberate deviations and design principles

Part of the `v2-shared` skill. `{pluginRoot}` is the plugin root the skill states.

### Deliberate Deviations (`openApprovals`)

A reviewer that re-raises a known, accepted deviation every round trains people to skim reviews. `plan.json` carries `openApprovals[]` as the one place a deviation is recorded:

```json
{ "id": "OA-1", "what": "phone validation accepts KR formats only",
  "why": "international formats are out of scope for v1 (spec §4.2 defers)",
  "status": "approved", "owner": "jieun.park", "at": "2026-08-11" }
```

- `spec-reviewer` and `quality-reviewer` **do not re-raise** an issue matching an `approved` entry; they list it once under "accepted deviations" so it stays visible.
- **`status: "pending"` is not approval, and neither is a free-text note.** Approval requires `status: "approved"` **and** a named `owner` — not `TBD`, not the agent. An agent may *propose* a `pending` entry; it may never approve one, or the pipeline would be approving its own shortcuts.
- Scope reduction without an approved entry is a review failure, not a smaller review. See § Design Principles, "Scope moves in both directions".

### Design Principles

Applied by every agent and skill in this plugin.

- **Subagent isolation.** Subagents never inherit session history. A coordinator constructs only the parameters each agent needs — no conversation context leaks between phases. Fresh judgement per task, no context pollution.
- **Delegation is named, not improvised.** Every phase that delegates names its agent explicitly; launch it with the `Agent` tool and only its declared params. Do not spawn an agent the skill did not name — in particular, never add a reviewer to double-check work a gate already covers. Verification belongs to the gate that owns it; `v2-clean-code` and `v2-test-review` are standalone audits a human invokes, not steps a phase adds for itself. When a skill names several independent agents, send them in one message so they run concurrently — but agents sharing a lock or a write target are **not** independent, whatever the fan-out looks like. The skill's own text wins over this paragraph.
- **Scope moves in both directions.** Silently narrowing what the plan asks for is the familiar failure; unrequested widening is the same failure mirrored. Do not add features, files, gates, or behavior the plan does not call for, and do not substitute your own judgement about what the task should have been. If the plan looks wrong, say so in a sentence and execute it as written — amending it belongs to whoever owns the decision, not the executor.
- **Evidence before claims, always** — see below.
