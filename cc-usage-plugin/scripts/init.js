#!/usr/bin/env node
// cc-usage setup helper — run by the /cc-usage-plugin:cc-init command and, for the receiver URL and
// token, by the person in a terminal (README § Install, D12). It reads and saves the plugin's options
// through `claude plugin configure`, so developer and team land in settings.json and endpoint and token
// in Claude Code's secure storage. It never prints, logs or passes on an endpoint or token value.
//
//   node init.js status                                   options set, upload state, next step
//   node init.js set --developer <id> [--team <label>]    save the developer id (normalized) and team
//   node init.js secrets                                  ask for endpoint and token without echo
//
// Every command takes --plugin <id> (e.g. cc-usage-plugin@acme) when the install cannot be found.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { normalizeDeveloper, endpointProblem } = require('./config');

const NAME = 'cc-usage-plugin';
const ROOT = path.resolve(__dirname, '..');
const SELF = path.join(ROOT, 'scripts', 'init.js');
const NODE_MIN = { 22: [23, 4], 24: [22, 1], 26: [12, 1] }; // README § Requirements
const configDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');

function out(line = '') { process.stdout.write(`${line}\n`); }
function fail(msg) { process.stderr.write(`cc-init: ${msg}\n`); process.exit(1); }
function safe(fn, fallback) { try { return fn(); } catch (_) { return fallback; } }

function parseArgs(argv) {
  const a = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const m = /^--([a-z-]+)(?:=(.*))?$/.exec(argv[i]);
    if (!m) { a._.push(argv[i]); continue; }
    if (m[2] !== undefined) a[m[1]] = m[2];
    else a[m[1]] = argv[++i] ?? '';
  }
  return a;
}

// The claude CLI is the only writer of plugin options; Windows resolves it as claude.cmd or claude.exe
// through the shell. Arguments are fixed strings and a checked plugin id; values travel on stdin.
function claude(args, input) {
  const r = spawnSync('claude', args, {
    input, encoding: 'utf8', timeout: 60e3, windowsHide: true, shell: process.platform === 'win32',
  });
  if (r.error) fail(`could not run the claude CLI (${r.error.code || r.error.message}); is Claude Code on PATH?`);
  return r;
}

function pluginId(flag) {
  if (flag) {
    if (!/^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$/.test(flag)) fail('--plugin takes an id like cc-usage-plugin@acme');
    return flag;
  }
  const r = claude(['plugin', 'list', '--json']);
  const list = safe(() => JSON.parse(r.stdout), []);
  const mine = (Array.isArray(list) ? list : []).filter((p) => String(p.id || '').startsWith(`${NAME}@`));
  const real = (p) => safe(() => fs.realpathSync(p), p);
  const here = mine.find((p) => p.installPath && real(p.installPath) === real(ROOT));
  if (here) return here.id;
  const ids = [...new Set(mine.map((p) => p.id))];
  if (ids.length === 1) return ids[0];
  if (ids.length > 1) fail(`more than one install (${ids.join(', ')}); pass --plugin <id>`);
  fail(`${NAME} is not installed from a marketplace, so its options cannot be saved. Install it first ` +
    `(README § Install); for a one-session trial with --plugin-dir use the CC_USAGE_* environment variables.`);
}

// { inputs, configured, unconfigured }; inputs come back empty for sensitive options.
function readOptions(id) {
  const r = claude(['plugin', 'configure', id, '--json']);
  const d = r.status === 0 ? safe(() => JSON.parse(r.stdout), null) : null;
  if (!d || !d.inputs) fail(`could not read the options of ${id} (claude plugin configure exited ${r.status})`);
  return { inputs: d.inputs, configured: new Set(d.configured || []) };
}

// Options left out keep their values. The CLI's own output is not echoed: it is not ours to vouch for.
function saveOptions(id, values) {
  const r = claude(['plugin', 'configure', id, '--values-stdin'], JSON.stringify(values));
  if (r.status !== 0) fail(`saving the options failed (claude plugin configure exited ${r.status})`);
}

