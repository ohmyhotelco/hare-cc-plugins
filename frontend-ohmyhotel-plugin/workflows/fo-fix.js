// fo-fix — one review-fixer per approved cluster, strictly one after another (they edit code in the
// same screen; parallel fixers would race on files). Stops at the first failed cluster so the skill
// can re-run verify before the rest.
// args: { app, screen, config, planFile, specDir, clusters: [ { id, title, source, findings } ] }

export const meta = {
  name: 'fo-fix',
  description: 'Apply approved review/gate finding clusters to a screen, one fixer per cluster in sequence',
  whenToUse: 'Started by /frontend-ohmyhotel-plugin:fo-fix after the user approves clusters; not run by hand',
  phases: [{ title: 'Fix', detail: 'one agent per cluster, sequential' }],
}

const RESULT = {
  type: 'object',
  properties: {
    clusterId: { type: 'string' }, status: { type: 'string', enum: ['done', 'partial', 'failed'] },
    applied: { type: 'array', items: { type: 'object' } }, declined: { type: 'array', items: { type: 'object' } }, outOfCluster: { type: 'array', items: { type: 'object' } },
    evidence: { type: 'array', items: { type: 'object' } }, notes: { type: 'array', items: { type: 'string' } },
  },
  required: ['clusterId', 'status', 'applied', 'evidence'],
}

phase('Fix')
const base = `app: ${args.app}\nscreen: ${args.screen}\nconfig: ${JSON.stringify(args.config)}\nplanFile: ${args.planFile}\nspecDir: ${args.specDir}`
const results = []
for (const c of args.clusters || []) {
  const r = await agent(`${base}\ncluster: ${JSON.stringify(c)}`, { label: `${args.screen}:fix:${c.id}`, phase: 'Fix', schema: RESULT, agentType: 'frontend-ohmyhotel-plugin:review-fixer' })
  results.push(r || { clusterId: c.id, status: 'failed', applied: [], evidence: [], notes: ['fixer returned no result'] })
  log(`${c.id}: ${results[results.length - 1].status} (${(r && r.applied ? r.applied.length : 0)} applied)`)
  if (!r || r.status === 'failed') break
}
const remaining = (args.clusters || []).slice(results.length).map(c => c.id)
return { ok: results.every(r => r.status === 'done') && remaining.length === 0, results, remaining }
