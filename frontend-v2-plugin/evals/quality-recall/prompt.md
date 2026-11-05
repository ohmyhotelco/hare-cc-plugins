---
description: quality-reviewer in standalone mode finds defects seeded in a small feature, and leaves a correct file alone.
max_turns: 6
timeout_seconds: 420
allowed_tools: [Agent, Read, Glob, Grep]
tags: [quality, recall]
---

Start the `frontend-v2-plugin:quality-reviewer` agent with the Agent tool and these parameters: mode: standalone, targetPath: src/features/orders, projectRoot: the current directory. Then reply with the agent's full report, unchanged.
