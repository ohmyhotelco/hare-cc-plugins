---
description: This request should go through be-debug.
max_turns: 5
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
tags: [routing, routing-exec]
---

Creating a reservation with a past check-in date returns 200 instead of 400, and I can't see why. Find the root cause and fix it.
