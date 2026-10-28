#!/usr/bin/env node
// cc-usage weekly report — aggregates the local ledger into one JSON (and a short text table).
// Usage: node report.js [--days 7] [--json out.json] [--data-dir <plugin data folder>]
'use strict';
const fs = require('fs'); const path = require('path');
const { configDir: configFolder, WEEK_FILE } = require('./config');
const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const days = Number(opt('--days', 7)); const outJson = opt('--json', null);
const configDir = configFolder();
// Hooks get the data folder as CLAUDE_PLUGIN_DATA; a shell does not, so look for the installed plugin's
// folder (plugins/data/cc-usage-plugin-<marketplace>, or -inline under --plugin-dir), the one whose ledger
// file was written last (appending to a file does not touch its folder's time).
function findDataDir() {
  const explicit = opt('--data-dir', null) || process.env.CLAUDE_PLUGIN_DATA;
  if (explicit) return explicit;
  const root = path.join(configDir, 'plugins', 'data');
  const last = (d) => Math.max(0, ...fs.readdirSync(path.join(d, 'ledger')).filter((f) => WEEK_FILE.test(f))
    .map((f) => fs.statSync(path.join(d, 'ledger', f)).mtimeMs));
  const found = (fs.existsSync(root) ? fs.readdirSync(root) : []).filter((d) => d.startsWith('cc-usage-plugin-'))
    .map((d) => path.join(root, d)).filter((d) => fs.existsSync(path.join(d, 'ledger')))
    .map((d) => [d, last(d)]).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).map(([d]) => d);
  return found[0] || path.join(root, 'cc-usage-local');
}
const dataDir = findDataDir();
const ledgerDir = path.join(dataDir, 'ledger');
const since = Date.now() - days * 864e5;

const all = [], ids = new Set(); // a record seen twice (re-sent batch, copied ledger) counts once
if (fs.existsSync(ledgerDir)) for (const f of fs.readdirSync(ledgerDir)) {
  if (!WEEK_FILE.test(f)) continue;
  for (const line of fs.readFileSync(path.join(ledgerDir, f), 'utf8').split('\n')) {
    if (!line) continue; let d; try { d = JSON.parse(line); } catch (_) { continue; }
    if (d.id) { if (ids.has(d.id)) continue; ids.add(d.id); }
    all.push(d);
  }
}
const recs = all.filter((d) => Date.parse(d.ts) >= since);
// v0.1.6 recorded HEAD moves from pull/checkout/reset/switch/rebase as commits, and PRs from any gh
// command that printed a PR URL; only authored commits and PR create/merge count.
const AUTHORING = ['commit', 'cherry-pick', 'revert', 'am', 'merge'];
const inc = (o, k, n = 1) => { o[k] = (o[k] || 0) + n; };
const sessions = new Set(), byRepo = {}, byModel = {}, byEffort = {}, bySource = {}, byAgentType = {}, cmds = {}, skills = {}, agents = {};
let tot = { requests: 0, input: 0, output: 0, cache_read: 0, cache_create: 0, thinking: 0 };
let who = null;
let commits = 0, prs = [], edits = { count: 0, bytes: 0, files: 0, by_tool: {} };
// Both maps read the whole ledger: the record naming a session's origin or an agent's type can be older
// than the reporting window.
const agentTypeById = {}; // agent_id -> agent_type, from SubagentStop records
for (const r of all) if (r.kind === 'subagent' && r.agent_id && r.agent_type) agentTypeById[r.agent_id] = r.agent_type;
// Only Stop's usage records carry the origin; SessionEnd and SubagentStop ones get it from their session.
const repoBySession = {};
for (const r of all) if (r.session_id && r.repo && !repoBySession[r.session_id]) repoBySession[r.session_id] = r.repo;
// Usage records name the account signed in when they were written (0.1.8). One without the field
// (older) takes the account of its session's latest session_open at or before it: a session opens again
// on resume and compact, possibly under another account. Session ids are only matched here, never
// written to the output.
const opensBySession = {};
for (const r of all) {
  if (r.kind === 'session_open' && r.session_id && r.email) (opensBySession[r.session_id] || (opensBySession[r.session_id] = [])).push([r.ts, r.email]);
}
for (const list of Object.values(opensBySession)) list.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
function sessionAccount(sid, ts) {
  const list = opensBySession[sid];
  if (!list) return null;
  let found = list[0][1];
  for (const [t, email] of list) if (t <= ts) found = email;
  return found;
}
const byAccount = {}, accountSessions = {};
// A 0.1.8 record with email null could not read the account then; it is not the session's.
const accountOf = (r) => ('email' in r ? r.email : sessionAccount(r.session_id, r.ts)) || '(unknown)';
const accountEntry = (account) => byAccount[account]
  || (byAccount[account] = { sessions: 0, requests: 0, input: 0, output: 0, cache_read: 0, cache_create: 0, thinking: 0, rate_limits: 0 });
