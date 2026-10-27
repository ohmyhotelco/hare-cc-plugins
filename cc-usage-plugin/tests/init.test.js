'use strict';
// Run from the repo root: node --test 'cc-usage-plugin/tests/*.test.js'
// init.js runs as a child process against a fake `claude` CLI placed first on PATH. The fake keeps the
// options in a JSON file, masks sensitive ones in `configure --json` as the real CLI does, refuses
// values that are not single-line strings (the CLI's stdin contract), and records every
// `--values-stdin` payload so a test can see exactly what would have been saved. `secrets` reads only a
// terminal, so its cases run on a pseudo-terminal; they are skipped where none is available (Windows).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const INIT = path.join(ROOT, 'scripts', 'init.js');
const ID = 'cc-usage-plugin@acme';
const SENSITIVE = ['endpoint', 'token'];

const FAKE = `#!/usr/bin/env node
const fs = require('fs'); const path = require('path');
const dir = process.env.FAKE_CLAUDE_DIR;
const state = JSON.parse(fs.readFileSync(path.join(dir, 'state.json'), 'utf8'));
const a = process.argv.slice(2);
fs.appendFileSync(path.join(dir, 'config-dirs.log'), (process.env.CLAUDE_CONFIG_DIR || '-') + '\\n');
const sleep = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
if (a[0] === 'plugin' && a[1] === 'list') {
  if (state.listFail) process.exit(1);
  process.stdout.write(JSON.stringify(state.list)); process.exit(0);
}
if (a[0] === 'plugin' && a[1] === 'configure') {
  if (state.fail) { process.stderr.write('boom'); process.exit(2); }
  if (a.includes('--values-stdin')) {
    if (state.slow) sleep(500);
    const values = JSON.parse(fs.readFileSync(0, 'utf8'));
    if (Object.values(values).some((v) => typeof v !== 'string' || /[\\r\\n]/.test(v))) process.exit(3);
    fs.appendFileSync(path.join(dir, 'saved.jsonl'), JSON.stringify(values) + '\\n');
    Object.assign(state.options, values);
    fs.writeFileSync(path.join(dir, 'state.json'), JSON.stringify(state));
    process.stdout.write('Configuration saved. Restart Claude Code to apply it.\\n'); process.exit(0);
  }
  if (state.slowRead) sleep(700);
  const keys = ['developer', 'team', 'endpoint', 'token', 'flush_hours'];
  const inputs = {}; for (const k of keys) inputs[k] = ${JSON.stringify(SENSITIVE)}.includes(k) ? '' : (state.options[k] || '');
  const configured = keys.filter((k) => k in state.options);
  process.stdout.write(JSON.stringify({ pluginId: a[2], inputs, configured: state.badConfigured ? 5 : configured, unconfigured: keys.filter((k) => !configured.includes(k)) }));
  process.exit(0);
}
process.exit(9);
`;

function setup({ options = {}, list, fail = false, slow = false, slowRead = false, listFail = false, badConfigured = false } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-init-test-'));
  const bin = path.join(dir, 'bin');
  fs.mkdirSync(bin);
  fs.writeFileSync(path.join(bin, 'claude'), FAKE, { mode: 0o755 });
  fs.writeFileSync(path.join(bin, 'claude.cmd'), '@node "%~dp0claude" %*\r\n');
  const installs = list || [{ id: ID, installPath: ROOT, scope: 'user' }];
  fs.writeFileSync(path.join(dir, 'state.json'), JSON.stringify({ list: installs, options, fail, slow, slowRead, listFail, badConfigured }));
  return dir;
}
function envFor(dir, extra = {}) {
  const env = { ...process.env };
  for (const k of Object.keys(env)) if (/^(CLAUDE_PLUGIN_|CC_USAGE_)/.test(k)) delete env[k];
  const out = {
    ...env, CLAUDE_CONFIG_DIR: path.join(dir, 'config'), ...extra,
    PATH: `${path.join(dir, 'bin')}${path.delimiter}${process.env.PATH}`,
    FAKE_CLAUDE_DIR: dir,
  };
  for (const [k, v] of Object.entries(out)) if (v === null) delete out[k]; // null in extra removes a variable
  return out;
}
function run(dir, args, input = '', extra = {}) {
  const r = spawnSync(process.execPath, [INIT, ...args], { env: envFor(dir, extra), input, encoding: 'utf8' });
  return { code: r.status, out: r.stdout, err: r.stderr };
}

