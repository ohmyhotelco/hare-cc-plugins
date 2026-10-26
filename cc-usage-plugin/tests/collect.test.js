'use strict';
// Run from the repo root: node --test cc-usage-plugin/tests/collect.test.js
// Each test runs the real hook script as a child process against a local receiver on 127.0.0.1.
// The timeout test waits for the 15 s request timeout, so the whole file takes about 20 s.
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, execFileSync } = require('node:child_process');

const ROOT = path.join(__dirname, '..');
const COLLECT = path.join(ROOT, 'scripts', 'collect.js');
const REPORT = path.join(ROOT, 'scripts', 'report.js');

function isoWeek(d) {
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const day = t.getUTCDay() || 7; t.setUTCDate(t.getUTCDate() + 4 - day);
  const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  return `${t.getUTCFullYear()}-W${String(Math.ceil((((t - y0) / 864e5) + 1) / 7)).padStart(2, '0')}`;
}

function tmp() { return fs.mkdtempSync(path.join(os.tmpdir(), 'cc-usage-test-')); }
function env(dir, extra = {}) {
  const out = {};
  for (const [k, v] of Object.entries(process.env)) if (!/^(CLAUDE_PLUGIN_|CC_USAGE_)/.test(k)) out[k] = v;
  // HOME points at the temp dir so identity() never reads the tester's own account file.
  return { ...out, CLAUDE_PLUGIN_DATA: path.join(dir, 'data'), HOME: dir, USERPROFILE: dir, ...extra };
}
function run(dir, event, input = {}, extra = {}) {
  return new Promise((resolve) => {
    const p = spawn(process.execPath, [COLLECT, event], { env: env(dir, extra) });
    let out = '';
    p.stdout.on('data', (d) => { out += d; });
    p.on('close', (code) => resolve({ code, out }));
    p.stdin.end(JSON.stringify(input));
  });
}
const data = (dir, ...p) => path.join(dir, 'data', ...p);
const sendState = (dir) => JSON.parse(fs.readFileSync(data(dir, 'state', '_send.json'), 'utf8'));
const pending = (dir) => fs.readdirSync(data(dir, 'send')).filter((f) => f.endsWith('.ndjson'));
const lines = (text) => text.split('\n').filter(Boolean).map((l) => JSON.parse(l));
const ledger = (dir) => fs.readdirSync(data(dir, 'ledger')).sort().map((f) => fs.readFileSync(data(dir, 'ledger', f), 'utf8')).join('');
function patchState(dir, patch) {
  const file = data(dir, 'state', '_send.json');
  fs.writeFileSync(file, JSON.stringify({ ...sendState(dir), ...patch }));
}
function appendLedger(dir, rec) {
  fs.appendFileSync(data(dir, 'ledger', `${isoWeek(new Date(rec.ts))}.jsonl`), JSON.stringify(rec) + '\n');
}

// Answers every POST with the current mode: a status code, or 'hang' (never answers).
function receiver() {
  const reqs = []; const sockets = new Set();
  let mode = 202, delay = 0;
  const server = http.createServer((req, res) => {
    let body = ''; req.setEncoding('utf8');
    req.on('data', (c) => { body += c; });
    req.on('end', () => {
      reqs.push({ url: new URL(req.url, 'http://receiver'), headers: req.headers, body });
      if (mode === 'hang') return;
      const status = mode;
      setTimeout(() => { res.statusCode = status; res.end(); }, delay);
    });
  });
  server.on('connection', (s) => { sockets.add(s); s.on('close', () => sockets.delete(s)); });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve({
    url: `http://127.0.0.1:${server.address().port}/hook?sig=example`,
    reqs,
    set(m, d = 0) { mode = m; delay = d; },
    close() { for (const s of sockets) s.destroy(); return new Promise((r) => server.close(r)); },
  })));
}
const upload = (r, token = 'tok-1', developer = 'alex') => ({ CC_USAGE_ENDPOINT: r.url, CC_USAGE_TOKEN: token, CC_USAGE_DEVELOPER: developer });