// A prompt ran a plugin command when an expansion with the same prompt id came from a plugin (0.1.9, D14):
// each prompt counts once however many commands it expanded, and the prompt's own timestamp puts it in the
// window, so the expansions are looked up in the whole ledger. A prompt without an id (before 0.1.9, or
// from a Claude Code that sends none) counts by its typed `plugin:skill` form, missing a short name.
const pluginPromptIds = new Set(all.filter((r) => r.kind === 'expansion' && r.prompt_id && r.command_source === 'plugin').map((r) => r.prompt_id));
const isPluginPrompt = (r) => (r.prompt_id ? pluginPromptIds.has(r.prompt_id) : Boolean(r.command && r.command.includes(':')));
const commandSources = {}, resolvedCmds = {}, stopFailures = {}, tierAt = {};
let pluginPrompts = 0;
for (const r of recs) {
  if (r.session_id) sessions.add(r.session_id);
  if (r.kind === 'session_open' && !who) who = { developer: r.developer, team: r.team, host: r.host };
  // The plan tier of each account, from its latest session start in the window.
  const tier = r.kind === 'session_open' && r.email && (r.user_rate_limit_tier || r.org_rate_limit_tier);
  if (tier && !(tierAt[r.email] && tierAt[r.email][0] > r.ts)) tierAt[r.email] = [r.ts, tier];
  if (r.kind === 'prompt' && r.command) inc(cmds, r.command);
  if (r.kind === 'prompt' && isPluginPrompt(r)) pluginPrompts++;
  if (r.kind === 'expansion') {
    inc(commandSources, r.command_source || '(unknown)');
    if (r.command_name) inc(resolvedCmds, r.command_name);
  }
  if (r.kind === 'stop_failure') {
    inc(stopFailures, r.error || 'unknown');
    if (r.error === 'rate_limit') accountEntry(accountOf(r)).rate_limits++;
  }
  if (r.kind === 'skill' && r.skill) inc(skills, r.skill);
  if (r.kind === 'subagent' && r.agent_type) inc(agents, r.agent_type);
  if (r.kind === 'commit' && (!r.op || AUTHORING.includes(r.op))) commits += r.commits || 1;
  if (r.kind === 'pr' && r.action) prs.push({ repo: r.repo || r.repo_dir, number: r.number, action: r.action, url: r.url });
  if (r.kind === 'edits') { edits.count += r.count || 0; edits.bytes += r.bytes || 0; edits.files += r.files || 0; for (const [k, v] of Object.entries(r.by_tool || {})) inc(edits.by_tool, k, v); }
  if (r.kind === 'usage') {
    const repo = r.repo || repoBySession[r.session_id] || r.repo_dir || '?';
    const agentType = r.agent_type || (r.agent_id && agentTypeById[r.agent_id]) || null;
    const account = accountOf(r);
    const acc = accountEntry(account);
    if (r.session_id) (accountSessions[account] || (accountSessions[account] = new Set())).add(r.session_id);
    for (const m of r.by_model || []) {
      const total = m.input + m.output + m.cache_read + m.cache_create;
      inc(byRepo, repo, total); inc(byModel, m.model, total); inc(byEffort, m.effort || 'n/a', total);
      inc(bySource, m.query_source || 'main', total);
      if ((m.query_source || 'main') === 'subagent') inc(byAgentType, agentType || '(unknown)', total);
      for (const k of Object.keys(tot)) { tot[k] += m[k] || 0; acc[k] += m[k] || 0; }
    }
  }
}
for (const [account, set] of Object.entries(accountSessions)) byAccount[account].sessions = set.size;
// Every account signed in during the window, also one whose sessions used no tokens.
const accounts = [...new Set([...recs.filter((r) => r.kind === 'session_open' && r.email).map((r) => r.email),
  ...Object.keys(byAccount).filter((a) => a !== '(unknown)')])].sort();
