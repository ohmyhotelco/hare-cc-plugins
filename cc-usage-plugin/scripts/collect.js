#!/usr/bin/env node
// cc-usage — Claude Code hook collector. Node 22.23.4+ / 24.22.1+ / 26.12.1+ (README § Requirements),
// no dependencies, Windows/macOS/Linux. Writes a local JSON-lines ledger under ${CLAUDE_PLUGIN_DATA}/ledger
// and, when an endpoint is configured, uploads it in batches from the async Stop hook (README § Upload
// contract). Never prints to stdout (hooks must stay silent), never exits non-zero.
// Collected: README § What is recorded. NOT collected: prompt text, tool arguments, file contents, file paths.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');
const { randomUUID, createHash } = require('crypto');
const { normalizeDeveloper, uploadProblem } = require('./config');

const EVENT = process.argv[2] || 'unknown';
const PLUGIN_VERSION = '0.1.8';
const STARTED = Date.now();

function safe(fn, fallback) { try { return fn(); } catch (_) { return fallback; } }
function sleep(ms) { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); }
function sha(s) { return createHash('sha256').update(String(s)).digest('hex'); }

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

// Error lines carry a fixed label and a status or error code — never a URL, token, path or record body.
function logError(msg) { safe(() => fs.appendFileSync(path.join(dataDir, 'errors.log'), `${new Date().toISOString()} ${EVENT} ${msg}\n`)); }

// ---------- config (userConfig -> env, or plain env; rules in config.js) ----------
const opt =(key, env) => String(process.env[`CLAUDE_PLUGIN_OPTION_${key}`] || process.env[env] || '').trim();
const developerOpt = opt('DEVELOPER', 'CC_USAGE_DEVELOPER');
const flushHours = Number(opt('FLUSH_HOURS', 'CC_USAGE_FLUSH_HOURS'));
const cfg = {
  team: opt('TEAM', 'CC_USAGE_TEAM'),
  developer: normalizeDeveloper(developerOpt || safe(() => os.userInfo().username, '')),
  developerSet: Boolean(developerOpt), // uploads need an assigned id; the OS login name is not unique across machines
  endpoint: opt('ENDPOINT', 'CC_USAGE_ENDPOINT'),
  token: opt('TOKEN', 'CC_USAGE_TOKEN'),
  flushHours: flushHours > 0 ? flushHours : 24,
};
const FLUSH_MAX_BYTES = 64 * 1024;   // upload before flush_hours once this much is waiting
const MAX_BATCH_BYTES = 1024 * 1024; // larger cuts are split, so one batch never grows with an outage
const SEND_TIMEOUT_MS = 15e3;        // per request; the receiver checks the token before it answers
const SEND_BUDGET_MS = 40e3;         // no new request this long after the hook started (async hooks get no timeout)
const RETRY_BASE_MS = 30 * 60e3;     // first retry after a failed upload; doubles per consecutive failure
const RETRY_MAX_MS = 6 * 3600e3;
const COMMIT_WINDOW_MS = 15 * 60e3;  // a commit made by the command just run is younger than this
const STATE_TTL_MS = 30 * 864e5;     // per-session state older than this is removed at SessionStart

