'use strict';
// Run from the repo root: node --test 'cc-usage-plugin/tests/*.test.js'
// init.js runs as a child process against a fake `claude` CLI placed first on PATH. The fake keeps the
// options in a JSON file, masks sensitive ones in `configure --json` as the real CLI does, and records
// every `--values-stdin` payload so a test can see exactly what would have been saved.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const INIT = path.join(ROOT, 'scripts', 'init.js');
const ID = 'cc-usage-plugin@acme';
const SENSITIVE = ['endpoint', 'token'];

const FAKE = `#!/usr/bin/env node
const fs = require('fs'); const path = require('path');
const dir = process.env.FAKE_CLAUDE_DIR;
const state = JSON.parse(fs.readFileSync(path.join(dir, 'state.json'), 'utf8'));
const a = process.argv.slice(2);
if (a[0] === 'plugin' && a[1] === 'list') { process.stdout.write(JSON.stringify(state.list)); process.exit(0); }
if (a[0] === 'plugin' && a[1] === 'configure') {
  if (state.fail) { process.stderr.write('boom'); process.exit(2); }
  if (a.includes('--values-stdin')) {
    const values = JSON.parse(fs.readFileSync(0, 'utf8'));
    fs.appendFileSync(path.join(dir, 'saved.jsonl'), JSON.stringify(values) + '\\n');
    Object.assign(state.options, values);
    fs.writeFileSync(path.join(dir, 'state.json'), JSON.stringify(state));
    process.stdout.write('Configuration saved. Restart Claude Code to apply it.\\n'); process.exit(0);
  }
  const keys = ['developer', 'team', 'endpoint', 'token', 'flush_hours'];
  const inputs = {}; for (const k of keys) inputs[k] = ${JSON.stringify(SENSITIVE)}.includes(k) ? '' : (state.options[k] || '');
  const configured = keys.filter((k) => k in state.options);
  process.stdout.write(JSON.stringify({ pluginId: a[2], inputs, configured, unconfigured: keys.filter((k) => !configured.includes(k)) }));
  process.exit(0);
}
process.exit(9);
`;

function setup({ options = {}, list, fail = false } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cc-init-test-'));
  const bin = path.join(dir, 'bin');
  fs.mkdirSync(bin);
  fs.writeFileSync(path.join(bin, 'claude'), FAKE, { mode: 0o755 });
  fs.writeFileSync(path.join(bin, 'claude.cmd'), '@node "%~dp0claude" %*\r\n');
  const installs = list || [{ id: ID, installPath: ROOT, scope: 'user' }];
  fs.writeFileSync(path.join(dir, 'state.json'), JSON.stringify({ list: installs, options, fail }));
  return dir;
}
function run(dir, args, input = '', extra = {}) {
  const env = { ...process.env, ...extra };
  for (const k of Object.keys(env)) if (/^(CLAUDE_PLUGIN_|CC_USAGE_)/.test(k)) delete env[k];
  Object.assign(env, extra, {
    PATH: `${path.join(dir, 'bin')}${path.delimiter}${process.env.PATH}`,
    FAKE_CLAUDE_DIR: dir,
    CLAUDE_CONFIG_DIR: path.join(dir, 'config'),
  });
  const r = spawnSync(process.execPath, [INIT, ...args], { env, input, encoding: 'utf8' });
  return { code: r.status, out: r.stdout, err: r.stderr };
}
const saved = (dir) => {
  const f = path.join(dir, 'saved.jsonl');
  return fs.existsSync(f) ? fs.readFileSync(f, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)) : [];
};
const dataDir = (dir) => path.join(dir, 'config', 'plugins', 'data', ID.replace('@', '-'));

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
  assert.ok(r.out.includes(`node "${INIT}" secrets`), 'points at this install\'s init.js for the secrets');

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

test('the install is found by its path; ambiguous or missing installs stop with a message', () => {
  let dir = setup({ list: [{ id: 'cc-usage-plugin@other', installPath: path.join(os.tmpdir(), 'x') }, { id: ID, installPath: ROOT }] });
  let r = run(dir, ['status']);
  assert.equal(r.code, 0, r.err);
  assert.match(r.out, new RegExp(`^${ID}$`, 'm'));

  dir = setup({ list: [{ id: 'cc-usage-plugin@a', installPath: '/a' }, { id: 'cc-usage-plugin@b', installPath: '/b' }] });
  r = run(dir, ['status']);
  assert.equal(r.code, 1);
  assert.match(r.err, /more than one install .*--plugin <id>/);
  r = run(dir, ['status', '--plugin', 'cc-usage-plugin@b']);
  assert.equal(r.code, 0, r.err);
  assert.match(r.out, /^cc-usage-plugin@b$/m);
  r = run(dir, ['status', '--plugin', 'cc-usage-plugin@b; rm -rf /']);
  assert.equal(r.code, 1);
  assert.match(r.err, /--plugin takes an id/);

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

  r = run(dir, ['set', '--developer', 'sam']);
  assert.equal(r.code, 0, r.err);
  assert.deepEqual(saved(dir)[1], { developer: 'sam' }, 'a team left out is not overwritten');
  assert.match(r.out, /previous id was "alex-kim"; records stamped with it stay in the local ledger/);

  dir = setup();
  r = run(dir, ['set']);
  assert.equal(r.code, 1);
  assert.match(r.err, /--developer is required/);
  r = run(dir, ['set', '--developer', 'a\nb']);
  assert.equal(r.code, 1);
  assert.deepEqual(saved(dir), []);
});

test('secrets needs the developer first, checks the endpoint and never prints what it saves', () => {
  let dir = setup();
  let r = run(dir, ['secrets'], 'https://example.com/h\ntok\n');
  assert.equal(r.code, 1);
  assert.match(r.err, /save your developer id first/);
  assert.deepEqual(saved(dir), []);

  dir = setup({ options: { developer: 'alex' } });
  r = run(dir, ['secrets'], 'http://example.com/h\ntok\n');
  assert.equal(r.code, 1);
  assert.match(r.err, /endpoint not saved: endpoint-not-https/);
  r = run(dir, ['secrets'], 'https://example.com/h?week=1\ntok\n');
  assert.match(r.err, /endpoint-has-developer-week-or-id/);
  assert.deepEqual(saved(dir), []);

  r = run(dir, ['secrets'], 'https://example.com/h?sig=SECRET1\nSECRET2\n');
  assert.equal(r.code, 0, r.err);
  assert.deepEqual(saved(dir), [{ endpoint: 'https://example.com/h?sig=SECRET1', token: 'SECRET2' }]);
  assert.match(r.out, /Saved endpoint and token in Claude Code's secure storage/);
  assert.ok(!/SECRET/.test(r.out + r.err));

  r = run(dir, ['secrets'], '\nNEWTOKEN3\n');
  assert.equal(r.code, 0, r.err);
  assert.deepEqual(saved(dir)[1], { token: 'NEWTOKEN3' }, 'an empty answer keeps the current endpoint');
  assert.ok(!/NEWTOKEN3/.test(r.out + r.err));
  r = run(dir, ['secrets'], '\n\n');
  assert.match(r.out, /Nothing entered; nothing changed/);
  assert.equal(saved(dir).length, 2);

  dir = setup({ options: { developer: 'alex' } });
  r = run(dir, ['secrets'], 'http://127.0.0.1:8080/h\n\n');
  assert.equal(r.code, 0, r.err);
  assert.deepEqual(saved(dir), [{ endpoint: 'http://127.0.0.1:8080/h' }]);
  assert.match(r.out, /No token is set yet, so uploads stay refused \(no-token\)/);
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
