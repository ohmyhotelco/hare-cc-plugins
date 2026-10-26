#!/usr/bin/env node
// cc-usage — Claude Code hook collector. Node >= 22.23.4 (README § Requirements), no dependencies,
// Windows/macOS/Linux. Writes a local JSON-lines ledger under ${CLAUDE_PLUGIN_DATA}/ledger and, when an
// endpoint is configured, uploads it in batches from the async Stop hook (README § Upload contract).
// Never prints to stdout (hooks must stay silent), never exits non-zero.
// Collected: session/repo/model/token metadata, slash-command names, skill names, subagent types,
// commit/PR/edit counts. NOT collected: prompt text, tool arguments, file contents.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { randomUUID, createHash } = require('crypto');

const EVENT = process.argv[2] || 'unknown';
const PLUGIN_VERSION = '0.1.7';

function safe(fn, fallback) { try { return fn(); } catch (_) { return fallback; } }
function sleep(ms) { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); }

// ---------- paths ----------
const configDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
const dataDir = process.env.CLAUDE_PLUGIN_DATA
  || path.join(configDir, 'plugins', 'data', 'cc-usage-local');
const ledgerDir = path.join(dataDir, 'ledger');
const stateDir = path.join(dataDir, 'state');
const sendDir = path.join(dataDir, 'send');      // batches cut from the ledger, kept until the receiver answers 202
const sendState = path.join(stateDir, '_send.json');
const sendLock = path.join(dataDir, 'send.lock');
for (const d of [ledgerDir, stateDir, sendDir]) safe(() => fs.mkdirSync(d, { recursive: true }));

function logError(msg) { safe(() => fs.appendFileSync(path.join(dataDir, 'errors.log'), `${new Date().toISOString()} ${EVENT} ${msg}\n`)); }

// ---------- config (userConfig -> env, or plain env) ----------
// The developer id becomes a folder name on the receiver, so it is kept to [a-z0-9._-]. A value with
// nothing left (e.g. only non-Latin letters) becomes a stable hash, so two people never share one id.
function normalizeDeveloper(raw) {
  const src = String(raw || '').normalize('NFKC').trim();
  let s = src.toLowerCase().replace(/[^a-z0-9._-]+/g, '-').replace(/_vti_/g, '-vti-')
    .replace(/-{2,}/g, '-').slice(0, 64).replace(/^[._-]+|[._-]+$/g, '');
  if (/^(con|prn|aux|nul|com\d|lpt\d)$/.test(s)) s = `u-${s}`;
  if (s) return s;
  return src ? `u-${createHash('sha256').update(src).digest('hex').slice(0, 8)}` : 'unknown';
}
const opt = (key, env) => String(process.env[`CLAUDE_PLUGIN_OPTION_${key}`] || process.env[env] || '').trim();
const cfg = {
  team: opt('TEAM', 'CC_USAGE_TEAM'),
  developer: normalizeDeveloper(opt('DEVELOPER', 'CC_USAGE_DEVELOPER') || safe(() => os.userInfo().username, '')),
  endpoint: opt('ENDPOINT', 'CC_USAGE_ENDPOINT'),
  token: opt('TOKEN', 'CC_USAGE_TOKEN'),
  flushHours: Number(opt('FLUSH_HOURS', 'CC_USAGE_FLUSH_HOURS')) || 24,
};
const FLUSH_MAX_BYTES = 64 * 1024;   // upload before flush_hours once this much is waiting
const SEND_TIMEOUT_MS = 15e3;        // per request; the receiver checks the token before it answers
const SEND_BUDGET_MS = 40e3;         // no new request after this, so Stop ends inside its 60 s hook timeout
const RETRY_BASE_MS = 30 * 60e3;     // first retry after a failed upload; doubles per consecutive failure
const RETRY_MAX_MS = 6 * 3600e3;

// ---------- identity (account metadata, not credentials) ----------
function identity() {
  const acct = safe(() => JSON.parse(fs.readFileSync(path.join(os.homedir(), '.claude.json'), 'utf8')).oauthAccount, null) || {};
  return {
    email: acct.emailAddress || null,
    account_uuid: acct.accountUuid || null,
    org_uuid: acct.organizationUuid || null,
    seat_tier: acct.seatTier || null,
    billing_type: acct.billingType || null,
    host: os.hostname(),
    os_user: safe(() => os.userInfo().username, null),
    os: `${process.platform}/${os.release()}`,
  };
}

