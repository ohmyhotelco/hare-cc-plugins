# v2-plan: Standalone requirements gathering

Part of the `v2-plan` skill. `{pluginRoot}` is the plugin root the skill states.

### Step 1-S: Standalone Requirements Gathering (standalone mode only)

Gather minimal requirements interactively from the user.

#### 1-S.1: Feature Description
> "Describe '{feature}' in 2-3 sentences. What does this feature do?"

#### 1-S.2: Working Language
> "Working language? (en/ko/vi, default: en)"

#### 1-S.3: Entities
> "List the main data entities (e.g., Hotel, Room, Booking)."
> "For each entity, list key fields (e.g., Hotel: id, name, rating, location)."

#### 1-S.4: Screens
> "List the screens/pages for this feature."
> "Briefly describe what each screen does and which entities it uses."

#### 1-S.5: Confirm & Proceed

Display collected requirements summary and confirm:

```
Standalone Plan for '{feature}':
  Description: {description}
  Entities: {count} ({names})
  Screens: {count} ({names})
  Language: {workingLanguage}

  Note: Standalone mode generates a simplified plan.
  For a complete spec-based plan with validation rules,
  error codes, and test scenarios, use planning-plugin.
```

> "Proceed with standalone plan generation?"
- If the user declines, stop here.

#### 1-S.6: Generate Minimal Spec Files

Create the following directory structure:

```
docs/specs/{feature}/
├── .progress/{feature}.json  ← status: "finalized", standalone: true
├── {workingLanguage}/
│   └── {feature}-spec.md     ← auto-generated from user input
└── .implementation/
    └── frontend/
```

**Progress file**: Include `"standalone": true` flag:
```json
{
  "feature": "{feature}",
  "status": "finalized",
  "standalone": true,
  "workingLanguage": "{workingLanguage}",
  "createdAt": "{ISO timestamp}"
}
```

**Minimal spec**: Auto-generate from user input — include overview section, entity definitions with fields, screen descriptions, and basic CRUD functional requirements per entity.

#### 1-S.7: Continue to Plan Generation

Set `uiDslAvailable = false`, `prototypeAvailable = false`.
Proceed to Step 3 (Launch Planner Agent) — the implementation-planner already handles `uiDslAvailable = false` and `standalone: true` in the progress file.
