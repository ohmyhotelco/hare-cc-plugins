// fo-seo — one seo-verifier per aspect, in parallel; merged in code.
// args: { app, screen, config, planFile, specDir, outDir, aspects: [ 'head', 'links', 'sitemap', 'structuredData', 'slugs' ] }

export const meta = {
  name: 'fo-seo',
  description: 'Check a screen against the SEO spec: head meta, canonical/hreflang, sitemap/robots, structured data, slugs — in parallel',
  whenToUse: 'Started by /frontend-ohmyhotel-plugin:fo-seo; not run by hand',
  phases: [{ title: 'Check', detail: 'one agent per aspect' }],
}

const RESULT = {
  type: 'object',
  properties: {
    aspect: { type: 'string' }, result: { type: 'string', enum: ['pass', 'fail', 'skipped', 'not-run'] }, reason: { type: ['string', 'null'] },
    routesChecked: { type: 'integer' },
    findings: { type: 'array', items: { type: 'object', properties: { severity: { type: 'string' }, confidence: { type: 'string' }, route: { type: 'string' }, lang: { type: 'string' }, message: { type: 'string' }, evidence: { type: 'string' }, fixHint: { type: 'string' } }, required: ['severity', 'confidence', 'message'] } },
    evidence: { type: 'array', items: { type: 'object' } }, notes: { type: 'array', items: { type: 'string' } },
  },
  required: ['aspect', 'result', 'findings', 'evidence'],
}

phase('Check')
if (!args || !args.app || !args.screen) return { ok: false, result: 'not-run', reason: 'args {app, screen, …} are required; this workflow is started by its skill' }
const common = `app: ${args.app}\nscreen: ${args.screen}\nconfig: ${JSON.stringify(args.config)}\nplanFile: ${args.planFile}\nspecDir: ${args.specDir}\nserverUrl: ${args.serverUrl || ''}\noutDir: ${args.outDir}`
const resultsRaw = (await parallel((args.aspects || []).map(a => () =>
  agent(`aspect: ${a}\n${common}`, { label: `${args.screen}:seo:${a}`, phase: 'Check', schema: RESULT, agentType: 'frontend-ohmyhotel-plugin:seo-verifier' })
    .then(r => r || { aspect: a, result: 'not-run', reason: 'agent returned no result', findings: [], evidence: [] })
    .catch(e => ({ aspect: a, result: 'not-run', reason: String(e), findings: [], evidence: [] }))
)))

const results = resultsRaw.map((r, i) => r || { aspect: (args.aspects || [])[i], result: 'not-run', reason: 'agent returned no result', findings: [], evidence: [] })
const byResult = results.reduce((m, r) => ({ ...m, [r.result]: (m[r.result] || 0) + 1 }), {})
const critical = results.flatMap(r => r.findings).filter(f => f.severity === 'critical').length
const overall = !results.length ? 'not-run' : results.some(r => r.result === 'fail') ? 'fail' : results.some(r => r.result === 'not-run') ? 'not-run' : 'pass'
log(`${results.length} aspects — ${JSON.stringify(byResult)}, critical findings ${critical}`)
return { ok: overall === 'pass', result: overall, aspects: results }