function gitOrigin(cwd) {
  if (!cwd) return null;
  const url = safe(() => execFileSync('git', ['-C', cwd, 'config', '--get', 'remote.origin.url'],
    { encoding: 'utf8', timeout: 1500, stdio: ['ignore', 'pipe', 'ignore'] }).trim(), null);
  if (!url) return null;
  // strip credentials, normalize to host/owner/repo
  return url.replace(/^[a-z+]+:\/\/[^@/]+@/i, 'https://').replace(/^git@([^:]+):/, 'https://$1/').replace(/\.git$/, '');
}

function gitBranch(cwd) {
  if (!cwd) return null;
  return safe(() => execFileSync('git', ['-C', cwd, 'rev-parse', '--abbrev-ref', 'HEAD'],
    { encoding: 'utf8', timeout: 1500, stdio: ['ignore', 'pipe', 'ignore'] }).trim(), null);
}


function gitHead(cwd) {
  if (!cwd) return null;
  return safe(() => execFileSync('git', ['-C', cwd, 'rev-parse', 'HEAD'],
    { encoding: 'utf8', timeout: 1500, stdio: ['ignore', 'pipe', 'ignore'] }).trim(), null);
}
function gitCount(cwd, from, to) {
  return safe(() => Number(execFileSync('git', ['-C', cwd, 'rev-list', '--count', `${from}..${to}`],
    { encoding: 'utf8', timeout: 1500, stdio: ['ignore', 'pipe', 'ignore'] }).trim()), null);
}
function gitParents(cwd, sha) {
  return safe(() => execFileSync('git', ['-C', cwd, 'rev-list', '--parents', '-n', '1', sha],
    { encoding: 'utf8', timeout: 1500, stdio: ['ignore', 'pipe', 'ignore'] }).trim().split(/\s+/).length - 1, 0);
}
// Per-session small state (last seen HEAD, pending edit counters) in the state dir.
function loadState(name) { return safe(() => JSON.parse(fs.readFileSync(path.join(stateDir, name), 'utf8')), null) || {}; }
function saveState(name, obj) { safe(() => fs.writeFileSync(path.join(stateDir, name), JSON.stringify(obj))); }