test('uploads the ledger with X-Webhook-Token only, keeps the URL query, and empties send/ on 202', async () => {
  const dir = tmp(); const r = await receiver();
  try {
    const e = upload(r, '  tok-1  ', 'Alex Kim');
    for (const [ev, input] of [['SessionStart', { session_id: 's1', cwd: dir }], ['UserPromptSubmit', { session_id: 's1', prompt: '/review now' }], ['Stop', { session_id: 's1' }]]) {
      const res = await run(dir, ev, input, e);
      assert.equal(res.code, 0); assert.equal(res.out, '', 'hooks print nothing');
    }
    assert.equal(r.reqs.length, 1);
    const [q] = r.reqs;
    assert.equal(q.headers['x-webhook-token'], 'tok-1', 'token is trimmed');
    assert.equal(q.headers.authorization, undefined);
    assert.equal(q.headers['content-type'], 'application/x-ndjson');
    const recs = lines(q.body);
    assert.equal(q.url.searchParams.get('sig'), 'example', 'existing query kept');
    assert.equal(q.url.searchParams.get('developer'), 'alex-kim');
    assert.equal(q.url.searchParams.get('week'), isoWeek(new Date(recs[0].ts)));
    assert.equal(q.url.searchParams.get('id'), recs[0].id);
    assert.equal(q.body, ledger(dir), 'body is the ledger lines unchanged');
    assert.ok(q.body.endsWith('\n'));
    assert.ok(recs.every((x) => x.developer === 'alex-kim'));
    assert.deepEqual(pending(dir), []);
    assert.ok(sendState(dir).last_ok > 0);
    assert.ok(!fs.existsSync(data(dir, 'outbox.jsonl')));
  } finally { await r.close(); }
});

test('cuts one batch per ISO week and per developer, oldest week first', async () => {
  const dir = tmp(); const r = await receiver();
  try {
    const e = upload(r);
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, e);
    const old = new Date(Date.now() - 21 * 864e5).toISOString();
    appendLedger(dir, { id: 'old-1', kind: 'prompt', ts: old, developer: 'alex' });
    appendLedger(dir, { id: 'old-2', kind: 'prompt', ts: old, developer: 'alex' });
    appendLedger(dir, { id: 'sam-1', kind: 'prompt', ts: new Date().toISOString(), developer: 'Sam' });
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.equal(r.reqs.length, 3);
    for (const q of r.reqs) {
      const recs = lines(q.body);
      const week = q.url.searchParams.get('week'), dev = q.url.searchParams.get('developer');
      assert.ok(recs.every((x) => isoWeek(new Date(x.ts)) === week), 'one week per batch');
      assert.ok(recs.every((x) => x.developer.toLowerCase() === dev), 'one developer per batch');
      assert.equal(q.url.searchParams.get('id'), recs[0].id);
    }
    assert.equal(r.reqs[0].url.searchParams.get('week'), isoWeek(new Date(old)));
    assert.deepEqual(r.reqs.map((q) => q.url.searchParams.get('developer')).slice(1).sort(), ['alex', 'sam']);
  } finally { await r.close(); }
});

test('401 stops uploads until the token changes, then the same batch is resent unchanged', async () => {
  const dir = tmp(); const r = await receiver();
  try {
    r.set(401);
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, upload(r, 'wrong'));
    await run(dir, 'Stop', { session_id: 's1' }, upload(r, 'wrong'));
    assert.equal(r.reqs.length, 1);
    assert.equal(pending(dir).length, 1);
    assert.ok(sendState(dir).auth_block);
    await run(dir, 'Stop', { session_id: 's1' }, upload(r, 'wrong'));
    assert.equal(r.reqs.length, 1, 'no retry with the same token');
    const log = fs.readFileSync(data(dir, 'errors.log'), 'utf8');
    assert.match(log, /upload 401/);
    assert.ok(!log.includes('sig=example') && !log.includes('wrong'), 'log carries no URL or token');
    r.set(202);
    await run(dir, 'Stop', { session_id: 's1' }, upload(r, 'tok-2'));
    assert.equal(r.reqs.length, 2);
    assert.equal(r.reqs[1].body, r.reqs[0].body);
    assert.equal(r.reqs[1].url.search, r.reqs[0].url.search);
    assert.equal(r.reqs[1].headers['x-webhook-token'], 'tok-2');
    assert.deepEqual(pending(dir), []);
    assert.equal(sendState(dir).auth_block, null);
  } finally { await r.close(); }
});

