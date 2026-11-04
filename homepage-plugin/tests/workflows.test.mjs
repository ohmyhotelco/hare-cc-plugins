// Runs each workflow script with stubbed hooks, so its order, stop rules and arithmetic are tested without a model call.
// node homepage-plugin/tests/workflows.test.mjs
import { readFileSync } from 'node:fs'
import assert from 'node:assert/strict'

const AsyncFunction = (async () => {}).constructor
const load = path => {
  const src = readFileSync(path, 'utf8').replace(/export const meta\s*=/, 'const meta =')
  return new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', src)
}
const H = new URL('../workflows', import.meta.url).pathname
const go = async (file, args, responder) => {
  const calls = []
  const agent = async (prompt, opts) => { calls.push({ prompt, ...opts }); return responder(opts, prompt) }
  const result = await load(`${H}/${file}`)(agent, null, null, () => {}, () => {}, args)
  return { result, calls, labels: calls.map(c => c.label) }
}

const dims = (score, n = 2) => Array.from({ length: n }, (_, i) => ({ name: `d${i}`, score, weight: 1 / n }))
const issue = (severity, n = 1) => Array.from({ length: n }, (_, i) => ({ severity, message: `${severity}${i}`, fixHint: 'x' }))
const rep = (score, issues = []) => ({ dimensions: dims(score), issues })
const vis = (score, issues = []) => ({ skipped: false, sections: [{ sectionType: 'Hero', subDimensions: dims(score) }], issues })
const reviewArgs = { projectRoot: '/p', pages: [{ pageName: 'home', planFile: 'a.json' }], visual: { componentMapFile: 'c.json', fileKey: 'K', mcpToolPrefix: 'mcp__figma__' } }
const review = (r, args = reviewArgs) => go('hp-review-run.js', args, o => {
  if (o.agentType.endsWith('seo-reviewer')) return typeof r.seo === 'function' ? r.seo() : r.seo
  if (o.agentType.endsWith('quality-reviewer')) return r.quality
  return r.visual
})

let n = 0
const t = async (name, fn) => { await fn(); n += 1; console.log(`ok ${name}`) }

await t('only info issues reach done', async () => {
  const { result, labels } = await review({ seo: rep(9, issue('info')), quality: rep(9), visual: vis(9) })
  assert.equal(result.pages[0].status, 'done')
  assert.equal(labels.length, 3)
  assert.equal(result.pages[0].report.overall.verdict, 'pass')
  assert.deepEqual(result.pages[0].report.overall.totalIssues, { critical: 0, warning: 0, info: 1 })
})
await t('one warning is reviewed, not done', async () => {
  const { result } = await review({ seo: rep(9, issue('warning')), quality: rep(9), visual: vis(9) })
  assert.equal(result.pages[0].status, 'reviewed')
  assert.equal(result.pages[0].report.overall.verdict, 'pass')
})
await t('more than three warnings pass with warnings', async () => {
  const { result } = await review({ seo: rep(9, issue('warning', 4)), quality: rep(9), visual: vis(9) })
  assert.equal(result.pages[0].report.seo.verdict, 'pass_with_warnings')
  assert.equal(result.pages[0].status, 'reviewed')
})
await t('SEO critical fails and stops the run', async () => {
  const { result, labels } = await review({ seo: rep(9, issue('critical')) })
  assert.deepEqual(labels, ['home:seo'])
  assert.equal(result.pages[0].status, 'review-failed')
  assert.equal(result.pages[0].report.quality.verdict, 'skipped')
  assert.deepEqual(result.pages[0].report.quality.issues, [])
})
await t('a model saying pass cannot lift a low score', async () => {
  const { result, labels } = await review({ seo: { ...rep(6.9), verdict: 'pass', overallScore: 9 } })
  assert.equal(result.pages[0].status, 'review-failed')
  assert.deepEqual(labels, ['home:seo'])
})
await t('score at 6.96 fails, it is not rounded up into a pass', async () => {
  const { result } = await review({ seo: rep(6.96) })
  assert.equal(result.pages[0].report.seo.verdict, 'fail')
})
await t('quality failure skips the visual stage', async () => {
  const { result, labels } = await review({ seo: rep(9), quality: rep(6) })
  assert.deepEqual(labels, ['home:seo', 'home:quality'])
  assert.equal(result.pages[0].status, 'review-failed')
  assert.equal(result.pages[0].report.visualFidelity, undefined)
})
await t('no visual args skips the visual stage', async () => {
  const { result, labels } = await review({ seo: rep(9), quality: rep(9) }, { ...reviewArgs, visual: null })
  assert.equal(labels.length, 2)
  assert.equal(result.pages[0].status, 'done')
})
for (const [score, verdict, status] of [[4.9, 'fail', 'review-failed'], [5, 'pass_with_warnings', 'reviewed'], [6.9, 'pass_with_warnings', 'reviewed'], [7, 'pass', 'done']]) {
  await t(`visual score ${score} is ${verdict}`, async () => {
    const { result } = await review({ seo: rep(9), quality: rep(9), visual: vis(score) })
    assert.equal(result.pages[0].report.visualFidelity.verdict, verdict)
    assert.equal(result.pages[0].status, status)
  })
}
await t('visual score 9 with a critical issue never reaches done', async () => {
  const { result } = await review({ seo: rep(9), quality: rep(9), visual: vis(9, issue('critical')) })
  assert.equal(result.pages[0].status, 'reviewed')
})
await t('visual skipped by the reviewer is omitted with a note', async () => {
  const { result } = await review({ seo: rep(9), quality: rep(9), visual: { skipped: true, skipReason: 'no preview', sections: [], issues: [] } })
  assert.equal(result.pages[0].report.visualFidelity, undefined)
  assert.equal(result.pages[0].status, 'done')
  assert.match(result.pages[0].note, /no preview/)
})
await t('a dead reviewer is incomplete at every stage', async () => {
  let r = await review({ seo: null })
  assert.equal(r.result.pages[0].status, 'incomplete')
  assert.equal(r.result.pages[0].missing, 'seo-reviewer')
  assert.equal(r.result.ok, false)
  r = await review({ seo: rep(9), quality: null })
  assert.equal(r.result.pages[0].missing, 'quality-reviewer')
  assert.equal(r.result.pages[0].report.seo.score, 9)
  r = await review({ seo: rep(9), quality: rep(9), visual: null })
  assert.equal(r.result.pages[0].missing, 'visual-fidelity-reviewer')
})
await t('a reviewer that throws is incomplete', async () => {
  const { result } = await review({ seo: () => { throw new Error('boom') } })
  assert.equal(result.pages[0].status, 'incomplete')
})
await t('a reviewer with no scored dimension is incomplete, not a pass', async () => {
  const { result } = await review({ seo: { dimensions: [], issues: [] } })
  assert.equal(result.pages[0].status, 'incomplete')
})
await t('weights are normalised', async () => {
  const { result } = await review({ seo: { dimensions: [{ name: 'a', score: 10, weight: 3 }, { name: 'b', score: 5, weight: 1 }], issues: [] }, quality: rep(9) }, { ...reviewArgs, visual: null })
  assert.equal(result.pages[0].report.seo.score, 8.8)
})
await t('each page gets its own run and prompt', async () => {
  const args = { ...reviewArgs, visual: null, pages: [{ pageName: 'home', planFile: 'a.json' }, { pageName: 'about', planFile: 'b.json' }] }
  const { result, calls } = await go('hp-review-run.js', args, o => (o.label === 'home:seo' ? rep(2) : rep(9)))
  assert.deepEqual(result.pages.map(p => p.status), ['review-failed', 'done'])
  assert.match(calls.at(-1).prompt, /pageName: about\nplanFile: b.json\nprojectRoot: \/p/)
})
await t('review args are checked', async () => {
  const { result, calls } = await go('hp-review-run.js', undefined, () => null)
  assert.equal(result.ok, false)
  assert.equal(calls.length, 0)
})

