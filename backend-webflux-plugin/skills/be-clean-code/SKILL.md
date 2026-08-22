---
name: be-clean-code
description: "Audit Java source for DRY, KISS, YAGNI, naming, and structure violations (god classes, deep nesting, long parameter lists). Use when the user asks to check code smells, DRY/KISS/YAGNI, or 'is this file too complex' — distinct from be-review (multi-dimension review orchestration), be-test-review (test quality only), and be-security (vulnerabilities only)."
argument-hint: "[file-or-directory-path]"
user-invocable: true
allowed-tools: Read, Glob, Grep
---

# Clean Code Audit

Audit Java source code for clean code principles: DRY, KISS, YAGNI, naming, and structure.

**Mode**: Semi-Structured. Input is a plain file/directory path; output is a fixed-shape
report (counts + `{file}:{line} — {description}` lines) meant to be pasted into a ticket
or PR comment as-is. No `<thinking>` block, no free-flow prose. Findings are heuristic —
see "Failure Modes & Exclusions" before treating any single finding as ground truth.

## Instructions

### Step 0: Validate Configuration

1. Read `.claude/backend-webflux-plugin.json`
2. If missing, tell the user to run `/backend-webflux-plugin:be-init` first and stop

### Step 1: Determine Scope

- If argument provided: audit the specified file or directory
- If no argument: audit all Java files in `{sourceDir}/{basePackage}/`

### Step 1b: Handle Empty / Invalid Scope

Before scanning, resolve the scope and check it:

- **Path does not exist** (argument given but `Glob`/`Read` finds nothing at that path):
  report `"Path not found: {path}. Nothing to audit."` and stop — do not fall back to the
  default scope silently.
- **Zero Java files found** (path exists but contains no `.java` files, or the default
  `{sourceDir}/{basePackage}/` is empty): report `"0 files scanned, no audit performed."`
  and stop — never emit an empty findings report or a pass message for zero files scanned.
- **Large scope** (`Glob` returns more than ~150 files): warn the user that a full scan
  at this size will take significant time and context, and suggest scoping to a
  subdirectory or domain package. If the user supplied an explicit path argument, treat
  that as confirmation and proceed without asking; only ask for confirmation when the
  large scope came from the no-argument default.

### Step 2: Scan for Issues

For each rule below: the threshold defines what counts as a candidate finding, the
rationale explains why it matters, and the exclusion lists cases that must not be
flagged even though they match the raw pattern. If a candidate is close to a threshold
(within ~10%) or its intent is unclear from static text alone, report it suffixed
`(uncertain — needs human judgment)` instead of asserting it as a definitive violation.

#### DRY (Don't Repeat Yourself)