// ---------- identity (account metadata, not credentials) ----------
function oauthAccount() {
  const file = [process.env.CLAUDE_CONFIG_DIR, os.homedir()].filter(Boolean)
    .map((d) => path.join(d, '.claude.json')).find((f) => fs.existsSync(f));
  return (file && safe(() => JSON.parse(fs.readFileSync(file, 'utf8')).oauthAccount, null)) || {};
}
// The account signed in when a usage record is written: a person can switch accounts with /login in the
// middle of a session, so the session's opening account is not enough to split usage by account.
function accountEmail() { return oauthAccount().emailAddress || null; }
function identity() {
  const acct = oauthAccount();
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

// A remote becomes https://host/owner/repo: user info, port, query and fragment are dropped, and a remote
// that is not a network URL (a local path, file://) is not recorded at all.
function cleanOrigin(url) {
  if (/^file:/i.test(url)) return null;
  // scp-like [user@]host:owner/repo; a one-letter host is a Windows drive (C:/repo)
  const scp = /^(?:[^@/\\\s]+@)?([^@:/\\\s]{2,}):(?!\/\/)(.+)$/.exec(url);
  let host, p;
  if (scp) { host = scp[1]; p = scp[2]; } else {
    const u = safe(() => new URL(url), null);
    if (!u || !/^(https?|ssh|git):$/.test(u.protocol) || !u.hostname) return null;
    host = u.hostname; p = u.pathname;
  }
  p = p.replace(/[?#].*$/, '').replace(/^\/+|\/+$/g, '').replace(/\.git$/, '');
  return p ? `https://${host}/${p}` : null;
}
function gitOrigin(cwd) {
  if (!cwd) return null;
  const url = safe(() => execFileSync('git', ['-C', cwd, 'config', '--get', 'remote.origin.url'],
    { encoding: 'utf8', timeout: 1500, stdio: ['ignore', 'pipe', 'ignore'] }).trim(), null);
  return url ? cleanOrigin(url) : null;
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
function gitEmail(cwd) {
  return safe(() => execFileSync('git', ['-C', cwd, 'config', '--get', 'user.email'],
    { encoding: 'utf8', timeout: 1500, stdio: ['ignore', 'pipe', 'ignore'] }).trim(), '');
}
// The merge commits a merge command made: HEAD's first-parent line back to the previous HEAD, every step a
// merge commit. A fast-forward onto merges made elsewhere does not lead back to `from` that way.
function gitMergeChain(cwd, from, to) {
  const out = safe(() => execFileSync('git', ['-C', cwd, 'rev-list', '--first-parent', '--parents', `${from}..${to}`],
    { encoding: 'utf8', timeout: 1500, stdio: ['ignore', 'pipe', 'ignore'] }), '');
  const chain = []; let want = to;
  for (const line of out.split('\n').filter(Boolean)) {
    const [sha, first, second] = line.split(' ');
    if (sha !== want || !second) return [];
    chain.push(sha); want = first;
  }
  return want === from ? chain : [];
}
// Commits reachable from `to` but not `from`, committed after `sinceMs`, by `email` when it is known.
function gitNewCommits(cwd, from, to, sinceMs, email) {
  const by = email ? ['--fixed-strings', `--committer=<${email}>`] : [];
  const out = safe(() => execFileSync('git', ['-C', cwd, 'rev-list', `--since=@${Math.floor(sinceMs / 1000)}`, ...by, `${from}..${to}`],
    { encoding: 'utf8', timeout: 1500, stdio: ['ignore', 'pipe', 'ignore'] }), null);
  return out == null ? [] : out.split(/\s+/).filter(Boolean);
}
// Per-session small state (last seen HEAD, counted commits, pending edit counters) in the state dir.
function loadState(name) { return safe(() => JSON.parse(fs.readFileSync(path.join(stateDir, name), 'utf8')), null) || {}; }
function saveState(name, obj) { safe(() => writeAtomic(path.join(stateDir, name), JSON.stringify(obj))); }
// A transcript checkpoint past the TTL is kept as its offset alone (a few bytes), so a session resumed later
// does not count its earlier requests again; other session state past the TTL is removed.
function pruneState() {
  const cutoff = Date.now() - STATE_TTL_MS;
  for (const f of safe(() => fs.readdirSync(stateDir), [])) {
    if (f === '_send.json') continue;
    const p = path.join(stateDir, f);
    if (safe(() => fs.statSync(p).mtimeMs, Infinity) >= cutoff) continue;
    const cp = /\.json$/.test(f) && !/\.(git|edits)\.json$/.test(f) && safe(() => JSON.parse(fs.readFileSync(p, 'utf8')), null);
    if (cp && Number.isFinite(cp.offset)) { if (cp.seen && cp.seen.length) saveState(f, { offset: cp.offset, seen: [] }); }
    else safe(() => fs.unlinkSync(p));
  }
}

const GIT_HEAD_MOVING = /\bgit\b[^|;&\n]*?\b(commit|merge|rebase|cherry-pick|revert|am|pull|reset|stash\s+pop|switch|checkout)\b/g;
// Only these make commits of the developer's own; the others move HEAD over commits that already exist.
const GIT_AUTHORING = ['commit', 'cherry-pick', 'revert', 'am', 'merge'];
const PR_URL = /https:\/\/[^\s"']+\/(?:pull|merge_requests|pull-requests)\/(\d+)/;
const PR_ERROR = /\b(error|failed|not mergeable|not accessible|could not|cannot|denied)\b|^(X |GraphQL:|HTTP \d{3}\b)/im;
const PR_TOOLS = { gh: 'pr', glab: 'mr' };
// Options that take a value, per CLI (`-m` is a flag in gh, a message in glab), so the value is not read
// as the PR number.
const PR_VALUE_OPTS = {
  gh: ['-t', '--subject', '-b', '--body', '-F', '--body-file', '-A', '--author-email', '--match-head-commit', '-R', '--repo'],
  glab: ['-m', '--message', '--sha', '--squash-message', '-R', '--repo'],
};
// A command line as shell words, quotes removed, in segments split at unquoted ; & | ( ) and newlines —
// enough to find a gh / glab command and its arguments without running a shell.
function shellSegments(cmd) {
  const segs = []; let words = [], w = null, q = null;
  const endWord = () => { if (w !== null) words.push(w); w = null; };
  const endSeg = () => { endWord(); if (words.length) segs.push(words); words = []; };
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i];
    if (q) { if (c === q) q = null; else if (c === '\\' && q === '"' && i + 1 < cmd.length) w += cmd[++i]; else w += c; }
    else if (c === '"' || c === "'") { q = c; if (w === null) w = ''; }
    else if (c === '\\' && i + 1 < cmd.length) w = (w || '') + cmd[++i];
    else if (/[;&|()\n]/.test(c)) endSeg();
    else if (/\s/.test(c)) endWord();
    else w = (w || '') + c;
  }
  endSeg();
  return segs;
}
// The first `gh pr` / `glab mr` create or merge in the command, with its arguments.
function prCommand(cmd) {
  for (const seg of shellSegments(cmd)) {
    const words = seg.slice(seg.findIndex((x) => !/^\w+=/.test(x))); // VAR=value prefixes
    const [tool, noun, action, ...args] = words;
    if (PR_TOOLS[tool] && PR_TOOLS[tool] === noun && (action === 'create' || action === 'merge')) return { tool, action, args };
  }
  return null;
}
// The PR a merge command names: its first positional argument, a number or a PR URL (a branch name gives
// none). `--help` shows help and `--disable-auto` merges nothing.
function prTarget(tool, args) {
  let target = null;
  for (let i = 0; i < args.length; i++) {
    if (['--help', '-h', '--disable-auto'].includes(args[i])) return null;
    if (PR_VALUE_OPTS[tool].includes(args[i])) { i++; continue; }
    if (!args[i].startsWith('-') && target === null) target = args[i]; // flags and --option=value are skipped
  }
  const m = target && PR_URL.exec(target);
  if (m) return { number: Number(m[1]), url: m[0] };
  return target && /^#?\d+$/.test(target) ? { number: Number(target.replace('#', '')), url: null } : null;
}

// ---------- files and locks ----------
// tmp + rename, so a reader never sees half a file. Windows can refuse the rename for a moment while
// another process (an antivirus scan) has the target open, so it is retried briefly.
function writeAtomic(file, data) {
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, data);
  for (let i = 0; ; i++) {
    try { fs.renameSync(tmp, file); return; } catch (e) {
      if (i >= 4 || !['EPERM', 'EACCES', 'EBUSY'].includes(e.code)) { safe(() => fs.unlinkSync(tmp)); throw e; }
      sleep(50);
    }
  }
}
// Exclusive lock file holding an owner tag; only the owner releases it. A lock older than staleMs belongs
// to a process that was killed: it is renamed aside (one contender wins the rename), and a lock that
// turns out to be fresh — created after the age check — is put back.
const held = new Map();
function tryLock(file, staleMs) {
  const me = `${process.pid}.${randomUUID()}`;
  for (let i = 0; i < 2; i++) {
    try { fs.writeFileSync(file, me, { flag: 'wx' }); held.set(file, me); return true; } catch (e) {
      if (e.code !== 'EEXIST') return false;
    }
    if (safe(() => Date.now() - fs.statSync(file).mtimeMs, 0) < staleMs) return false;
    const aside = `${file}.${me}.stale`;
    if (!safe(() => { fs.renameSync(file, aside); return true; }, false)) continue;
    if (safe(() => Date.now() - fs.statSync(aside).mtimeMs, staleMs) < staleMs) {
      safe(() => fs.linkSync(aside, file)); safe(() => fs.unlinkSync(aside)); return false;
    }
    safe(() => fs.unlinkSync(aside));
  }
  return false;
}
function unlock(file) {
  if (safe(() => fs.readFileSync(file, 'utf8'), null) === held.get(file)) safe(() => fs.unlinkSync(file));
  held.delete(file);
}
function withLock(file, waitMs, fn) {
  const until = Date.now() + waitMs;
  while (!tryLock(file, 30e3)) { if (Date.now() >= until) return; sleep(50); }
  try { fn(); } finally { unlock(file); }
}

// ---------- ledger ----------
function isoWeek(d) {
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const day = t.getUTCDay() || 7; t.setUTCDate(t.getUTCDate() + 4 - day);
  const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  return `${t.getUTCFullYear()}-W${String(Math.ceil((((t - y0) / 864e5) + 1) / 7)).padStart(2, '0')}`;
}
function ledgerFiles() { return safe(() => fs.readdirSync(ledgerDir), []).filter((f) => /^\d{4}-W\d{2}\.jsonl$/.test(f)).sort(); }
// Returns whether the record reached the ledger, so callers advance their own state only after it did.
function record(kind, body) {
  const now = new Date();
  // id: unique per record so the aggregation can de-duplicate a batch that was uploaded twice.
  const rec = { id: randomUUID(), kind, ts: now.toISOString(), plugin: PLUGIN_VERSION, team: cfg.team || null, developer: cfg.developer, ...body };
  if (cfg.endpoint) startUploads(); else stopUploads();
  // One ledger file per ISO week of `ts`, so every batch cut from one file shares one week.
  const ok = safe(() => { fs.appendFileSync(path.join(ledgerDir, `${isoWeek(now)}.jsonl`), JSON.stringify(rec) + '\n'); return true; }, false);
  if (!ok) logError(`ledger write failed (${kind})`);
  return ok;
}

// Uploads cover records written while an endpoint is configured (D5): the send state is created with the
// first such record, every ledger byte that existed before it marked as already sent, and it is removed
// by the first record written without an endpoint. Batches already cut stay in send/.
let uploadsChecked = false;
function startUploads() {
  if (uploadsChecked) return;
  uploadsChecked = true;
  if (fs.existsSync(sendState)) return;
  const offsets = {};
  for (const f of ledgerFiles()) offsets[f] = safe(() => fs.statSync(path.join(ledgerDir, f)).size, 0);
  // gen marks this tracking period, so an upload that started in an earlier one cannot save over it
  const body = JSON.stringify({ gen: randomUUID(), offsets, last_ok: 0, fails: 0, next_try: 0, auth_block: null });
  const tmp = `${sendState}.${process.pid}.tmp`;
  safe(() => {
    fs.writeFileSync(tmp, body);
    // the link creates the file only if no other process did first; without links, an exclusive create does
    try { fs.linkSync(tmp, sendState); } catch (e) { if (e.code !== 'EEXIST') fs.writeFileSync(sendState, body, { flag: 'wx' }); }
  });
  safe(() => fs.unlinkSync(tmp));
  safe(() => fs.unlinkSync(path.join(dataDir, 'outbox.jsonl'))); // 0.1.6 queue, replaced by ledger offsets
}
// What was recorded while tracking was on is cut into send/ first, so it is still uploaded once an endpoint
// is set again. When an upload holds send.lock, nothing is cut here: lines that upload has not cut stay in
// the local ledger only, and the upload stops at its next save (saveSend).
function stopUploads() {
  if (uploadsChecked) return;
  uploadsChecked = true;
  if (!fs.existsSync(sendState)) return;
  const locked = tryLock(sendLock, 120e3);
  try {
    const st = locked && loadSend();
    if (st && !cutBatches({ ...st, offsets: st.offsets || {} })) logError('batch cut not saved');
    safe(() => fs.unlinkSync(sendState));
  } finally { if (locked) unlock(sendLock); }
}

// ---------- transcript usage (incremental) ----------
// stateKey: session id for the main transcript, "<session>.<agentId>" for a subagent transcript.
// opts.query_source overrides the per-record querySource (subagent transcripts carry none).
// Returns { delta, save }: the caller records the delta and calls save() only once the record is written.
function usageDelta(stateKey, transcriptPath, opts = {}) {
  if (!transcriptPath || !fs.existsSync(transcriptPath)) return null;
  const stPath = path.join(stateDir, `${stateKey}.json`);
  const size = fs.statSync(transcriptPath).size;
  let st = { offset: 0, seen: [] };
  if (fs.existsSync(stPath)) {
    const saved = safe(() => JSON.parse(fs.readFileSync(stPath, 'utf8')), null);
    if (saved) st = saved;
    else {
      // Restart at the end of the transcript: counting from 0 again would count every request twice.
      logError('usage checkpoint unreadable');
      st = { offset: size, seen: [] };
      safe(() => writeAtomic(stPath, JSON.stringify(st)));
    }
  }
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
  const next = { offset: st.offset + Buffer.byteLength(text.slice(0, lastNl + 1), 'utf8'), seen: Array.from(seen).slice(-5000) };
  // A checkpoint that cannot be saved after its record was written lets the next parse count the delta again.
  const save = () => { if (!safe(() => { writeAtomic(stPath, JSON.stringify(next)); return true; }, false)) logError('usage checkpoint not saved'); };
  return { delta: requests ? { requests, by_model: Object.values(agg), cwd, branch, claude_version: version, agent_id: agentId } : null, save };
}

// Sweep every subagent transcript of a session: <transcript dir>/<session>/subagents/agent-*.jsonl.
// Covers background agents and workflows that end without a SubagentStop hook.
function subagentDeltas(sessionId, transcriptPath) {
  if (!sessionId || !transcriptPath) return [];
  const dir = path.join(path.dirname(transcriptPath), sessionId, 'subagents');
  if (!fs.existsSync(dir)) return [];
  const out = [];
  for (const f of safe(() => fs.readdirSync(dir), [])) {
    if (!f.endsWith('.jsonl')) continue;
    const agentId = f.replace(/^agent-/, '').replace(/\.jsonl$/, '');
    const u = usageDelta(`${sessionId}.${agentId}`, path.join(dir, f), { query_source: 'subagent' });
    if (u) out.push({ delta: u.delta && { ...u.delta, agent_id: u.delta.agent_id || agentId }, save: u.save });
  }
  return out;
}


function flushEdits(sid, base, repoName) {
  const st = loadState(`${sid}.edits.json`);
  if (!st.count) return;
  if (record('edits', { ...base, repo_dir: repoName, count: st.count, by_tool: st.by_tool, by_ext: st.by_ext,
    bytes: st.bytes, files: Object.keys(st.files || {}).length })) saveState(`${sid}.edits.json`, {});
}

// Stop (async) and SessionEnd can run at once for the same session, and SubagentStop can overlap the
// Stop sweep; the session lock keeps them from counting the same transcript lines twice.
function sessionLock(sid) { return path.join(stateDir, `${sid}.lock`); }
function sessionUsage(sid, input, base, extra, waitMs) {
  withLock(sessionLock(sid), waitMs, () => {
    const email = accountEmail();
    for (const u of [usageDelta(sid, input.transcript_path), ...subagentDeltas(sid, input.transcript_path)]) {
      if (u && (!u.delta || record('usage', { ...base, ...extra, email, ...u.delta }))) u.save();
    }
    flushEdits(sid, base, extra.repo_dir);
  });
}

// ---------- upload ----------
// Policy (README § Upload contract): complete ledger lines of the configured developer are cut into batches
// of one ISO week (at most MAX_BATCH_BYTES) and kept in send/ until the receiver answers 202, then deleted. An
// upload is due every flush_hours, or earlier once FLUSH_MAX_BYTES are waiting. A failed batch is retried after
// 30 min, doubling per consecutive failure up to 6 h; a 401 stops uploads until the endpoint or token
// changes; a configuration that cannot be uploaded safely is refused once and logged. One process
// uploads at a time (send.lock).
function loadSend() { return safe(() => JSON.parse(fs.readFileSync(sendState, 'utf8')), null); }
// Saves only over the send state of the same tracking period: a record written without an endpoint may have
// ended tracking meanwhile, and another one started it again (D5); an upload still running must neither
// restore the old period nor write its offsets over the new one.
function ownsSend(st) { const cur = loadSend(); return Boolean(cur) && cur.gen === st.gen; }
function saveSend(st) { return ownsSend(st) && safe(() => { writeAtomic(sendState, JSON.stringify(st)); return true; }, false); }
function keepSend(st) {
  if (saveSend(st)) return true;
  if (ownsSend(st)) logError('send state not writable');
  return false;
}
function firstRecord(body) {
  for (const line of body.split('\n')) if (line.trim()) return safe(() => JSON.parse(line), null);
  return null;
}
function pendingBatches() { return safe(() => fs.readdirSync(sendDir), []).filter((f) => f.endsWith('.ndjson')).sort(); }
function authKey() { return sha(`${cfg.endpoint}\n${cfg.token}`).slice(0, 16); }
function configKey() { return sha(`${cfg.endpoint}\n${cfg.token}\n${cfg.developerSet ? cfg.developer : ''}`).slice(0, 16); }
function configProblem() { return uploadProblem(cfg); }
function unsentBytes(st) {
  let n = 0;
  for (const f of ledgerFiles()) n += Math.max(0, safe(() => fs.statSync(path.join(ledgerDir, f)).size, 0) - (st.offsets[f] || 0));
  return n;
}
function chunks(lines) {
  const out = []; let cur = [], size = 0;
  for (const l of lines) {
    const n = Buffer.byteLength(l, 'utf8') + 1;
    if (n > MAX_BATCH_BYTES) { logError('record over 1 MB not uploaded'); continue; } // records are a few KB at most
    if (cur.length && size + n > MAX_BATCH_BYTES) { out.push(cur.join('\n') + '\n'); cur = []; size = 0; }
    cur.push(l); size += n;
  }
  if (cur.length) out.push(cur.join('\n') + '\n');
  return out;
}
// Returns false when a batch or the new offset could not be saved; the batches of that file are then
// removed again, so the same range is cut once more later instead of being uploaded twice.
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
    // Only records of the configured developer: those written under an earlier or an unassigned id stay in
    // the local ledger (D6), so a batch never represents anyone but the sending configuration.
    const keep = [];
    for (const line of buf.subarray(0, end).toString('utf8').split('\n')) {
      const r = line.trim() && safe(() => JSON.parse(line), null);
      if (r && r.id && r.developer === cfg.developer) keep.push(line);
    }
    const written = [];
    const ok = safe(() => {
      for (const body of chunks(keep)) {
        const p = path.join(sendDir, `${stamp}-${f.slice(0, 8)}-${String(n++).padStart(3, '0')}.ndjson`);
        writeAtomic(p, body); written.push(p);
      }
      return true;
    }, false);
    st.offsets[f] = from + end + 1;
    if (!ok || !saveSend(st)) {
      for (const p of written) safe(() => fs.unlinkSync(p));
      st.offsets[f] = from;
      return false;
    }
  }
  return true;
}
// The upload URL carries developer / week / id as query parameters so a receiver can pick a folder and
// file name without parsing the body. week = ISO week of the first record (shared by the whole batch),
// id = that record's id. Existing query strings are kept byte for byte.
function uploadUrl(body) {
  const first = firstRecord(body);
  const ts = first && first.ts ? new Date(first.ts) : new Date();
  const q = new URLSearchParams({
    developer: (first && first.developer) || cfg.developer,
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
      headers: { 'content-type': 'application/x-ndjson', 'x-webhook-token': cfg.token },
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
    if (!st) {
      // The next process that writes a record starts the send state again from the end of the ledger.
      logError('send state unreadable; set aside');
      safe(() => fs.renameSync(sendState, `${sendState}.bad`));
      return;
    }
    st.offsets = st.offsets || {};
    const problem = configProblem();
    if (problem) {
      const tag = `${problem}:${configKey()}`;
      if (st.config_block !== tag) { logError(`upload refused: ${problem}`); st.config_block = tag; keepSend(st); }
      return;
    }
    st.config_block = null;
    const key = authKey();
    if (st.auth_block === key) return;
    if (st.auth_block) Object.assign(st, { auth_block: null, fails: 0, next_try: 0 });
    const now = Date.now();
    if (pendingBatches().length ? now < (st.next_try || 0)
      : unsentBytes(st) < FLUSH_MAX_BYTES && now - (st.last_ok || 0) < cfg.flushHours * 3600e3) return;
    // A send state that cannot be saved would forget a 401 or a backoff and resend on every Stop.
    if (!keepSend(st)) return;
    if (!cutBatches(st)) { logError('batch cut not saved'); return; }
    for (const f of pendingBatches()) {
      if (Date.now() - STARTED > SEND_BUDGET_MS) break;
      const file = path.join(sendDir, f);
      let body;
      try { body = fs.readFileSync(file, 'utf8'); } catch (e) { logError(`batch unreadable ${e.code || e.name}`); break; }
      if (!body.trim()) { safe(() => fs.unlinkSync(file)); continue; }
      // A batch cut under an earlier developer id is not sent from this configuration (D6); it is set aside.
      const first = firstRecord(body);
      if (!first || first.developer !== cfg.developer) {
        logError('upload held: batch of another developer');
        safe(() => fs.renameSync(file, `${file}.held`));
        continue;
      }
      const status = await post(body);
      if (status === 202) {
        safe(() => fs.unlinkSync(file));
        Object.assign(st, { last_ok: Date.now(), fails: 0, next_try: 0 });
        if (!keepSend(st)) break; // another tracking period began meanwhile, or the state is not writable
        continue;
      }
      logError(`upload ${status}`);
      if (status === 401) st.auth_block = key;
      else {
        st.fails = (st.fails || 0) + 1;
        st.next_try = Date.now() + Math.min(RETRY_BASE_MS * 2 ** (st.fails - 1), RETRY_MAX_MS);
      }
      keepSend(st);
      break;
    }
  } finally { unlock(sendLock); }
}

// ---------- main ----------
async function main() {
  let input = {};
  try { input = JSON.parse(fs.readFileSync(0, 'utf8') || '{}'); } catch (_) { logError('hook input not JSON'); }
  const base = { session_id: input.session_id || null, cwd: input.cwd || null };
  const repoName = base.cwd ? path.basename(base.cwd) : null;

  switch (EVENT) {
    case 'SessionStart':
      record('session_open', { ...base, ...identity(), repo: gitOrigin(base.cwd), repo_dir: repoName, branch: gitBranch(base.cwd),
        model: input.model || null, source: input.source || null, permission_mode: input.permission_mode || null,
        entrypoint: process.env.CLAUDE_CODE_ENTRYPOINT || null });
      { // a resumed or compacted session keeps its other baselines and the commits it already counted
        const h = gitHead(base.cwd), name = `${base.session_id || 'nosession'}.git.json`;
        if (h) saveState(name, { ...loadState(name), [base.cwd]: h }); }
      pruneState();
      break;
    case 'UserPromptSubmit': {
      const p = String(input.prompt || '');
      const m = p.match(/^\s*(\/[\w:-]+)(?=\s|$)/); // a slash command, not a path such as /Users/…
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
        const stderr = typeof resp === 'string' ? '' : String((resp && resp.stderr) || '');
        let where = null; // origin and branch, read once for both records (each git call can take 1.5 s)
        const place = () => where || (where = { repo: gitOrigin(base.cwd), branch: gitBranch(base.cwd) });
        // Commits: compare HEAD with the last HEAD this session saw. A failed commit leaves HEAD unchanged.
        const ops = Array.from(cmd.matchAll(GIT_HEAD_MOVING), (m) => m[1].replace(/\s+/g, ' '));
        if (ops.length) {
          const st = loadState(`${sid}.git.json`);
          const head = gitHead(base.cwd);
          const prev = st[base.cwd];
          const authoring = ops.filter((o) => GIT_AUTHORING.includes(o));
          let recorded = true;
          if (head && head !== prev && authoring.length) {
            // The commits of this command: new to HEAD, committed in the last COMMIT_WINDOW_MS by this repository's
            // git user, and not counted before in this session — so commits passed over by a checkout or pull in
            // the same command, and other people's recent commits, are left out. A command whose only authoring
            // steps are merges made only its merge commits (gitMergeChain); a fast-forward made none. Without a
            // baseline for this cwd, trust git's own "[branch abc1234] message" line only.
            const summary = /^\[[^\]\n]+ ([0-9a-f]{7,40})\]/m.exec(stdout);
            const counted = new Set(st._counted || []);
            let fresh = prev ? gitNewCommits(base.cwd, prev, head, Date.now() - COMMIT_WINDOW_MS, gitEmail(base.cwd)) : (summary ? [head] : []);
            if (authoring.every((o) => o === 'merge')) {
              const made = new Set(fresh);
              fresh = prev ? gitMergeChain(base.cwd, prev, head).filter((s) => made.has(s)) : [];
            }
            fresh = fresh.filter((s) => !counted.has(s));
            if (fresh.length) {
              recorded = record('commit', { ...base, repo_dir: repoName, ...place(),
                sha: head, from_sha: prev || null, commits: fresh.length, tool, op: authoring[0] });
              if (recorded) { for (const s of fresh) counted.add(s); st._counted = Array.from(counted).slice(-500); }
            }
          }
          // The baseline moves past these commits only once they are recorded (D11).
          if (head && recorded) { st[base.cwd] = head; saveState(`${sid}.git.json`, st); }
        }
        // Pull requests: `create` prints the PR URL; `merge` prints nothing when not run in a terminal, so its
        // number comes from the command, counted only when the output carries no error. `--auto` counts when
        // it is requested.
        const pc = prCommand(cmd);
        let number = null, url = null;
        if (pc && pc.action === 'create') {
          const m = !pc.args.some((a) => a === '--help' || a === '-h') && PR_URL.exec(stdout);
          if (m) { number = Number(m[1]); url = m[0]; }
        } else if (pc && !PR_ERROR.test(`${stdout}\n${stderr}`)) {
          const t = prTarget(pc.tool, pc.args);
          if (t) ({ number, url } = t);
        }
        if (number) record('pr', { ...base, repo_dir: repoName, ...place(), number, url, action: pc.action });
      } else {
        // Edits: accumulate per session, emitted as one "edits" record at Stop. Files are kept as hashes,
        // only to count distinct files; no path is stored.
        const st = loadState(`${sid}.edits.json`);
        const file = String(ti.file_path || ti.notebook_path || '');
        const ext = file ? (path.extname(file).toLowerCase() || '(none)') : '(none)';
        const text = ti.new_string || ti.content || ti.new_source
          || (Array.isArray(ti.edits) ? ti.edits.map((e) => (e && e.new_string) || '').join('') : '');
        st.count = (st.count || 0) + 1;
        st.by_tool = st.by_tool || {}; st.by_tool[tool] = (st.by_tool[tool] || 0) + 1;
        st.by_ext = st.by_ext || {}; st.by_ext[ext] = (st.by_ext[ext] || 0) + 1;
        st.bytes = (st.bytes || 0) + Buffer.byteLength(String(text), 'utf8');
        st.files = st.files || {}; if (file) st.files[sha(file).slice(0, 16)] = 1;
        saveState(`${sid}.edits.json`, st);
      }
      break;
    }
    case 'SubagentStop': {
      const sid = base.session_id || 'nosession';
      record('subagent', { ...base, repo_dir: repoName, agent_type: input.agent_type || null, agent_id: input.agent_id || null });
      // Subagent tokens live in their own transcript; parse it now while the agent type is known.
      withLock(sessionLock(sid), 1000, () => {
        const u = usageDelta(`${sid}.${input.agent_id || 'agent'}`, input.agent_transcript_path, { query_source: 'subagent' });
        if (u && (!u.delta || record('usage', { ...base, repo_dir: repoName, agent_type: input.agent_type || null,
          email: accountEmail(), ...u.delta, agent_id: u.delta.agent_id || input.agent_id || null }))) u.save();
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
      sessionUsage(sid, input, base, { repo_dir: repoName }, 600); // the hook timeout is 1 s (hooks.json)
      record('session_close', { ...base, reason: input.reason || null });
      break;
    }
    default:
      break;
  }
}

main().catch((e) => {
  const at = /collect\.js:(\d+)/.exec(String(e && e.stack));
  logError(`uncaught ${(e && e.name) || 'Error'}${e && e.code ? ` ${e.code}` : ''}${at ? ` at collect.js:${at[1]}` : ''}`);
}).finally(() => process.exit(0));
