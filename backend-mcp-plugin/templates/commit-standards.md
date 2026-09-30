# Commit Standards

Every commit message `mcp-commit` writes — and every rule `mcp-recall commit` checks — follows
these. Read from `{pluginRoot}/templates/commit-standards.md`.

1. Write in English
2. Use present tense in the subject line ("Add feature" not "Added feature")
3. Keep the subject line to 50 characters or less
4. Add a blank line between the subject and body
5. Keep the body to 72 characters or less per line
6. Only break lines within a paragraph when exceeding 72 characters
7. Do not mention test code in commit messages
8. Do not use any prefix (fix:, feat:, docs:, etc.) in the subject line
9. Start with an uppercase letter (exception: lowercase identifiers with justification)
10. Do not include tool advertisements, branding, or promotional content
11. Only operate on already-staged changes -- never stage additional files
12. Ensure all intended changes are staged before invoking commit
13. Use separate git commands to stage files before committing
