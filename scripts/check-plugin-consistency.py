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

import json
import re
import shutil
import subprocess
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
    "reviewReportFile", "e2eReportFile", "devPort", "standalone", "mode",
}

# Only tools whose use leaves a *syntactically distinctive* trace. `Write` and `Edit` are ordinary
# English words ("Edit entity flow" in a JSON sample), so guessing them produces noise; a missing
# Write/Edit permission surfaces the first time the skill runs, which is cheap. `npx` must be
# followed by a real package name — `npx …` in prose is documentation, not a command.
TOOL_EVIDENCE = {
    "Bash": [r"(?<!\\)```(?:bash|sh)\b", r"\bnpx [a-z@]", r"^\s*git \w", r"\bmkdir -p\b",
             r"\bpnpm (?:add|install|run) ", r"\bcd \{"],
    "Task": [r"\bTask\(subagent_type"],
    "Agent": [r"\bAgent\(subagent_type", r"(?<!Task\()subagent_type:\s*\""],   # call form and the prose form (a Task launch is not Agent evidence)
    "Workflow": [r'\bname:\s*"[a-z0-9-]+-plugin:[a-z0-9-]+"'],
}

# After auto-compaction a skill comes back cut at 5,000 "tokens", which the harness measures as characters / 4
# (a re-attached skill was cut at about 20,000 characters; real tokens run closer to 2.5 characters each). The
# rest then takes a Read to recover. The docs also ask for SKILL.md under 500 lines.
SKILL_MAX_TOKENS = 5000
SKILL_MAX_LINES = 500


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
                     agents: dict[str, tuple[Path, str]],
                     plugin_name: str = "") -> list[Finding]:
    """A launcher must pass every parameter the launched agent declares and actually uses."""
    out = []
    for sname, (spath, stext) in skills.items():
        # a launch may qualify the agent with its plugin (`backend-webflux-plugin:code-reviewer`):
        # two installed plugins can ship an agent of the same name -- and the qualifier must then
        # be THIS plugin's, or the launch reaches the other plugin's agent
        # both the call form `Agent(subagent_type: "x")` and the prose form "Launch the `x` agent
        # (`subagent_type: \"plugin:x\"`) with: - param: …" -- the parameter bullets follow either
        for m in re.finditer(r'subagent_type:\s*"(?:([a-z0-9-]+):)?([a-z0-9-]+)"', stext):
            qualifier, agent = m.group(1), m.group(2)
            if qualifier and plugin_name and qualifier != plugin_name:
                out.append(Finding(str(spath), lineno(stext, m.start()), "foreign-agent",
                                   f"launches `{qualifier}:{agent}` but this plugin is `{plugin_name}`"))
                continue
            if agent not in agents:
                out.append(Finding(str(spath), lineno(stext, m.start()), "missing-agent",
                                   f"launches `{agent}` but agents/{agent}.md does not exist"))
                continue
            _, atext = agents[agent]
            # the block is this launch's own text: up to its closing `")`, the next launch, or 2000 chars
            nxt = re.search(r'subagent_type:\s*"', stext[m.end():])
            limit = m.end() + (nxt.start() if nxt else 2000)
            block_end = stext.find('")', m.start(), limit)
            block = stext[m.start(): block_end if block_end != -1 else limit]
            used = {v for v, _ in placeholders(atext)}
            for p in sorted(declared_params(atext) & used & WIRING):
                if re.search(rf"^\s*-\s+`?{re.escape(p)}`?\s*:", block, re.M):   # `- param:` or `- `param`:`
                    continue
                if re.search(rf"\b{re.escape(p)}\b.*\bomit\b", block):
                    continue
                if re.search(rf"`{re.escape(p)}`", block):   # inline form: "with only its params: `app`, `page`"
                    continue
                out.append(Finding(str(spath), lineno(stext, m.start()), "call-site",
                                   f"`{agent}` uses `{{{p}}}` but this launch does not pass it"))
    return out


