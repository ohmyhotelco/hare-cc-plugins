#!/usr/bin/env python3
"""Cross-file consistency checker for the Claude Code plugins in this repo.

WHY THIS EXISTS
---------------
A plugin is a corpus of instructions an LLM executes literally. Nothing compiles it, so an edit
that is syntactically fine can still be unexecutable: it names a parameter no caller passes, runs a
tool the skill has no permission for, jumps past the section that takes the lock, or derives a value
from a variable that was rebound two lines earlier.

Three rounds of hand-editing this corpus produced roughly as many defects as they removed, all of
that shape. Every check below encodes one of those defects so it cannot come back silently.

This validates *wiring*, not meaning. A clean run does not mean the instructions are correct — only
that they refer to things that exist and can be reached. Judgement still needs a reader.

USAGE
    scripts/check-plugin-consistency.py [plugin-dir ...]      # default: every */. with a CLAUDE.md
    scripts/check-plugin-consistency.py --quiet               # findings only
EXIT
    0 no findings   1 findings   2 usage/IO error
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

# The cross-file wiring vocabulary: names a caller must pass and a callee must declare.
#
# Deliberately a closed list, not "every {placeholder}". Agents are full of local placeholders
# (`{Entity}`, `{score}`, `{fixHint}`) that are derived in prose and have no caller — flagging those
# produced 74 findings on a clean-ish tree, and a checker that cries wolf is one nobody reads.
# Only names that travel between files belong here. Add a name when it becomes a contract.
WIRING = {
    "appDir", "baseDir", "srcPath", "sourceBaseDir", "featureDir", "planBaseDir",
    "planFile", "specDir", "uiDslDir", "prototypeDir", "deltaFile", "scopedFiles", "deltaMode",
    "routerMode", "serverState", "formStack", "e2eTool", "mockFirst", "renderingDefault",
    "i18n", "localesDir", "prettierTemplate", "eslintTemplate", "skills", "fixMode",
    "reviewReportFile", "e2eReportFile",
}

# Only tools whose use leaves a *syntactically distinctive* trace. `Write` and `Edit` are ordinary
# English words ("Edit entity flow" in a JSON sample), so guessing them produces noise; a missing
# Write/Edit permission surfaces the first time the skill runs, which is cheap. `npx` must be
# followed by a real package name — `npx …` in prose is documentation, not a command.
TOOL_EVIDENCE = {
    "Bash": [r"```(?:bash|sh)\b", r"\bnpx [a-z@]", r"^\s*git \w", r"\bmkdir -p\b",
             r"\bpnpm (?:add|install|run) ", r"\bcd \{"],
    "Task": [r"\bTask\(subagent_type"],
    "Agent": [r"\bAgent\(subagent_type"],
}


@dataclass
class Finding:
    path: str
    line: int
    check: str
    message: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}  [{self.check}] {self.message}"


def lineno(text: str, idx: int) -> int:
    return text.count("\n", 0, idx) + 1


def frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        return {}
    out = {}
    for ln in text[3:end].split("\n"):
        if ":" in ln:
            k, v = ln.split(":", 1)
            out[k.strip()] = v.strip()
    return out


def declared_params(text: str) -> set[str]:
    """Names an agent declares as inputs.

    Two shapes are in use across this repo and both count, or the checker cries wolf on the plugin
    it was not written against: a `## Input Parameters` bullet list (frontend-react-plugin), and an
    inline prose sentence in the preamble listing them in backticks (frontend-migration-plugin).
    """
    out: set[str] = set()
    m = re.search(r"^## Input Parameters$(.*?)(?=^## )", text, re.S | re.M)
    if m:
        out |= set(re.findall(r"^-\s+`([A-Za-z_][\w.]*)`", m.group(1), re.M))
    body = text[text.find("\n---", 3) + 4:] if text.startswith("---") else text
    preamble = body[:body.index("\n## ")] if "\n## " in body else body
    out |= set(re.findall(r"`([A-Za-z_][\w.]*)`", preamble))
    return out


def placeholders(text: str) -> list[tuple[str, int]]:
    """`{name}` occurrences outside fenced code blocks that look like variables."""
    out, fenced = [], False
    for i, ln in enumerate(text.split("\n"), 1):
        if ln.lstrip().startswith("```"):
            fenced = not fenced
            continue
        for m in re.finditer(r"\{([A-Za-z_][\w]*)\}", ln):
            out.append((m.group(1), i))
    return out


# --------------------------------------------------------------------------- checks

def check_agent_params(agents: dict[str, tuple[Path, str]]) -> list[Finding]:
    """Every {var} an agent's body uses must be a declared input (or ambient)."""
    out = []
    for name, (path, text) in agents.items():
        decl = declared_params(text)
        seen = set()
        for var, ln in placeholders(text):
            if var not in WIRING or var in decl or var in seen:
                continue
            seen.add(var)
            out.append(Finding(str(path), ln, "agent-param",
                               f"`{{{var}}}` used but not declared in ## Input Parameters"))
    return out


