// hp-gen-run — generate pages: the shared infrastructure once, then sections and assembly page by page.
// Order and stop rules live here: a failed infrastructure stops the run, because every page needs it;
// a failed page does not stop the next one. page-assembler records each finished entry in stateFile, so
// progress survives a dead session; the skill records failures from this result.
//
// args: { projectRoot, config, stateFile, layoutPlanFile, fileKey, mcpToolPrefix,
//         infrastructure: { planFile } | null,        // null when it is already in place
//         pages: [ { pageName, planFile } ] }
// result: { ok, stoppedAt, infrastructure, pages: [ { pageName, status, failedAgent, failure, files, notes } ] }

export const meta = {
  name: 'hp-gen-run',
  description: 'Generate homepage pages: shared infrastructure, then sections and assembly per page',
  whenToUse: 'Started by /homepage-plugin:hp-gen after the user confirms; not run by hand',
  phases: [
    { title: 'Infrastructure', detail: 'layout, header and footer, SEO utilities, i18n, styles' },
    { title: 'Pages', detail: 'section-generator then page-assembler, one page at a time' },
  ],
}

const RESULT = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['done', 'failed'] },
    files: { type: 'array', items: { type: 'string' } },
    notes: { type: 'array', items: { type: 'string' } },
    failure: { type: ['string', 'null'], description: 'why this agent failed, when status is failed' },
  },
  required: ['status'],
}

const run = async (prompt, opts) => {
  try {
    return (await agent(prompt, opts)) || { status: 'failed', failure: 'agent returned no result' }
  } catch (e) {
    return { status: 'failed', failure: String(e) }
  }
}

if (!args || !args.projectRoot || !args.stateFile || !Array.isArray(args.pages)) return { ok: false, reason: 'args {projectRoot, stateFile, pages[]} are required; run /homepage-plugin:hp-gen instead of starting this workflow directly', pages: [] }

const shared = `projectRoot: ${args.projectRoot}\nconfig: ${JSON.stringify(args.config)}`
const assembler = (pageName, planFile, isFirstPage) => `pageName: ${pageName}\nplanFile: ${planFile}\nlayoutPlanFile: ${args.layoutPlanFile}\nstateFile: ${args.stateFile}\nisFirstPage: ${isFirstPage}\n${shared}`

let infrastructure = null
if (args.infrastructure) {
  phase('Infrastructure')
  infrastructure = await run(assembler('_infrastructure', args.infrastructure.planFile, true), { label: 'infrastructure', phase: 'Infrastructure', schema: RESULT, agentType: 'homepage-plugin:page-assembler' })
  if (infrastructure.status === 'failed') {
    log(`infrastructure failed: ${infrastructure.failure || 'see notes'}; no page started`)
    return { ok: false, stoppedAt: 'infrastructure', infrastructure, pages: [] }
  }
}

phase('Pages')
const pages = []
for (const page of args.pages) {
  const sectionPrompt = `pageName: ${page.pageName}\nplanFile: ${page.planFile}\n${shared}\nfileKey: ${args.fileKey || ''}\nmcpToolPrefix: ${args.mcpToolPrefix || ''}`
  const sections = await run(sectionPrompt, { label: `${page.pageName}:sections`, phase: 'Pages', schema: RESULT, agentType: 'homepage-plugin:section-generator' })
  if (sections.status === 'failed') {
    log(`${page.pageName}: section-generator failed; moving to the next page`)
    pages.push({ pageName: page.pageName, status: 'failed', failedAgent: 'section-generator', failure: sections.failure || null, files: sections.files || [], notes: sections.notes || [] })
    continue
  }
  const assembled = await run(assembler(page.pageName, page.planFile, false), { label: `${page.pageName}:assembly`, phase: 'Pages', schema: RESULT, agentType: 'homepage-plugin:page-assembler' })
  const files = [...(sections.files || []), ...(assembled.files || [])]
  const notes = [...(sections.notes || []), ...(assembled.notes || [])]
  if (assembled.status === 'failed') {
    log(`${page.pageName}: page-assembler failed; moving to the next page`)
    pages.push({ pageName: page.pageName, status: 'failed', failedAgent: 'page-assembler', failure: assembled.failure || null, files, notes })
    continue
  }
  log(`${page.pageName}: done (${files.length} files)`)
  pages.push({ pageName: page.pageName, status: 'done', failedAgent: null, failure: null, files, notes })
}

return { ok: pages.every(p => p.status === 'done'), stoppedAt: null, infrastructure, pages }
