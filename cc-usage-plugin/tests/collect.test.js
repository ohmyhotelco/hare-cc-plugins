'use strict';
// Run from the repo root: node --test cc-usage-plugin/tests/collect.test.js
// Most tests run the real hook script as a child process, the upload tests against a local receiver on
// 127.0.0.1. The timeout test waits for the 15 s request timeout, so the whole file takes about 25 s.
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
// chmod-based cases need POSIX permissions and a user that is not root.
const NO_CHMOD = process.platform === 'win32' || (process.getuid && process.getuid() === 0);

function isoWeek(d) {
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const day = t.getUTCDay() || 7; t.setUTCDate(t.getUTCDate() + 4 - day);
  const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  return `${t.getUTCFullYear()}-W${String(Math.ceil((((t - y0) / 864e5) + 1) / 7)).padStart(2, '0')}`;
}

function tmp() { return fs.mkdtempSync(path.join(os.tmpdir(), 'cc-usage-test-')); }
function env(dir, extra = {}) {
  const out = {};
  for (const [k, v] of Object.entries(process.env)) if (!/^(CLAUDE_PLUGIN_|CC_USAGE_|CLAUDE_CONFIG_DIR$)/.test(k)) out[k] = v;
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
const errors = (dir) => (fs.existsSync(data(dir, 'errors.log')) ? fs.readFileSync(data(dir, 'errors.log'), 'utf8') : '');
const count = (text, needle) => text.split(needle).length - 1;
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
    url: `http://127.0.0.1:${server.address().port}/hook?key=example`,
    reqs,
    set(m, d = 0) { mode = m; delay = d; },
    close() { for (const s of sockets) s.destroy(); return new Promise((r) => server.close(r)); },
  })));
}
const upload = (r, token = 'tok-1', developer = 'alex') => ({ CC_USAGE_ENDPOINT: r.url, CC_USAGE_TOKEN: token, CC_USAGE_DEVELOPER: developer });

// ---------- upload contract ----------