def check_passed_but_unbound(skills: dict[str, tuple[Path, str]]) -> list[Finding]:
    """A launcher may only pass a value it actually has.

    The call-site check verifies the callee's needs are met; this verifies the caller can meet
    them. Appending `- routerMode: {routerMode}` to a launch in a skill whose Step 0 never reads
    `routerMode` produces a prompt with an unresolved placeholder — the agent then receives the
    literal text, or the launcher invents a value.
    """
    out = []
    for name, (path, text) in skills.items():
        for m in re.finditer(r"^\s*-\s+`?(\w+)`?\s*:\s*\{(\w+)\}\s*$", text, re.M):   # `- param:` or `- `param`:`, space before the colon allowed
            param, var = m.group(1), m.group(2)
            if var not in WIRING:
                continue
            # "Bound before use" — anywhere earlier in the skill, not only Step 0. A value may
            # legitimately be read from plan.json in Step 1 (localesDir) rather than from config.
            # Other launches' parameter lines do not count as a binding.
            before = re.sub(r"^\s*-\s+`?\w+`?\s*:\s*\{\w+\}\s*$", "", text[: m.start()], flags=re.M)   # both bullet spellings
            if re.search(rf"`{var}`", before):
                continue
            if re.search(rf"Derive `{var}`", before):
                continue
            # `Set `fixMode = "e2e"`` binds it just as a config read does
            if re.search(rf"`{var}\s*=", before) or re.search(rf"Set `{var}`", before):
                continue
            out.append(Finding(str(path), lineno(text, m.start()), "passed-unbound",
                               f"launch passes `{{{var}}}` but Step 0 never reads or derives it"))
    return out


def check_stale_number_refs(files: dict[str, tuple[Path, str]]) -> list[Finding]:
    """Prose that cites a list item by number must cite one that exists.

    Renumbering a list silently invalidates every `proceed to step 7` / `skip checks 7-8` pointing
    into it. A script renumbered nine lists in this repo and broke two such references; both read
    fine and pointed at the wrong instruction.

    Resolution is by *existence of the label*, not by list length: these docs use letter-suffixed
    items (`6b.`) that a length comparison misreads as out of range. `step N` may also name a heading
    (`### Step 5:`, `#### 5.2 Manual`), anywhere in the file, so a heading counts as its label.
    """
    out = []
    ref = re.compile(r"(?:proceed to|go to|skip|see)\s+(?:prerequisite\s+)?"
                     r"(step|steps|check|checks|item|items)\s+(\d+)(?:\s*[-–]\s*(\d+))?", re.I)
    heading = re.compile(r"^#{1,6}\s+(?:Step\s+)?(\d+)", re.I)
    for name, (path, text) in files.items():
        lines = text.split("\n")
        headed = {int(m.group(1)) for m in map(heading.match, lines) if m}
        # section = run of lines between `### ` headings; labels defined in each
        bounds, cur = [], 0
        for i, ln in enumerate(lines):
            if ln.startswith("### "):
                bounds.append((cur, i))
                cur = i
        bounds.append((cur, len(lines)))
        for lo, hi in bounds:
            labels = set()
            for ln in lines[lo:hi]:
                m = re.match(r"^(\d+)[a-z]?\. ", ln)
                if m:
                    labels.add(int(m.group(1)))
            if not labels:
                continue
            for i in range(lo, hi):
                for m in ref.finditer(lines[i]):
                    known = labels | headed if m.group(1).lower().startswith("step") else labels
                    for g in (m.group(2), m.group(3)):
                        if g and int(g) not in known:
                            out.append(Finding(str(path), i + 1, "stale-number-ref",
                                               f"cites item {g}, which this section does not define "
                                               f"(defines {sorted(labels)}) — renumbering likely "
                                               f"invalidated this reference"))
    return out


