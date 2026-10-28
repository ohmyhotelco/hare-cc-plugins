'use strict';
// Run from the repo root: node --test 'cc-usage-plugin/tests/*.test.js' (this file alone: its path)
// Most tests run the real hook script as a child process, the upload tests against a local receiver on
// 127.0.0.1. The timeout test waits for the 15 s request timeout, so the whole file takes about 25 s.
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, spawnSync, execFileSync } = require('node:child_process');

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

test('cuts one batch per ISO week, oldest week first; records of another developer id stay local', async () => {
  const dir = tmp(); const r = await receiver();
  try {
    const e = upload(r);
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, e);
    const old = new Date(Date.now() - 21 * 864e5).toISOString();
    appendLedger(dir, { id: 'old-1', kind: 'prompt', ts: old, developer: 'alex' });
    appendLedger(dir, { id: 'old-2', kind: 'prompt', ts: old, developer: 'alex' });
    appendLedger(dir, { id: 'sam-1', kind: 'prompt', ts: new Date().toISOString(), developer: 'sam' });
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.equal(r.reqs.length, 2);
    for (const q of r.reqs) {
      const recs = lines(q.body);
      assert.ok(recs.every((x) => isoWeek(new Date(x.ts)) === q.url.searchParams.get('week')), 'one week per batch');
      assert.ok(recs.every((x) => x.developer === 'alex') && q.url.searchParams.get('developer') === 'alex');
      assert.equal(q.url.searchParams.get('id'), recs[0].id);
    }
    assert.equal(r.reqs[0].url.searchParams.get('week'), isoWeek(new Date(old)));
    assert.ok(!r.reqs.some((q) => q.body.includes('sam-1')), 'a record of another developer id is not uploaded');
  } finally { await r.close(); }
});

test('a batch cut under an earlier developer id is held, not sent from the new configuration', async () => {
  const dir = tmp(); const r = await receiver();
  try {
    r.set(500);
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, upload(r, 'tok-1', 'sam'));
    await run(dir, 'Stop', { session_id: 's1' }, upload(r, 'tok-1', 'sam'));
    assert.equal(pending(dir).length, 1);
    r.set(202); patchState(dir, { next_try: 0 });
    await run(dir, 'UserPromptSubmit', { session_id: 's1', prompt: 'hi' }, upload(r));
    await run(dir, 'Stop', { session_id: 's1' }, upload(r));
    assert.equal(r.reqs.length, 2);
    assert.equal(r.reqs[1].url.searchParams.get('developer'), 'alex');
    assert.deepEqual(lines(r.reqs[1].body).map((x) => x.kind), ['prompt']);
    assert.deepEqual(pending(dir), []);
    assert.equal(fs.readdirSync(data(dir, 'send')).filter((f) => f.endsWith('.held')).length, 1);
    assert.equal(count(errors(dir), 'upload held: batch of another developer'), 1);
  } finally { await r.close(); }
});

test('splits a cut above 1 MB into several batches', async () => {
  const dir = tmp(); const r = await receiver();
  try {
    const e = upload(r);
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, e);
    const ts = new Date().toISOString();
    for (let i = 0; i < 1200; i++) appendLedger(dir, { id: `big-${i}`, kind: 'prompt', ts, developer: 'alex', pad: 'x'.repeat(1000) });
    appendLedger(dir, { id: 'huge', kind: 'prompt', ts, developer: 'alex', pad: 'x'.repeat(1100 * 1024) }); // no real record is this big
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.ok(r.reqs.length >= 2);
    assert.ok(r.reqs.every((q) => Buffer.byteLength(q.body) <= 1024 * 1024));
    assert.equal(r.reqs.reduce((n, q) => n + lines(q.body).length, 0), 1201);
    assert.match(errors(dir), /record over 1 MB not uploaded/);
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
    const prompt = (text, extra) => run(dir, 'UserPromptSubmit', { session_id: 's1', prompt: text }, extra);
    await prompt('hello', e);
    await run(dir, 'Stop', { session_id: 's1' }, e);
    assert.equal(r.reqs.length, 1);
    assert.deepEqual(lines(r.reqs[0].body).map((x) => x.kind), ['prompt'], 'before the first configuration');
    await prompt('kept', e); // recorded with an endpoint, not yet due
    await prompt('local only', { CC_USAGE_DEVELOPER: 'alex' });
    assert.ok(!fs.existsSync(data(dir, 'state', '_send.json')), 'removing the endpoint ends tracking');
    assert.equal(pending(dir).length, 1, 'what was recorded with an endpoint is cut first');
    await prompt('again!', e);
    await run(dir, 'Stop', { session_id: 's1' }, e);
    const sent = r.reqs.slice(1).flatMap((q) => lines(q.body).map((x) => x.prompt_chars));
    assert.deepEqual(sent, [4, 6], 'the record written without an endpoint stays local');
  } finally { await r.close(); }
});

