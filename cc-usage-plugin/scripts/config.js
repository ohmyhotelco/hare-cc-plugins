'use strict';
// Configuration rules shared by the hook collector (collect.js) and the setup helper (init.js), so a
// value the helper accepts is one the collector uploads with. Node built-ins only.
const { createHash } = require('crypto');

const LOOPBACK = ['127.0.0.1', 'localhost', '[::1]'];

// The developer id becomes a folder name on the receiver, so it is kept to [a-z0-9._-]; a value with
// nothing left (e.g. only non-Latin letters) becomes a hash of the original. Two spellings can still
// normalize to one id, so ids are assigned per person after normalization (README § Install).
function normalizeDeveloper(raw) {
  const src = String(raw || '').normalize('NFKC').trim();
  let s = src.toLowerCase().replace(/[^a-z0-9._-]+/g, '-').replace(/_vti_/g, '-vti-')
    .replace(/-{2,}/g, '-').replace(/^[._-]+|[._-]+$/g, '');
  if (/^(con|prn|aux|nul|com\d|lpt\d)(\.|$)/.test(s)) s = `u-${s}`;
  s = s.slice(0, 64).replace(/[._-]+$/, ''); // the cap last, so normalizing a normalized id changes nothing
  if (s) return s;
  return src ? `u-${createHash('sha256').update(src).digest('hex').slice(0, 8)}` : 'unknown';
}

// Why an endpoint cannot be uploaded to, or null: HTTPS only (plain http only to loopback), and the
// query must not already carry the values the upload appends (README § Upload contract).
function endpointProblem(endpoint) {
  let u = null;
  try { u = new URL(endpoint); } catch (_) { /* not a URL */ }
  if (!u || !(u.protocol === 'https:' || (u.protocol === 'http:' && LOOPBACK.includes(u.hostname)))) return 'endpoint-not-https';
  if (['developer', 'week', 'id'].some((k) => u.searchParams.has(k))) return 'endpoint-has-developer-week-or-id';
  return null;
}

// Why an upload configuration is refused, or null (D4).
function uploadProblem({ endpoint, token, developerSet }) {
  return endpointProblem(endpoint) || (!token && 'no-token') || (!developerSet && 'no-developer') || null;
}

module.exports = { LOOPBACK, normalizeDeveloper, endpointProblem, uploadProblem };