def check_call_sites(skills: dict[str, tuple[Path, str]],
                     agents: dict[str, tuple[Path, str]]) -> list[Finding]:
    """A launcher must pass every parameter the launched agent declares and actually uses."""
    out = []
    for sname, (spath, stext) in skills.items():
        for m in re.finditer(r'(?:Agent|Task)\(subagent_type:\s*"([a-z0-9-]+)"', stext):
            agent = m.group(1)
            if agent not in agents:
                out.append(Finding(str(spath), lineno(stext, m.start()), "missing-agent",
                                   f"launches `{agent}` but agents/{agent}.md does not exist"))
                continue
            _, atext = agents[agent]
            block_end = stext.find('")', m.start())
            block = stext[m.start(): block_end if block_end != -1 else m.start() + 2000]
            used = {v for v, _ in placeholders(atext)}
            for p in sorted(declared_params(atext) & used & WIRING):
                if re.search(rf"^\s*-\s+{re.escape(p)}\s*:", block, re.M):
                    continue
                if re.search(rf"\b{re.escape(p)}\b.*\bomit\b", block):
                    continue
                out.append(Finding(str(spath), lineno(stext, m.start()), "call-site",
                                   f"`{agent}` uses `{{{p}}}` but this launch does not pass it"))
    return out


def check_tool_permissions(skills: dict[str, tuple[Path, str]]) -> list[Finding]:
    """A skill must declare every tool its body actually uses."""
    out = []
    for name, (path, text) in skills.items():
        fm = frontmatter(text)
        allowed = {t.strip() for t in fm.get("allowed-tools", "").split(",") if t.strip()}
        body = text[text.find("\n---", 3):]
        for tool, pats in TOOL_EVIDENCE.items():
            if tool in allowed:
                continue
            for pat in pats:
                m = re.search(pat, body)
                if m:
                    out.append(Finding(str(path), lineno(text, text.find("\n---", 3) + m.start()),
                                       "tool-permission",
                                       f"body uses {tool} (matched /{pat}/) but allowed-tools lacks it"))
                    break
    return out


def check_lock_reachability(skills: dict[str, tuple[Path, str]]) -> list[Finding]:
    """A `proceed to Step N` must not jump over the Lock Acquire section."""
    out = []
    for name, (path, text) in skills.items():
        lock = re.search(r"^###\s+Lock Acquire\s*$", text, re.M)
        if not lock:
            continue
        heads = {}
        for m in re.finditer(r"^###\s+Step\s+([\w.-]+)", text, re.M):
            heads.setdefault(m.group(1), m.start())
        # Case matters: these docs write `Step 3` for a section heading and `step 3` for a
        # numbered item inside another step. Matching case-insensitively flagged three jumps
        # between sub-items of Step 1 as lock bypasses.
        for m in re.finditer(r"(?:[Pp]roceed|[Gg]o|[Ss]kip) to Step\s+([\w.-]+)", text):
            target = m.group(1).rstrip(".,)")
            pos = heads.get(target)
            if pos is None:
                continue
            if m.start() < lock.start() < pos:
                out.append(Finding(str(path), lineno(text, m.start()), "lock-bypass",
                                   f"jump to Step {target} skips the Lock Acquire section"))
    return out


def check_bind_before_use(skills: dict[str, tuple[Path, str]]) -> list[Finding]:
    """Deriving from a name that the same step rebound, or before its default is applied."""
    out = []
    for name, (path, text) in skills.items():
        for m in re.finditer(r"^\d+\.\s+\*\*Derive `(\w+)`\*\*(.*)$", text, re.M):
            derived, rest = m.group(1), m.group(2)
            before = text[:m.start()]
            after = text[m.end():m.end() + 1500]
            for src in re.findall(r"`(\w+)`", rest):
                if src == derived:
                    continue
                rebind = re.search(rf"`{src}` as \*\*`(\w+)`\*\*", before)
                if rebind:
                    out.append(Finding(str(path), lineno(text, m.start()), "unbound-var",
                                       f"derives `{derived}` from `{src}`, but `{src}` was bound to "
                                       f"`{rebind.group(1)}` above — `{src}` is not in scope"))
                if re.search(rf"If `{src}` is missing, use default", after):
                    out.append(Finding(str(path), lineno(text, m.start()), "derive-before-default",
                                       f"derives `{derived}` from `{src}` before `{src}`'s default is applied"))
    return out


def check_command_paths(files: dict[str, tuple[Path, str]]) -> list[Finding]:
    """Commands run from appDir must not take repo-relative path arguments."""
    out = []
    bad = re.compile(r"npx\s+(?:vitest|eslint|tsc|playwright|vite|react-router)[^\n`]*"
                     r"\{(baseDir|planBaseDir|sourceBaseDir|featureDir)\}")
    for name, (path, text) in files.items():
        for m in bad.finditer(text):
            out.append(Finding(str(path), lineno(text, m.start()), "command-path",
                               f"command argument uses repo-relative `{{{m.group(1)}}}`; "
                               f"use `{{srcPath}}` (CLAUDE.md § Build Command Working Directory)"))
    return out


