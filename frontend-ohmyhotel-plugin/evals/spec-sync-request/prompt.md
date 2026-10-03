---
description: A developer brings a new planning-spec attachment into the repo; the fo-spec-sync skill should handle it and insist on the ledger fields.
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [routing, spec]
expected_outcome: fo-spec-sync fires; since this workspace has no plugin config, the reply points at fo-init and names the importer's dry run rather than importing by hand.
---

Lexi uploaded main-page-spec_v1.9_20261002.zip to Jira OMH-794. Bring it into this repo as the current spec for screen 01-main-page and tell me what changed versus the previous snapshot.