def check_section_refs(files: dict[str, tuple[Path, str]]) -> list[Finding]:
    """A prose reference to a numbered section must carry that section's current name.

    Round 5 swapped two section headings (2-D.6 <-> 2-D.7) and every prose reference written
    against the old numbering silently inverted its meaning. Numbers rot when sections move;
    a name beside the number turns the rot visible. So: a bare `2-D.N` reference is a finding,
    and a named one must match the heading that N currently carries.
    """
    out = []
    for name, (path, text) in files.items():
        heads = {m.group(1): m.group(2).strip()
                 for m in re.finditer(r"^#{3,4}\s+(2-D\.[\dF]+):\s*(.+?)\s*$", text, re.M)}
        if not heads:
            continue
        for m in re.finditer(r"(?<![#.\w])(2-D\.[\d]+)(?!:)", text):
            sec = m.group(1)
            line_start = text.rfind("\n", 0, m.start()) + 1
            line = text[line_start: text.find("\n", m.start())]
            if line.lstrip().startswith("#"):
                continue
            title = heads.get(sec)
            if title is None:
                out.append(Finding(str(path), lineno(text, m.start()), "section-ref",
                                   f"references section {sec}, which does not exist"))
                continue
            # a name must appear near the reference and match the current heading
            ctx = text[m.end(): m.end() + 90]
            first_word = re.sub(r"\s*\(.*", "", title).split()[0].rstrip("(").lower()
            if first_word not in ctx.lower() and first_word not in line.lower():
                out.append(Finding(str(path), lineno(text, m.start()), "section-ref",
                                   f'bare/mismatched reference to {sec} — its current heading is '
                                   f'"{title}"; name the section beside the number so a heading '
                                   f"swap cannot silently invert the meaning"))
    return out


def check_duplicate_json_keys(files: dict[str, tuple[Path, str]]) -> list[Finding]:
    """No object in a fenced JSON example may define the same key twice.

    Two mechanical edits in different rounds each added `sourceHash` to the same example object,
    with different values. JSON consumers keep one and drop the other, and nothing defines which —
    a single-line syntax check cannot see it because the members sit on different lines.
    """
    out = []
    for name, (path, text) in files.items():
        for bm in re.finditer(r"```json[c]?\n(.*?)```", text, re.S):
            block, base = bm.group(1), bm.start(1)
            stack: list[dict] = []
            for lm in re.finditer(r'[{}]|"([\w-]+)"\s*:', block):
                tok = lm.group(0)
                if tok == "{":
                    stack.append({})
                elif tok == "}":
                    if stack:
                        stack.pop()
                elif stack is not None and lm.group(1) and stack:
                    key = lm.group(1)
                    if key in stack[-1]:
                        out.append(Finding(str(path), lineno(text, base + lm.start()),
                                           "duplicate-json-key",
                                           f'object defines "{key}" twice (first at line '
                                           f"{lineno(text, base + stack[-1][key])})"))
                    else:
                        stack[-1][key] = lm.start()
    return out


def check_version_sync(plugin: Path) -> list[Finding]:
    """plugin.json, marketplace.json, and the root README's version label must agree.

    The repo rule synced the first two; the root README's `v{X}` labels were in nobody's rule and
    rotted silently — two of five were stale when this rule was written (one of them mine, missed
    across fourteen version-bumping commits; one predating the branch entirely).
    """
    import json
    out = []
    pj_path = plugin / ".claude-plugin" / "plugin.json"
    if not pj_path.exists():
        return out
    version = json.loads(pj_path.read_text()).get("version", "")
    root = plugin.parent
    mp_path = root / ".claude-plugin" / "marketplace.json"
    if mp_path.exists():
        for entry in json.loads(mp_path.read_text()).get("plugins", []):
            if entry.get("name") == plugin.name and entry.get("version") != version:
                out.append(Finding(str(mp_path), 1, "version-sync",
                                   f"{plugin.name}: marketplace says {entry.get('version')}, "
                                   f"plugin.json says {version}"))
    readme = root / "README.md"
    if readme.exists():
        text = readme.read_text()
        m = re.search(rf"\(\./{re.escape(plugin.name)}/\)\s+`v([\d.]+)`", text)
        if m and m.group(1) != version:
            out.append(Finding(str(readme), lineno(text, m.start()), "version-sync",
                               f"{plugin.name}: root README label is v{m.group(1)}, "
                               f"plugin.json says {version}"))
    return out


