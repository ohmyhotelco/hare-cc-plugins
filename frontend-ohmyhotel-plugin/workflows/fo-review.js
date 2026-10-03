// fo-review — four reviewers in parallel (spec, quality, test, security), then merge: normalise every
// finding to one shape, drop accepted deviations, cluster by file, order clusters by severity. The
// merge is code so the filtering is the same every run; the reviewers are asked to report everything.
//
// args: { app, screen, config, planFile, specDir, screenDir, figmaDir, packageFiles, packageTestFiles,
//         routeFiles, e2eDir, acceptedDeviations, reviewers: ['spec','quality','test','security'] }

export const meta = {
  name: 'fo-review',
  description: 'Review a generated screen with the spec, quality, test and security reviewers in parallel and merge their findings into clusters',
  whenToUse: 'Started by /frontend-ohmyhotel-plugin:fo-review; not run by hand',
  phases: [{ title: 'Review', detail: 'four reviewers in parallel' }],
}

const ISSUE = { type: 'object', properties: { severity: { type: 'string' }, confidence: { type: 'string' }, message: { type: 'string' }, file: { type: 'string' }, line: { type: ['integer', 'null'] }, fixHint: { type: 'string' }, refs: { type: 'array', items: { type: 'string' } } }, required: ['severity', 'message'] }
const REPORT = {
  type: 'object',
  properties: {
    agent: { type: 'string' }, status: { type: 'string' }, overallScore: { type: ['number', 'null'] },
    dimensions: { type: 'object', additionalProperties: { type: 'object', properties: { score: { type: ['number', 'null'] }, issues: { type: 'array', items: ISSUE } } } },
    findings: { type: 'array', items: ISSUE },
    acceptedDeviations: { type: 'array', items: { type: 'object' } },
    counts: { type: 'object' }, notes: { type: 'array', items: { type: 'string' } },
  },
  required: ['agent', 'status'],
}

const AGENT = { spec: 'spec-reviewer', quality: 'quality-reviewer', test: 'test-reviewer', security: 'security-auditor' }
if (!args || !args.app || !args.screen) return { ok: false, result: 'not-run', reason: 'args {app, screen, …} are required; this workflow is started by its skill' }
const base = `app: ${args.app}\nscreen: ${args.screen}\nconfig: ${JSON.stringify(args.config)}\nplanFile: ${args.planFile}\nscreenDir: ${args.screenDir}\nspecDir: ${args.specDir}\nacceptedDeviations: ${JSON.stringify(args.acceptedDeviations || [])}`
const extra = {
  spec: `figmaDir: ${args.figmaDir || ''}`,
  quality: `packageFiles: ${JSON.stringify(args.packageFiles || [])}`,
  test: `packageTestFiles: ${JSON.stringify(args.packageTestFiles || [])}\ne2eDir: ${args.e2eDir || ''}`,
  security: `packageFiles: ${JSON.stringify(args.packageFiles || [])}\nrouteFiles: ${JSON.stringify(args.routeFiles || [])}`,
}

phase('Review')
const names = args.reviewers || Object.keys(AGENT)
const reportsRaw = await parallel(names.map(n => () =>
  agent(`${base}\n${extra[n]}`, { label: `${args.screen}:${n}`, phase: 'Review', schema: REPORT, agentType: `frontend-ohmyhotel-plugin:${AGENT[n]}` })
    .then(r => ({ reviewer: n, report: r }))
    .catch(e => ({ reviewer: n, report: null, error: String(e) }))))
const reports = reportsRaw.map((r, i) => r || { reviewer: names[i], report: null, error: 'agent returned no result' })
const incomplete = reports.filter(r => !r.report || r.report.status === 'not-run').map(r => r.reviewer)

const SEV = { critical: 0, warning: 1, suggestion: 2 }
const findings = []
for (const { reviewer, report } of reports) {
  if (!report || report.status === 'not-run') continue   // tracked in `incomplete`, not disguised as a finding
  const issues = [...(report.findings || []), ...Object.entries(report.dimensions || {}).flatMap(([dim, d]) => (d.issues || []).map(i => ({ ...i, dimension: dim })))]
  for (const i of issues) findings.push({ reviewer, severity: i.severity || 'warning', confidence: i.confidence || 'medium', dimension: i.dimension || null, message: i.message, file: i.file || null, line: i.line ?? null, fixHint: i.fixHint || null, refs: i.refs || [] })
}

// cluster by file (findings without a file cluster by reviewer), order by worst severity then size
const groups = new Map()
for (const f of findings) {
  const key = f.file || `(${f.reviewer})`
  if (!groups.has(key)) groups.set(key, [])
  groups.get(key).push(f)
}
const clusters = [...groups.entries()].map(([key, items], i) => ({
  id: `C${i + 1}`, title: key, source: 'review', files: [...new Set(items.map(x => x.file).filter(Boolean))],
  worst: items.reduce((w, x) => Math.min(w, SEV[x.severity] ?? 1), 2), findings: items.sort((a, b) => (SEV[a.severity] ?? 1) - (SEV[b.severity] ?? 1)),
})).sort((a, b) => a.worst - b.worst || b.findings.length - a.findings.length).map((c, i) => ({ ...c, id: `C${i + 1}`, worst: ['critical', 'warning', 'suggestion'][c.worst] }))

const counts = findings.reduce((m, f) => ({ ...m, [f.severity]: (m[f.severity] || 0) + 1 }), {})
// a review is complete only when every requested reviewer reported; otherwise it is `incomplete` (recorded as not-run)
const status = incomplete.length ? 'incomplete'
  : reports.some(r => r.report.status === 'fail') || counts.critical ? 'fail'
  : (counts.warning || 0) > 5 ? 'pass_with_warnings' : 'pass'
log(`${findings.length} findings from ${names.length - incomplete.length}/${names.length} reviewers → ${clusters.length} clusters (${JSON.stringify(counts)}) → ${status}`)
return { status, incomplete, counts, reviewers: reports.map(r => ({ reviewer: r.reviewer, status: r.report ? r.report.status : 'not-run', error: r.error || null, overallScore: r.report ? r.report.overallScore ?? null : null, notes: r.report ? r.report.notes || [] : [] })), clusters }
