// fo-contract — one contract-verifier per rule list (and telemetry), in parallel; merged in code.
// args: { app, screen, config, planFile, specDir, outDir, checks: [ { check, ruleFile } ] }

export const meta = {
  name: 'fo-contract',
  description: 'Check a screen against the product rule lists (external URLs, WebView contract, sensitive query keys, request conventions) and its telemetry events, in parallel',
  whenToUse: 'Started by /frontend-ohmyhotel-plugin:fo-contract; not run by hand',
  phases: [{ title: 'Check', detail: 'one agent per rule list' }],
}

const RESULT = {
  type: 'object',
  properties: {
    check: { type: 'string' }, result: { type: 'string', enum: ['pass', 'fail', 'skipped', 'not-run'] }, reason: { type: ['string', 'null'] },
    entriesChecked: { type: 'integer' },
    findings: { type: 'array', items: { type: 'object', properties: { severity: { type: 'string' }, confidence: { type: 'string' }, entry: { type: 'string' }, message: { type: 'string' }, evidence: { type: 'string' }, fixHint: { type: 'string' } }, required: ['severity', 'confidence', 'message'] } },
    evidence: { type: 'array', items: { type: 'object' } }, notes: { type: 'array', items: { type: 'string' } },
  },
  required: ['check', 'result', 'findings', 'evidence'],
}

phase('Check')
const common = `app: ${args.app}\nscreen: ${args.screen}\nconfig: ${JSON.stringify(args.config)}\nplanFile: ${args.planFile}\nspecDir: ${args.specDir}\noutDir: ${args.outDir}`
const results = (await parallel((args.checks || []).map(c => () =>
  agent(`check: ${c.check}\nruleFile: ${c.ruleFile || ''}\n${common}`, { label: `${args.screen}:${c.check}`, phase: 'Check', schema: RESULT, agentType: 'frontend-ohmyhotel-plugin:contract-verifier' })
    .then(r => r || { check: c.check, result: 'not-run', reason: 'agent returned no result', findings: [], evidence: [] })
))).filter(Boolean)

const byResult = results.reduce((m, r) => ({ ...m, [r.result]: (m[r.result] || 0) + 1 }), {})
const critical = results.flatMap(r => r.findings).filter(f => f.severity === 'critical').length
const overall = results.some(r => r.result === 'fail') ? 'fail' : results.some(r => r.result === 'not-run') ? 'not-run' : 'pass'
log(`${results.length} checks — ${JSON.stringify(byResult)}, critical findings ${critical}`)
return { ok: overall === 'pass', result: overall, checks: results }