test('an upload in flight neither restores tracking that ended nor overwrites tracking started again', async () => {
  const dir = tmp(); const r = await receiver();
  try {
    const e = upload(r), off = { CC_USAGE_DEVELOPER: 'alex' };
    const prompt = (text, extra) => run(dir, 'UserPromptSubmit', { session_id: 's1', prompt: text }, extra);
    const inFlight = async (n) => { while (r.reqs.length < n) await new Promise((res) => setTimeout(res, 20)); };
    await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, e);
    r.set(202, 1500);
    let stop = run(dir, 'Stop', { session_id: 's1' }, e);
    await inFlight(1);
    await prompt('local only', off);                       // tracking ends while the upload waits
    await stop;
    assert.ok(!fs.existsSync(data(dir, 'state', '_send.json')));
    await prompt('again!', e);
    stop = run(dir, 'Stop', { session_id: 's1' }, e);
    await inFlight(2);
    await prompt('offline', off); await prompt('back', e); // ends and starts again while the upload waits
    await stop;
    r.set(202);
    await run(dir, 'Stop', { session_id: 's1' }, e);
    const sent = r.reqs.slice(1).flatMap((q) => lines(q.body).map((x) => x.prompt_chars));
    assert.deepEqual(sent, [6, 4], 'records written without an endpoint stay local');
  } finally { await r.close(); }
});

