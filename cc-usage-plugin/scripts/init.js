#!/usr/bin/env node
// cc-usage setup helper — run by the /cc-usage-plugin:cc-init command and, for the receiver URL and
// token, by the person in a terminal (README § Install, D12). It reads and saves the plugin's options
// through `claude plugin configure`, so developer and team land in settings.json and endpoint and token
// in Claude Code's secure storage. It never prints, logs or passes on an endpoint or token value.
//
//   node init.js status                                   options set, upload state, next step
//   node init.js set [--developer <id>] [--team <label>]  save the developer id (normalized), the team, or both
//   node init.js secrets                                  ask for endpoint and token without echo
//
// Every command takes --plugin <id> (e.g. cc-usage-plugin@acme) when the install cannot be found, and
// --config-dir <folder> for a Claude Code configuration folder other than the default (CLAUDE_CONFIG_DIR).
'use strict';
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { WEEK_FILE, configDir, normalizeDeveloper, endpointProblem, tokenProblem } = require('./config');

const NAME = 'cc-usage-plugin';
const ROOT = path.resolve(__dirname, '..');
const SELF = path.join(ROOT, 'scripts', 'init.js');
const NODE_MIN = { 22: [23, 4], 24: [22, 1], 26: [12, 1] }; // README § Requirements

// While secrets holds the terminal, an error must not give the terminal back with unread input in it:
// the input would be echoed and handed to the shell. fail() then throws, and main() drains first.
class Exit extends Error { constructor(message, code = 1) { super(message); this.code = code; } }
let held = null; // the terminal, while secrets has it in raw mode
function out(line = '') { process.stdout.write(`${line}\n`); }
function fail(msg, code = 1) {
  if (held) throw new Exit(msg, code);
  if (msg) process.stderr.write(`cc-init: ${msg}\n`);
  process.exit(code);
}
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
// through the shell. Arguments are fixed strings and a checked plugin id; values travel on stdin. The
// CLI reads CLAUDE_CONFIG_DIR from the environment, so --config-dir reaches it that way.
function claude(args, input) {
  const r = spawnSync('claude', args, {
    input, encoding: 'utf8', timeout: 60e3, windowsHide: true, shell: process.platform === 'win32',
  });
  if (r.error) fail(`could not run the claude CLI (${r.error.code || r.error.message}); is Claude Code on PATH?`);
  return r;
}

// Every id becomes a CLI argument (through the shell on Windows), so every id is checked, found or given.
const ID = /^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$/;
function checkedId(id) {
  if (!ID.test(id)) fail('the installed plugin id is not of the form cc-usage-plugin@<marketplace>; pass --plugin <id>');
  return id;
}