// The pseudo-terminal comes from Python's pty module (python3 is already this repository's tool for
// scripts/check-plugin-consistency.py); script(1) on macOS refuses a socket or FIFO as its stdin.
const PTY_PY = 'import os,pty,sys\nsys.exit(os.waitstatus_to_exitcode(pty.spawn(sys.argv[1:])))';
const PTY = process.platform !== 'win32' && spawnSync('python3', ['-I', '-c', 'import pty, os; os.waitstatus_to_exitcode']).status === 0;
// After init.js, a shell reads one more line from the same terminal and shows it: whatever init.js
// left unread would reach a person's shell the same way.
const THEN_READ = 'node "$0" "$@"; echo "--exit:$?--"; IFS= read -r rest; printf "LEFTOVER:[%s]\\n" "$rest"';
// Runs init.js on a pseudo-terminal. Each step waits until its prompt has appeared on the terminal,
// then types its parts (a string or Buffer each), 120 ms apart. `out` is everything the terminal showed.
function onTerminal(dir, args, steps, { thenRead = false, env: extra = {} } = {}) {
  return new Promise((resolve) => {
    const argv = thenRead ? ['sh', '-c', THEN_READ, INIT, ...args] : [process.execPath, INIT, ...args];
    const p = spawn('python3', ['-I', '-c', PTY_PY, ...argv], { env: envFor(dir, extra) });
    let shown = '', pos = 0, i = 0, busy = false;
    const next = () => {
      if (busy || i >= steps.length) return;
      const m = steps[i].after.exec(shown.slice(pos));
      if (!m) return;
      pos += m.index + m[0].length;
      const parts = [].concat(steps[i++].type);
      busy = true;
      parts.forEach((part, k) => setTimeout(() => p.stdin.write(part), 60 + k * 120));
      setTimeout(() => { busy = false; next(); }, 60 + parts.length * 120);
    };
    p.stdout.on('data', (d) => { shown += d; next(); });
    setTimeout(next, 300); // a step that waits for nothing types while init.js is still starting
    const timer = setTimeout(() => p.kill(), 20e3);
    p.on('close', (code) => { clearTimeout(timer); resolve({ code, out: shown }); });
  });
}
const URL_PROMPT = /Receiver URL, input hidden[^:]*: /;
const TOKEN_PROMPT = /Receiver token, input hidden[^:]*: /;
const tty = { skip: !PTY && 'needs python3 (pty module) for a pseudo-terminal' };

const saved = (dir) => {
  const f = path.join(dir, 'saved.jsonl');
  return fs.existsSync(f) ? fs.readFileSync(f, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)) : [];
};
const dataDir = (dir) => path.join(dir, 'config', 'plugins', 'data', ID.replace('@', '-'));
// A path as init.js prints it in a command: one shell word.
const q = (s) => (process.platform === 'win32' ? `"${s}"` : `'${s}'`);

test('status reports each option, hides sensitive values and names the next step', () => {
  let dir = setup();
  let r = run(dir, ['status']);
  assert.equal(r.code, 0, r.err);
  assert.match(r.out, /developer +not set/);
  assert.match(r.out, /endpoint +not set/);
  assert.match(r.out, /last record +none yet/);
  assert.match(r.out, /Next: save your developer id — \/cc-usage-plugin:cc-init/);

  dir = setup({ options: { developer: 'Alex Kim', team: 'platform' } });
  r = run(dir, ['status']);
  assert.match(r.out, /developer +Alex Kim +\(uploads as "alex-kim"\)/);
  assert.match(r.out, /team +platform/);
  assert.ok(r.out.includes(`node ${q(INIT)} secrets --plugin ${ID} --config-dir ${q(path.join(dir, 'config'))}`),
    'points at this install\'s init.js, with its id and configuration folder');

  dir = setup({ options: { developer: 'alex', endpoint: 'https://example.com/h?sig=SECRET1', token: 'SECRET2' } });
  r = run(dir, ['status']);
  assert.match(r.out, /endpoint +saved \(value hidden\)/);
  assert.match(r.out, /token +saved \(value hidden\)/);
  assert.match(r.out, /All options are set/);
  assert.ok(!/SECRET/.test(r.out + r.err));
});