def check_tool_permissions(skills: dict[str, tuple[Path, str]]) -> list[Finding]:
    """A skill must declare every tool its body actually uses."""
    out = []
    for name, (path, text) in skills.items():
        fm = frontmatter(text)
        if fm.get("user-invocable") == "false":
            continue   # a conventions skill preloaded into agents names commands for them; it runs nothing
        rules = [t.strip() for t in fm.get("allowed-tools", "").split(",") if t.strip()]
        # A scoped rule such as Bash(node:*) declares the tool, but only for the commands it covers.
        allowed = {re.sub(r"\(.*\)$", "", t) for t in rules}
        start = text.find("\n---", 3)
        body = text[start:]
        for tool, pats in TOOL_EVIDENCE.items():
            if tool in allowed:
                continue
            for pat in pats:
                m = re.search(pat, body)
                if m:
                    out.append(Finding(str(path), lineno(text, start + m.start()),
                                       "tool-permission",
                                       f"body uses {tool} (matched /{pat}/) but allowed-tools lacks it"))
                    break
        scopes = [re.sub(r"(?::\*| \*)$", "", m.group(1)) for m in (re.fullmatch(r"Bash\((.*)\)", t) for t in rules) if m]
        if scopes and "Bash" not in rules:
            # Each command of a chained line is checked on its own, as the permission rules do; a
            # command substitution cannot be checked against a prefix at all.
            for block in re.finditer(r"```(?:bash|sh|shell|console|zsh)\r?\n(.*?)```", body, re.S):
                for k, line in enumerate(block.group(1).splitlines()):
                    cmd = re.sub(r"^\$\s+", "", line.strip())
                    if not cmd or cmd.startswith("#"):
                        continue
                    parts = re.split(r"\s*(?:&&|\|\||;|\|)\s*", cmd)
                    bad = "$(" in cmd or "`" in cmd or any(p and not any(p.startswith(s) for s in scopes) for p in parts)
                    if bad:
                        out.append(Finding(str(path), lineno(text, start + block.start(1)) + k,
                                           "tool-permission",
                                           f"bash command outside the allowed-tools scope: {cmd[:60]}"))
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
    """A derivation must name a variable that is in scope and already defaulted."""
    out = []
    for name, (path, text) in skills.items():
        for m in re.finditer(r"^\d+\.\s+\*\*Derive `(\w+)`\*\*(.*)$", text, re.M):
            derived, rest = m.group(1), m.group(2)
            before, after = text[: m.start()], text[m.end(): m.end() + 1500]
            claims_default = "after its default is applied" in rest
            for src in dict.fromkeys(re.findall(r"`(\w+)`", rest)):
                if src == derived or src not in WIRING:
                    continue
                rebind = re.search(rf"`{src}` as \*\*`(\w+)`\*\*", before)
                if rebind:
                    out.append(Finding(str(path), lineno(text, m.start()), "unbound-var",
                                       f"derives `{derived}` from `{src}`, but `{src}` was bound to "
                                       f"`{rebind.group(1)}` above — `{src}` is not in scope"))
                if re.search(rf"If `{src}` is missing, use default", after):
                    out.append(Finding(str(path), lineno(text, m.start()), "derive-before-default",
                                       f"derives `{derived}` from `{src}` before `{src}`'s default "
                                       f"is applied"))
                # Claiming a default was applied is a claim; it needs one to exist.
                if claims_default and not re.search(rf"If `{src}` is missing, use default", text):
                    out.append(Finding(str(path), lineno(text, m.start()), "missing-default",
                                       f'derives `{derived}` from `{src}` "after its default is '
                                       f'applied", but no default for `{src}` is ever applied'))
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
    for sdir in sorted((plugin / "skills").glob("*-shared")):
        shared = (sdir / "SKILL.md").read_text()
        heads = {m.group(1).strip() for m in re.finditer(r"^#{2,4}\s+(.+?)\s*$", shared, re.M)}
        heads |= {m.group(1).strip().rstrip(".") for m in re.finditer(r"^\*\*(.+?)\*\*[:.]?", shared, re.M)}
        ref = re.compile(re.escape(sdir.name) + r"`?\s+§\s+([A-Za-z0-9 &'`+\-]+?)(?=[,.:;)|\n]|\s+—|\s+\(|\s+\|)")
        for name, (path, text) in files.items():
            for m in ref.finditer(text):
                for part in m.group(1).split("+"):
                    hl = part.strip().lower()
                    if not any(hl in x.lower() or x.lower() in hl for x in heads):
                        out.append(Finding(str(path), lineno(text, m.start()), "dangling-section",
                                           f'references {sdir.name} § "{part.strip()}", which is not a heading there'))
    return out


