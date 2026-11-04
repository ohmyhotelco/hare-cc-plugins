// hp-review-run — review each page in stages: SEO, then quality when SEO passes, then visual fidelity when
// both pass and the skill asked for it. Reviewers judge dimensions and report issues; scores, counts,
// verdicts and the page status are computed here, so the same findings always get the same status.
//
// args: { projectRoot, pages: [ { pageName, planFile } ], visual: { componentMapFile, fileKey, mcpToolPrefix } | null }
// result: { pages: [ { pageName, status, report, missing, note } ] }
//   status: done | reviewed | review-failed | incomplete. `incomplete` means a reviewer returned nothing,
//   so the skill records no status for that page; `report` then holds only the stages that finished.

export const meta = {
  name: 'hp-review-run',
  description: 'Review homepage pages in stages (SEO, quality, visual fidelity), computing scores and verdicts in code',
  whenToUse: 'Started by /homepage-plugin:hp-review; not run by hand',
  phases: [
    { title: 'SEO', detail: 'seo-reviewer' },
    { title: 'Quality', detail: 'quality-reviewer, when SEO passes' },
    { title: 'Visual fidelity', detail: 'visual-fidelity-reviewer, when both pass and Figma references exist' },
  ],
}

const ISSUE = {
  type: 'object',
  properties: {
    severity: { type: 'string', enum: ['critical', 'warning', 'info'] },
    dimension: { type: 'string' }, subDimension: { type: 'string' }, sectionType: { type: 'string' },
    message: { type: 'string' }, file: { type: 'string' }, line: { type: ['integer', 'null'] }, fixHint: { type: 'string' },
  },
  required: ['severity', 'message', 'fixHint'],
}
const SCORE = { type: 'object', properties: { name: { type: 'string' }, score: { type: 'number' }, weight: { type: 'number' }, notes: { type: 'string' } }, required: ['name', 'score', 'weight'] }
const REPORT = {
  type: 'object',
  properties: { dimensions: { type: 'array', items: SCORE }, issues: { type: 'array', items: ISSUE } },
  required: ['dimensions', 'issues'],
}
const VISUAL = {
  type: 'object',
  properties: {
    skipped: { type: 'boolean' }, skipReason: { type: ['string', 'null'] },
    sections: { type: 'array', items: { type: 'object', properties: { sectionType: { type: 'string' }, subDimensions: { type: 'array', items: SCORE } }, required: ['sectionType', 'subDimensions'] } },
    issues: { type: 'array', items: ISSUE },
    coverage: { type: 'object' },
  },
  required: ['skipped', 'sections', 'issues'],
}

const weighted = scores => {
  const total = scores.reduce((sum, s) => sum + s.weight, 0)
  return total > 0 ? scores.reduce((sum, s) => sum + s.score * s.weight, 0) / total : null
}
const round = n => (n === null ? null : Math.round(n * 10) / 10)
const count = issues => {
  const c = { critical: 0, warning: 0, info: 0 }
  for (const i of issues) c[i.severity] += 1
  return c
}
const stageVerdict = (score, c) => (score === null || score < 7 || c.critical > 0 ? 'fail' : c.warning > 3 ? 'pass_with_warnings' : 'pass')
// Below 5 the design diverges too far to accept; below 7 it is flagged for hp-fix; a lower score never passes silently.
const visualVerdict = (score, c) => (score === null || score < 5 ? 'fail' : score < 7 || c.critical > 0 || c.warning > 3 ? 'pass_with_warnings' : 'pass')

const scoreStage = r => {
  const score = weighted(r.dimensions)
  return { score: round(score), verdict: stageVerdict(score, count(r.issues)), dimensions: r.dimensions, issues: r.issues }
}
const scoreVisual = r => {
  const sections = r.sections.map(s => ({ ...s, score: weighted(s.subDimensions) }))
  const scored = sections.filter(s => s.score !== null)
  const score = scored.length ? scored.reduce((sum, s) => sum + s.score, 0) / scored.length : null
  return { score: round(score), verdict: visualVerdict(score, count(r.issues)), sections: sections.map(s => ({ ...s, score: round(s.score) })), issues: r.issues, coverage: r.coverage || null }
}

