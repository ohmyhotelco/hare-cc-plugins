# MCP Tool Plan Schema

Reference for `plan.json` — the structured tool plan produced by the `mcp-planner` agent and
consumed by `mcp-code` (work-document generation) and `mcp-review` (Spec Compliance dimension).

Location: `docs/specs/{feature}/.implementation/mcp/plan.json`

Used by: `mcp-planner` agent (generation), `mcp-code` (consumption), `code-reviewer` (spec compliance)

The plan holds **data-retrieval tools only** (`templates/scope-rules.md`). A requirement that needs business logic is not a tool: it lives in `outOfScopeRequirements`.

## Type Mapping Table

From spec / API-inventory types to `@ToolParam` Java types:

| Spec type | Java type | Notes |
|---|---|---|
| `string` | `String` | |
| `enum` | `String` + a validated `Set<String>` constant | Enum values are listed in the param description; a Java enum in a tool signature renders a schema some clients handle poorly |
| `date` | `String` (`yyyy-MM-dd`) | Parsed and range-checked in the tool; format stated in the description |
| `datetime` | `String` (ISO-8601 with offset) | Same |
| `integer` (optional) | `Integer` / `Long` | Boxed so "absent" is representable |
| `integer` (required) | `int` / `long` | |
| `decimal` | `BigDecimal` | |
| `boolean` | `Boolean` | |
| `object` | a record | Only for genuinely structured input; flat parameters are easier for models |
| `array` | `List<String>` / `List<Integer>` | Bounded size, validated |

## plan.json Schema

```json
{
  "feature": "string — feature name (kebab-case)",
  "specSource": "string — planning-plugin | document | task",
  "specStatus": "string — the `specStatus` parameter mcp-plan passes (reviewing|finalized), or null for a task or document source",
  "specDir": "string — path to the spec directory or the source document",
  "workingLanguage": "string — working language code (en|ko|vi)",
  "planGeneratedAt": "string — the `generatedAt` parameter mcp-plan passes (UTC, `Z`-suffixed); the planner never invents a timestamp",
  "readOnly": "boolean — copied from config; a write tool in a readOnly plan is flagged, never silently planned",

  "tools": [
    {
      "name": "string — snake_case tool name (verb_domain[_qualifier])",
      "toolClass": "string — {Domain}Tools class that owns it (existing or new)",
      "verb": "string — list | get | query | a write verb",
      "accessScope": "string — Read-only | Finance-scoped | write description",
      "annotations": { "readOnlyHint": "boolean", "destructiveHint": "boolean", "idempotentHint": "boolean", "openWorldHint": "boolean — all four set explicitly (templates/scope-rules.md § 7 C2)" },
      "scopeCheck": {
        "verdict": "string — in-scope (the only value a planned tool may carry)",
        "upstreamReads": "number — exactly 1",
        "derivedFields": ["string — must be empty: fields not returned by the upstream"],
        "note": "string — why the scope test (templates/scope-rules.md § 4) passes, e.g. the upstream computes the total"
      },
      "writeOptIn": "string or null — who/when/why the user opted in to this write tool; null for every read tool; a write tool with null is blocked by mcp-code",
      "description": {
        "scope": "string — What + gotcha + access-scope tag (becomes <tool_scope>)",
        "input": "string — required input + key constraint + cross-reference (becomes <input>)"
      },
      "params": [
        {
          "name": "string — camelCase parameter name",
          "type": "string — spec type",
          "javaType": "string — Java type per the mapping table",
          "required": "boolean",
          "description": "string — @ToolParam description",
          "validation": "string — rule, e.g. enum:EN|KO|VI, date-range-max:31d, clamp:1..1000",
          "source": "string — spec reference"
        }
      ],
      "upstream": {
        "client": "string — {Upstream}Client",
        "method": "string — client method name (existing or new)",
        "http": "string — e.g. POST /mcp/v1/bookings",
        "idempotent": "boolean",
        "cache": "string — cache name + TTL, or none",
        "source": "string — inventory/spec reference"
      },
      "rbac": {
        "permission": "string — tool code checked by @rbac.canCall, or an alias tool",
        "fieldScoped": ["string — fields nulled for callers without the grant"],
        "rowScope": "string — region/tenant scoping rule, or none"
      },
      "output": {
        "type": "string — result record name",
        "shape": "string — object | list | envelope",
        "maxRows": "number — row cap clamped in the tool (null when not a list)",
        "fieldSources": ["string — `resultField <- upstream.field` for every output field; none may lack an upstream source"],
        "sanitizedFields": ["string"],
        "maskedFields": ["string"]
      },
      "errors": [
        { "code": "string — McpToolException code", "condition": "string", "source": "string" }
      ],
      "testScenarios": [
        { "id": "string — TS-nnn or generated", "scenario": "string — lowercase single sentence", "source": "string" }
      ],
      "source": "string — FR/BR/inventory references"
    }
  ],

  "toolOrder": ["string — tool names in implementation order (shared client methods first)"],
  "skippedRequirements": [
    { "ref": "string", "reason": "string — e.g. write operation on a readOnly server, UI-only" }
  ],
  "outOfScopeRequirements": [
    {
      "ref": "string — FR/BR/AC/inventory reference or a short quote",
      "rule": "string — BL-1..BL-8 (templates/scope-rules.md § 3), or `unclear` when it is unknown whether the upstream already computes it",
      "reason": "string — one sentence: what business logic the requirement would put in the MCP server",
      "upstreamAsk": "string — the endpoint or field the upstream owner should expose, so a plain read tool can wrap it",
      "closestInScopeTool": "string or null — a planned read tool that lets the model answer from raw rows, if any"
    }
  ],
  "existingTools": ["string — tools already published that this plan reuses or extends"],
  "summary": {
    "tools": "number",
    "newToolClasses": "number",
    "newClientMethods": "number",
    "testScenarios": "number",
    "outOfScope": "number — outOfScopeRequirements.length"
  }
}
```

## Rules the planner applies

- Every requirement is classified with the `templates/scope-rules.md` § 4 scope test before it becomes
  a tool. One that needs a calculation, a derived field, an aggregation, a multi-endpoint join, a
  business decision or server-side state is listed in `outOfScopeRequirements` — never planned,
  never "simplified" into a tool that does part of it
- A planned tool makes exactly one upstream read; every output field is traced to an upstream
  field in `output.fieldSources`; `scopeCheck.derivedFields` is empty
- A write tool is planned only on a non-`readOnly` server, as a pure pass-through of one upstream
  endpoint, with honest annotations; `writeOptIn` is filled by `mcp-code` after the user's explicit
  opt-in (`templates/scope-rules.md` § 6)
- A requirement that would need a mutating upstream call on a `readOnly` server is listed in
  `skippedRequirements`, never planned as a tool
- A change to an existing published tool is planned as additive (new optional param, new output
  field); a breaking change is planned as a new tool name, and the old tool stays
- Descriptions are drafted to `templates/tool-conventions.md` (or the project's
  `descriptionConvention` document) — compact, no narrative
- Every tool gets at least: one validation scenario, one happy-path scenario, one access-control
  scenario (when security is enabled), one output-safety scenario for each free-text/PII field,
  one pass-through scenario (the result carries the upstream's values unchanged — no derived or
  recomputed field), and the final contract scenario
- The plan covers tools only. MCP resources, prompts and server-instructions changes are not
  planned — no skill implements them from a plan; they are the team's deliberate edit
  (`templates/tool-conventions.md` § Server instructions, resources and prompts)