def check_plugin_paths(name: str, agents: dict[str, tuple[Path, str]],
                       skills: dict[str, tuple[Path, str]]) -> list[Finding]:
    """Installed, the working directory is the user's project, so a bare `templates/x.md` finds nothing,
    and the Agent tool rejects an unqualified plugin agent name, leaving the model to retry from a list."""
    out = []
    for path, text in [v for v in agents.values()] + [v for v in skills.values()]:
        for m in re.finditer(r"(?<![/}\w.-])templates/(?:[a-z0-9-]+\.(?:md|json))?|(?<=[Rr]ead `)agents/[a-z0-9-]+\.md", text):
            out.append(Finding(str(path), lineno(text, m.start()), "bare-plugin-path",
                               f"{m.group(0)} resolves against the project; use ${{CLAUDE_PLUGIN_ROOT}}/{m.group(0)}"))
        for m in re.finditer(r'subagent_type:\s*"?([a-z0-9-]+)"?(?![a-z0-9:-])', text):
            out.append(Finding(str(path), lineno(text, m.start()), "unqualified-agent",
                               f'launches "{m.group(1)}" without the `{name}:` qualifier'))
    # The prose spellings name no subagent_type at all; a skill that qualifies the agent anywhere is fine.
    prose = re.compile(r"[Ll]aunch(?: the| an?)? (?:`|\*\*)([a-z0-9-]+)(?:`|\*\*)|`([a-z0-9-]+)`(?: agent)?\s+\(Agent(?: tool)?\)")
    for path, text in skills.values():
        for m in prose.finditer(text):
            agent = m.group(1) or m.group(2)
            if agent in agents and f"{name}:{agent}" not in text:
                out.append(Finding(str(path), lineno(text, m.start()), "unqualified-agent",
                                   f'launches `{agent}` in prose without `subagent_type: "{name}:{agent}"`'))
    return out