test('status reads the hooks\' data folder of this install, not CLAUDE_PLUGIN_DATA', () => {
  const dir = setup({ options: { developer: 'alex' } });
  const d = dataDir(dir);
  fs.mkdirSync(path.join(d, 'ledger'), { recursive: true });
  fs.mkdirSync(path.join(d, 'state'), { recursive: true });
  fs.mkdirSync(path.join(d, 'send'), { recursive: true });
  fs.writeFileSync(path.join(d, 'ledger', '2026-W44.jsonl'),
    `${JSON.stringify({ ts: '2026-10-27T01:00:00Z', kind: 'session_open', developer: 'alex', plugin: '0.1.8' })}\n`);
  fs.writeFileSync(path.join(d, 'send', '1-2026-W44-0.ndjson'), '{}\n');
  fs.writeFileSync(path.join(d, 'state', '_send.json'), JSON.stringify({ gen: 'g', offsets: {}, last_ok: 0, fails: 0, next_try: 0, auth_block: 'k' }));
  fs.writeFileSync(path.join(d, 'errors.log'), '2026-10-27T01:00:01Z Stop upload 401\n');
  const other = path.join(dir, 'other-plugin-data');
  const r = run(dir, ['status'], '', { CLAUDE_PLUGIN_DATA: other });
  assert.equal(r.code, 0, r.err);
  assert.match(r.out, /last record +2026-10-27T01:00:00Z session_open, developer "alex", plugin 0\.1\.8/);
  assert.match(r.out, /uploads +stopped by 401 until the endpoint or token changes; .*1 batch\(es\) waiting/);
  assert.match(r.out, /errors\.log +2026-10-27T01:00:01Z Stop upload 401/);
});

test('the install is found by its path; ambiguous, missing or malformed installs stop with a message', () => {
  let dir = setup({ list: [{ id: 'cc-usage-plugin@other', installPath: path.join(os.tmpdir(), 'x') }, { id: ID, installPath: ROOT }] });
  let r = run(dir, ['status']);
  assert.equal(r.code, 0, r.err);
  assert.match(r.out, new RegExp(`^${ID}$`, 'm'));

  dir = setup({ options: { developer: 'alex' }, list: [{ id: 'cc-usage-plugin@a', installPath: '/a' }, { id: 'cc-usage-plugin@b', installPath: '/b' }] });
  r = run(dir, ['status']);
  assert.equal(r.code, 1);
  assert.match(r.err, /more than one install .*--plugin <id>/);
  r = run(dir, ['status', '--plugin', 'cc-usage-plugin@b']);
  assert.equal(r.code, 0, r.err);
  assert.match(r.out, /^cc-usage-plugin@b$/m);
  assert.match(r.out, /secrets --plugin cc-usage-plugin@b --config-dir ['"][^'"]+['"]$/m, 'the printed command keeps the chosen install');
  r = run(dir, ['status', '--plugin', 'cc-usage-plugin@b; rm -rf /']);
  assert.equal(r.code, 1);
  assert.match(r.err, /--plugin takes an id/);

  dir = setup({ list: [{ id: 'cc-usage-plugin@acme&echo x', installPath: ROOT }] });
  r = run(dir, ['status']);
  assert.equal(r.code, 1);
  assert.match(r.err, /installed plugin id is not of the form/);

  dir = setup({ list: [{ id: 'other-plugin@acme', installPath: '/o' }] });
  r = run(dir, ['status']);
  assert.equal(r.code, 1);
  assert.match(r.err, /not installed from a marketplace.*CC_USAGE_\*/);
});