const genArgs = { projectRoot: '/p', config: { x: 1 }, stateFile: 's.json', layoutPlanFile: 'l.json', fileKey: 'K', mcpToolPrefix: 'mcp__figma__', infrastructure: { planFile: 'a.json' }, pages: [{ pageName: 'home', planFile: 'a.json' }, { pageName: 'about', planFile: 'b.json' }] }
const ok = { status: 'done', files: ['f'] }
await t('gen runs infrastructure first, then each page in order', async () => {
  const { result, labels, calls } = await go('hp-gen-run.js', genArgs, () => ok)
  assert.deepEqual(labels, ['infrastructure', 'home:sections', 'home:assembly', 'about:sections', 'about:assembly'])
  assert.equal(result.ok, true)
  assert.match(calls[0].prompt, /pageName: _infrastructure\n/)
  assert.match(calls[0].prompt, /isFirstPage: true/)
  assert.match(calls[2].prompt, /isFirstPage: false/)
  assert.match(calls[2].prompt, /stateFile: s\.json/)
  assert.match(calls[1].prompt, /fileKey: K\nmcpToolPrefix: mcp__figma__/)
})
await t('failed infrastructure starts no page', async () => {
  const { result, labels } = await go('hp-gen-run.js', genArgs, o => (o.label === 'infrastructure' ? { status: 'failed', failure: 'no' } : ok))
  assert.deepEqual(labels, ['infrastructure'])
  assert.equal(result.stoppedAt, 'infrastructure')
  assert.equal(result.ok, false)
})
await t('infrastructure already in place is not run', async () => {
  const { labels } = await go('hp-gen-run.js', { ...genArgs, infrastructure: null }, () => ok)
  assert.equal(labels[0], 'home:sections')
})
await t('a failed page does not stop the next', async () => {
  const { result, labels } = await go('hp-gen-run.js', genArgs, o => (o.label === 'home:sections' ? { status: 'failed', failure: 'bad' } : ok))
  assert.deepEqual(labels, ['infrastructure', 'home:sections', 'about:sections', 'about:assembly'])
  assert.deepEqual(result.pages.map(p => [p.pageName, p.status, p.failedAgent]), [['home', 'failed', 'section-generator'], ['about', 'done', null]])
  assert.equal(result.ok, false)
  assert.equal(result.stoppedAt, null)
})
await t('a dead assembler is a failed page, and null or a throw both count', async () => {
  let r = await go('hp-gen-run.js', genArgs, o => (o.label === 'home:assembly' ? null : ok))
  assert.equal(r.result.pages[0].failedAgent, 'page-assembler')
  r = await go('hp-gen-run.js', { ...genArgs, infrastructure: null }, o => { if (o.label === 'home:sections') throw new Error('boom'); return ok })
  assert.match(r.result.pages[0].failure, /boom/)
})
await t('gen args are checked', async () => {
  const { result, calls } = await go('hp-gen-run.js', { projectRoot: '/p' }, () => ok)
  assert.equal(result.ok, false)
  assert.equal(calls.length, 0)
})

console.log(`${n} tests passed`)