def check_ordered_lists(files: dict[str, tuple[Path, str]]) -> list[Finding]:
    """Top-level ordered lists must be sequential from 1."""
    out = []
    for name, (path, text) in files.items():
        lines, i, fenced = text.split("\n"), 0, False
        while i < len(lines):
            if lines[i].lstrip().startswith("```"):
                fenced = not fenced
            if fenced:
                i += 1
                continue
            m = re.match(r"^(\d+)\. ", lines[i])
            if not m or m.group(1) != "1":
                i += 1
                continue
            nums, start, expect = [1], i, 2
            i += 1
            while i < len(lines):
                if lines[i].lstrip().startswith("```"):
                    fenced = not fenced
                    i += 1
                    continue
                mm = re.match(r"^(\d+)\. ", lines[i])
                if mm and not fenced:
                    nums.append(int(mm.group(1)))
                    expect += 1
                elif fenced or lines[i].startswith(("   ", "\t", ">")) or lines[i].strip() == "":
                    pass
                else:
                    break
                i += 1
            if len(nums) > 1 and nums != list(range(1, len(nums) + 1)):
                out.append(Finding(str(path), start + 1, "list-numbering",
                                   f"ordered list is {nums}, expected 1..{len(nums)}"))
    return out


def check_references(plugin: Path, files: dict[str, tuple[Path, str]]) -> list[Finding]:
    """`templates/x.md`, `agents/x.md`, and `CLAUDE.md § Heading` must resolve."""
    out = []
    claude = (plugin / "CLAUDE.md").read_text() if (plugin / "CLAUDE.md").exists() else ""
    headings = set()
    for m in re.finditer(r"^#{2,4}\s+(.+?)\s*$", claude, re.M):
        headings.add(m.group(1).strip())
    for m in re.finditer(r"^\*\*(.+?)\*\*[:.]?", claude, re.M):
        headings.add(m.group(1).strip().rstrip("."))
    for name, (path, text) in files.items():
        for m in re.finditer(r"(templates/[a-z0-9-]+\.md|agents/[a-z0-9-]+\.md)", text):
            if not (plugin / m.group(1)).exists():
                out.append(Finding(str(path), lineno(text, m.start()), "dangling-file",
                                   f"references {m.group(1)}, which does not exist"))
        for m in re.finditer(r"CLAUDE\.md\s+§\s+([A-Za-z0-9 &'`\-]+?)(?=[,.;)\n]|\s+—|\s+\()", text):
            h = m.group(1).strip().rstrip(",")
            if not h:
                continue
            hl = h.lower()
            if any(hl in x.lower() or x.lower() in hl for x in headings if len(x) > 8):
                continue
            out.append(Finding(str(path), lineno(text, m.start()), "dangling-section",
                               f'references CLAUDE.md § "{h}", which is not a heading there'))
    return out


# --------------------------------------------------------------------------- driver

def load(d: Path, pattern: str) -> dict[str, tuple[Path, str]]:
    out = {}
    for p in sorted(d.glob(pattern)):
        out[p.stem if p.name != "SKILL.md" else p.parent.name] = (p, p.read_text())
    return out


def run(plugin: Path) -> list[Finding]:
    agents = load(plugin / "agents", "*.md")
    skills = load(plugin / "skills", "*/SKILL.md")
    every = {**{f"agent:{k}": v for k, v in agents.items()},
             **{f"skill:{k}": v for k, v in skills.items()}}
    if (plugin / "CLAUDE.md").exists():
        every["CLAUDE.md"] = (plugin / "CLAUDE.md", (plugin / "CLAUDE.md").read_text())
    for p in sorted((plugin / "templates").glob("*.md")):
        every[f"template:{p.stem}"] = (p, p.read_text())

    return (check_agent_params(agents)
            + check_call_sites(skills, agents)
            + check_tool_permissions(skills)
            + check_lock_reachability(skills)
            + check_bind_before_use(skills)
            + check_command_paths(every)
            + check_ordered_lists(every)
            + check_references(plugin, every))


def main(argv: list[str]) -> int:
    quiet = "--quiet" in argv
    args = [a for a in argv[1:] if not a.startswith("--")]
    root = Path(__file__).resolve().parent.parent
    plugins = [Path(a) for a in args] or [p.parent for p in sorted(root.glob("*/CLAUDE.md"))]

    total = 0
    for plugin in plugins:
        if not plugin.is_dir():
            print(f"not a directory: {plugin}", file=sys.stderr)
            return 2
        seen, findings = set(), []
        for f in sorted(run(plugin), key=lambda f: (f.check, f.path, f.line)):
            k = (f.path, f.line, f.check, f.message)
            if k not in seen:
                seen.add(k)
                findings.append(f)
        if not quiet:
            print(f"\n=== {plugin.name} ===")
        if findings:
            by_check: dict[str, list[Finding]] = {}
            for f in findings:
                by_check.setdefault(f.check, []).append(f)
            for check, group in sorted(by_check.items()):
                print(f"\n  {check} ({len(group)})")
                for f in group:
                    print(f"    {f}")
            total += len(findings)
        elif not quiet:
            print("  no findings")

    if not quiet:
        print(f"\n{total} finding(s)")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