test('set saves the normalized developer id and the team, and warns when the id changes', () => {
  let dir = setup();
  let r = run(dir, ['set', '--developer', 'Alex Kim', '--team', 'platform']);
  assert.equal(r.code, 0, r.err);
  assert.deepEqual(saved(dir), [{ developer: 'alex-kim', team: 'platform' }]);
  assert.match(r.out, /Saved developer "alex-kim" \(from "Alex Kim"\) and team "platform"/);
  assert.match(r.out, /next Claude Code session/);
  assert.match(r.out, /secrets --plugin cc-usage-plugin@acme --config-dir ['"][^'"]+['"]$/m);

  r = run(dir, ['set', '--developer', 'sam']);
  assert.equal(r.code, 0, r.err);
  assert.deepEqual(saved(dir)[1], { developer: 'sam' }, 'a team left out is not overwritten');
  assert.match(r.out, /previous id was "alex-kim"; records stamped with it stay in the local ledger/);

  r = run(dir, ['set', 'pat', 'data']);
  assert.equal(r.code, 0, r.err);
  assert.deepEqual(saved(dir)[2], { developer: 'pat', team: 'data' }, 'positional developer and team');

  dir = setup();
  r = run(dir, ['set']);
  assert.equal(r.code, 1);
  assert.match(r.err, /--developer or --team is required/);
  for (const args of [['set', '--developer', 'a\nb'], ['set', 'alex', 'one\ntwo'], ['set', '--developer', 'alex', '--team', 'x\ry']]) {
    r = run(dir, args);
    assert.equal(r.code, 1, args.join(' '));
    assert.match(r.err, /single-line/);
  }
  assert.deepEqual(saved(dir), []);
});

test('secrets refuses input that does not come from a terminal', () => {
  const dir = setup({ options: { developer: 'alex' } });
  const r = run(dir, ['secrets'], 'https://example.com/h\nSECRET2\n');
  assert.equal(r.code, 1);
  assert.match(r.err, /run this in a terminal/);
  assert.deepEqual(saved(dir), []);
});

test('secrets needs the developer id first and checks the endpoint before saving anything', tty, async () => {
  let dir = setup();
  let r = await onTerminal(dir, ['secrets'], []);
  assert.equal(r.code, 1);
  assert.match(r.out, /save your developer id first/);

  dir = setup({ options: { developer: 'alex' } });
  r = await onTerminal(dir, ['secrets'], [{ after: URL_PROMPT, type: 'http://example.com/hSECRET1\r' }]);
  assert.equal(r.code, 1);
  assert.match(r.out, /endpoint not saved: endpoint-not-https/);
  r = await onTerminal(dir, ['secrets'], [{ after: URL_PROMPT, type: 'https://example.com/h?week=1&s=SECRET1\r' }]);
  assert.match(r.out, /endpoint-has-developer-week-or-id/);
  assert.ok(!/SECRET/.test(r.out), 'the refused URL is not echoed');
  assert.deepEqual(saved(dir), []);
});