- **Duplicate code blocks across classes** (>5 lines of near-identical logic, found via
  `Grep` on distinctive line fragments across files). *Why*: duplicated logic diverges
  silently — one copy gets fixed, the other doesn't. *Exclude*: near-identical test
  setup/fixture blocks across independent test classes (test isolation is intentional
  here), and the standard `onErrorResume` exception-mapping chain repeated per domain
  router (each domain's error mapping is meant to be self-contained, not shared).
- **Copy-pasted validation logic** that should be extracted to a shared validator.
  *Exclude*: two validators that happen to look similar today but validate different
  business rules (e.g. two `{Entity}PropertyValidator` classes checking different
  fields) — flag only when the exact same rule is duplicated, not merely similar shape.
- **Repeated DTO-to-entity mapping** that could use a shared mapper method.

#### KISS (Keep It Simple)

- **Overly complex conditional logic** (>3 nested `if`/`else`, counted from the Read
  tool's indentation levels). *Why*: each nested level roughly doubles the number of
  paths a reader must hold in mind at once. *Exclude*: a `switch` expression's arms, and
  a stream lambda's own body indentation — neither compounds cognitive load the way
  nested `if`/`else` branching does.
- **Method doing too many things** (>30 lines, counted via `Read`'s line-numbered
  output from the method's opening `{` to its closing `}`). *Why*: a method that doesn't
  fit on one screen forces the reader to scroll and lose context mid-review. *Exclude*: a
  method that is mostly a single large `switch`/pattern-match mapping, or a builder chain
  assembling one object — these are linear, not complex, despite the line count.
- **Unnecessary abstraction layers** (interface with a single implementation that will
  never change). *Exclude*: `{Entity}Repository` (R2DBC) and `{Entity}Mapper` (MyBatis)
  interfaces — single-impl-by-design under Spring Data / MyBatis proxy mechanics, not a
  YAGNI/KISS violation even though they match the raw "single impl" pattern.
- **Complex stream operations** where a simple loop would be clearer.

#### YAGNI (You Ain't Gonna Need It)

- **Unused methods** (defined but never called, checked via `Grep` for the method name
  across the scope). *Exclude from a hard "unused" claim*: methods that satisfy a
  framework contract (`ReactiveCrudRepository`/`R2dbcRepository` overrides, `@Mapper`
  interface methods bound via XML, Lombok-generated accessors) or that may be invoked
  reflectively/via Spring wiring outside the scanned scope — `Grep` cannot prove absence
  of a caller outside the scan path, so report these as `(uncertain — needs human
  judgment)` rather than a confirmed violation.
- **Unused fields** in classes — same reflective/framework caveat as above.
- **Over-engineered factory patterns** for simple object creation.
- **Generic implementations** for single-use cases.
- **Unused imports** (low ambiguity — `Grep` for the imported symbol's usage in the same
  file is reliable here; report these as confirmed findings, not uncertain).

#### Naming

- Single-letter variable names (except loop counters `i`, `j`, `k`)
- Generic names: `data`, `info`, `temp`, `result`, `obj`, `item`
- Boolean variables without `is`/`has`/`can` prefix context
- Methods that don't describe their action
- Classes that don't describe their responsibility
- Inconsistency with the naming conventions table in CLAUDE.md

#### Structure

- **God classes**: files exceeding 300 lines (count via `Read`'s line-numbered output,
  or `Glob` + reading the file to its end). *Why*: beyond ~300 lines a class usually
  mixes multiple responsibilities and stops being reviewable as one unit. *Exclude*:
  generated code and enum-heavy constant classes whose length comes from a flat list of
  named entries, not logic.
- **Deep nesting**: more than 3 levels of indentation — same measurement and exclusions
  as the KISS conditional-logic rule above.
- **Long parameter lists**: methods with >5 parameters. *Why*: past ~5 parameters,
  callers routinely swap argument order by mistake and the signature stops being
  self-documenting. *Exclude*: constructor DI on `Router`/`Handler`/`CommandExecutor`/
  `QueryProcessor` records where each parameter is a distinct collaborator (repository,
  mapper, client) — record-based constructor injection is this plugin's CQRS
  convention, not a smell.
- **Missing `record` usage**: classes that should be records (immutable DTOs with only
  fields and constructor).
- **Mutable state** where immutable would suffice.

### Step 3: Report

Display findings in the working language. Evidence (the exact file:line and offending
snippet) always precedes any summary verdict — never lead with a conclusion the counts
don't back up. Any finding that falls under an "uncertain" case above must carry the
`(uncertain — needs human judgment)` suffix; do not silently upgrade it to a confirmed
violation.

```
Clean Code Audit
================

Files scanned: {count}
Scope: {path}

DRY Issues ({count}):
  {file}:{line} — {description}

KISS Issues ({count}):
  {file}:{line} — {description}

YAGNI Issues ({count}):
  {file}:{line} — {description}

Naming Issues ({count}):
  {file}:{line} — {description}

Structure Issues ({count}):
  {file}:{line} — {description}
```

If no issues found, restate scope instead of asserting a bare quality claim:

> "Clean code audit passed: {count} files scanned under {path}, no violations found
> against the DRY/KISS/YAGNI/naming/structure rules in Step 2."

## Examples

### Example 1 — Clean pass

Input: `/be-clean-code src/main/java/com/example/hr/`, 3 files found:
`Employee.java` (record, 12 lines), `EmployeeRepository.java` (R2DBC interface, 9 lines),
`CreateEmployeeCommandExecutor.java` (28 lines, single responsibility, 4 constructor
params).

None of the files cross a Step 2 threshold: no method over 30 lines, no class over 300
lines, no duplicate blocks, all imports used. Report:

```
Clean Code Audit
================

Files scanned: 3
Scope: src/main/java/com/example/hr/

DRY Issues (0):
KISS Issues (0):
YAGNI Issues (0):
Naming Issues (0):
Structure Issues (0):
```

> "Clean code audit passed: 3 files scanned under src/main/java/com/example/hr/, no
> violations found against the DRY/KISS/YAGNI/naming/structure rules in Step 2."

### Example 2 — Findings across categories

Input: `/be-clean-code src/main/java/com/example/booking/`. Source excerpt from
`BookingHandler.java`:

```java
public Mono<ServerResponse> create(ServerRequest request) {
    return request.bodyToMono(CreateBooking.class)
        .flatMap(cmd -> {
            if (cmd.checkIn() != null) {
                if (cmd.checkOut() != null) {
                    if (cmd.checkIn().isBefore(cmd.checkOut())) {
                        if (cmd.guestCount() > 0) {
                            return executor.execute(cmd);
                        }
                    }
                }
            }
            return Mono.error(new InvalidBookingException());
        })
        .flatMap(id -> ServerResponse.status(201).bodyValue(id));
}
```

An unused field found via `Grep` returning zero call sites within the scanned scope:

```java
private final Clock clock; // never referenced elsewhere in this file or package
```

And a generic variable name in the same method:

```java
var data = cmd.checkIn(); // generic name gives no hint about what "data" is
```

Report:

```
Clean Code Audit
================

Files scanned: 14
Scope: src/main/java/com/example/booking/

DRY Issues (0):
KISS Issues (1):
  BookingHandler.java:5 — 4 levels of nested if inside create() exceeds the >3 nesting
  threshold; flatten with an early-return guard clause or combine conditions with &&

YAGNI Issues (1):
  BookingHandler.java:2 — field `clock` has no call site within the scanned scope
  (uncertain — needs human judgment: may be used via a superclass or reflectively)

Naming Issues (1):
  BookingHandler.java:9 — variable `data` is a generic name; rename to describe what
  it holds (e.g. `checkInDate`)

Structure Issues (0):
```

## Failure Modes & Exclusions

This is a static, heuristic text scan using only `Read`/`Glob`/`Grep` — not a compiler
or bytecode analysis. Declared limitations:

- **No cross-scope proof of absence.** "Unused method/field" findings can only prove
  "no call site found within the scanned scope" — never "unused" in the whole codebase.
  Always report these as uncertain (see YAGNI section above), never as confirmed.
- **Indentation-based nesting/line counts can misjudge non-standard formatting** (tabs
  vs. spaces, chained builder calls, generated code). Treat borderline cases as
  uncertain rather than a hard violation.
- **Generated code, record-heavy DTOs, and `config/`-package bean-wiring classes are
  out of scope for length/parameter-count thresholds** unless a rule above states
  otherwise — these are expected to look different from hand-written business logic.
- **This skill does not run the build or tests.** It reads source text only; it cannot
  confirm a method is dead code the way a coverage report or IDE "find usages" can. Treat
  every finding as a lead for the developer to confirm, not a verified defect.