test('a timeout keeps the batch; retries wait 30 min, doubling to a 6 h cap, and resend it unchanged', async () => {
  const dir = tmp(); const r = await receiver();
  try {
    const e = upload(r);
    r.set('hang');
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, e);
    const t0 = Date.now();
    await run(dir, 'Stop', { session_id: 's1' }, e);
    const took = Date.now() - t0;
    assert.ok(took >= 14e3 && took < 25e3, `gave up after the 15 s timeout (${took} ms)`);
    let st = sendState(dir);
    assert.equal(st.fails, 1);
    assert.ok(Math.abs(st.next_try - Date.now() - 30 * 60e3) < 60e3);
    assert.equal(pending(dir).length, 1);
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.equal(r.reqs.length, 1, 'nothing before next_try');
    r.set(500); patchState(dir, { next_try: 0 });
    await run(dir, 'Stop', { session_id: 's1' }, e);
    st = sendState(dir);
    assert.equal(st.fails, 2);
    assert.ok(Math.abs(st.next_try - Date.now() - 60 * 60e3) < 60e3);
    patchState(dir, { next_try: 0, fails: 8 });
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.ok(Math.abs(sendState(dir).next_try - Date.now() - 6 * 3600e3) < 60e3, '6 h cap');
    r.set(202); patchState(dir, { next_try: 0 });
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.equal(r.reqs.length, 4);
    assert.ok(r.reqs.every((q) => q.body === r.reqs[0].body && q.url.search === r.reqs[0].url.search));
    assert.deepEqual(pending(dir), []);
    assert.equal(sendState(dir).fails, 0);
  } finally { await r.close(); }
});

test('no upload before flush_hours unless 64 KB are waiting', async () => {
  const dir = tmp(); const r = await receiver();
  try {
    const e = upload(r);
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, e);
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.equal(r.reqs.length, 1);
    await run(dir, 'UserPromptSubmit', { session_id: 's1', prompt: 'hello' }, e);
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.equal(r.reqs.length, 1, 'small batch waits for flush_hours');
    const now = new Date().toISOString();
    for (let i = 0; i < 400; i++) appendLedger(dir, { id: `bulk-${i}`, kind: 'prompt', ts: now, developer: 'alex', pad: 'x'.repeat(200) });
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.equal(r.reqs.length, 2);
    assert.equal(lines(r.reqs[1].body).length, 401);
  } finally { await r.close(); }
});

test('records written before an endpoint is configured are never uploaded', async () => {
  const dir = tmp(); const r = await receiver();
  try {
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, { CC_USAGE_DEVELOPER: 'alex' });
    const e = upload(r);
    await run(dir, 'UserPromptSubmit', { session_id: 's1', prompt: 'hello' }, e);
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.equal(r.reqs.length, 1);
    assert.deepEqual(lines(r.reqs[0].body).map((x) => x.kind), ['prompt']);
  } finally { await r.close(); }
});

test('two Stop hooks at once upload each record once', async () => {
  const dir = tmp(); const r = await receiver();
  try {
    const e = upload(r);
    r.set(202, 1000);
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, e);
    await Promise.all([run(dir, 'Stop', { session_id: 's1' }, e), run(dir, 'Stop', { session_id: 's2' }, e)]);
    assert.equal(r.reqs.length, 1);
    assert.equal(r.reqs[0].body, ledger(dir));
  } finally { await r.close(); }
});

test('usage from one transcript counts once when Stop and SessionEnd overlap', async () => {
  const dir = tmp();
  const tr = path.join(dir, 's1.jsonl');
  const usage = { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 };
  fs.writeFileSync(tr, ['r1', 'r2', 'r3'].map((id) => JSON.stringify({ type: 'assistant', requestId: id, message: { model: 'claude-x', usage } })).join('\n') + '\n');
  const input = { session_id: 's1', transcript_path: tr };
  await Promise.all([run(dir, 'Stop', input), run(dir, 'SessionEnd', input)]);
  const requests = lines(ledger(dir)).filter((x) => x.kind === 'usage').reduce((n, x) => n + x.requests, 0);
  assert.equal(requests, 3);
});