function pluginId(flag) {
  if (flag) {
    if (!ID.test(flag)) fail('--plugin takes an id like cc-usage-plugin@acme');
    return flag;
  }
  const r = claude(['plugin', 'list', '--json']);
  // On Windows a missing claude is the shell's exit status, not a spawn error.
  if (r.status !== 0) fail(`claude plugin list exited ${r.status}; is Claude Code on PATH?`);
  const list = safe(() => JSON.parse(r.stdout), []);
  const mine = (Array.isArray(list) ? list : []).filter((p) => p && typeof p === 'object' && String(p.id || '').startsWith(`${NAME}@`));
  const real = (p) => safe(() => fs.realpathSync(p), p);
  const here = mine.find((p) => p.installPath && real(p.installPath) === real(ROOT));
  if (here) return checkedId(here.id);
  const ids = [...new Set(mine.map((p) => p.id))];
  if (ids.length === 1) return checkedId(ids[0]);
  if (ids.length > 1) fail(`more than one install (${ids.join(', ')}); pass --plugin <id>`);
  fail(`${NAME} is not installed from a marketplace in ${configDir()}, so its options cannot be saved. ` +
    'Install it first (README § Install), or pass --config-dir for another configuration folder; for a ' +
    'one-session trial with --plugin-dir use the CC_USAGE_* environment variables.');
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
// "@" becomes "-" (seen); other characters an id may hold might be replaced too, so either spelling is
// taken, whichever exists.
function dataDir(id) {
  const root = path.join(configDir(), 'plugins', 'data');
  const names = [id.replace('@', '-'), id.replace(/[^A-Za-z0-9_-]/g, '-')];
  return path.join(root, names.find((n) => fs.existsSync(path.join(root, n))) || names[0]);
}

// What the hooks have done so far: the last record, batches waiting, the send state, recent errors.
function ledgerState(id) {
  const dir = dataDir(id);
  const ledger = safe(() => fs.readdirSync(path.join(dir, 'ledger')).filter((f) => WEEK_FILE.test(f)).sort(), []);
  let last = null;
  if (ledger.length) {
    const text = safe(() => fs.readFileSync(path.join(dir, 'ledger', ledger[ledger.length - 1]), 'utf8'), '');
    const line = text.trimEnd().split('\n').pop();
    last = safe(() => JSON.parse(line), null);
  }
  const sent = safe(() => fs.readdirSync(path.join(dir, 'send')), []);
  const send = safe(() => JSON.parse(fs.readFileSync(path.join(dir, 'state', '_send.json'), 'utf8')), null);
  const log = safe(() => fs.readFileSync(path.join(dir, 'errors.log'), 'utf8'), '').trimEnd().split('\n').filter(Boolean);
  const refused = log.map((l) => /upload refused: (\S+)/.exec(l)).filter(Boolean).pop();
  return {
    last, send, errors: log.slice(-3), refused: refused && refused[1],
    waiting: sent.filter((f) => f.endsWith('.ndjson')).length, held: sent.filter((f) => f.endsWith('.held')).length,
  };
}

function iso(ms) { return ms ? new Date(ms).toISOString().replace(/\.\d+Z$/, 'Z') : '-'; }

// The developer id the hooks use: the saved option, else CC_USAGE_DEVELOPER (README § Install).
function developerOf(inputs) {
  const saved = String(inputs.developer || '').trim();
  if (saved) return { dev: saved, from: '' };
  const env = String(process.env.CC_USAGE_DEVELOPER || '').trim();
  return { dev: env, from: env ? ', from CC_USAGE_DEVELOPER' : '' };
}

function status(id) {
  const { inputs, configured } = readOptions(id);
  const { dev, from } = developerOf(inputs);
  // Sensitive options come back empty, so for them only "saved" is known, not the value.
  const set = (k) => configured.has(k);
  out(`${id}`);
  out(`  developer    ${dev ? `${dev}  (uploads as "${normalizeDeveloper(dev)}"${from})` : 'not set — uploads need it'}`);
  out(`  team         ${String(inputs.team || '').trim() || 'not set'}`);
  out(`  endpoint     ${set('endpoint') ? 'saved (value hidden)' : 'not set — local ledger only'}`);
  out(`  token        ${set('token') ? 'saved (value hidden)' : 'not set'}`);
  out(`  flush_hours  ${String(inputs.flush_hours || '').trim() || '24 (default)'}`);
  out(`  Node         ${process.versions.node} ${nodeOk() ? 'ok' : '— not supported: needs 22.23.4+, 24.22.1+ or 26.12.1+'}`);
  const st = ledgerState(id);
  out(`  last record  ${st.last ? `${st.last.ts} ${st.last.kind}, developer "${st.last.developer}", plugin ${st.last.plugin}` : 'none yet — starts with the next session'}`);
  if (st.send) {
    const refused = st.send.config_block ? `refused by the configuration (${st.refused || 'see errors.log'})` : null;
    const block = st.send.auth_block ? 'stopped by 401 until the endpoint or token changes' : null;
    const backoff = st.send.next_try > Date.now() ? `retrying after ${iso(st.send.next_try)} (${st.send.fails} failed)` : null;
    out(`  uploads      ${refused || block || backoff || 'tracking'}; last 202 ${iso(st.send.last_ok)}; ${st.waiting} batch(es) waiting${st.held ? `, ${st.held} held` : ''}`);
  } else {
    out(`  uploads      not tracking${st.waiting ? `; ${st.waiting} batch(es) waiting for an endpoint` : ''}`);
  }
  for (const e of st.errors) out(`  errors.log   ${e}`);
  out();
  if (!dev) out('Next: save your developer id — /cc-usage-plugin:cc-init <developer> [team]');
  else if (!set('endpoint') || !set('token')) out(`Next, in a terminal (not in Claude Code): ${secretsCommand(id)}`);
  else out('All options are set. Changes apply from the next Claude Code session.');
}

// The id and a non-default configuration folder are printed too, so the command works as printed in a
// new terminal, which has neither the session's CLAUDE_CONFIG_DIR nor a way to tell installs apart.
function secretsCommand(id) {
  const dir = process.env.CLAUDE_CONFIG_DIR ? ` --config-dir ${shellArg(path.resolve(process.env.CLAUDE_CONFIG_DIR))}` : '';
  return `node ${shellArg(SELF)} secrets --plugin ${id}${dir}`;
}
// A path as one shell word, to paste as printed: single quotes on POSIX shells ($, backticks and " stay
// literal); double quotes on Windows, where a trailing backslash would escape the closing quote.
function shellArg(s) {
  if (process.platform === 'win32') return `"${s.replace(/\\$/, '\\.')}"`;
  return `'${s.replace(/'/g, "'\\''")}'`;
}

function setIdentity(id, a) {
  const raw = String(a.developer ?? a._[1] ?? '').trim();
  const team = a.team ?? a._[2];
  if (!raw && team === undefined) fail('--developer or --team is required: the developer id assigned to you in the install guide, or a team');
  if (/[\r\n]/.test(raw) || (team !== undefined && /[\r\n]/.test(team))) fail('values must be single-line');
  const { inputs } = readOptions(id);
  const before = String(inputs.developer || '').trim();
  const values = {};
  if (raw) values.developer = normalizeDeveloper(raw);
  if (team !== undefined) values.team = String(team).trim();
  saveOptions(id, values);
  const saved = [
    values.developer !== undefined && `developer "${values.developer}"${values.developer !== raw ? ` (from "${raw}")` : ''}`,
    values.team !== undefined && `team "${values.team}"`,
  ].filter(Boolean);
  out(`Saved ${saved.join(' and ')}.${values.developer === undefined && before ? ` The developer id stays "${before}".` : ''}`);
  if (values.developer !== undefined && before && normalizeDeveloper(before) !== values.developer) {
    out(`The previous id was "${normalizeDeveloper(before)}"; records stamped with it stay in the local ledger (D6).`);
  }
  out('Changes apply from the next Claude Code session.');
  out(`Next, for the receiver URL and token, in a terminal (not in Claude Code): ${secretsCommand(id)}`);
}

// Answers typed in the terminal, never shown: raw mode is on before anything else runs and stays on until
// the end, so neither type-ahead nor a late paste is echoed. Keys are decoded as strict UTF-8, escape
// sequences (arrow keys and the like) are dropped even when split across reads, and a paste of several
// lines answers the questions in order. Every way out — done, an error, Ctrl-C — goes through close(),
// which reads and drops what is still arriving before echo comes back.
function terminal() {
  const stdin = process.stdin;
  const decoder = new TextDecoder('utf-8', { fatal: true });
  const lines = [];
  let cur = '', esc = 0, lastCR = false, bad = false, interrupted = false, waiting = null;
  const onData = (buf) => {
    let text = '';
    try { text = decoder.decode(buf, { stream: true }); } catch (_) { bad = true; }
    for (const ch of text) {
      if (interrupted) break;
      // An escape sequence is ESC [ <parameters> <final> or ESC O <final>; a key that cannot continue it
      // (Enter, Ctrl-C, or a lone Esc followed by a letter) ends it and is read as itself.
      if (esc === 1) {
        if (ch === '[') { esc = 2; continue; }
        if (ch === 'O') { esc = 3; continue; }
        esc = 0;
      } else if (esc === 2) {
        if (ch >= ' ' && ch <= '?') continue;
        esc = 0;
        if (ch >= '@' && ch <= '~') continue;
      } else if (esc === 3) {
        esc = 0;
        if (ch >= '@' && ch <= '~') continue;
      }
      if (ch === '\u001b') { esc = 1; continue; }
      if (ch === '\u0003') { interrupted = true; break; }
      const nl = ch === '\r' || ch === '\n';
      if (ch === '\n' && lastCR) { lastCR = false; continue; }    // \r\n is one Enter
      lastCR = ch === '\r';
      if (nl) { lines.push(cur); cur = ''; } else if (ch === '\u007f' || ch === '\b') cur = cur.slice(0, -1);
      else if (ch === '\u0015') cur = '';                                      // Ctrl-U: the whole answer
      else if (ch === '\u0017') cur = cur.replace(/\s+$/, '').replace(/\S+$/, ''); // Ctrl-W: the last word
      else if (ch >= ' ') cur += ch;
    }
    if (waiting && (bad || interrupted || lines.length)) { const w = waiting; waiting = null; w(); }
  };
  stdin.setRawMode(true);
  stdin.on('data', onData);
  stdin.resume();
  const restore = () => {
    stdin.removeListener('data', onData);
    safe(() => stdin.setRawMode(false));
    stdin.pause();
  };
  process.on('exit', restore); // a last resort; every planned exit drains first
  held = {
    ask: (question) => new Promise((resolve, reject) => {
      process.stderr.write(question);
      const take = () => {
        process.stderr.write('\n');
        if (interrupted) reject(new Exit('', 130));
        else if (bad) reject(new Exit('the input is not valid UTF-8; nothing saved'));
        else resolve(lines.shift().trim());
      };
      if (bad || interrupted || lines.length) take(); else waiting = take;
    }),
    close: () => (held ? new Promise((resolve) => setTimeout(() => {
      restore(); held = null; resolve();
    }, 150)) : Promise.resolve()),
  };
  return held;
}

async function secrets(id, term) {
  const { inputs, configured } = readOptions(id);
  // Records are uploaded only under the id set now (D6), so the id comes before the endpoint.
  if (!developerOf(inputs).dev) fail('save your developer id first: /cc-usage-plugin:cc-init <developer> [team]');
  const keep = (k) => (configured.has(k) ? ' (Enter keeps the current value)' : '');
  const endpoint = await term.ask(`Receiver URL, input hidden${keep('endpoint')}: `);
  const badEndpoint = endpoint && endpointProblem(endpoint);
  if (badEndpoint) fail(`endpoint not saved: ${badEndpoint} (README § Upload contract)`);
  const token = await term.ask(`Receiver token, input hidden${keep('token')}: `);
  const badToken = token && tokenProblem(token);
  if (badToken) fail(`nothing saved: ${badToken} — retype the token rather than pasting it from a document or chat`);
  const values = {};
  if (endpoint) values.endpoint = endpoint;
  if (token) values.token = token;
  if (Object.keys(values).length) saveOptions(id, values);
  await term.close();
  if (!endpoint && !token) { out('Nothing entered; nothing changed.'); return; }
  out(`Saved ${Object.keys(values).join(' and ')} in Claude Code's secure storage. Changes apply from the next Claude Code session.`);
  if (!token && !configured.has('token')) out('No token is set yet, so uploads stay refused (no-token) until one is saved.');
  if (!endpoint && !configured.has('endpoint')) out('No endpoint is set yet, so nothing is uploaded until one is saved.');
}

async function main() {
  const a = parseArgs(process.argv.slice(2));
  const cmd = a._[0] || 'status';
  if (!['status', 'set', 'secrets'].includes(cmd)) fail(`unknown command "${cmd}" (status, set, secrets)`);
  if (a['config-dir'] !== undefined) {
    if (!a['config-dir']) fail('--config-dir takes a folder');
    process.env.CLAUDE_CONFIG_DIR = path.resolve(a['config-dir']);
  }
  if (cmd !== 'secrets') {
    const id = pluginId(a.plugin);
    if (cmd === 'status') status(id); else setIdentity(id, a);
    return;
  }
  // A pipe or a file could carry the values from a command line or a log; the terminal prompt cannot.
  if (!process.stdin.isTTY) fail('run this in a terminal: it asks for the receiver URL and token itself and reads neither from a pipe or file');
  const term = terminal(); // before anything slow, so type-ahead is not echoed while the install is looked up
  let failure = null;
  try {
    await secrets(pluginId(a.plugin), term);
  } catch (e) {
    failure = e;
  } finally {
    await term.close(); // whatever ended it, an unexpected error included
  }
  if (failure instanceof Exit) fail(failure.message, failure.code);
  if (failure) throw failure;
}

main();
