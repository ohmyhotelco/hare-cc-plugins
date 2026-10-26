#!/usr/bin/env node
// cc-usage weekly report — aggregates the local ledger into one JSON (and a short text table).
// Usage: node report.js [--days 7] [--json out.json]
'use strict';
const fs = require('fs'); const os = require('os'); const path = require('path');
const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const days = Number(opt('--days', 7)); const outJson = opt('--json', null);
const configDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const dataDir = process.env.CLAUDE_PLUGIN_DATA || path.join(configDir, 'plugins', 'data', 'cc-usage-local');
const ledgerDir = path.join(dataDir, 'ledger');
const since = Date.now() - days * 864e5;

const recs = [], ids = new Set(); // a record seen twice (re-sent batch, copied ledger) counts once
if (fs.existsSync(ledgerDir)) for (const f of fs.readdirSync(ledgerDir)) {
  if (!f.endsWith('.jsonl')) continue;
  for (const line of fs.readFileSync(path.join(ledgerDir, f), 'utf8').split('\n')) {
    if (!line) continue; let d; try { d = JSON.parse(line); } catch (_) { continue; }
    if (d.id) { if (ids.has(d.id)) continue; ids.add(d.id); }
    if (Date.parse(d.ts) >= since) recs.push(d);
  }
}
// v0.1.6 recorded HEAD moves from pull/checkout/reset/switch/rebase as commits, and PRs from any gh
// command that printed a PR URL; only authored commits and PR create/merge count.
const AUTHORING = ['commit', 'cherry-pick', 'revert', 'am', 'merge'];
const inc = (o, k, n = 1) => { o[k] = (o[k] || 0) + n; };
const sessions = new Set(), byRepo = {}, byModel = {}, byEffort = {}, bySource = {}, byAgentType = {}, cmds = {}, skills = {}, agents = {};
let tot = { requests: 0, input: 0, output: 0, cache_read: 0, cache_create: 0, thinking: 0 };
let who = null;
let commits = 0, prs = [], edits = { count: 0, bytes: 0, files: 0, by_tool: {} };
const agentTypeById = {}; // agent_id -> agent_type, from SubagentStop records
for (const r of recs) if (r.kind === 'subagent' && r.agent_id && r.agent_type) agentTypeById[r.agent_id] = r.agent_type;
for (const r of recs) {
  if (r.session_id) sessions.add(r.session_id);
  if (r.kind === 'session_open' && !who) who = { developer: r.developer, email: r.email, team: r.team, host: r.host };
  if (r.kind === 'prompt' && r.command) inc(cmds, r.command);
  if (r.kind === 'skill' && r.skill) inc(skills, r.skill);
  if (r.kind === 'subagent' && r.agent_type) inc(agents, r.agent_type);
  if (r.kind === 'commit' && (!r.op || AUTHORING.includes(r.op))) commits += r.commits || 1;
  if (r.kind === 'pr' && r.action) prs.push({ repo: r.repo || r.repo_dir, number: r.number, action: r.action, url: r.url });
  if (r.kind === 'edits') { edits.count += r.count || 0; edits.bytes += r.bytes || 0; edits.files += r.files || 0; for (const [k, v] of Object.entries(r.by_tool || {})) inc(edits.by_tool, k, v); }
  if (r.kind === 'usage') {
    const repo = r.repo || r.repo_dir || '?';
    const agentType = r.agent_type || (r.agent_id && agentTypeById[r.agent_id]) || null;
    for (const m of r.by_model || []) {
      const total = m.input + m.output + m.cache_read + m.cache_create;
      inc(byRepo, repo, total); inc(byModel, m.model, total); inc(byEffort, m.effort || 'n/a', total);
      inc(bySource, m.query_source || 'main', total);
      if ((m.query_source || 'main') === 'subagent') inc(byAgentType, agentType || '(unknown)', total);
      for (const k of Object.keys(tot)) tot[k] += m[k] || 0;
    }
  }
}
const top = (o, n = 10) => Object.entries(o).sort((a, b) => b[1] - a[1]).slice(0, n);
const M = n => (n / 1e6).toFixed(1) + 'M';
const summary = { generated: new Date().toISOString(), days, who, sessions: sessions.size, totals: tot,
  by_repo: Object.fromEntries(top(byRepo, 20)), by_model: byModel, by_effort: byEffort,
  by_query_source: bySource, subagent_tokens_by_agent_type: Object.fromEntries(top(byAgentType, 20)),
  commands: Object.fromEntries(top(cmds, 20)), skills: Object.fromEntries(top(skills, 20)), subagents: Object.fromEntries(top(agents, 20)),
  commits, prs, edits,
  skill_or_plugin_prompt_ratio: null };
const promptCount = recs.filter(r => r.kind === 'prompt').length;
const pluginPrompts = recs.filter(r => r.kind === 'prompt' && r.command && r.command.includes(':')).length;
if (promptCount) summary.skill_or_plugin_prompt_ratio = +(pluginPrompts / promptCount).toFixed(3);
if (outJson) fs.writeFileSync(outJson, JSON.stringify(summary, null, 2));
console.log(`cc-usage · last ${days}d · ${who ? [who.developer, who.team, who.email].filter(Boolean).join(' · ') : ''} · sessions ${sessions.size} · requests ${tot.requests}`);
console.log(`tokens: output ${M(tot.output)} · cache_read ${M(tot.cache_read)} · cache_create ${M(tot.cache_create)} · input ${M(tot.input)}`);
console.log('by repo:'); for (const [k, v] of top(byRepo, 8)) console.log(`  ${k}  ${M(v)}`);
console.log('by model:'); for (const [k, v] of top(byModel)) console.log(`  ${k}  ${M(v)}`);
const srcTotal = Object.values(bySource).reduce((a, b) => a + b, 0) || 1;
console.log('by query source:', Object.entries(bySource).map(([k, v]) => `${k} ${(100 * v / srcTotal).toFixed(0)}%`).join(' · ') || '-');
console.log('subagent tokens by agent type:', top(byAgentType, 6).map(([k, v]) => `${k} ${M(v)}`).join(' · ') || '-');
console.log('commands:', top(cmds, 8).map(([k, v]) => `${k}×${v}`).join(' ') || '-');
console.log('skills:', top(skills, 8).map(([k, v]) => `${k}×${v}`).join(' ') || '-');
console.log('plugin-command prompt ratio:', summary.skill_or_plugin_prompt_ratio);
console.log(`outcomes: commits ${commits} · PRs ${prs.length}${prs.length ? ' (' + prs.map(p => '#' + p.number + ' ' + (p.action || '')).join(', ') + ')' : ''} · edits ${edits.count} (${edits.files} files, ${(edits.bytes / 1024).toFixed(0)} KB)`);
