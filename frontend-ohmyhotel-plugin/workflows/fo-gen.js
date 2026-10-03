// fo-gen — generate one screen from its implementation plan, stage by stage.
//
// Started by the fo-gen skill, which has already taken the screen lock, checked the plan is approved,
// initialised generation-state.json and decided which stages run. Stages are strictly sequential:
// each one builds on the files of the one before, so there is nothing to run in parallel inside a
// screen. The workflow fixes the order and the stop-on-failure rule in code; the agents do the work
// and write their own stage entry into generation-state.json.
//
// args: {
//   app, screen, planFile, stateFile, specDir, config,          // passed through to every agent
//   stages: [ { stage, enabled, files, testFiles } ],            // from the plan's buildOrder; enabled=false → skipped
//   resumeFrom: "component-tdd" | null,                          // stages before it are skipped (already done)
//   effort: { foundation: "medium", tdd: "medium", integration: "medium" }   // optional overrides
// }

export const meta = {
  name: 'fo-gen',
  description: 'Generate a screen: foundation → api-tdd → component-tdd → page-tdd → integration, stopping at the first failed stage',
  whenToUse: 'Started by /frontend-ohmyhotel-plugin:fo-gen after the plan is approved; not run by hand',
  phases: [
    { title: 'Foundation', detail: 'types, schemas, MSW, once-per-app harness' },
    { title: 'API', detail: 'package hook additions, TDD' },
    { title: 'Components', detail: 'screen components and logic, TDD' },
    { title: 'Page', detail: 'screen view + headless hook, TDD' },
    { title: 'Integration', detail: 'routes, i18n, MSW aggregate, full check' },
  ],
}

const ORDER = ['foundation', 'api-tdd', 'component-tdd', 'page-tdd', 'integration']
const PHASE = { foundation: 'Foundation', 'api-tdd': 'API', 'component-tdd': 'Components', 'page-tdd': 'Page', integration: 'Integration' }
const AGENT = {
  foundation: 'frontend-ohmyhotel-plugin:foundation-generator',
  'api-tdd': 'frontend-ohmyhotel-plugin:tdd-cycle-runner',
  'component-tdd': 'frontend-ohmyhotel-plugin:tdd-cycle-runner',
  'page-tdd': 'frontend-ohmyhotel-plugin:tdd-cycle-runner',
  integration: 'frontend-ohmyhotel-plugin:integration-generator',
}

const RESULT = {
  type: 'object',
  properties: {
    stage: { type: 'string' },
    status: { type: 'string', enum: ['done', 'failed', 'skipped'] },
    files: { type: 'array', items: { type: 'string' } },
    evidence: { type: 'array', items: { type: 'object', properties: { command: { type: 'string' }, exitCode: { type: ['integer', 'null'] }, summary: { type: 'string' } }, required: ['command', 'exitCode'] } },
    notes: { type: 'array', items: { type: 'string' } },
    failure: { type: ['string', 'null'], description: 'why the stage failed, when status is failed' },
  },
  required: ['stage', 'status', 'evidence'],
}

const common = `app: ${args.app}\nscreen: ${args.screen}\nplanFile: ${args.planFile}\nstateFile: ${args.stateFile}\nspecDir: ${args.specDir}\nconfig: ${JSON.stringify(args.config)}`
const effortFor = s => (args.effort && (args.effort[s] || (s.endsWith('-tdd') ? args.effort.tdd : undefined))) || undefined

const results = []
let resumed = !args.resumeFrom
for (const name of ORDER) {
  const entry = (args.stages || []).find(s => s.stage === name) || { stage: name, enabled: false, files: [], testFiles: [] }
  if (!resumed) {
    if (name === args.resumeFrom) resumed = true
    else { results.push({ stage: name, status: 'skipped', evidence: [], notes: ['done in an earlier run'] }); continue }
  }
  if (!entry.enabled) {
    log(`${name}: nothing planned — skipped`)
    results.push({ stage: name, status: 'skipped', evidence: [], notes: ['no files in buildOrder'] })
    continue
  }
  phase(PHASE[name])
  const prompt = `Run stage "${name}" for this screen.\n${common}\nstage: ${name}\nfiles: ${JSON.stringify(entry.files)}\ntestFiles: ${JSON.stringify(entry.testFiles || [])}\nWrite your stage entry into stateFile when you finish, then return the stage result.`
  const r = await agent(prompt, { label: `${args.screen}:${name}`, phase: PHASE[name], schema: RESULT, agentType: AGENT[name], effort: effortFor(name) })
  if (r === null) {
    results.push({ stage: name, status: 'failed', evidence: [], failure: 'agent returned no result (skipped by user or terminal error)' })
    log(`${name}: no result — stopping`)
    break
  }
  results.push(r)
  if (r.status === 'failed') {
    log(`${name}: failed — ${r.failure || 'see evidence'}; later stages not started`)
    break
  }
  log(`${name}: ${r.status} (${(r.files || []).length} files, ${r.evidence.length} runs)`)
}

const failed = results.find(r => r.status === 'failed')
const lastDone = [...results].reverse().find(r => r.status === 'done')
return {
  ok: !failed && results.every(r => r.status !== 'failed'),
  stoppedAt: failed ? failed.stage : null,
  resumeFrom: failed ? failed.stage : null,
  lastDone: lastDone ? lastDone.stage : null,
  stages: results,
}