const GIT_HEAD_MOVING = /\bgit\b[^|;&\n]*?\b(commit|merge|rebase|cherry-pick|revert|am|pull|reset|stash\s+pop|switch|checkout)\b/g;
// Only these make commits of the developer's own; the others move HEAD over commits that already exist.
const GIT_AUTHORING = ['commit', 'cherry-pick', 'revert', 'am', 'merge'];
const PR_URL = /https:\/\/[^\s"']+\/(?:pull|merge_requests|pull-requests)\/(\d+)/;
const PR_CMD = /\b(?:gh\s+pr|glab\s+mr)\s+(create|merge)\b/;

// ---------- locks ----------
// Exclusive lock file. A lock older than staleMs belongs to a process that was killed, so it is taken over.
function tryLock(file, staleMs) {
  for (let i = 0; i < 2; i++) {
    try { fs.writeFileSync(file, String(process.pid), { flag: 'wx' }); return true; } catch (e) {
      if (e.code !== 'EEXIST') return false;
      if (safe(() => Date.now() - fs.statSync(file).mtimeMs, 0) < staleMs) return false;
      safe(() => fs.unlinkSync(file));
    }
  }
  return false;
}
function withLock(file, waitMs, fn) {
  const until = Date.now() + waitMs;
  while (!tryLock(file, 30e3)) { if (Date.now() >= until) return; sleep(50); }
  try { fn(); } finally { safe(() => fs.unlinkSync(file)); }
}

// ---------- ledger ----------
function isoWeek(d) {
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const day = t.getUTCDay() || 7; t.setUTCDate(t.getUTCDate() + 4 - day);
  const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  return `${t.getUTCFullYear()}-W${String(Math.ceil((((t - y0) / 864e5) + 1) / 7)).padStart(2, '0')}`;
}
function ledgerFiles() { return safe(() => fs.readdirSync(ledgerDir), []).filter((f) => /^\d{4}-W\d{2}\.jsonl$/.test(f)).sort(); }
function record(kind, body) {
  const now = new Date();
  // id: unique per record so the aggregation can de-duplicate a batch that was uploaded twice.
  const rec = { id: randomUUID(), kind, ts: now.toISOString(), plugin: PLUGIN_VERSION, team: cfg.team || null, developer: cfg.developer, ...body };
  if (cfg.endpoint) startUploads();
  // One ledger file per ISO week of `ts`, so every batch cut from one file shares one week.
  safe(() => fs.appendFileSync(path.join(ledgerDir, `${isoWeek(now)}.jsonl`), JSON.stringify(rec) + '\n'));
  return rec;
}

// Uploads cover records written while an endpoint is configured: the send state is created with the
// first such record, and every ledger byte that existed before it is marked as already sent.
let uploadsStarted = false;
function startUploads() {
  if (uploadsStarted) return;
  uploadsStarted = true;
  if (fs.existsSync(sendState)) return;
  const offsets = {};
  for (const f of ledgerFiles()) offsets[f] = safe(() => fs.statSync(path.join(ledgerDir, f)).size, 0);
  safe(() => fs.writeFileSync(sendState, JSON.stringify({ offsets, last_ok: 0, fails: 0, next_try: 0, auth_block: null }), { flag: 'wx' }));
  safe(() => fs.unlinkSync(path.join(dataDir, 'outbox.jsonl'))); // v0.1.6 queue, replaced by ledger offsets
}

// ---------- transcript usage (incremental) ----------
// stateKey: session id for the main transcript, "<session>.<agentId>" for a subagent transcript.
// opts.query_source overrides the per-record querySource (subagent transcripts carry none).
function usageDelta(stateKey, transcriptPath, opts = {}) {
  if (!transcriptPath || !fs.existsSync(transcriptPath)) return null;
  const stPath = path.join(stateDir, `${stateKey}.json`);
  const st = safe(() => JSON.parse(fs.readFileSync(stPath, 'utf8')), null) || { offset: 0, seen: [] };
  const size = fs.statSync(transcriptPath).size;
  if (size < st.offset) st.offset = 0; // rewritten transcript
  if (size === st.offset) return null;
  const fd = fs.openSync(transcriptPath, 'r');
  const buf = Buffer.alloc(size - st.offset);
  fs.readSync(fd, buf, 0, buf.length, st.offset); fs.closeSync(fd);
  const text = buf.toString('utf8');
  const lastNl = text.lastIndexOf('\n');
  if (lastNl < 0) return null; // partial line only
  const seen = new Set(st.seen);
  const agg = {}; // key model|effort|query_source
  let requests = 0, cwd = null, branch = null, version = null, agentId = null;
  for (const line of text.slice(0, lastNl).split('\n')) {
    if (!line) continue;
    let d; try { d = JSON.parse(line); } catch (_) { continue; }
    if (d.type !== 'assistant') continue;
    const rid = d.requestId || d.uuid;
    if (!rid || seen.has(rid)) continue;
    seen.add(rid);
    const m = d.message || {}; const u = m.usage || {};
    const src = opts.query_source || d.querySource || (d.isSidechain ? 'subagent' : 'main');
    agentId = d.agentId || agentId;
    const key = `${m.model || d.requestedModel || '?'}|${d.effort || ''}|${src}`;
    const a = agg[key] || (agg[key] = { model: m.model || d.requestedModel || '?', effort: d.effort || null, query_source: src, requests: 0, input: 0, output: 0, cache_read: 0, cache_create: 0, thinking: 0 });
    a.requests++; requests++;
    a.input += u.input_tokens || 0; a.output += u.output_tokens || 0;
    a.cache_read += u.cache_read_input_tokens || 0; a.cache_create += u.cache_creation_input_tokens || 0;
    a.thinking += (u.output_tokens_details && u.output_tokens_details.thinking_tokens) || 0;
    cwd = d.cwd || cwd; branch = d.gitBranch || branch; version = d.version || version;
  }
  st.offset += Buffer.byteLength(text.slice(0, lastNl + 1), 'utf8');
  st.seen = Array.from(seen).slice(-5000);
  safe(() => fs.writeFileSync(stPath, JSON.stringify(st)));
  if (!requests) return null;
  return { requests, by_model: Object.values(agg), cwd, branch, claude_version: version, agent_id: agentId };
}

// Sweep every subagent transcript of a session: <transcript dir>/<session>/subagents/agent-*.jsonl.
// Covers background agents and workflows that end without a SubagentStop hook. Returns usage records.
function subagentDeltas(sessionId, transcriptPath) {
  if (!sessionId || !transcriptPath) return [];
  const dir = path.join(path.dirname(transcriptPath), sessionId, 'subagents');
  if (!fs.existsSync(dir)) return [];
  const out = [];
  for (const f of safe(() => fs.readdirSync(dir), [])) {
    if (!f.endsWith('.jsonl')) continue;
    const agentId = f.replace(/^agent-/, '').replace(/\.jsonl$/, '');
    const d = usageDelta(`${sessionId}.${agentId}`, path.join(dir, f), { query_source: 'subagent' });
    if (d) out.push({ ...d, agent_id: d.agent_id || agentId });
  }
  return out;
}


function flushEdits(sid, base, repoName) {
  const st = loadState(`${sid}.edits.json`);
  if (!st.count) return;
  record('edits', { ...base, repo_dir: repoName, count: st.count, by_tool: st.by_tool, by_ext: st.by_ext,
    bytes: st.bytes, files: Object.keys(st.files || {}).length });
  saveState(`${sid}.edits.json`, {});
}

// Stop (async) and SessionEnd can run at once for the same session, and SubagentStop can overlap the
// Stop sweep; the session lock keeps them from counting the same transcript lines twice.
function sessionLock(sid) { return path.join(stateDir, `${sid}.lock`); }
function sessionUsage(sid, input, base, extra, waitMs) {
  withLock(sessionLock(sid), waitMs, () => {
    const d = usageDelta(sid, input.transcript_path);
    if (d) record('usage', { ...base, ...extra, ...d });
    for (const s of subagentDeltas(sid, input.transcript_path)) record('usage', { ...base, ...extra, ...s });
    flushEdits(sid, base, extra.repo_dir);
  });
}

// ---------- upload ----------
// Policy (README § Upload contract): complete ledger lines are cut into one batch per developer and ISO
// week and kept in send/ until the receiver answers 202, then deleted. An upload is due every
// flush_hours, or earlier once FLUSH_MAX_BYTES are waiting. A failed batch is retried after 30 min,
// doubling per consecutive failure up to 6 h; a 401 stops uploads until the endpoint or token changes.
// Only one process uploads at a time (send.lock).
function loadSend() { return safe(() => JSON.parse(fs.readFileSync(sendState, 'utf8')), null); }
function writeAtomic(file, data) { const tmp = `${file}.${process.pid}.tmp`; fs.writeFileSync(tmp, data); fs.renameSync(tmp, file); }
function saveSend(st) { safe(() => writeAtomic(sendState, JSON.stringify(st))); }
function pendingBatches() { return safe(() => fs.readdirSync(sendDir), []).filter((f) => f.endsWith('.ndjson')).sort(); }
function credKey() { return createHash('sha256').update(`${cfg.endpoint}\n${cfg.token}`).digest('hex').slice(0, 16); }
function unsentBytes(st) {
  let n = 0;
  for (const f of ledgerFiles()) n += Math.max(0, safe(() => fs.statSync(path.join(ledgerDir, f)).size, 0) - (st.offsets[f] || 0));
  return n;
}
function cutBatches(st) {
  const stamp = String(Date.now()).padStart(15, '0');
  let n = 0;
  for (const f of ledgerFiles()) {
    const file = path.join(ledgerDir, f);
    const from = st.offsets[f] || 0;
    const size = safe(() => fs.statSync(file).size, 0);
    if (size <= from) continue;
    const buf = Buffer.alloc(size - from);
    const fd = fs.openSync(file, 'r'); try { fs.readSync(fd, buf, 0, buf.length, from); } finally { fs.closeSync(fd); }
    const end = buf.lastIndexOf(0x0a);
    if (end < 0) continue; // a line still being written
    const groups = new Map(); // developer -> lines, in ledger order
    for (const line of buf.subarray(0, end).toString('utf8').split('\n')) {
      const r = line.trim() && safe(() => JSON.parse(line), null);
      if (!r || !r.id) continue;
      const dev = r.developer ? normalizeDeveloper(r.developer) : cfg.developer;
      if (!groups.has(dev)) groups.set(dev, []);
      groups.get(dev).push(line);
    }
    for (const lines of groups.values()) writeAtomic(path.join(sendDir, `${stamp}-${f.slice(0, 8)}-${String(n++).padStart(3, '0')}.ndjson`), lines.join('\n') + '\n');
    st.offsets[f] = from + end + 1;
    saveSend(st); // after the batch files: a crash in between re-cuts the range, which de-duplication absorbs
  }
}
// The upload URL carries developer / week / id as query parameters so a no-code receiver can pick a
// folder and file name without parsing the body. week = ISO week of the first record (shared by the
// whole batch), id = that record's id. Existing query strings are kept.
function uploadUrl(body) {
  let first = null;
  for (const line of body.split('\n')) { if (line.trim()) { first = safe(() => JSON.parse(line), null); break; } }
  const ts = first && first.ts ? new Date(first.ts) : new Date();
  const q = new URLSearchParams({
    developer: first && first.developer ? normalizeDeveloper(first.developer) : cfg.developer,
    week: isoWeek(isNaN(ts) ? new Date() : ts),
    id: (first && first.id) || '',
  }).toString();
  const [base, frag] = cfg.endpoint.split('#');
  return base + (base.includes('?') ? '&' : '?') + q + (frag ? '#' + frag : '');
}
// Returns the HTTP status, or 'timeout' / 'network'. Redirects are refused because a custom header
// would follow them to another host.
async function post(body) {
  const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), SEND_TIMEOUT_MS);
  try {
    const res = await fetch(uploadUrl(body), {
      method: 'POST', signal: ctl.signal, redirect: 'error',
      headers: { 'content-type': 'application/x-ndjson', ...(cfg.token ? { 'x-webhook-token': cfg.token } : {}) },
      body,
    });
    if (res.body) res.body.cancel().catch(() => {});
    return res.status;
  } catch (_) { return ctl.signal.aborted ? 'timeout' : 'network'; } finally { clearTimeout(t); }
}
async function flush() {
  if (!cfg.endpoint || typeof fetch !== 'function') return;
  if (!fs.existsSync(sendState) || !tryLock(sendLock, 120e3)) return;
  try {
    const st = loadSend();
    if (!st) return;
    st.offsets = st.offsets || {};
    const key = credKey();
    if (st.auth_block === key) return;
    if (st.auth_block) Object.assign(st, { auth_block: null, fails: 0, next_try: 0 });
    const started = Date.now();
    if (pendingBatches().length ? started < (st.next_try || 0)
      : unsentBytes(st) < FLUSH_MAX_BYTES && started - (st.last_ok || 0) < cfg.flushHours * 3600e3) return;
    cutBatches(st);
    for (const f of pendingBatches()) {
      if (Date.now() - started > SEND_BUDGET_MS) break;
      const file = path.join(sendDir, f);
      const body = safe(() => fs.readFileSync(file, 'utf8'), '');
      if (!body.trim()) { safe(() => fs.unlinkSync(file)); continue; }
      const status = await post(body);
      if (status === 202) {
        safe(() => fs.unlinkSync(file));
        Object.assign(st, { last_ok: Date.now(), fails: 0, next_try: 0 });
        saveSend(st);
        continue;
      }
      logError(`upload ${status}`); // status only: never the URL or the token
      if (status === 401) st.auth_block = key;
      else {
        st.fails = (st.fails || 0) + 1;
        st.next_try = Date.now() + Math.min(RETRY_BASE_MS * 2 ** (st.fails - 1), RETRY_MAX_MS);
      }
      saveSend(st);
      break;
    }
  } finally { safe(() => fs.unlinkSync(sendLock)); }
}

