---
name: hp-init
description: Initialize Homepage Plugin configuration for the current project. Sets content strategy, i18n, and deploy target.
argument-hint: ""
user-invocable: true
allowed-tools: Read, Write, Glob, Bash
---

# Initialize Homepage Plugin

Set up the Homepage Plugin configuration for this project.

## Instructions

### Step 1: Check Existing Configuration

Read `.claude/homepage-plugin.json`. If it exists, show current settings and ask the user if they want to reconfigure. If they decline, exit.

### Step 2: Content Strategy

Ask: "How do you want to manage content?"

Options:
- **mdx** (default) — MDX files in the repo, version-controlled
- **headless-cms** — Headless CMS (Sanity, Contentful, Strapi)
- **both** — MDX for blog posts + headless CMS for dynamic content

### Step 3: i18n Configuration

Ask: "Which languages should the site support?"

- Ask for a list of locale codes (default: `ko, en`)
- Ask which is the default locale (default: `ko`)

### Step 4: Deploy Target

Ask: "Where will this site be deployed?"

Options:
- **aws** (default) — S3 + CloudFront static hosting
- **vercel**
- **netlify**
- **cloudflare** — CloudFlare Pages
- **static** — generic static hosting

### Step 5: ESLint Template

Ask: "Should the plugin auto-generate ESLint config when none exists?"

- **true** (default) — auto-generate `eslint.config.js` from bundled template
- **false** — skip ESLint in projects without their own config

### Step 5.5: Figma Configuration (Optional)

Ask: "Do you have a Figma design system file? (Paste URL or skip)"

- If the user provides a URL, extract the file key using regex: `figma\.com/(file|design)/([a-zA-Z0-9]+)`
- Store the extracted key as `figmaFileKey` and the full URL as `figmaFileUrl` in the configuration
- If skipped, omit both fields from the configuration

### Step 6: Write Configuration

Write `.claude/homepage-plugin.json`:

```json
{
  "framework": "astro",
  "contentStrategy": "{user choice}",
  "i18nLocales": ["{user choices}"],
  "defaultLocale": "{user choice}",
  "deployTarget": "{user choice, default: aws}",
  "eslintTemplate": true,
  "figmaFileKey": "{extracted key, omit if skipped}",
  "figmaFileUrl": "{full URL, omit if skipped}"
}
```

### Step 7: Install External Skills

Install the following skills using `claude mcp add-skill` or equivalent:

1. **Web Design Guidelines** — `vercel-labs/agent-skills` → `web-design-guidelines`
2. **Composition Patterns** — `vercel-labs/agent-skills` → `vercel-composition-patterns`

For each skill, check if already installed at `.claude/skills/{skill-name}/SKILL.md`. Skip if present.

### Step 8: Confirmation

Display:
- Configuration summary
- Installed skills
- Figma status: if `figmaFileKey` is set, show "Figma connected — run `/homepage-plugin:hp-design-sync` to extract design tokens." Otherwise show "No Figma configured — using shadcn/ui defaults."
- Next step: "Run `/homepage-plugin:hp-plan` to define pages and sections."

## Communication Language

Use the `defaultLocale` from the configuration for all user-facing output:
- `ko` → Korean
- `en` → English
- `vi` → Vietnamese
