---
type: llm
---

PASS if the report identifies that useAutoRefresh.ts reads `ticks`, or `onTick` or `seconds`, from a stale closure because of the empty dependency array, at any severity. FAIL if the report does not mention it.
