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