test('commits count authored work only; PR records need create/merge and a PR number', async () => {
  const dir = tmp();
  const repo = path.join(dir, 'repo'); fs.mkdirSync(repo);
  const git = (...a) => execFileSync('git', ['-C', repo, '-c', 'user.name=t', '-c', 'user.email=t@example.com', ...a], { env: env(dir), stdio: 'pipe' }).toString();
  git('init', '-q', '-b', 'main'); git('commit', '-q', '--allow-empty', '-m', 'init');
  git('branch', 'other'); git('switch', '-q', 'other'); git('commit', '-q', '--allow-empty', '-m', 'o1'); git('switch', '-q', 'main');
  const base = { session_id: 's1', cwd: repo };
  const bash = (command, stdout = '') => run(dir, 'PostToolUse', { ...base, tool_name: 'Bash', tool_input: { command }, tool_response: { stdout } });
  await run(dir, 'SessionStart', base);
  git('switch', '-q', 'other'); await bash('git switch other');
  git('switch', '-q', 'main'); await bash('git checkout main');
  git('commit', '-q', '--allow-empty', '-m', 'c1'); await bash('git add . && git commit -m c1');
  git('branch', 'ff'); git('switch', '-q', 'ff'); git('commit', '-q', '--allow-empty', '-m', 'f1'); git('switch', '-q', 'main');
  git('merge', '-q', '--ff-only', 'ff'); await bash('git merge ff');
  git('merge', '-q', '--no-ff', '-m', 'm1', 'other'); await bash('git merge --no-ff other');
  await bash('gh pr view 5', 'https://github.com/acme/app/pull/5\n');
  await bash('gh pr create --fill', '');
  await bash('gh pr create --fill', 'https://github.com/acme/app/pull/7\n');
  await bash('gh pr merge 7 --squash', 'Squashed and merged pull request acme/app#7 (c1)\n');
  const recs = lines(ledger(dir));
  assert.deepEqual(recs.filter((x) => x.kind === 'commit').map((x) => [x.op, x.commits]), [['commit', 1], ['merge', 1]]);
  assert.deepEqual(recs.filter((x) => x.kind === 'pr').map((x) => [x.action, x.number]), [['create', 7], ['merge', 7]]);
});

test('developer ids are path-safe and distinct', async () => {
  const cases = [['Alex Kim', 'alex-kim'], ['../x', 'x'], ['CON', 'u-con'], ['a_vti_b', 'a-vti-b'], ['홍길동', /^u-[0-9a-f]{8}$/]];
  for (const [raw, want] of cases) {
    const dir = tmp();
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, { CC_USAGE_DEVELOPER: raw });
    const got = lines(ledger(dir))[0].developer;
    if (want instanceof RegExp) assert.match(got, want); else assert.equal(got, want);
  }
});

test('report.js counts each record id once, authored commits and PR create/merge only', () => {
  const dir = tmp();
  fs.mkdirSync(data(dir, 'ledger'), { recursive: true });
  const ts = new Date().toISOString();
  const recs = [
    { id: 'u1', kind: 'usage', ts, by_model: [{ model: 'claude-x', input: 1, output: 2, cache_read: 0, cache_create: 0, requests: 1 }] },
    { id: 'c1', kind: 'commit', ts, op: 'commit', commits: 2 },
    { id: 'c2', kind: 'commit', ts, op: 'pull', commits: 9 },
    { id: 'p1', kind: 'pr', ts, action: 'create', number: 7 },
    { id: 'p2', kind: 'pr', ts, action: null, number: 5 },
  ];
  const text = recs.map((x) => JSON.stringify(x)).join('\n') + '\n';
  fs.writeFileSync(data(dir, 'ledger', `${isoWeek(new Date())}.jsonl`), text + text); // every record twice
  const out = path.join(dir, 'weekly.json');
  execFileSync(process.execPath, [REPORT, '--days', '7', '--json', out], { env: env(dir), stdio: 'pipe' });
  const s = JSON.parse(fs.readFileSync(out, 'utf8'));
  assert.equal(s.totals.requests, 1);
  assert.equal(s.commits, 2);
  assert.deepEqual(s.prs.map((p) => p.number), [7]);
});
