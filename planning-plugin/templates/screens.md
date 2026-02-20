## 4. Screen Definitions

### Screen: {Screen Name}

**Purpose**: {What does this screen do?}

**Entry Points**: {How does the user reach this screen?}

**Layout**:
```
+----------------------------------------+
| [ Header ]                             |
| - Breadcrumb                           |
| - SearchInput            - ActionButton|
+----------------------------------------+
| [ Content ]                            |
| - DataTable                            |
+----------------------------------------+
| [ Footer ]                             |
| - Pagination                           |
+----------------------------------------+
```
<!-- ASCII layout rules:
     - Draw regions with +---, |, + characters
     - Label each region with [ Name ] on first line
     - List components as "- ComponentName" inside regions
     - Use || to separate side-by-side columns
     - Nest boxes inside boxes for hierarchy
-->

**Components**:
| Component | Type | Behavior |
|-----------|------|----------|
| {name} | {type} | {description} |

**User Actions**:
| Action | Trigger | Result |
|--------|---------|--------|
| {action} | {trigger} | {expected result} |

---

## 5. Error Handling

| Error Code | Condition | User Message | Resolution |
|------------|-----------|--------------|------------|
| {code} | {when does this occur?} | {message shown to user} | {how to resolve} |