test('refuses an unsafe configuration, logs it once, and uploads once it is fixed', async () => {
  const r = await receiver();
  try {
    const cases = [
      ['endpoint-not-https', { CC_USAGE_ENDPOINT: 'http://receiver.example/hook', CC_USAGE_TOKEN: 't', CC_USAGE_DEVELOPER: 'alex' }],
      ['endpoint-has-developer-week-or-id', { ...upload(r), CC_USAGE_ENDPOINT: `${r.url}&week=2026-W01` }],
      ['no-token', upload(r, '')],
      ['token-not-visible-ascii', upload(r, 'tok\u200b1')],
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
        const set = upload(r, 'tok-1', 'dev-assigned');
        await run(dir, 'UserPromptSubmit', { session_id: 's1', prompt: 'hi' }, set);
        await run(dir, 'Stop', { session_id: 's1' }, set);
        assert.equal(r.reqs.length, 1, 'uploads once the developer is set');
        assert.deepEqual(lines(r.reqs[0].body).map((x) => [x.kind, x.developer]), [['prompt', 'dev-assigned']],
          'records written under the OS login name stay local');
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
  const git = (...a) => execFileSync('git', ['-C', repo, ...a], { env: env(dir), stdio: 'pipe' }).toString();
  const oldGit = (...a) => execFileSync('git', ['-C', repo, ...a], { env: env(dir, OLD), stdio: 'pipe' }).toString();
  const samGit = (...a) => git('-c', 'user.name=sam', '-c', 'user.email=sam@example.com', ...a); // someone else, just now
  // existing history, committed long ago: other (3 commits), other2 (ends in a merge commit), other3
  oldGit('init', '-q', '-b', 'main'); git('config', 'user.name', 't'); git('config', 'user.email', 't@example.com');
  oldGit('commit', '-q', '--allow-empty', '-m', 'init');
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
  await run(dir, 'SessionStart', { ...base, source: 'compact' });   // keeps the commits already counted
  git('merge', '-q', '--ff-only', 'feat'); git('commit', '-q', '--allow-empty', '-m', 'c3');
  await bash('git merge --ff-only feat && git commit -m c3');     // f1 already counted: 1
  git('switch', '-q', '-c', 'mine'); git('commit', '-q', '--allow-empty', '-m', 'm1'); git('switch', '-q', 'main');
  git('merge', '-q', '--ff-only', 'mine'); await bash('git merge --ff-only mine'); // a recent commit made elsewhere: 0
  git('switch', '-q', '-c', 'theirs'); samGit('commit', '-q', '--allow-empty', '-m', 's1'); git('switch', '-q', 'main');
  git('merge', '-q', '--ff-only', 'theirs'); git('commit', '-q', '--allow-empty', '-m', 'c4');
  await bash('git merge --ff-only theirs && git commit -m c4');   // c4, not the other committer's s1: 1
  git('switch', '-q', '-c', 'x'); git('commit', '-q', '--allow-empty', '-m', 'x1');
  git('switch', '-q', '-c', 'merged', 'main'); git('commit', '-q', '--allow-empty', '-m', 'y1'); git('merge', '-q', '--no-ff', '-m', 'M', 'x');
  git('switch', '-q', 'main'); git('merge', '-q', '--ff-only', 'merged');
  await bash('git merge --ff-only merged');                       // onto a recent merge commit made elsewhere: 0
  git('switch', '-q', '-c', 'a'); git('commit', '-q', '--allow-empty', '-m', 'a1');
  git('switch', '-q', '-c', 'b', 'main'); git('commit', '-q', '--allow-empty', '-m', 'b1'); git('switch', '-q', 'main');
  git('merge', '-q', '--no-ff', '-m', 'Ma', 'a'); git('merge', '-q', '--no-ff', '-m', 'Mb', 'b');
  await bash('git merge --no-ff a && git merge --no-ff b');       // two merge commits: 2
  const recs = lines(ledger(dir)).filter((x) => x.kind === 'commit');
  assert.deepEqual(recs.map((x) => [x.op, x.commits]), [['commit', 1], ['commit', 2], ['commit', 1], ['merge', 1], ['merge', 1], ['merge', 2]]);
});

test('a commit whose record cannot be written is counted with the next one', { skip: NO_CHMOD }, async () => {
  const dir = tmp();
  const repo = path.join(dir, 'repo'); fs.mkdirSync(repo);
  const git = (...a) => execFileSync('git', ['-C', repo, ...a], { env: env(dir), stdio: 'pipe' }).toString();
  git('init', '-q', '-b', 'main'); git('config', 'user.name', 't'); git('config', 'user.email', 't@example.com');
  git('commit', '-q', '--allow-empty', '-m', 'init');
  const base = { session_id: 's1', cwd: repo };
  const bash = (command) => run(dir, 'PostToolUse', { ...base, tool_name: 'Bash', tool_input: { command }, tool_response: { stdout: '' } });
  await run(dir, 'SessionStart', base);
  const [week] = fs.readdirSync(data(dir, 'ledger'));
  fs.chmodSync(data(dir, 'ledger', week), 0o444);
  git('commit', '-q', '--allow-empty', '-m', 'c1'); await bash('git commit -m c1');
  fs.chmodSync(data(dir, 'ledger', week), 0o644);
  git('commit', '-q', '--allow-empty', '-m', 'c2'); await bash('git commit -m c2');
  assert.deepEqual(lines(ledger(dir)).filter((x) => x.kind === 'commit').map((x) => x.commits), [2]);
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
  await bash('echo gh pr merge 3');                                 // text, not a command
  await bash('gh pr merge --subject "fix 12 things" 11 --squash'); // an option value is not the number
  await bash('gh pr merge 12 --disable-auto');                      // merges nothing
  await bash('gh pr merge 13 --squash || true', '', 'GraphQL: Resource not accessible by integration (mergePullRequest)\n');
  await bash('cd app && gh pr merge 14 --auto');                    // counted when requested
  await bash('gh pr merge --subject="fix 123" 21 --squash');         // --option=value with a space
  await bash('gh pr merge 22 --subject "please --disable-auto later"'); // the flag only inside a value
  await bash('gh pr merge 23 "--disable-auto"');                     // still the flag once quotes are removed
  await bash('echo "text; gh pr merge 24 --squash"');                // a separator inside quotes
  await bash('glab mr merge --message 125 25');                      // glab's own value option
  await bash('gh pr merge 26 --squash --help');                      // help only
  const recs = lines(ledger(dir)).filter((x) => x.kind === 'pr');
  assert.deepEqual(recs.map((x) => [x.action, x.number, x.url]), [
    ['create', 7, 'https://github.com/acme/app/pull/7'], ['merge', 7, null], ['merge', 9, 'https://github.com/acme/app/pull/9'],
    ['merge', 11, null], ['merge', 14, null], ['merge', 21, null], ['merge', 22, null], ['merge', 25, null]]);
});

test('repository origins keep host and path only', async () => {
  const cases = [
    ['https://user:secret@example.com/acme/app.git?access_token=x#frag', 'https://example.com/acme/app'],
    ['git@example.com:acme/app.git', 'https://example.com/acme/app'],
    ['ssh://git@example.com:2222/acme/app.git', 'https://example.com/acme/app'],
    ['example.com:acme/app.git', 'https://example.com/acme/app'],
    ['alex+work@example.com:acme/app.git', 'https://example.com/acme/app'],
    ['/srv/git/app.git', null],
    ['file:/srv/git/app.git', null],
    ['C:/repos/app', null],
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
  const cases = [['Alex Kim', 'alex-kim'], ['../x', 'x'], ['CON', 'u-con'], ['con.txt', 'u-con.txt'], ['a_vti_b', 'a-vti-b'], ['김민수', /^u-[0-9a-f]{8}$/], ['이민수', /^u-[0-9a-f]{8}$/],
    [`con.${'a'.repeat(70)}`, `u-con.${'a'.repeat(58)}`]]; // 64 characters with the prefix
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

test('hooks.json registers exactly the events collect.js handles, each as exec-form node', () => {
  const hooks = JSON.parse(fs.readFileSync(path.join(ROOT, 'hooks', 'hooks.json'), 'utf8')).hooks;
  const handled = Array.from(fs.readFileSync(COLLECT, 'utf8').matchAll(/^ {4}case '(\w+)':/gm), (m) => m[1]);
  assert.deepEqual(Object.keys(hooks).sort(), handled.slice().sort());
  for (const [event, groups] of Object.entries(hooks)) {
    for (const h of groups.flatMap((g) => g.hooks)) assert.deepEqual([h.command, h.args[1]], ['node', event]);
  }
});

test('a typed command is recorded as Claude Code resolved it, without its arguments', async () => {
  const dir = tmp();
  await run(dir, 'UserPromptSubmit', { session_id: 's1', cwd: dir, prompt: '/cc-init alex platform', effort: { level: 'high' } });
  await run(dir, 'UserPromptExpansion', { session_id: 's1', cwd: dir, expansion_type: 'slash_command', command_name: 'cc-init',
    command_args: 'alex platform', command_source: 'plugin', prompt: '/cc-init alex platform' });
  await run(dir, 'UserPromptExpansion', { session_id: 's1', cwd: dir, expansion_type: 'slash_command', command_name: 'two\nlines', command_source: 'project' });
  const [prompt, exp, bad] = lines(ledger(dir));
  assert.equal(prompt.command, '/cc-init', 'the prompt record keeps what was typed');
  assert.ok(!('effort' in prompt), 'a prompt carries no effort: Claude Code passes it only in a tool-use context');
  assert.deepEqual([exp.kind, exp.expansion_type, exp.command_name, exp.command_source, exp.args_chars],
    ['expansion', 'slash_command', 'cc-init', 'plugin', 13]);
  assert.deepEqual([bad.command_name, bad.command_source, bad.args_chars], [null, 'project', 0]);
  assert.ok(!ledger(dir).includes('alex platform'), 'no argument or prompt text in the ledger');
});

test('a turn ended by an API error records its type and the account, never its message', async () => {
  const dir = tmp();
  fs.writeFileSync(path.join(dir, '.claude.json'), JSON.stringify({ oauthAccount: { emailAddress: 'alex@example.com' } }));
  for (const error of ['rate_limit', 'Rate limit: retry in 5 min', undefined]) {
    await run(dir, 'StopFailure', { session_id: 's1', cwd: dir, error, error_details: '429 Too Many Requests', last_assistant_message: 'API Error: Rate limit reached' });
  }
  const recs = lines(ledger(dir));
  assert.deepEqual(recs.map((x) => [x.kind, x.error, x.email]),
    [['stop_failure', 'rate_limit', 'alex@example.com'], ['stop_failure', 'unknown', 'alex@example.com'], ['stop_failure', 'unknown', 'alex@example.com']]);
  assert.ok(!/429|API Error|retry in/.test(ledger(dir)), 'no error details, message or free text');
});

test('session_open records the plan tier and no permission mode', async () => {
  const dir = tmp();
  fs.writeFileSync(path.join(dir, '.claude.json'), JSON.stringify({ oauthAccount: { emailAddress: 'alex@example.com',
    organizationType: 'claude_max', organizationRateLimitTier: 'default_claude_max_20x', userRateLimitTier: null, seatTier: null } }));
  await run(dir, 'SessionStart', { session_id: 's1', cwd: dir, permission_mode: 'default' });
  const [open] = lines(ledger(dir));
  assert.deepEqual([open.org_type, open.org_rate_limit_tier, open.user_rate_limit_tier, open.seat_tier], ['claude_max', 'default_claude_max_20x', null, null]);
  assert.ok(!('permission_mode' in open), 'SessionStart gets no permission mode; prompt records carry it');
});

test('Claude Code\'s own agents leave no subagent record, but their usage still counts', async () => {
  const dir = tmp();
  const agentTr = path.join(dir, 'agent.jsonl');
  fs.copyFileSync(transcript(dir, ['a1']), agentTr);
  await run(dir, 'SubagentStop', { session_id: 's1', cwd: dir, agent_id: 'in1', agent_type: '' }); // a prompt suggestion: no transcript
  await run(dir, 'SubagentStop', { session_id: 's1', cwd: dir, agent_id: 'in2', agent_type: '', agent_transcript_path: agentTr });
  await run(dir, 'SubagentStop', { session_id: 's1', cwd: dir, agent_id: 'ag1', agent_type: 'Explore', agent_transcript_path: transcript(dir, ['a2']) });
  const recs = lines(ledger(dir));
  assert.deepEqual(recs.filter((x) => x.kind === 'subagent').map((x) => [x.agent_type, x.agent_id]), [['Explore', 'ag1']]);
  assert.deepEqual(recs.filter((x) => x.kind === 'usage').map((x) => [x.agent_id, x.agent_type]), [['in2', null], ['ag1', 'Explore']]);
});

test('account fields come from CLAUDE_CONFIG_DIR when it is set', async () => {
  const dir = tmp();
  fs.mkdirSync(path.join(dir, 'cfg'));
  fs.writeFileSync(path.join(dir, 'cfg', '.claude.json'), JSON.stringify({ oauthAccount: { emailAddress: 'alex@example.com' } }));
  await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, { CLAUDE_CONFIG_DIR: path.join(dir, 'cfg') });
  assert.equal(lines(ledger(dir))[0].email, 'alex@example.com');
});

test('usage records name the account signed in when they are written, also after a switch mid-session', async () => {
  const dir = tmp();
  const signIn = (email) => fs.writeFileSync(path.join(dir, '.claude.json'), JSON.stringify({ oauthAccount: { emailAddress: email } }));
  signIn('first@example.com');
  await run(dir, 'SessionStart', { session_id: 's1', cwd: dir });
  await run(dir, 'Stop', { session_id: 's1', cwd: dir, transcript_path: transcript(dir, ['r1']) });
  signIn('second@example.com'); // /login to another account, same session
  await run(dir, 'Stop', { session_id: 's1', cwd: dir, transcript_path: transcript(dir, ['r1', 'r2', 'r3']) });
  const agentTr = path.join(dir, 'agent.jsonl');
  fs.copyFileSync(transcript(dir, ['a1']), agentTr);
  await run(dir, 'SubagentStop', { session_id: 's1', cwd: dir, agent_id: 'ag1', agent_type: 'Explore', agent_transcript_path: agentTr });
  const recs = lines(ledger(dir));
  assert.equal(recs.find((x) => x.kind === 'session_open').email, 'first@example.com');
  assert.deepEqual(recs.filter((x) => x.kind === 'usage').map((x) => [x.email, x.requests, x.agent_id || null]),
    [['first@example.com', 1, null], ['second@example.com', 2, null], ['second@example.com', 1, 'ag1']]);
});

test('an unreadable account file leaves the account out of a usage record; no account signed in is null', async () => {
  const dir = tmp();
  fs.writeFileSync(path.join(dir, '.claude.json'), '{"oauthAccount": {"emailAddress": "half'); // a write in progress
  await run(dir, 'Stop', { session_id: 's1', cwd: dir, transcript_path: transcript(dir, ['r1']) });
  fs.writeFileSync(path.join(dir, '.claude.json'), JSON.stringify({ projects: {} }));
  await run(dir, 'Stop', { session_id: 's1', cwd: dir, transcript_path: transcript(dir, ['r1', 'r2']) });
  const usage = lines(ledger(dir)).filter((x) => x.kind === 'usage');
  assert.equal(usage.length, 2);
  assert.ok(!('email' in usage[0]), 'not readable: left out, so the report uses the session\'s account');
  assert.equal(usage[1].email, null);
});

test('a hook that cannot load config.js records it and exits 0 without output', async () => {
  const dir = tmp();
  const copy = path.join(dir, 'plugin', 'scripts');
  fs.mkdirSync(copy, { recursive: true });
  fs.copyFileSync(COLLECT, path.join(copy, 'collect.js')); // no config.js next to it
  const r = spawnSync(process.execPath, [path.join(copy, 'collect.js'), 'SessionStart'], { env: env(dir), input: '{}', encoding: 'utf8' });
  assert.equal(r.status, 0);
  assert.equal(r.stdout + r.stderr, '');
  assert.match(errors(dir), /SessionStart config\.js not loadable/);
});

test('config.js: a token is visible ASCII, with spaces only inside it', () => {
  const { tokenProblem } = require(path.join(ROOT, 'scripts', 'config.js'));
  assert.deepEqual(['abc', 'abc def', '', ' abc', 'abc ', 'a\tb', 'tok\u200b1', 'tok\u00a01'].map(tokenProblem),
    [null, null, 'no-token', 'token-not-visible-ascii', 'token-not-visible-ascii', 'token-not-visible-ascii', 'token-not-visible-ascii', 'token-not-visible-ascii']);
});

test('session state older than 30 days is removed at SessionStart; checkpoints shrink to their offset', async () => {
  const dir = tmp();
  fs.mkdirSync(data(dir, 'state'), { recursive: true });
  const old = new Date(Date.now() - 40 * 864e5);
  const put = (f, v) => { fs.writeFileSync(data(dir, 'state', f), JSON.stringify(v)); fs.utimesSync(data(dir, 'state', f), old, old); };
  put('old.json', { offset: 7, seen: ['r1'] }); put('old.git.json', { [dir]: 'abc' }); put('_send.json', { offsets: {} });
  fs.writeFileSync(data(dir, 'state', 'new.json'), '{}');
  // an endpoint is set, so the send state belongs to a live configuration (SessionStart never uploads)
  await run(dir, 'SessionStart', { session_id: 's1', cwd: dir }, { CC_USAGE_ENDPOINT: 'https://receiver.example/hook' });
  assert.deepEqual(fs.readdirSync(data(dir, 'state')).sort(), ['_send.json', 'new.json', 'old.json']);
  assert.deepEqual(JSON.parse(fs.readFileSync(data(dir, 'state', 'old.json'), 'utf8')), { offset: 7, seen: [] },
    'a session resumed later starts after the requests it already counted');
});

// ---------- report.js ----------

test('report.js finds the installed ledger, counts each record id once, and keeps one key per repository', () => {
  const dir = tmp();
  const led = path.join(dir, '.claude', 'plugins', 'data', 'cc-usage-plugin-acme', 'ledger');
  fs.mkdirSync(led, { recursive: true });
  const ts = new Date().toISOString(), old = new Date(Date.now() - 8 * 864e5).toISOString();
  const m = (n) => [{ model: 'claude-x', input: n, output: 0, cache_read: 0, cache_create: 0, requests: 1 }];
  const recs = [
    { id: 's2', kind: 'session_open', ts: old, session_id: 's2', repo: 'https://example.com/acme/lib', repo_dir: 'lib' },
    { id: 'u3', kind: 'usage', ts, session_id: 's2', repo_dir: 'lib', by_model: m(4) }, // its session opened before the window
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
  // A trial ledger is not the one read although its folder is newer and holds another file written just now:
  // its ledger file was last written ten days ago.
  const stale = new Date(Date.now() - 10 * 864e5), minute = new Date(Date.now() - 60e3);
  fs.utimesSync(path.join(led, `${isoWeek(new Date())}.jsonl`), minute, minute);
  fs.utimesSync(led, stale, stale);
  const trial = path.join(dir, '.claude', 'plugins', 'data', 'cc-usage-plugin-inline', 'ledger');
  fs.mkdirSync(trial, { recursive: true });
  fs.writeFileSync(path.join(trial, `${isoWeek(new Date())}.jsonl`), JSON.stringify({ id: 't1', kind: 'usage', ts, by_model: m(100) }) + '\n');
  fs.utimesSync(path.join(trial, `${isoWeek(new Date())}.jsonl`), stale, stale);
  fs.writeFileSync(path.join(trial, '.DS_Store'), ''); // a file browser's own file
  const out = path.join(dir, 'weekly.json');
  execFileSync(process.execPath, [REPORT, '--days', '7', '--json', out], { env: env(dir, { CLAUDE_PLUGIN_DATA: '' }), stdio: 'pipe' });
  const s = JSON.parse(fs.readFileSync(out, 'utf8'));
  assert.equal(s.totals.requests, 3);
  assert.deepEqual(s.by_repo, { 'https://example.com/acme/app': 3, 'https://example.com/acme/lib': 4 });
  assert.equal(s.commits, 2);
  assert.deepEqual(s.prs.map((p) => p.number), [7]);
});

test('report.js splits usage by account and writes no session id', () => {
  const dir = tmp();
  const led = path.join(dir, 'data', 'ledger');
  fs.mkdirSync(led, { recursive: true });
  const at = (min) => new Date(Date.now() - 3600e3 + min * 60e3).toISOString();
  const m = (n) => [{ model: 'claude-x', input: 0, output: n, cache_read: 0, cache_create: 0, requests: 1 }];
  const recs = [
    { id: 'o1', kind: 'session_open', ts: at(0), session_id: 'sess-ZZ01', email: 'a@example.com' },
    { id: 'u1', kind: 'usage', ts: at(1), session_id: 'sess-ZZ01', by_model: m(5) }, // a 0.1.7 record: its session's account
    { id: 'u2', kind: 'usage', ts: at(2), session_id: 'sess-ZZ01', email: 'b@example.com', by_model: m(7) }, // after /login
    { id: 'u3', kind: 'usage', ts: at(3), session_id: 'sess-ZZ01', email: null, by_model: m(2) }, // 0.1.8, account unreadable
    { id: 'o2', kind: 'session_open', ts: at(4), session_id: 'sess-ZZ02', email: 'c@example.com' }, // no usage yet
    { id: 'u4', kind: 'usage', ts: at(5), session_id: 'sess-ZZ03', by_model: m(1) }, // its session_open is missing
    { id: 'o5', kind: 'session_open', ts: at(6), session_id: 'sess-ZZ05', email: 'a@example.com' },
    { id: 'u5', kind: 'usage', ts: at(7), session_id: 'sess-ZZ05', by_model: m(3) },
    { id: 'o6', kind: 'session_open', ts: at(8), session_id: 'sess-ZZ05', email: 'b@example.com' }, // compact under b
    { id: 'u6', kind: 'usage', ts: at(9), session_id: 'sess-ZZ05', by_model: m(4) },
    { id: 'u7', kind: 'usage', ts: at(10), email: 'b@example.com', by_model: m(1) }, // no session id: no session counted
  ];
  fs.writeFileSync(path.join(led, `${isoWeek(new Date())}.jsonl`), recs.map((x) => JSON.stringify(x)).join('\n') + '\n');
  fs.writeFileSync(path.join(led, 'notes.jsonl'), JSON.stringify({ id: 'n1', kind: 'usage', ts: at(1), email: 'z@example.com', by_model: m(100) }) + '\n'); // not a week file
  const out = path.join(dir, 'weekly.json');
  const text = execFileSync(process.execPath, [REPORT, '--data-dir', path.join(dir, 'data'), '--json', out], { env: env(dir), encoding: 'utf8' });
  const s = JSON.parse(fs.readFileSync(out, 'utf8'));
  assert.deepEqual(s.accounts, ['a@example.com', 'b@example.com', 'c@example.com']);
  assert.deepEqual(Object.fromEntries(Object.entries(s.by_account).map(([k, v]) => [k, [v.sessions, v.requests, v.output]])), {
    'a@example.com': [2, 2, 8], // u1, u5
    'b@example.com': [2, 3, 12], // u2, u6 (opened again under b), u7 (no session)
    '(unknown)': [2, 2, 3], // u3 (email null), u4 (no session_open)
  });
  assert.equal(s.totals.output, 23);
  assert.match(text, /3 account\(s\)/);
  assert.match(text, /b@example\.com +sessions 2 · requests 3/);
  assert.ok(!/sess-ZZ/.test(text + fs.readFileSync(out, 'utf8')), 'no session id in the text or the JSON');
});

test('report.js counts a short plugin command through its expansion, and rate limits per account with the plan tier', () => {
  const dir = tmp();
  const led = path.join(dir, 'data', 'ledger');
  fs.mkdirSync(led, { recursive: true });
  const at = (min) => new Date(Date.now() - 3600e3 + min * 60e3).toISOString();
  const recs = [
    { id: 'o1', kind: 'session_open', ts: at(0), session_id: 'n1', email: 'a@example.com', org_rate_limit_tier: 'default_claude_max_5x' },
    { id: 'o2', kind: 'session_open', ts: at(1), session_id: 'n1', email: 'a@example.com', org_rate_limit_tier: 'default_claude_max_20x' }, // later: this tier
    { id: 'p1', kind: 'prompt', ts: at(2), session_id: 'n1', command: '/cc-init' },
    { id: 'e1', kind: 'expansion', ts: at(2), session_id: 'n1', command_name: 'cc-init', command_source: 'plugin' },
    { id: 'p2', kind: 'prompt', ts: at(3), session_id: 'n1', command: '/acme:review' },
    { id: 'e2', kind: 'expansion', ts: at(3), session_id: 'n1', command_name: 'acme:review', command_source: 'plugin' }, // counted once, not twice
    { id: 'p3', kind: 'prompt', ts: at(4), session_id: 'n1', command: '/notes' },
    { id: 'e3', kind: 'expansion', ts: at(4), session_id: 'n1', command_name: 'notes', command_source: 'project' },
    { id: 'p4', kind: 'prompt', ts: at(5), session_id: 'n1', command: null },
    { id: 'o3', kind: 'session_open', ts: at(6), session_id: 'old', email: 'b@example.com', org_rate_limit_tier: 'default_claude_max_20x', user_rate_limit_tier: 'seat_premium' },
    { id: 'p5', kind: 'prompt', ts: at(7), session_id: 'old', command: '/acme:plan' }, // before 0.1.9: the typed form decides
    { id: 'p6', kind: 'prompt', ts: at(8), session_id: 'old', command: '/plan' },
    { id: 'f1', kind: 'stop_failure', ts: at(9), session_id: 'n1', email: 'a@example.com', error: 'rate_limit' },
    { id: 'f2', kind: 'stop_failure', ts: at(10), session_id: 'old', error: 'rate_limit' }, // account unreadable: its session's
    { id: 'f3', kind: 'stop_failure', ts: at(11), session_id: 'n1', email: 'a@example.com', error: 'overloaded' },
  ];
  fs.writeFileSync(path.join(led, `${isoWeek(new Date())}.jsonl`), recs.map((x) => JSON.stringify(x)).join('\n') + '\n');
  const out = path.join(dir, 'weekly.json');
  const text = execFileSync(process.execPath, [REPORT, '--data-dir', path.join(dir, 'data'), '--json', out], { env: env(dir), encoding: 'utf8' });
  const s = JSON.parse(fs.readFileSync(out, 'utf8'));
  assert.equal(s.skill_or_plugin_prompt_ratio, 0.5, 'p1, p2 through their expansions and p5 by its prefix: 3 of 6');
  assert.deepEqual(s.command_sources, { plugin: 2, project: 1 });
  assert.deepEqual(s.commands_resolved, { 'cc-init': 1, 'acme:review': 1, notes: 1 });
  assert.match(text, /commands as resolved: cc-init×1 acme:review×1 notes×1/);
  assert.deepEqual(s.stop_failures, { rate_limit: 2, overloaded: 1 });
  assert.deepEqual([s.by_account['a@example.com'].rate_limits, s.by_account['b@example.com'].rate_limits], [1, 1]);
  assert.deepEqual(s.account_tiers, { 'a@example.com': 'default_claude_max_20x', 'b@example.com': 'seat_premium' });
  assert.match(text, /a@example\.com \(default_claude_max_20x\) +sessions 0 · requests 0 · output 0\.0M · cache_read 0\.0M · rate limits 1/);
  assert.match(text, /turns ended by an API error: rate_limit×2 overloaded×1/);
});