test('uploads the ledger with X-Webhook-Token only, keeps the URL query, and empties send/ on 202', async () => {
  const dir = tmp(); const r = await receiver();
  try {
    fs.mkdirSync(data(dir), { recursive: true });
    fs.writeFileSync(data(dir, 'outbox.jsonl'), '{"id":"old"}\n'); // a 0.1.6 queue
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
    assert.equal(q.url.searchParams.get('key'), 'example', 'existing query kept');
    assert.equal(q.url.searchParams.get('developer'), 'alex-kim');
    assert.equal(q.url.searchParams.get('week'), isoWeek(new Date(recs[0].ts)));
    assert.equal(q.url.searchParams.get('id'), recs[0].id);
    assert.equal(q.body, ledger(dir), 'body is the ledger lines unchanged');
    assert.ok(q.body.endsWith('\n'));
    assert.ok(recs.every((x) => x.developer === 'alex-kim'));
    assert.deepEqual(pending(dir), []);
    assert.ok(sendState(dir).last_ok > 0);
    assert.ok(!fs.existsSync(data(dir, 'outbox.jsonl')), '0.1.6 outbox removed');
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

test('splits a cut above 1 MB into several batches', async () => {
  const dir = tmp(); const r = await receiver();
  try {
    const e = upload(r);
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, e);
    const ts = new Date().toISOString();
    for (let i = 0; i < 1200; i++) appendLedger(dir, { id: `big-${i}`, kind: 'prompt', ts, developer: 'alex', pad: 'x'.repeat(1000) });
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.ok(r.reqs.length >= 2);
    assert.ok(r.reqs.every((q) => Buffer.byteLength(q.body) <= 1024 * 1024));
    assert.equal(r.reqs.reduce((n, q) => n + lines(q.body).length, 0), 1201);
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
    const log = errors(dir);
    assert.match(log, /upload 401/);
    assert.ok(!log.includes('key=example') && !log.includes('wrong'), 'log carries no URL or token');
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

test('no upload before flush_hours unless 64 KB are waiting; a non-positive flush_hours means 24', async () => {
  const dir = tmp(); const r = await receiver();
  try {
    const e = { ...upload(r), CC_USAGE_FLUSH_HOURS: '-1' };
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

test('records written while no endpoint is configured are never uploaded', async () => {
  const dir = tmp(); const r = await receiver();
  try {
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, { CC_USAGE_DEVELOPER: 'alex' });
    const e = upload(r);
    await run(dir, 'UserPromptSubmit', { session_id: 's1', prompt: 'hello' }, e);
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.equal(r.reqs.length, 1);
    assert.deepEqual(lines(r.reqs[0].body).map((x) => x.kind), ['prompt'], 'before the first configuration');
    await run(dir, 'UserPromptSubmit', { session_id: 's1', prompt: 'local only' }, { CC_USAGE_DEVELOPER: 'alex' });
    assert.ok(!fs.existsSync(data(dir, 'state', '_send.json')), 'removing the endpoint forgets the send state');
    await run(dir, 'UserPromptSubmit', { session_id: 's1', prompt: 'again' }, e);
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.equal(r.reqs.length, 2);
    assert.deepEqual(lines(r.reqs[1].body).map((x) => x.prompt_chars), [5], 'the record written without an endpoint stays local');
  } finally { await r.close(); }
});

test('refuses an unsafe configuration, logs it once, and uploads once it is fixed', async () => {
  const r = await receiver();
  try {
    const cases = [
      ['endpoint-not-https', { CC_USAGE_ENDPOINT: 'http://receiver.example/hook', CC_USAGE_TOKEN: 't', CC_USAGE_DEVELOPER: 'alex' }],
      ['endpoint-has-developer-week-or-id', { ...upload(r), CC_USAGE_ENDPOINT: `${r.url}&week=2026-W01` }],
      ['no-token', upload(r, '')],
      ['no-developer', upload(r, 'tok-1', '')],
    ];
    for (const [problem, e] of cases) {
      const dir = tmp();
      await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, e);
      await run(dir, 'Stop', { session_id: 's1' }, e);
      await run(dir, 'Stop', { session_id: 's1' }, e);
      assert.equal(r.reqs.length, 0, problem);
      assert.equal(count(errors(dir), `upload refused: ${problem}`), 1, problem);
      if (problem === 'no-developer') {
        await run(dir, 'Stop', { session_id: 's1' }, upload(r));
        assert.equal(r.reqs.length, 1, 'uploads once the developer is set');
      }
    }
  } finally { await r.close(); }
});

test('a batch that cannot be read stays in send/ and is sent once it can', { skip: NO_CHMOD }, async () => {
  const dir = tmp(); const r = await receiver();
  try {
    const e = upload(r);
    r.set(500);
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, e);
    await run(dir, 'Stop', { session_id: 's1' }, e);
    const [f] = pending(dir);
    fs.chmodSync(data(dir, 'send', f), 0o000);
    r.set(202); patchState(dir, { next_try: 0 });
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.equal(r.reqs.length, 1);
    assert.deepEqual(pending(dir), [f]);
    assert.match(errors(dir), /batch unreadable EACCES/);
    fs.chmodSync(data(dir, 'send', f), 0o644);
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.equal(r.reqs.length, 2);
    assert.equal(r.reqs[1].body, r.reqs[0].body);
  } finally { await r.close(); }
});

// ---------- locks ----------

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

test('a stale upload lock is taken over; a fresh one is left to its owner', async () => {
  const dir = tmp(); const r = await receiver();
  try {
    const e = upload(r);
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, e);
    const lock = data(dir, 'send.lock');
    fs.writeFileSync(lock, 'someone-else');
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.equal(r.reqs.length, 0, 'fresh lock respected');
    assert.equal(fs.readFileSync(lock, 'utf8'), 'someone-else', 'and not removed');
    const old = new Date(Date.now() - 10 * 60e3);
    fs.utimesSync(lock, old, old);
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.equal(r.reqs.length, 1, 'stale lock taken over');
    assert.ok(!fs.existsSync(lock), 'released by its new owner');
    // While an upload is in flight, another process takes the lock over; the first one must not remove it.
    r.set(202, 1000);
    for (let i = 0; i < 400; i++) appendLedger(dir, { id: `bulk-${i}`, kind: 'prompt', ts: new Date().toISOString(), developer: 'alex', pad: 'x'.repeat(200) });
    const stop = run(dir, 'Stop', { session_id: 's1' }, e);
    while (r.reqs.length < 2) await new Promise((res) => setTimeout(res, 20));
    fs.writeFileSync(lock, 'new-owner');
    await stop;
    assert.equal(fs.readFileSync(lock, 'utf8'), 'new-owner', 'a lock now owned by another process is left in place');
  } finally { await r.close(); }
});

// ---------- usage ----------

function transcript(dir, ids) {
  const tr = path.join(dir, 's1.jsonl');
  const usage = { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 };
  fs.writeFileSync(tr, ids.map((id) => JSON.stringify({ type: 'assistant', requestId: id, message: { model: 'claude-x', usage } })).join('\n') + '\n');
  return tr;
}
const usageRequests = (dir) => lines(ledger(dir)).filter((x) => x.kind === 'usage').reduce((n, x) => n + x.requests, 0);

test('usage from one transcript counts once when Stop and SessionEnd overlap', async () => {
  const dir = tmp();
  const input = { session_id: 's1', transcript_path: transcript(dir, ['r1', 'r2', 'r3']) };
  await Promise.all([run(dir, 'Stop', input), run(dir, 'SessionEnd', input)]);
  assert.equal(usageRequests(dir), 3);
});

test('the transcript checkpoint advances only after the usage record is written', { skip: NO_CHMOD }, async () => {
  const dir = tmp();
  const input = { session_id: 's1', transcript_path: transcript(dir, ['r1', 'r2', 'r3']) };
  await run(dir, 'SessionStart', { session_id: 's1', cwd: dir });
  const [week] = fs.readdirSync(data(dir, 'ledger'));
  fs.chmodSync(data(dir, 'ledger', week), 0o444);
  await run(dir, 'Stop', input);
  assert.match(errors(dir), /ledger write failed \(usage\)/);
  assert.ok(!fs.existsSync(data(dir, 'state', 's1.json')), 'checkpoint not saved');
  fs.chmodSync(data(dir, 'ledger', week), 0o644);
  await run(dir, 'Stop', input);
  assert.equal(usageRequests(dir), 3);
});

// ---------- commits and pull requests ----------

test('commits count only commits the command made, each once per session', async () => {
  const dir = tmp();
  const repo = path.join(dir, 'repo'); fs.mkdirSync(repo);
  const OLD = { GIT_COMMITTER_DATE: '2020-01-01T00:00:00Z', GIT_AUTHOR_DATE: '2020-01-01T00:00:00Z' };
  const git = (...a) => execFileSync('git', ['-C', repo, '-c', 'user.name=t', '-c', 'user.email=t@example.com', ...a], { env: env(dir), stdio: 'pipe' }).toString();
  const oldGit = (...a) => execFileSync('git', ['-C', repo, '-c', 'user.name=t', '-c', 'user.email=t@example.com', ...a], { env: env(dir, OLD), stdio: 'pipe' }).toString();
  // existing history, committed long ago: other (3 commits), other2 (ends in a merge commit), other3
  oldGit('init', '-q', '-b', 'main'); oldGit('commit', '-q', '--allow-empty', '-m', 'init');
  oldGit('switch', '-q', '-c', 'other'); for (const m of ['o1', 'o2', 'o3']) oldGit('commit', '-q', '--allow-empty', '-m', m);
  oldGit('switch', '-q', '-c', 'y', 'main'); oldGit('commit', '-q', '--allow-empty', '-m', 'y1');
  oldGit('switch', '-q', '-c', 'other2', 'main'); oldGit('commit', '-q', '--allow-empty', '-m', 'x1'); oldGit('merge', '-q', '--no-ff', '-m', 'old merge', 'y');
  oldGit('switch', '-q', '-c', 'other3', 'main'); oldGit('commit', '-q', '--allow-empty', '-m', 'z1');
  oldGit('switch', '-q', 'main');
  const base = { session_id: 's1', cwd: repo };
  const bash = (command) => run(dir, 'PostToolUse', { ...base, tool_name: 'Bash', tool_input: { command }, tool_response: { stdout: '' } });
  await run(dir, 'SessionStart', base);
  git('checkout', '-q', 'other'); git('commit', '-q', '--allow-empty', '-m', 'c1');
  await bash('git checkout other && git commit -m c1');           // 1, not the 3 old commits passed over
  git('switch', '-q', 'main'); await bash('git switch main');
  git('merge', '-q', '--ff-only', 'other2'); await bash('git merge --ff-only other2'); // fast-forward onto an old merge commit: 0
  git('commit', '-q', '--allow-empty', '-m', 'c2'); git('merge', '-q', '--no-ff', '-m', 'm2', 'other3');
  await bash('git commit -m c2 && git merge --no-ff other3');     // c2 and the merge commit: 2
  git('switch', '-q', '-c', 'feat'); git('commit', '-q', '--allow-empty', '-m', 'f1');
  await bash('git switch -c feat && git commit -m f1');           // 1
  git('switch', '-q', 'main'); await bash('git switch main');
  git('merge', '-q', '--ff-only', 'feat'); await bash('git merge --ff-only feat'); // f1 already counted: 0
  const recs = lines(ledger(dir)).filter((x) => x.kind === 'commit');
  assert.deepEqual(recs.map((x) => [x.op, x.commits]), [['commit', 1], ['commit', 2], ['commit', 1]]);
});

test('PR records need create with a URL in the output, or merge with a number and no error', async () => {
  const dir = tmp();
  const base = { session_id: 's1', cwd: dir };
  const bash = (command, stdout = '', stderr = '') => run(dir, 'PostToolUse', { ...base, tool_name: 'Bash', tool_input: { command }, tool_response: { stdout, stderr } });
  await bash('gh pr view 5', 'https://github.com/acme/app/pull/5\n');
  await bash('gh pr create --fill', '');
  await bash('gh pr create --fill', 'https://github.com/acme/app/pull/7\n');
  await bash('gh pr merge 7 --squash');                            // gh prints nothing when not in a terminal
  await bash('gh pr merge --squash 8', '', 'X Pull request #8 is not mergeable: the base branch policy prohibits the merge.\n');
  await bash('gh pr merge --squash');                              // no number: unknown PR
  await bash('gh pr merge https://github.com/acme/app/pull/9 --merge');
  const recs = lines(ledger(dir)).filter((x) => x.kind === 'pr');
  assert.deepEqual(recs.map((x) => [x.action, x.number, x.url]), [
    ['create', 7, 'https://github.com/acme/app/pull/7'], ['merge', 7, null], ['merge', 9, 'https://github.com/acme/app/pull/9']]);
});

test('repository origins keep host and path only', async () => {
  const cases = [
    ['https://user:secret@example.com/acme/app.git?access_token=x#frag', 'https://example.com/acme/app'],
    ['git@example.com:acme/app.git', 'https://example.com/acme/app'],
    ['ssh://git@example.com:2222/acme/app.git', 'https://example.com/acme/app'],
    ['/srv/git/app.git', null],
  ];
  for (const [origin, want] of cases) {
    const dir = tmp();
    execFileSync('git', ['init', '-q', dir], { env: env(dir), stdio: 'pipe' });
    execFileSync('git', ['-C', dir, 'remote', 'add', 'origin', origin], { env: env(dir), stdio: 'pipe' });
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir });
    assert.equal(lines(ledger(dir))[0].repo, want, origin);
  }
});

// ---------- record fields ----------

test('developer ids are path-safe, and non-Latin names stay distinct', async () => {
  const cases = [['Alex Kim', 'alex-kim'], ['../x', 'x'], ['CON', 'u-con'], ['con.txt', 'u-con.txt'], ['a_vti_b', 'a-vti-b'], ['김민수', /^u-[0-9a-f]{8}$/], ['이민수', /^u-[0-9a-f]{8}$/]];
  const got = [];
  for (const [raw, want] of cases) {
    const dir = tmp();
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, { CC_USAGE_DEVELOPER: raw });
    const id = lines(ledger(dir))[0].developer;
    if (want instanceof RegExp) assert.match(id, want); else assert.equal(id, want);
    got.push(id);
  }
  assert.notEqual(got[5], got[6]);
});

test('only a slash command is recorded as a command, not a path', async () => {
  const dir = tmp();
  for (const prompt of ['/Users/alex/notes.txt summarize this', '/review now', '/plugin:skill']) await run(dir, 'UserPromptSubmit', { session_id: 's1', prompt });
  assert.deepEqual(lines(ledger(dir)).map((x) => x.command), [null, '/review', '/plugin:skill']);
});

test('account fields come from CLAUDE_CONFIG_DIR when it is set', async () => {
  const dir = tmp();
  fs.mkdirSync(path.join(dir, 'cfg'));
  fs.writeFileSync(path.join(dir, 'cfg', '.claude.json'), JSON.stringify({ oauthAccount: { emailAddress: 'alex@example.com' } }));
  await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, { CLAUDE_CONFIG_DIR: path.join(dir, 'cfg') });
  assert.equal(lines(ledger(dir))[0].email, 'alex@example.com');
});

