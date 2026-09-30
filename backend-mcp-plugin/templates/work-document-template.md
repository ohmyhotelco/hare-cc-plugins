# {tool_name}

<!-- Template used by: mcp-code (one work document per tool; plan-driven or drafted with the user) -->

Tool class: `{toolsPackage}.{Domain}Tools`   <!-- read by the implement agent: where the @Tool method goes -->
Upstream client: `{basePackage}.client.{Upstream}Client`   <!-- or "none" for a tool that calls no upstream -->

## Tool Specification

| Item | Value |
|------|-------|
| Name | `{tool_name}` |
| Verb | `list` \| `get` \| `query` \| `{write verb}` |
| Access scope | Read-only \| Finance-scoped \| {write: what it changes, idempotent?} |
| RBAC permission | `@rbac.canCall('{tool_name}')` \| `{alias tool}` \| none (security disabled) |
| Rate limiter | `mcpTools` \| `{bucket}` |

### Description (the published contract)

```
<tool_scope>{What}. {Gotcha}. {Access-scope tag}</tool_scope><input>{Required input + key constraint + cross-reference}</input>
```

### Parameters

| Name | Java type | Required | `@ToolParam` description | Validation |
|------|-----------|----------|--------------------------|------------|
| {param} | String | yes | {format / enum / source tool} | {rule → INVALID_INPUT} |

### Upstream Call

| Item | Value |
|------|-------|
| Method | `{Upstream}Client#{method}` (new \| existing) |
| HTTP | `{GET\|POST} {path}` |
| Idempotent | yes \| no (never retried) |
| Cache | `{cacheName}`, TTL {ttl} \| none (live data) |
| Rate / circuit | `{limiter}` / `{circuitBreaker}` |

### Output

| Item | Value |
|------|-------|
| Result type | `{Result}` record (`client/dto/` or tool-local) |
| Shape | object \| list \| `{list, totalCount, limit, offset}` envelope |
| Row cap | {n} (clamped in the tool) + the server-wide result limiter |
| Sanitized fields | {free-text fields routed through the sanitizer} |
| Masked fields | {PII fields and their mask} |
| Field-scoped (RBAC) | {fields nulled for callers without the grant, disclosed in `restrictedFields`} |
| Row scope | {rows filtered to the caller's region/tenant, and how} \| none |

### Errors

| Code | Condition |
|------|-----------|
| INVALID_INPUT | {validation rule} |
| NOT_FOUND | {when} |
| ACCESS_DENIED | caller lacks `{permission}` / entity outside caller scope |
| UPSTREAM_* | classified by the upstream client |

### Contract

- Snapshot: `{contractSnapshot}` gains / changes the `{tool_name}` entry
- Changelog: `{contractChangelog}` entry — Added \| Changed ({what})

## Test Scenarios

Write scenarios following these rules:
1. One scenario at a time, most important first
2. Single sentence in English, present tense
3. Start with lowercase (usable as a test method name)
4. Concise while preserving meaning
5. Use to-do checkbox format
6. The contract scenario is always last
7. End each scenario with its source comment — `<!-- TS-003 -->`, `<!-- AC-2 -->`, `<!-- BR-004 -->`, or `<!-- manual -->`

### Input validation

- [ ] {invalid input} is rejected with INVALID_INPUT before calling upstream <!-- {source} -->

### Behavior

- [ ] valid request returns {expected result}
- [ ] {not found condition} fails with NOT_FOUND

### Access control

- [ ] caller without {permission} is denied
- [ ] field-scoped caller sees {fields} nulled and listed in restrictedFields

### Output safety

- [ ] {free-text field} is sanitized
- [ ] {pii field} is masked

### Upstream

- [ ] upstream {failure} surfaces as {code}

### Contract

- [ ] tool contract snapshot includes {tool_name} and the changelog records it

## Implementation Notes

- {Upstream quirks, cap values quoted from the upstream, related tools}