def check_workflows(plugin: Path, name: str, agents: dict[str, tuple[Path, str]],
                    skills: dict[str, tuple[Path, str]]) -> list[Finding]:
    """What a workflow starts is wiring too. What it passes in a prompt is not checked."""
    out = []
    workflows = {p.stem: (p, p.read_text()) for p in sorted((plugin / "workflows").glob("*.js"))}
    for path, text in skills.values():
        for m in re.finditer(rf'\bname:\s*"{re.escape(name)}:([a-z0-9-]+)"', text):
            if m.group(1) not in workflows:
                out.append(Finding(str(path), lineno(text, m.start()), "missing-workflow",
                                   f"starts `{m.group(1)}` but workflows/{m.group(1)}.js does not exist"))
    node = shutil.which("node")
    # A script has top-level `await` and `return`, and only `export const meta`, so it compiles as a function body.
    compile_js = ("const s=require('fs').readFileSync(process.argv[1],'utf8').replace(/export const meta\\s*=/,'const meta =');"
                  "new (Object.getPrototypeOf(async function(){}).constructor)(s)")
    for wname, (path, text) in workflows.items():
        # `meta.name` becomes `/plugin:name`, and that command wins over a skill of the same name: the skill's
        # preconditions and locks are skipped, and the workflow gets the slash command's text as its `args`.
        m = re.search(r"""\bname:\s*['"]([a-z0-9-]+)['"]""", text)
        declared = m.group(1) if m else wname
        if declared != wname:
            out.append(Finding(str(path), lineno(text, m.start()), "workflow-name",
                               f"meta.name `{declared}` differs from the file name, and a skill starts it by name"))
        if declared in skills:
            out.append(Finding(str(path), lineno(text, m.start()) if m else 1, "workflow-shadows-skill",
                               f"`{declared}` takes over the slash command of skills/{declared}; name the workflow `{declared}-run`"))
        if node:
            r = subprocess.run([node, "-e", compile_js, str(path)], capture_output=True, text=True)
            if r.returncode:
                detail = next((ln for ln in r.stderr.split("\n") if "Error" in ln), "does not compile")
                out.append(Finding(str(path), 1, "workflow-syntax", detail.strip()))
        for m in re.finditer(r"\bDate\.now\(|\bMath\.random\(|\bnew Date\(\)", text):
            out.append(Finding(str(path), lineno(text, m.start()), "workflow-resume",
                               f"`{m.group(0)}` throws in a workflow, because it would break resume; pass the value in `args`"))
        for m in re.finditer(r"""agentType:\s*['"]([a-z0-9-]+)['"]""", text):
            out.append(Finding(str(path), lineno(text, m.start()), "unqualified-agent",
                               f'launches "{m.group(1)}" without the `{name}:` qualifier'))
        launched = {}
        for m in re.finditer(r"""['"`]([a-z0-9-]+-plugin):([a-z0-9-]+)['"`]""", text):
            if m.group(1) != name:
                out.append(Finding(str(path), lineno(text, m.start()), "foreign-agent",
                                   f"launches `{m.group(1)}:{m.group(2)}` but this plugin is `{name}`"))
            else:
                launched.setdefault(m.group(2), m.start())
        # a table of bare names used through a template: `plugin:${AGENT[n]}`
        table = re.search(r"const AGENT = \{(.*?)\}", text, re.S)
        if table and f"{name}:${{AGENT[" in text:
            for m in re.finditer(r""":\s*['"]([a-z0-9-]+)['"]""", table.group(1)):
                launched.setdefault(m.group(1), table.start(1) + m.start())
        for agent, idx in sorted(launched.items()):
            if agent not in agents:
                out.append(Finding(str(path), lineno(text, idx), "missing-agent",
                                   f"launches `{agent}` but agents/{agent}.md does not exist"))
    return out


def check_agent_frontmatter(agents: dict[str, tuple[Path, str]]) -> list[Finding]:
    """An agent on another model ignores the session's effort, so each agent states both."""
    return [Finding(str(path), 1, "agent-frontmatter", f"declares no `{key}`")
            for path, text in agents.values() for key in ("model", "effort") if not frontmatter(text).get(key)]