test('secrets saves what is typed without echo, including a late paste', tty, async () => {
  const dir = setup({ options: { developer: 'alex' } });
  let r = await onTerminal(dir, ['secrets'], [
    { after: URL_PROMPT, type: 'https://example.com/h?sig=SECRET1\r' },
    { after: TOKEN_PROMPT, type: ['SECRET2\r', 'SECRET3LATE'] },
  ]);
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(saved(dir), [{ endpoint: 'https://example.com/h?sig=SECRET1', token: 'SECRET2' }]);
  assert.match(r.out, /Saved endpoint and token in Claude Code's secure storage/);
  assert.ok(!/SECRET/.test(r.out), 'nothing typed appears on the terminal');

  r = await onTerminal(dir, ['secrets'], [
    { after: /Receiver URL, input hidden \(Enter keeps the current value\): /, type: '\r' },
    { after: TOKEN_PROMPT, type: 'SECRET4\r' },
  ]);
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(saved(dir)[1], { token: 'SECRET4' }, 'an empty answer keeps the current endpoint');
  r = await onTerminal(dir, ['secrets'], [{ after: URL_PROMPT, type: '\r' }, { after: TOKEN_PROMPT, type: '\r' }]);
  assert.match(r.out, /Nothing entered; nothing changed/);
  assert.equal(saved(dir).length, 2);
  assert.ok(!/SECRET/.test(r.out));
});

test('input that arrives while the values are saved is read and dropped, not left for the shell', tty, async () => {
  const dir = setup({ options: { developer: 'alex' }, slow: true });
  const r = await onTerminal(dir, ['secrets'], [
    { after: URL_PROMPT, type: 'https://example.com/h\r' },
    { after: TOKEN_PROMPT, type: ['SECRET2\r', 'SECRET3LATE'] },
    { after: /Saved endpoint and token/, type: '\r' },
  ], { thenRead: true });
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(saved(dir), [{ endpoint: 'https://example.com/h', token: 'SECRET2' }]);
  assert.match(r.out, /LEFTOVER:\[\]/);
  assert.ok(!/SECRET/.test(r.out));
});

test('secrets reads a pasted pair of lines, drops escape sequences across reads and refuses bad UTF-8', tty, async () => {
  let dir = setup({ options: { developer: 'alex' } });
  let r = await onTerminal(dir, ['secrets'], [{ after: URL_PROMPT, type: 'https://example.com/a\r\nSECRET5\r' }]);
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(saved(dir), [{ endpoint: 'https://example.com/a', token: 'SECRET5' }]);

  dir = setup({ options: { developer: 'alex' } });
  r = await onTerminal(dir, ['secrets'], [
    { after: URL_PROMPT, type: '\r' },
    { after: TOKEN_PROMPT, type: ['tok\u001b[', 'Dxy\u001bOAz\r'] },
  ]);
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(saved(dir), [{ token: 'tokxyz' }]);

  dir = setup({ options: { developer: 'alex' } });
  r = await onTerminal(dir, ['secrets'], [{ after: URL_PROMPT, type: '\r' }, { after: TOKEN_PROMPT, type: Buffer.from([0x74, 0xff, 0x6b, 0x0d]) }]);
  assert.equal(r.code, 1);
  assert.match(r.out, /not valid UTF-8; nothing saved/);
  assert.deepEqual(saved(dir), []);

  r = await onTerminal(dir, ['secrets'], [{ after: URL_PROMPT, type: 'https://example.com/SECRET6\u0003' }]);
  assert.equal(r.code, 130);
  assert.deepEqual(saved(dir), []);
  assert.ok(!/SECRET/.test(r.out));
});

test('--config-dir reaches the CLI, the data folder and the printed command; a missing CLI says so', () => {
  let dir = setup({ options: { developer: 'alex' } });
  const other = path.join(dir, 'other-config');
  const d = path.join(other, 'plugins', 'data', 'cc-usage-plugin-acme', 'ledger');
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(d, '2026-W44.jsonl'), `${JSON.stringify({ ts: '2026-10-27T02:00:00Z', kind: 'prompt', developer: 'alex', plugin: '0.1.8' })}\n`);
  let r = run(dir, ['status', '--config-dir', other], '', { CLAUDE_CONFIG_DIR: null });
  assert.equal(r.code, 0, r.err);
  assert.deepEqual([...new Set(fs.readFileSync(path.join(dir, 'config-dirs.log'), 'utf8').trim().split('\n'))], [other]);
  assert.match(r.out, /last record +2026-10-27T02:00:00Z prompt/);
  assert.ok(r.out.includes(`--config-dir ${q(other)}`));
  r = run(dir, ['status'], '', { CLAUDE_CONFIG_DIR: null, HOME: dir, USERPROFILE: dir });
  assert.ok(!r.out.includes('--config-dir'), 'the default folder needs no flag');

  dir = setup({ listFail: true });
  r = run(dir, ['status']);
  assert.equal(r.code, 1);
  assert.match(r.err, /claude plugin list exited 1; is Claude Code on PATH\?/);
});

