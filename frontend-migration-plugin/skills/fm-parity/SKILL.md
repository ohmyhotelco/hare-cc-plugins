---
name: fm-parity
description: "Use after fm-e2e to run the non-behavioral parity gates on a migrated page — visual regression vs legacy baseline, API contract freeze, WebView bridge round-trip, and telemetry dual-fire parity — the last gate before a route flip."
argument-hint: "<page> [--app pc|mobile|hana]"
user-invocable: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# Parity Gate

The final gate before flip, on top of `fm-e2e`. Proves the page matches legacy in appearance,
API contract, native bridge, and analytics. All user-facing output in `workingLanguage`.

## Instructions

### Step 0: Config & prerequisites
Read config (absent → run `fm-init`; stop). Resolve `app`, `appDir`, `targetDir`, `legacyDir`,
`workingLanguage`. Require the page at `e2e-passed` in `tracker.json` and `migration-plan.json`
with `requiredGates`/`gateTriggers` (else point to `fm-e2e`). Require `plan.gateAcceptance`
(absent → the plan is incomplete; point to `fm-plan {page}` and stop).

### Step 1: Lock
Acquire `docs/migration/{app}/{page}/.lock` (stale after 30 min).

### Step 2: Run the verifier
Launch `parity-verifier` (Agent) with only its params: `app`, `page`, `planPath`,
`analysisPath`, `styleSpecPath` = `docs/migration/{app}/{page}/style-spec.json`, `targetDir`,
`appDir`, `legacyDir`/legacy base URL, `outPath` =
`docs/migration/{app}/{page}/parity-report.json`, `workingLanguage`. The verifier runs only the
gates the plan requires (always visual + contract; webview/telemetry when triggered), enforces
`plan.gateAcceptance` verbatim, and reuses the `style-spec` legacy baseline for the visual probe set.
Ensure the Playwright permission exists (added by `fm-e2e`).

### Step 3: Inspect the evidence (before recording)
Do not trust the verdict string. Read `parity-report.json` and, per gate:
1. **Name vs compared surface** — check the report's what-was-compared against the gate's name
   and its `gateAcceptance` entry. A `visual` verdict must rest on a visual comparison of
   symmetric artifacts (same pattern/scope both apps); a content-structure/text match is not a
   visual pass.
2. **Open the legacy and v2 screenshots SIDE BY SIDE** and compare them axis by axis against
   `templates/visual-parity-checklist.md` — Read the *legacy* screenshot and the *v2* screenshot in
   the same pass and diff the two **renders** (not each against its own baseline). Walk every axis:
   frame, **inter-element spacing/gaps** (list↔pager, section, item — the most-missed), **icons/glyphs**
   (existence + faithful render + position + size + open/active state), alignment, control geometry,
   color/border, typography. A pass recorded without this side-by-side walk is invalid. Any axis that
   differs is a diff to fix or explicitly accept — never a silent pass.
3. **Cross-framework fallback rigor** — PC legacy(Angular)↔v2(React) cannot pixel-diff, so the gate
   uses per-side baselines + computed-style probes. Two checks: (a) the v2 baseline is NOT treated as
   the reference — it is valid only if it was checked against legacy in 2 above (a fresh
   `--update-snapshots` capture is NOT that check); (b) the probe set covers **every** content-
   independent axis in the checklist, not a subset — a page pinning color but not the pager gap or the
   toggle icon is an **incomplete probe set = fail**.
4. **Scope reductions** — any criterion the verifier scoped down, skipped, or reinterpreted is a
   **fail** unless the report records the user's explicit approval — never a silent pass. In
   particular, a lift-out delta covers only the shed shell, NOT axis diffs (spacing/icon/alignment)
   inside the compared content-area.
Any failed check overrides the report: treat the gate (and the page) as failed.

### Step 4: Record
Read `parity-report.json`. Update `tracker.json` (Read-Modify-Write):
- `result: pass` **and Step 3 clean** → `apps[app].pages[page].status = "parity-passed"`.
- `result: fail` or any Step 3 override → `parity-failed`.
Release the lock.

### Step 4b: Codex audit (advisory) — see CLAUDE.md → "Codex Independent Audit"
If `codexAudit` is enabled and Codex is available, after the lock is released spawn `codex-auditor`
(Agent) for the `parity` stage (params: `app`, `page`, `stage="parity"`, `appDir`, `legacyDir`,
`parityReportPath` + `planPath` (→ `gateAcceptance`) + the legacy baseline,
`outPath = docs/migration/{app}/{page}/codex-audit.json`,
`workingLanguage`). Codex cross-checks for regressions passed off as parity. Advisory — never
changes the page status. Surface its verdict below.

### Step 5: Report
In `workingLanguage`: per-gate result (visual / contract / webview / telemetry) with evidence,
the Codex audit verdict (advisory), and the next step — on pass
`/frontend-migration-plugin:fm-route {page} --flag-off` (then the flag-on PR after review); on fail
`/frontend-migration-plugin:fm-fix {page}` (auto-detects parity-fix mode).
