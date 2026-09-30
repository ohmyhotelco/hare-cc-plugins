# MCP Tool Plan Schema

Reference for `plan.json` — the structured tool plan produced by the `mcp-planner` agent and
consumed by `mcp-code` (work-document generation) and `mcp-review` (Spec Compliance dimension).

Location: `docs/specs/{feature}/.implementation/mcp/plan.json`

Used by: `mcp-planner` agent (generation), `mcp-code` (consumption), `code-reviewer` (spec compliance)

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
  "existingTools": ["string — tools already published that this plan reuses or extends"],
  "summary": {
    "tools": "number",
    "newToolClasses": "number",
    "newClientMethods": "number",
    "testScenarios": "number"
  }
}
```

## Rules the planner applies

- A requirement that would need a mutating upstream call on a `readOnly` server is listed in
  `skippedRequirements`, never planned as a tool
- A change to an existing published tool is planned as additive (new optional param, new output
  field); a breaking change is planned as a new tool name, and the old tool stays
- Descriptions are drafted to `templates/tool-conventions.md` (or the project's
  `descriptionConvention` document) — compact, no narrative
- Every tool gets at least: one validation scenario, one happy-path scenario, one access-control
  scenario (when security is enabled), one output-safety scenario for each free-text/PII field,
  and the final contract scenario
- The plan covers tools only. MCP resources, prompts and server-instructions changes are not
  planned — no skill implements them from a plan; they are the team's deliberate edit
  (`templates/tool-conventions.md` § Server instructions, resources and prompts)