test('status reads a data folder whose name had other characters replaced, week files only, and shows a refused configuration', () => {
  const id = 'cc-usage-plugin@acme.tools';
  const dir = setup({ options: { developer: 'alex' }, list: [{ id, installPath: ROOT }] });
  const d = path.join(dir, 'config', 'plugins', 'data', 'cc-usage-plugin-acme-tools');
  fs.mkdirSync(path.join(d, 'ledger'), { recursive: true });
  fs.mkdirSync(path.join(d, 'state'), { recursive: true });
  fs.writeFileSync(path.join(d, 'ledger', '2026-W44.jsonl'), `${JSON.stringify({ ts: '2026-10-27T03:00:00Z', kind: 'usage', developer: 'alex', plugin: '0.1.8' })}\n`);
  fs.writeFileSync(path.join(d, 'ledger', 'notes.jsonl'), `${JSON.stringify({ ts: '1999-01-01T00:00:00Z', kind: 'stray' })}\n`);
  fs.writeFileSync(path.join(d, 'state', '_send.json'), JSON.stringify({ gen: 'g', offsets: {}, last_ok: 0, fails: 0, next_try: 0, auth_block: null, config_block: 'k' }));
  fs.writeFileSync(path.join(d, 'errors.log'), ['x Stop upload refused: endpoint-not-https', 'x Stop upload network', 'x Stop upload network', 'x Stop upload network'].join('\n') + '\n');
  const r = run(dir, ['status']);
  assert.equal(r.code, 0, r.err);
  assert.match(r.out, /last record +2026-10-27T03:00:00Z usage/);
  assert.match(r.out, /uploads +refused by the configuration \(endpoint-not-https\)/, 'the reason survives later log lines');
});

test('an error or Ctrl-C after the terminal is taken drains what was typed: nothing is shown or left for the shell', tty, async () => {
  let dir = setup({ slowRead: true }); // no developer id: refused after a slow options load
  let r = await onTerminal(dir, ['secrets'], [
    { after: /(?:)/, type: 'https://example.com/SECRET8\r' },
    { after: /--exit:\d+--/, type: '\r' },
  ], { thenRead: true });
  assert.match(r.out, /save your developer id first/);
  assert.match(r.out, /--exit:1--/);
  assert.match(r.out, /LEFTOVER:\[\]/);
  assert.ok(!/SECRET/.test(r.out), 'typed during the load, not echoed when the error gave the terminal back');

  dir = setup({ options: { developer: 'alex' } });
  r = await onTerminal(dir, ['secrets'], [
    { after: URL_PROMPT, type: ['https://example.com/SECRET9\u0003', 'SECRET10'] },
    { after: /--exit:\d+--/, type: '\r' },
  ], { thenRead: true });
  assert.match(r.out, /--exit:130--/);
  assert.match(r.out, /LEFTOVER:\[\]/);
  assert.ok(!/SECRET/.test(r.out));
  assert.deepEqual(saved(dir), []);
});

test('secrets refuses a token a header cannot carry', tty, async () => {
  const dir = setup({ options: { developer: 'alex' } });
  const r = await onTerminal(dir, ['secrets'], [
    { after: URL_PROMPT, type: 'https://example.com/h\r' },
    { after: TOKEN_PROMPT, type: 'tok\u200bSECRET11\r' },
  ]);
  assert.equal(r.code, 1);
  assert.match(r.out, /nothing saved: token-not-visible-ascii/);
  assert.deepEqual(saved(dir), []);
  assert.ok(!/SECRET/.test(r.out));
});

