// fo-probe — smoke test for the plugin's orchestration path.
//
// Starts each plugin agent once through the workflow runtime (agentType + schema) with a trivial
// read-only task and reports whether the agent resolved and identified itself with its own role.
// Run it after adding or renaming an agent, and after a Claude Code upgrade, before trusting
// fo-gen / fo-review on a real screen.
//
// args (optional): { "agents": ["spec-reviewer", ...], "file": "<repo-relative file to read>" }

export const meta = {
  name: 'fo-probe',
  description: 'Resolve every frontend-ohmyhotel-plugin agent through the workflow runtime and check it answers as itself',
  whenToUse: 'After adding/renaming a plugin agent or upgrading Claude Code; before running fo-gen or fo-review on a real screen',
  phases: [{ title: 'Probe', detail: 'one trivial read-only task per agent' }],
}

const AGENTS = (args && args.agents) || ['spec-reviewer']
const FILE = (args && args.file) || 'README.md'

const SCHEMA = {
  type: 'object',
  properties: {
    role: { type: 'string', description: 'Your role as your own system prompt states it, one sentence' },
    sawSharedConventions: { type: 'boolean', description: 'true if your context includes the fo-shared conventions (state files, locks, reporting rules)' },
    headings: { type: 'array', items: { type: 'string' } },
    lineCount: { type: 'integer' },
  },
  required: ['role', 'sawSharedConventions', 'headings', 'lineCount'],
}

phase('Probe')
const results = await parallel(AGENTS.map(name => () =>
  agent(
    `Plumbing probe — not a review. Read the file ${FILE} in the current repository and return: your role as your system prompt states it (role), whether the fo-shared conventions are present in your context (sawSharedConventions), the markdown headings of the file (headings), and its line count (lineCount). Do nothing else.`,
    { label: `probe:${name}`, phase: 'Probe', schema: SCHEMA, effort: 'low', agentType: `frontend-ohmyhotel-plugin:${name}` },
  ).then(r => ({ agent: name, resolved: r !== null, result: r }))
   .catch(e => ({ agent: name, resolved: false, error: String(e) }))))

const failed = results.filter(r => !r.resolved)
log(`${results.length - failed.length}/${results.length} agents resolved${failed.length ? ` — failed: ${failed.map(f => f.agent).join(', ')}` : ''}`)
return { ok: failed.length === 0, results }
