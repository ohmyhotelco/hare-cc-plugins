---
type: llm
---

PASS if the report identifies that CancelButton.tsx leaves `busy` true, or skips onDone, when the async work throws, for lack of try/finally, at any severity. FAIL if the report does not mention it.
