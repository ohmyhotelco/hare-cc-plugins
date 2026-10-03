// fo-visual — visual gate for one screen: capture every state × viewport × language, then compare
// each capture that has a Figma frame against that frame, in parallel. Breakage findings come from the
// capture; divergence findings from the comparisons; the skill writes the evidence from this result.
//
// args: { app, screen, config, planFile, outDir, fileKey, figma: [ { state, viewport, nodeId, export } ] }

export const meta = {
  name: 'fo-visual',
  description: 'Capture a screen at every viewport × language × state, check breakage, compare captures with their Figma frames',
  whenToUse: 'Started by /frontend-ohmyhotel-plugin:fo-visual after fo-verify passes; not run by hand',
  phases: [{ title: 'Capture', detail: 'Playwright spec, breakage checks' }, { title: 'Compare', detail: 'one agent per Figma frame' }],
}

const CAPTURE = {
  type: 'object',
  properties: {
    mode: { type: 'string' }, spec: { type: 'string' },
    captures: { type: 'array', items: { type: 'object', properties: { path: { type: 'string' }, state: { type: 'string' }, viewport: { type: 'integer' }, lang: { type: 'string' }, breakage: { type: 'array', items: { type: 'object' } }, error: { type: ['string', 'null'] } }, required: ['state', 'viewport', 'lang'] } },
    breakage: { type: 'object' },
    evidence: { type: 'array', items: { type: 'object' } }, notes: { type: 'array', items: { type: 'string' } },
    status: { type: 'string', enum: ['done', 'not-run', 'failed'] }, reason: { type: ['string', 'null'] },
  },
  required: ['captures', 'evidence', 'status'],
}
const COMPARE = {
  type: 'object',
  properties: {
    state: { type: 'string' }, viewport: { type: 'integer' }, scores: { type: 'object' },
    findings: { type: 'array', items: { type: 'object', properties: { severity: { type: 'string' }, confidence: { type: 'string' }, area: { type: 'string' }, message: { type: 'string' }, fixHint: { type: 'string' } }, required: ['severity', 'confidence', 'message'] } },
  },
  required: ['state', 'viewport', 'findings'],
}

const common = `app: ${args.app}\nscreen: ${args.screen}\nconfig: ${JSON.stringify(args.config)}\nplanFile: ${args.planFile}\noutDir: ${args.outDir}`

phase('Capture')
const cap = await agent(`mode: capture\n${common}`, { label: `${args.screen}:capture`, phase: 'Capture', schema: CAPTURE, agentType: 'frontend-ohmyhotel-plugin:visual-verifier' })
if (!cap || cap.status !== 'done') {
  return { ok: false, result: cap && cap.status === 'not-run' ? 'not-run' : 'fail', reason: cap ? cap.reason : 'capture agent returned no result', capture: cap, comparisons: [] }
}

const frames = (args.figma || []).map(f => ({ ...f, rendered: cap.captures.find(c => c.state === f.state && c.viewport === f.viewport && !c.error) }))
const missing = frames.filter(f => !f.rendered)
if (missing.length) log(`${missing.length} Figma frame(s) have no rendered capture: ${missing.map(f => `${f.state}@${f.viewport}`).join(', ')}`)
const pairs = frames.filter(f => f.rendered)
if (!pairs.length) log('no Figma frames for this screen — breakage check only')

phase('Compare')
const comparisons = (await parallel(pairs.map(f => () =>
  agent(`mode: compare\nscreen: ${args.screen}\nstate: ${f.state}\nviewport: ${f.viewport}\nnodeId: ${f.nodeId || ''}\nfileKey: ${args.fileKey || ''}\nrendered: ${f.rendered.path}\nfigma: ${f.export || ''}`,
    { label: `${args.screen}:compare:${f.state}@${f.viewport}`, phase: 'Compare', schema: COMPARE, agentType: 'frontend-ohmyhotel-plugin:visual-verifier' })
))).filter(Boolean)

const breakageCount = cap.captures.reduce((n, c) => n + ((c.breakage || []).length), 0)
const critical = comparisons.flatMap(c => c.findings).filter(f => f.severity === 'critical').length
const result = breakageCount === 0 && critical === 0 ? 'pass' : 'fail'
log(`captures ${cap.captures.length}, breakage ${breakageCount}, frames compared ${comparisons.length}, critical divergences ${critical}`)
return { ok: result === 'pass', result, capture: cap, comparisons, framesWithoutCapture: missing.map(f => ({ state: f.state, viewport: f.viewport })) }