// ---------- main ----------
async function main() {
  let input = {};
  try { input = JSON.parse(fs.readFileSync(0, 'utf8') || '{}'); } catch (_) {}
  const base = { session_id: input.session_id || null, cwd: input.cwd || null };
  const repoName = base.cwd ? path.basename(base.cwd) : null;

  switch (EVENT) {
    case 'SessionStart':
      record('session_open', { ...base, ...identity(), repo: gitOrigin(base.cwd), repo_dir: repoName, branch: gitBranch(base.cwd),
        model: input.model || null, source: input.source || null, permission_mode: input.permission_mode || null,
        entrypoint: process.env.CLAUDE_CODE_ENTRYPOINT || null });
      { const h = gitHead(base.cwd); if (h) saveState(`${base.session_id || 'nosession'}.git.json`, { [base.cwd]: h }); }
      break;
    case 'UserPromptSubmit': {
      const p = String(input.prompt || '');
      const m = p.match(/^\s*(\/[\w:-]+)/);
      record('prompt', { ...base, repo_dir: repoName, command: m ? m[1] : null, prompt_chars: p.length,
        permission_mode: input.permission_mode || null, effort: input.effort && input.effort.level || null });
      break;
    }
    case 'PreToolUse':
      if (input.tool_name === 'Skill') {
        const ti = input.tool_input || {};
        record('skill', { ...base, repo_dir: repoName, skill: ti.skill || null, args_chars: String(ti.args || '').length, agent_type: input.agent_type || null });
      }
      break;
    case 'PostToolUse': {
      const sid = base.session_id || 'nosession';
      const tool = input.tool_name || '';
      const ti = input.tool_input || {};
      if (tool === 'Bash' || tool === 'PowerShell') {
        const cmd = String(ti.command || '');
        const resp = input.tool_response;
        const stdout = typeof resp === 'string' ? resp : String((resp && (resp.stdout || resp.output)) || '');
        // Commits: compare HEAD with the last HEAD this session saw. A failed commit leaves HEAD unchanged.
        const ops = Array.from(cmd.matchAll(GIT_HEAD_MOVING), (m) => m[1].replace(/\s+/g, ' '));
        if (ops.length) {
          const st = loadState(`${sid}.git.json`);
          const head = gitHead(base.cwd);
          const prev = st[base.cwd];
          // Without a baseline for this cwd, trust git's own "[branch abc1234] message" summary line only.
          const summary = /^\[[^\]\n]+ ([0-9a-f]{7,40})\]/m.exec(stdout);
          const changed = head && ((prev && head !== prev) || (!prev && summary));
          const op = ops.find((o) => GIT_AUTHORING.includes(o));
          if (changed && op) {
            // A merge counts once, and only when it made a merge commit; a fast-forward adds no commit of ours.
            const n = op === 'merge' ? (gitParents(base.cwd, head) > 1 ? 1 : 0) : (prev ? gitCount(base.cwd, prev, head) : null);
            if (n !== 0) record('commit', { ...base, repo_dir: repoName, repo: gitOrigin(base.cwd), branch: gitBranch(base.cwd),
              sha: head, from_sha: prev || null, commits: n == null ? 1 : Math.max(n, 1), tool, op });
          }
          if (head) { st[base.cwd] = head; saveState(`${sid}.git.json`, st); }
        }
        // Pull requests: gh pr / glab mr create|merge whose output names the PR (a failed command names none).
        const prc = PR_CMD.exec(cmd);
        const prm = prc && (PR_URL.exec(stdout) || /#(\d+)\b/.exec(stdout));
        if (prm) {
          record('pr', { ...base, repo_dir: repoName, repo: gitOrigin(base.cwd), branch: gitBranch(base.cwd),
            number: Number(prm[1]), url: prm[0].startsWith('https://') ? prm[0] : null, action: prc[1] });
        }
      } else {
        // Edits: accumulate per session, emitted as one "edits" record at Stop (keeps volume low; no file paths).
        const st = loadState(`${sid}.edits.json`);
        const file = String(ti.file_path || ti.notebook_path || '');
        const ext = file ? (path.extname(file).toLowerCase() || '(none)') : '(none)';
        const bytes = Buffer.byteLength(String(ti.new_string || ti.content || ti.new_source || ''), 'utf8');
        st.count = (st.count || 0) + 1;
        st.by_tool = st.by_tool || {}; st.by_tool[tool] = (st.by_tool[tool] || 0) + 1;
        st.by_ext = st.by_ext || {}; st.by_ext[ext] = (st.by_ext[ext] || 0) + 1;
        st.bytes = (st.bytes || 0) + bytes;
        st.files = st.files || {}; if (file) st.files[file] = 1;
        saveState(`${sid}.edits.json`, st);
      }
      break;
    }
    case 'SubagentStop': {
      const sid = base.session_id || 'nosession';
      record('subagent', { ...base, repo_dir: repoName, agent_type: input.agent_type || null, agent_id: input.agent_id || null });
      // Subagent tokens live in their own transcript; parse it now while the agent type is known.
      withLock(sessionLock(sid), 1000, () => {
        const d = usageDelta(`${sid}.${input.agent_id || 'agent'}`, input.agent_transcript_path, { query_source: 'subagent' });
        if (d) record('usage', { ...base, repo_dir: repoName, agent_type: input.agent_type || null, ...d, agent_id: d.agent_id || input.agent_id || null });
      });
      break;
    }
    case 'Stop': {
      const sid = base.session_id || 'nosession';
      sessionUsage(sid, input, base, { repo_dir: repoName, repo: gitOrigin(base.cwd) }, 5000);
      await flush(); // the only upload point: async, so a slow receiver never blocks the session
      break;
    }
    case 'SessionEnd': {
      const sid = base.session_id || 'nosession';
      sessionUsage(sid, input, base, { repo_dir: repoName }, 300); // SessionEnd budget is about 1.5 s
      record('session_close', { ...base, reason: input.reason || null });
      break;
    }
    default:
      break;
  }
}

main().catch((e) => logError(e && e.stack || e)).finally(() => process.exit(0));
