---
name: bundle
description: "Rebuild bundle.html from existing prototype source files."
argument-hint: "[feature-name]"
user-invocable: true
allowed-tools: Read, Write, Bash, Glob
---

# Rebuild Prototype Bundle

Rebuild bundle for: **$ARGUMENTS**

## Instructions

### Step 1: Parse & Validate

1. Parse `feature` from arguments (required, kebab-case)
2. Verify `src/prototypes/{feature}/package.json` exists. If not, stop with:
   > "No prototype found for '{feature}'. Run `/planning-plugin:prototype {feature}` first."
3. Read the progress file at `docs/specs/{feature}/.progress/{feature}.json`. If it does not exist, stop with:
   > "No progress file found for '{feature}'."

### Step 2: Run Bundle Script

1. Execute the bundle script:
   ```
   ${CLAUDE_PLUGIN_ROOT}/scripts/bundle-artifact.sh src/prototypes/{feature}
   ```
2. Capture exit code and output

### Step 3: Update Progress

On **success**:
1. Read the progress file
2. Set `design.stages.prototype.bundleStatus` to `"current"`
3. Set `design.stages.prototype.generatedAt` to the current ISO-8601 UTC timestamp
4. Write the updated progress file

On **failure**:
1. Report the error output to the user
2. Do NOT change `bundleStatus`

### Step 4: Report Result

On success, display:
```
Bundle rebuilt successfully for '{feature}'.
  File: src/prototypes/{feature}/bundle.html
  Size: {size} KB
  Status: current
```

On failure, display the error and suggest checking build logs.