function nodeOk(v = process.versions.node) {
  const [maj, min, pat] = v.split('.').map(Number);
  if (maj > 26) return true;
  const need = NODE_MIN[maj];
  return Boolean(need) && (min > need[0] || (min === need[0] && pat >= need[1]));
}

// From the id, not CLAUDE_PLUGIN_DATA: a shell inside Claude Code can carry another plugin's value.
function dataDir(id) { return path.join(configDir, 'plugins', 'data', id.replace('@', '-')); }

// What the hooks have done so far: the last record, batches waiting, the send state, recent errors.
function ledgerState(id) {
  const dir = dataDir(id);
  const ledger = safe(() => fs.readdirSync(path.join(dir, 'ledger')).filter((f) => f.endsWith('.jsonl')).sort(), []);
  let last = null;
  if (ledger.length) {
    const text = safe(() => fs.readFileSync(path.join(dir, 'ledger', ledger[ledger.length - 1]), 'utf8'), '');
    const line = text.trimEnd().split('\n').pop();
    last = safe(() => JSON.parse(line), null);
  }
  const waiting = safe(() => fs.readdirSync(path.join(dir, 'send')).filter((f) => f.endsWith('.ndjson')).length, 0);
  const held = safe(() => fs.readdirSync(path.join(dir, 'send')).filter((f) => f.endsWith('.held')).length, 0);
  const send = safe(() => JSON.parse(fs.readFileSync(path.join(dir, 'state', '_send.json'), 'utf8')), null);
  const errors = safe(() => fs.readFileSync(path.join(dir, 'errors.log'), 'utf8'), '').trimEnd().split('\n').filter(Boolean).slice(-3);
  return { last, waiting, held, send, errors };
}