const accountTiers = Object.fromEntries(Object.entries(tierAt).map(([email, [, tier]]) => [email, tier]));
const top = (o, n = 10) => Object.entries(o).sort((a, b) => b[1] - a[1]).slice(0, n);
const M = n => (n / 1e6).toFixed(1) + 'M';
const summary = { generated: new Date().toISOString(), days, who, accounts, account_tiers: accountTiers, sessions: sessions.size, totals: tot,
  by_account: byAccount, by_repo: Object.fromEntries(top(byRepo, 20)), by_model: byModel, by_effort: byEffort,
  by_query_source: bySource, subagent_tokens_by_agent_type: Object.fromEntries(top(byAgentType, 20)),
  commands: Object.fromEntries(top(cmds, 20)), commands_resolved: Object.fromEntries(top(resolvedCmds, 20)),
  command_sources: commandSources, skills: Object.fromEntries(top(skills, 20)),
  subagents: Object.fromEntries(top(agents, 20)), stop_failures: stopFailures,
  commits, prs, edits,
  skill_or_plugin_prompt_ratio: null };
const promptCount = recs.filter(r => r.kind === 'prompt').length;
if (promptCount) summary.skill_or_plugin_prompt_ratio = +(pluginPrompts / promptCount).toFixed(3);
if (outJson) fs.writeFileSync(outJson, JSON.stringify(summary, null, 2));
console.log(`cc-usage · last ${days}d · ${who ? [who.developer, who.team].filter(Boolean).join(' · ') : ''} · ${accounts.length} account(s) · sessions ${sessions.size} · requests ${tot.requests}`);
console.log(`tokens: output ${M(tot.output)} · cache_read ${M(tot.cache_read)} · cache_create ${M(tot.cache_create)} · input ${M(tot.input)}`);
console.log('by account:'); for (const [k, v] of Object.entries(byAccount).sort((a, b) => b[1].output - a[1].output)) {
  console.log(`  ${k}${accountTiers[k] ? ` (${accountTiers[k]})` : ''}  sessions ${v.sessions} · requests ${v.requests} · output ${M(v.output)} · cache_read ${M(v.cache_read)}${v.rate_limits ? ` · rate limits ${v.rate_limits}` : ''}`);
}
console.log('by repo:'); for (const [k, v] of top(byRepo, 8)) console.log(`  ${k}  ${M(v)}`);
console.log('by model:'); for (const [k, v] of top(byModel)) console.log(`  ${k}  ${M(v)}`);
const srcTotal = Object.values(bySource).reduce((a, b) => a + b, 0) || 1;
console.log('by query source:', Object.entries(bySource).map(([k, v]) => `${k} ${(100 * v / srcTotal).toFixed(0)}%`).join(' · ') || '-');
console.log('subagent tokens by agent type:', top(byAgentType, 6).map(([k, v]) => `${k} ${M(v)}`).join(' · ') || '-');
console.log('commands:', top(cmds, 8).map(([k, v]) => `${k}×${v}`).join(' ') || '-');
console.log('commands as resolved:', top(resolvedCmds, 8).map(([k, v]) => `${k}×${v}`).join(' ') || '-');
console.log('skills:', top(skills, 8).map(([k, v]) => `${k}×${v}`).join(' ') || '-');
console.log('plugin-command prompt ratio:', summary.skill_or_plugin_prompt_ratio);
console.log('turns ended by an API error:', top(stopFailures).map(([k, v]) => `${k}×${v}`).join(' ') || '-');
console.log(`outcomes: commits ${commits} · PRs ${prs.length}${prs.length ? ' (' + prs.map(p => '#' + p.number + ' ' + (p.action || '')).join(', ') + ')' : ''} · edits ${edits.count} (${edits.files} files, ${(edits.bytes / 1024).toFixed(0)} KB)`);