test('session state older than 30 days is removed at SessionStart; the send state is kept', async () => {
  const dir = tmp();
  fs.mkdirSync(data(dir, 'state'), { recursive: true });
  const old = new Date(Date.now() - 40 * 864e5);
  for (const f of ['old.json', '_send.json']) { fs.writeFileSync(data(dir, 'state', f), '{}'); fs.utimesSync(data(dir, 'state', f), old, old); }
  fs.writeFileSync(data(dir, 'state', 'new.json'), '{}');
  // an endpoint is set, so the send state belongs to a live configuration (SessionStart never uploads)
  await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, { CC_USAGE_ENDPOINT: 'https://receiver.example/hook' });
  assert.deepEqual(fs.readdirSync(data(dir, 'state')).sort(), ['_send.json', 'new.json']);
});

// ---------- report.js ----------

test('report.js finds the installed ledger, counts each record id once, and keeps one key per repository', () => {
  const dir = tmp();
  const led = path.join(dir, '.claude', 'plugins', 'data', 'cc-usage-plugin-acme', 'ledger');
  fs.mkdirSync(led, { recursive: true });
  const ts = new Date().toISOString();
  const m = (n) => [{ model: 'claude-x', input: n, output: 0, cache_read: 0, cache_create: 0, requests: 1 }];
  const recs = [
    { id: 's', kind: 'session_open', ts, session_id: 's1', repo: 'https://example.com/acme/app', repo_dir: 'app' },
    { id: 'u1', kind: 'usage', ts, session_id: 's1', repo: 'https://example.com/acme/app', repo_dir: 'app', by_model: m(1) },
    { id: 'u2', kind: 'usage', ts, session_id: 's1', repo_dir: 'app', by_model: m(2) }, // from SessionEnd: no origin
    { id: 'c1', kind: 'commit', ts, op: 'commit', commits: 2 },
    { id: 'c2', kind: 'commit', ts, op: 'pull', commits: 9 },
    { id: 'p1', kind: 'pr', ts, action: 'create', number: 7 },
    { id: 'p2', kind: 'pr', ts, action: null, number: 5 },
  ];
  const text = recs.map((x) => JSON.stringify(x)).join('\n') + '\n';
  fs.writeFileSync(path.join(led, `${isoWeek(new Date())}.jsonl`), text + text); // every record twice
  const out = path.join(dir, 'weekly.json');
  execFileSync(process.execPath, [REPORT, '--days', '7', '--json', out], { env: env(dir, { CLAUDE_PLUGIN_DATA: '' }), stdio: 'pipe' });
  const s = JSON.parse(fs.readFileSync(out, 'utf8'));
  assert.equal(s.totals.requests, 2);
  assert.deepEqual(s.by_repo, { 'https://example.com/acme/app': 3 });
  assert.equal(s.commits, 2);
  assert.deepEqual(s.prs.map((p) => p.number), [7]);
});
