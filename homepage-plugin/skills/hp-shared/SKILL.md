---
name: hp-shared
description: Shared conventions for every homepage-plugin agent and skill — stack, code conventions, state-file writes, check commands and how to report them. Preloaded into agents through their `skills:` frontmatter; not meant to be invoked by hand.
user-invocable: false
---

# Shared conventions (homepage-plugin)

Agents receive this skill through `skills: [hp-shared]`. The plugin-root `CLAUDE.md` is maintainer notes and reaches no agent.

## Stack

- Node.js 22.12+, pnpm, TypeScript strict, Astro 5 (static output by default, SSR through adapters)
- Tailwind CSS with shadcn/ui, or Figma-derived custom components when `docs/design-system/design-tokens.json` exists
- Lucide icons; React 19 for interactive islands only
- Content Collections with Zod, MDX, and an optional headless CMS per `contentStrategy`
- Translations in `src/i18n/{locale}.json`; dates through `Intl.DateTimeFormat` and `Intl.RelativeTimeFormat`
- Playwright, Lighthouse CI (90+ in every category) and axe-core (WCAG 2.1 AA) for testing

These sites are static and public, so they use no Zustand, Axios, MSW, CRUD stores, auth or RBAC.

## Code conventions

- 2-space indentation
- `.astro` for static sections, React `.tsx` only for interactive islands
- User-facing text goes through the i18n translation functions
- Images use `<Image />` from `astro:assets` with explicit `width`, `height` and `alt`
- Mobile-first responsive design with Tailwind breakpoints `sm:`, `md:`, `lg:`, `xl:`
- One `<h1>` per page and a logical heading order
- `aria-label` on icon-only buttons and proper focus management
- `truncate` or `line-clamp-*` on variable-length text
- Every page defines `<title>`, `<meta name="description">`, Open Graph tags, a canonical URL and JSON-LD

## State files

When updating a state JSON file, read its latest content immediately before writing, change only the fields you own, and write the whole merged object. The `.lock` file belongs to the skill that started the run; agents leave it alone.

## Checks

- TypeScript: `tsc --noEmit`, or `tsc -b` when `tsconfig.json` has a `references` array
- Build: `astro build`, zero errors

Run these through `npx`. Report a check's result from its output in this run. A check that did not run is reported as not run.