def check_skill_layout(plugin: Path, skills: dict[str, tuple[Path, str]]) -> list[Finding]:
    """A long skill loses its tail after compaction, and a reference file is read as plain text.

    `${CLAUDE_PLUGIN_ROOT}` is substituted in a skill's body but not in a file read with the Read tool,
    so text moved into `references/` must not carry it. A file nothing names is never read.
    """
    out = []
    for name, (path, text) in skills.items():
        if frontmatter(text).get("user-invocable") != "false":   # a preloaded skill is injected whole
            tokens, lines = len(text) // 4, text.count("\n")
            if tokens > SKILL_MAX_TOKENS or lines > SKILL_MAX_LINES:
                out.append(Finding(str(path), 1, "skill-size",
                                   f"about {tokens} tokens, {lines} lines (limits {SKILL_MAX_TOKENS}, {SKILL_MAX_LINES}); move a rarely used part to references/"))
        sdir = path.parent
        for m in re.finditer(r"references/([a-z0-9-]+\.md)", text):
            if not (sdir / "references" / m.group(1)).exists():
                out.append(Finding(str(path), lineno(text, m.start()), "dangling-file",
                                   f"references references/{m.group(1)}, which does not exist"))
        for ref in sorted((sdir / "references").glob("*.md")):
            rtext = ref.read_text()
            if f"references/{ref.name}" not in text:
                out.append(Finding(str(ref), 1, "orphan-reference", f"{name}/SKILL.md never names this file"))
            for m in re.finditer(r"\$\{CLAUDE_PLUGIN_ROOT\}", rtext):
                out.append(Finding(str(ref), lineno(rtext, m.start()), "literal-plugin-root",
                                   "not substituted in a file read with the Read tool; use {pluginRoot}, which the skill binds in its body"))
    return out


# --------------------------------------------------------------------------- driver

def load(d: Path, pattern: str) -> dict[str, tuple[Path, str]]:
    out = {}
    for p in sorted(d.glob(pattern)):
        out[p.stem if p.name != "SKILL.md" else p.parent.name] = (p, p.read_text())
    return out


def plugin_name(plugin: Path) -> str:
    """The name a launch qualifies an agent with is plugin.json's, not the checkout directory's."""
    pj = plugin / ".claude-plugin" / "plugin.json"
    try:
        name = json.loads(pj.read_text()).get("name")
    except Exception:
        name = None
    if not name:
        # said out loud rather than silently using the directory: the qualifier check is only as
        # good as the name it compares against
        print(f"  warning: {pj} has no `name`; qualified launches are checked against `{plugin.name}`", file=sys.stderr)
        return plugin.name
    return name


def run(plugin: Path) -> list[Finding]:
    agents = load(plugin / "agents", "*.md")
    skills = load(plugin / "skills", "*/SKILL.md")
    every = {**{f"agent:{k}": v for k, v in agents.items()},
             **{f"skill:{k}": v for k, v in skills.items()}}
    if (plugin / "CLAUDE.md").exists():
        every["CLAUDE.md"] = (plugin / "CLAUDE.md", (plugin / "CLAUDE.md").read_text())
    for p in sorted((plugin / "templates").glob("*.md")):
        every[f"template:{p.stem}"] = (p, p.read_text())
    for p in sorted((plugin / "skills").glob("*/references/*.md")):
        every[f"reference:{p.parent.parent.name}/{p.stem}"] = (p, p.read_text())

    # What a skill runs from its reference files still needs its permissions and its launches checked. A finding
    # there cites SKILL.md with a line number past its end; the message names what to look for.
    launchers = {k: (p, t + "".join("\n" + r.read_text() for r in sorted((p.parent / "references").glob("*.md"))))
                 for k, (p, t) in skills.items()}

    return (check_agent_params(agents)
            + check_call_sites(launchers, agents, plugin_name(plugin))
            + check_passed_but_unbound(launchers)
            + check_tool_permissions(launchers)
            + check_lock_reachability(skills)
            + check_bind_before_use(skills)
            + check_command_paths(every)
            + check_ordered_lists(every)
            + check_stale_number_refs(every)
            + check_section_refs(every)
            + check_duplicate_json_keys(every)
            + check_references(plugin, every)
            + check_plugin_paths(plugin_name(plugin), agents, launchers)
            + check_workflows(plugin, plugin_name(plugin), agents, skills)
            + check_skill_layout(plugin, skills)
            + check_agent_frontmatter(agents)
            + check_version_sync(plugin))


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