const finish = (page, seo, quality, visual, note) => {
  const stages = [seo, quality, visual].filter(Boolean)
  const totalIssues = count(stages.flatMap(s => s.issues))
  const verdict = stages.some(s => s.verdict === 'fail') ? 'fail' : stages.some(s => s.verdict === 'pass_with_warnings') ? 'pass_with_warnings' : 'pass'
  const status = verdict === 'fail' ? 'review-failed' : verdict === 'pass' && totalIssues.critical + totalIssues.warning === 0 ? 'done' : 'reviewed'
  return { pageName: page.pageName, status, note: note || null, report: { seo, quality, ...(visual ? { visualFidelity: visual } : {}), overall: { verdict, totalIssues } } }
}
const incomplete = (page, missing, seo, quality) => ({ pageName: page.pageName, status: 'incomplete', missing, report: { ...(seo ? { seo } : {}), ...(quality ? { quality } : {}) } })

const run = async (prompt, opts) => {
  try {
    return await agent(prompt, opts)
  } catch (e) {
    log(`${opts.label}: ${e}`)
    return null
  }
}

if (!args || !args.projectRoot || !Array.isArray(args.pages) || !args.pages.length) return { ok: false, reason: 'args {projectRoot, pages[]} are required; run /homepage-plugin:hp-review instead of starting this workflow directly', pages: [] }

const results = []
for (const page of args.pages) {
  const common = `pageName: ${page.pageName}\nplanFile: ${page.planFile}\nprojectRoot: ${args.projectRoot}`

  phase('SEO')
  const seoRaw = await run(common, { label: `${page.pageName}:seo`, phase: 'SEO', schema: REPORT, agentType: 'homepage-plugin:seo-reviewer' })
  if (!seoRaw || !seoRaw.dimensions.length) { results.push(incomplete(page, 'seo-reviewer')); continue }
  const seo = scoreStage(seoRaw)
  const notRun = { score: null, verdict: 'skipped', dimensions: [], issues: [] }
  if (seo.verdict === 'fail') { results.push(finish(page, seo, notRun)); continue }

  phase('Quality')
  const qualityRaw = await run(common, { label: `${page.pageName}:quality`, phase: 'Quality', schema: REPORT, agentType: 'homepage-plugin:quality-reviewer' })
  if (!qualityRaw || !qualityRaw.dimensions.length) { results.push(incomplete(page, 'quality-reviewer', seo)); continue }
  const quality = scoreStage(qualityRaw)
  if (quality.verdict === 'fail' || !args.visual) { results.push(finish(page, seo, quality)); continue }

  phase('Visual fidelity')
  const visualPrompt = `${common}\ncomponentMapFile: ${args.visual.componentMapFile}\nfileKey: ${args.visual.fileKey || ''}\nmcpToolPrefix: ${args.visual.mcpToolPrefix || ''}`
  const visualRaw = await run(visualPrompt, { label: `${page.pageName}:visual`, phase: 'Visual fidelity', schema: VISUAL, agentType: 'homepage-plugin:visual-fidelity-reviewer' })
  if (!visualRaw) { results.push(incomplete(page, 'visual-fidelity-reviewer', seo, quality)); continue }
  if (visualRaw.skipped || !visualRaw.sections.length) { results.push(finish(page, seo, quality, null, `Visual fidelity skipped: ${visualRaw.skipReason || 'no section could be compared'}`)); continue }
  results.push(finish(page, seo, quality, scoreVisual(visualRaw)))
}

log(results.map(r => `${r.pageName}: ${r.status}`).join(', '))
return { ok: results.every(r => r.status !== 'incomplete'), pages: results }