test('set changes the team alone; status and secrets accept a developer id from CC_USAGE_DEVELOPER', tty, async () => {
  let dir = setup({ options: { developer: 'alex', team: 'old' }, list: [null, { id: ID, installPath: ROOT }] });
  let r = run(dir, ['set', '--plugin', ID, '--team', 'platform']);
  assert.equal(r.code, 0, r.err);
  assert.deepEqual(saved(dir), [{ team: 'platform' }]);
  assert.match(r.out, /Saved team "platform"\. The developer id stays "alex"\./);
  r = run(dir, ['set', '--plugin', ID]);
  assert.equal(r.code, 1);
  assert.match(r.err, /--developer or --team is required/);
  r = run(dir, ['status']); // a null entry in the install list is skipped
  assert.equal(r.code, 0, r.err);

  dir = setup();
  r = run(dir, ['status'], '', { CC_USAGE_DEVELOPER: 'Env Dev' });
  assert.match(r.out, /developer +Env Dev +\(uploads as "env-dev", from CC_USAGE_DEVELOPER\)/);
  assert.match(r.out, /Next, in a terminal/);
  r = await onTerminal(dir, ['secrets'], [{ after: URL_PROMPT, type: '\r' }, { after: TOKEN_PROMPT, type: '\r' }], { env: { CC_USAGE_DEVELOPER: 'env-dev' } });
  assert.equal(r.code, 0, r.out);
  assert.match(r.out, /Nothing entered/);
});

test('editing keys: a lone Esc keeps the next key, Enter and Ctrl-C end an escape sequence, Ctrl-U and Ctrl-W erase', tty, async () => {
  let dir = setup({ options: { developer: 'alex' } });
  let r = await onTerminal(dir, ['secrets'], [
    { after: URL_PROMPT, type: '\r' },
    { after: TOKEN_PROMPT, type: ['\u001b', 'abcdef\r'] },
  ]);
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(saved(dir), [{ token: 'abcdef' }]);

  dir = setup({ options: { developer: 'alex' } });
  r = await onTerminal(dir, ['secrets'], [
    { after: URL_PROMPT, type: '\r' },
    { after: TOKEN_PROMPT, type: 'wrong tok\u0017ok\r' },
  ]);
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(saved(dir), [{ token: 'wrong ok' }], 'Ctrl-W erases the last word');

  dir = setup({ options: { developer: 'alex' } });
  r = await onTerminal(dir, ['secrets'], [
    { after: URL_PROMPT, type: '\r' },
    { after: TOKEN_PROMPT, type: 'mistake\u0015right\u001b[1\r' },
  ]);
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(saved(dir), [{ token: 'right' }], 'Ctrl-U erases the answer; Enter ends an unfinished sequence');

  dir = setup({ options: { developer: 'alex' } });
  r = await onTerminal(dir, ['secrets'], [{ after: URL_PROMPT, type: ['\u001b', '\u0003', 'x\r'] }]);
  assert.equal(r.code, 130, r.out);
  assert.deepEqual(saved(dir), []);
});

test('an unexpected error after the terminal is taken still drains what was typed', tty, async () => {
  const dir = setup({ options: { developer: 'alex' }, slowRead: true, badConfigured: true });
  const r = await onTerminal(dir, ['secrets'], [
    { after: /(?:)/, type: 'https://example.com/SECRET12\r' },
    { after: /--exit:\d+--/, type: '\r' },
  ], { thenRead: true });
  assert.doesNotMatch(r.out, /--exit:0--/);
  assert.match(r.out, /LEFTOVER:\[\]/);
  assert.ok(!/SECRET/.test(r.out));
});

test('a failing claude CLI stops with its exit status and nothing else', () => {
  const dir = setup({ options: { developer: 'alex' }, fail: true });
  const r = run(dir, ['set', '--developer', 'alex']);
  assert.equal(r.code, 1);
  assert.match(r.err, /could not read the options of cc-usage-plugin@acme \(claude plugin configure exited 2\)/);
  assert.ok(!/boom/.test(r.err), 'the CLI\'s own stderr is not passed on');
  const u = run(dir, ['nope']);
  assert.equal(u.code, 1);
  assert.match(u.err, /unknown command "nope"/);
});
