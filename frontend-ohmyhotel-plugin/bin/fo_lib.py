"""Shared helpers for the fo-* scripts (imported by file path; bin/ is not a package).

- sibling(name): path of another bin/ script, so scripts work when bin/ is not on PATH.
- read_json / write_json_atomic: tolerant read, atomic replace on write.
- locked(path): an exclusive file lock around read-modify-write of a shared file (progress.json).
- read_stdin_json(): a JSON payload from a pipe, {} when stdin is empty or a TTY — the Claude Code
  Bash tool gives a non-TTY empty stdin, which json.load() would reject.
"""
import contextlib, fcntl, json, os, sys, tempfile

BIN = os.path.dirname(os.path.realpath(__file__))

def sibling(name):
    p = os.path.join(BIN, name)
    return p if os.path.exists(p) else name

def read_json(p, default=None):
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default

def write_json_atomic(p, obj):
    d = os.path.dirname(p) or "."
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".tmp-", dir=d)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, p)

@contextlib.contextmanager
def locked(path):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path + ".lock", "w") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lf, fcntl.LOCK_UN)

def read_stdin_json():
    if sys.stdin is None or sys.stdin.isatty():
        return {}
    data = sys.stdin.read()
    if not data.strip():
        return {}
    return json.loads(data)

def utcnow():
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ---- e2e layout (shared by fo-verify-run and fo-progress-report) -------------------------------
import hashlib, re, subprocess

E2E_ALLOWED = [
    re.compile(r"^fixtures\.ts$"),
    re.compile(r"^tsconfig\.json$"),
    re.compile(r"^support/[a-z][A-Za-z0-9-]*\.ts$"),                      # cross-screen helpers (no leading digit: not a screen id)
    re.compile(r"^support/[a-z][A-Za-z0-9-]*\.setup\.ts$"),                # Playwright setup tests (auth.setup.ts)
    re.compile(r"^support/pages/\d{2,3}[a-z]?-[a-z0-9-]+\.ts$"),            # one page object per screen
    re.compile(r"^screens/\d{2,3}[a-z]?-[a-z0-9-]+/(?:TS|E2E)-\d{3}(?:-\d+)*\.spec\.ts$"),
    re.compile(r"^visual/\d{2,3}[a-z]?-[a-z0-9-]+\.spec\.ts$"),
    re.compile(r"^visual/__snapshots__/.+\.(?:png|jpg|webp)$"),
    re.compile(r"^seo/\d{2,3}[a-z]?-[a-z0-9-]+\.[a-zA-Z]+\.spec\.ts$"),
    re.compile(r"^(?:support/pages|screens|visual|seo)/(?:.*/)?\.gitkeep$"),
]
# run output is judged by LOCATION, never by extension across the app (a hotel site ships .webm and .zip assets)
RUN_OUTPUT_DIRS = re.compile(r"^(?:test-results|playwright-report|\.auth)(/|$)|(^|/)\.artifacts(/|$)")
RUN_OUTPUT_NAMES_IN_E2E = re.compile(r"(^|/)(?:test-failed-.*\.png|trace\.zip|video\.webm|error-context\.md|\.last-run\.json)$")

def repo_root():
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None

def e2e_inventory(app_root):
    """→ (files, misplaced, leaked, error). files/misplaced are e2e-relative; leaked are app-relative tracked
    run-output paths. error is set when git could not be consulted (the caller records not-run)."""
    e2e = os.path.join(app_root, "e2e")
    files, misplaced = [], []
    if os.path.isdir(e2e):
        for root, dirs, names in os.walk(e2e):
            dirs[:] = [d for d in dirs if d != "node_modules"]
            for n in names:
                if n == ".DS_Store": continue
                rel = os.path.relpath(os.path.join(root, n), e2e)
                files.append(rel)
                if not any(rx.match(rel) for rx in E2E_ALLOWED): misplaced.append(rel)
    r = subprocess.run(["git", "ls-files", "--", app_root], capture_output=True, text=True)
    if r.returncode != 0:
        return sorted(files), sorted(misplaced), [], (r.stderr.strip() or f"git ls-files exited {r.returncode}")
    leaked = []
    for t in r.stdout.splitlines():
        rel = os.path.relpath(t, app_root)
        if RUN_OUTPUT_DIRS.search(rel) or (rel.startswith("e2e/") and RUN_OUTPUT_NAMES_IN_E2E.search(rel)):
            leaked.append(rel)
    return sorted(files), sorted(misplaced), sorted(leaked), None

def e2e_layout_fingerprint(files, leaked):
    h = hashlib.sha256()
    for f in files: h.update(b"f:" + f.encode() + b"\0")
    for l in leaked: h.update(b"l:" + l.encode() + b"\0")
    return h.hexdigest()[:16]