function iso(ms) { return ms ? new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z') : '-'; }

function status(id) {
  const { inputs, configured } = readOptions(id);
  const dev = String(inputs.developer || '').trim();
  // Sensitive options come back empty, so for them only "saved" is known, not the value.
  const set = (k) => configured.has(k) && (k === 'endpoint' || k === 'token' || String(inputs[k] || '').trim() !== '');
  out(`${id}`);
  out(`  developer    ${dev ? `${dev}  (uploads as "${normalizeDeveloper(dev)}")` : 'not set — uploads need it'}`);
  out(`  team         ${String(inputs.team || '').trim() || 'not set'}`);
  out(`  endpoint     ${set('endpoint') ? 'saved (value hidden)' : 'not set — local ledger only'}`);
  out(`  token        ${set('token') ? 'saved (value hidden)' : 'not set'}`);
  out(`  flush_hours  ${String(inputs.flush_hours || '').trim() || '24 (default)'}`);
  out(`  Node         ${process.versions.node} ${nodeOk() ? 'ok' : '— not supported: needs 22.23.4+, 24.22.1+ or 26.12.1+'}`);
  const st = ledgerState(id);
  out(`  last record  ${st.last ? `${st.last.ts} ${st.last.kind}, developer "${st.last.developer}", plugin ${st.last.plugin}` : 'none yet — starts with the next session'}`);
  if (st.send) {
    const block = st.send.auth_block ? 'stopped by 401 until the endpoint or token changes' : null;
    const backoff = st.send.next_try > Date.now() ? `retrying after ${iso(st.send.next_try)} (${st.send.fails} failed)` : null;
    out(`  uploads      ${block || backoff || 'tracking'}; last 202 ${iso(st.send.last_ok)}; ${st.waiting} batch(es) waiting${st.held ? `, ${st.held} held` : ''}`);
  } else {
    out(`  uploads      not tracking${st.waiting ? `; ${st.waiting} batch(es) waiting for an endpoint` : ''}`);
  }
  for (const e of st.errors) out(`  errors.log   ${e}`);
  out();
  if (!dev) out('Next: save your developer id — /cc-usage-plugin:cc-init <developer> [team]');
  else if (!set('endpoint') || !set('token')) out(`Next, in a terminal (not in Claude Code): node "${SELF}" secrets`);
  else out('All options are set. Changes apply from the next Claude Code session.');
}

function setIdentity(id, a) {
  const raw = String(a.developer ?? a._[1] ?? '').trim();
  if (!raw) fail('--developer is required: the id assigned to you in the install guide');
  if (/[\r\n]/.test(raw) || (a.team !== undefined && /[\r\n]/.test(a.team))) fail('values must be single-line');
  const developer = normalizeDeveloper(raw);
  const { inputs } = readOptions(id);
  const before = String(inputs.developer || '').trim();
  const values = { developer };
  const team = a.team ?? a._[2];
  if (team !== undefined) values.team = String(team).trim();
  saveOptions(id, values);
  out(`Saved developer "${developer}"${developer !== raw ? ` (from "${raw}")` : ''}${values.team !== undefined ? ` and team "${values.team}"` : ''}.`);
  if (before && normalizeDeveloper(before) !== developer) {
    out(`The previous id was "${normalizeDeveloper(before)}"; records stamped with it stay in the local ledger (D6).`);
  }
  out('Changes apply from the next Claude Code session.');
  out(`Next, for the receiver URL and token, in a terminal (not in Claude Code): node "${SELF}" secrets`);
}

// One line from the person without echo (a terminal), or the next line of piped input.
function reader() {
  if (!process.stdin.isTTY) {
    const lines = safe(() => fs.readFileSync(0, 'utf8'), '').split(/\r?\n/);
    return async () => (lines.shift() || '').trim();
  }
  return (question) => new Promise((resolve) => {
    const stdin = process.stdin;
    process.stderr.write(question);
    let s = '';
    const finish = () => {
      stdin.removeListener('data', onData); stdin.setRawMode(false); stdin.pause();
      process.stderr.write('\n'); resolve(s.trim());
    };
    const onData = (chunk) => {
      for (const ch of chunk.replace(/\u001b\[[0-9;?]*[~A-Za-z]/g, '')) {
        if (ch === '\r' || ch === '\n') return finish();
        if (ch === '\u0003') { stdin.setRawMode(false); process.stderr.write('\n'); process.exit(130); }
        if (ch === '\u007f' || ch === '\b') s = s.slice(0, -1);
        else if (ch >= ' ') s += ch;
      }
    };
    stdin.setEncoding('utf8'); stdin.setRawMode(true); stdin.resume(); stdin.on('data', onData);
  });
}

async function secrets(id) {
  const { inputs, configured } = readOptions(id);
  // Records are uploaded only under the id set now (D6), so the id comes before the endpoint.
  if (!String(inputs.developer || '').trim()) fail('save your developer id first: /cc-usage-plugin:cc-init <developer> [team]');
  const ask = reader();
  const keep = (k) => (configured.has(k) ? ' (Enter keeps the current value)' : '');
  const endpoint = await ask(`Receiver URL, input hidden${keep('endpoint')}: `);
  if (endpoint) {
    const problem = endpointProblem(endpoint);
    if (problem) fail(`endpoint not saved: ${problem} (README § Upload contract)`);
  }
  const token = await ask(`Receiver token, input hidden${keep('token')}: `);
  if (!endpoint && !token) { out('Nothing entered; nothing changed.'); return; }
  const values = {};
  if (endpoint) values.endpoint = endpoint;
  if (token) values.token = token;
  saveOptions(id, values);
  out(`Saved ${Object.keys(values).join(' and ')} in Claude Code's secure storage. Changes apply from the next Claude Code session.`);
  if (!token && !configured.has('token')) out('No token is set yet, so uploads stay refused (no-token) until one is saved.');
  if (!endpoint && !configured.has('endpoint')) out('No endpoint is set yet, so nothing is uploaded until one is saved.');
}

async function main() {
  const a = parseArgs(process.argv.slice(2));
  const cmd = a._[0] || 'status';
  if (!['status', 'set', 'secrets'].includes(cmd)) fail(`unknown command "${cmd}" (status, set, secrets)`);
  const id = pluginId(a.plugin);
  if (cmd === 'status') status(id);
  else if (cmd === 'set') setIdentity(id, a);
  else await secrets(id);
}

main();
