# Configuration

How every skill resolves `config`, and what each key means. Read from
`{pluginRoot}/templates/configuration.md`.

There is no init step. Every skill resolves `config` itself, at its start:

1. Run `bash "{pluginRoot}/scripts/detect-project.sh"`.
2. Exit `0` → its stdout (a JSON object) **is** `config`. Any other exit → show its stderr message
   and stop (`2`: no Gradle build or no Spring AI MCP server starter; `3`: Maven-only project).
3. When `config.warnings` is non-empty, show each warning once, before the skill's own output.

The script detects every value from the build files and sources on each run — nothing is cached,
so the config never drifts from the code (a newly applied `jacoco` plugin or a newly added snapshot
test is picked up by the next skill run). It then applies the **optional** policy file
`.claude/backend-mcp-plugin.json`, a flat JSON object holding:

- the three policy keys, which cannot be detected: `readOnly` (default `true` unless an ArchUnit
  read-only rule already proves it), `workDocDir` (default `work/features`), `workingLanguage`
  (default `en`)
- any scalar override of a detected key, for the rare case detection is wrong (e.g. `toolsPackage`
  when `@Tool` classes span several packages). `moduleDir` / `sourceDir` / `testDir` overrides are
  applied before the source scan, so they redirect detection itself

Only top-level keys count. Each value is type-checked (booleans `true`/`false` only, enums for
`buildTool` / `toolRegistration` / `security`, valid JSON strings); `transports` and the informational
keys cannot be overridden. An invalid or unknown entry is skipped with a warning; a file that is not a
well-formed flat object is ignored entirely, with a warning.

```json
{ "readOnly": true, "workingLanguage": "vi", "toolsPackage": "com.example.mcp.tools" }
```

Nobody has to create the file: a project without it runs on detected values and defaults. A skill
that needs a policy the defaults deny (a write tool under `readOnly: true`) stops and tells the user
which key to set in that file. `bash "{pluginRoot}/scripts/detect-project.sh" --summary` prints the
one-line status the SessionStart hook shows (plus `| module X` for a multi-module build);
`--get <key> [<key>…]` prints raw values, one per line. `--get workDocDir` / `--get workingLanguage`
read only the policy file (no detection) and exit 0 in any project.

Resolved `config` shape (example — oh-ellis-mcp):

```json
{
  "javaVersion": "25", "springBootVersion": "4.1.0", "springAiVersion": "2.0.0",
  "buildTool": "gradle-groovy", "gradleCommand": "./gradlew",
  "buildCommand": "./gradlew build", "testCommand": "./gradlew test",
  "moduleDir": ".", "basePackage": "com.example.mcp", "toolsPackage": "com.example.mcp.tools",
  "sourceDir": "src/main/java", "testDir": "src/test/java",
  "transports": ["webmvc", "stdio"], "toolRegistration": "spec-list",
  "security": "oauth2-resource-server", "readOnly": true,
  "contractSnapshot": "src/test/resources/tool-contract.snapshot.json",
  "contractTest": "ToolContractSnapshotTest", "contractActual": "build/tool-contract.actual.json",
  "contractChangelog": "docs/tool-contract-changelog.md",
  "descriptionConvention": "docs/mcp-tool-description-convention.md",
  "checkstyle": false, "coverage": false, "lombokEnabled": true,
  "workDocDir": "work/features", "workingLanguage": "en",
  "toolClassCount": 5, "toolPackages": ["com.example.mcp.tools"], "readOnlySource": "archunit",
  "policyFile": false, "overridden": [], "warnings": []
}
```

- `toolClassCount` / `toolPackages`: classes declaring a `@Tool`/`@McpTool` method and their packages (informational)
- `readOnlySource`: `"archunit"` (detected rule) | `"policy"` (set in the policy file) | `"default"`
- `policyFile` / `overridden`: whether the policy file exists, and which detected keys it overrides
- `warnings`: detection findings to show the user (two HTTP transports, pre-1.0 starter names, an HTTP transport with no inbound security, `@Tool` classes across several packages or with no common parent, `toolsPackage` unresolved, several modules with an MCP starter, a `ToolCallbackProvider` bean beside tool-spec beans, rejected policy-file entries)
- `javaVersion` / `springBootVersion` / `springAiVersion`: Java toolchain, Spring Boot, and Spring AI (BOM) versions (e.g. "25", "4.1.0", "2.0.0")
- `buildTool`: `"gradle-kotlin"` | `"gradle-groovy"` — Gradle only; every gate row is a Gradle task, so every skill stops on a Maven-only project (`detect-project.sh` exit 3)
- `gradleCommand`: the wrapper the task-level gate rows run (`./gradlew`; `gradle` when no wrapper). Absent → `./gradlew`
- (not a config key) `{pluginRoot}` is the plugin's install directory: every skill sets it from `${CLAUDE_PLUGIN_ROOT}`, which Claude Code substitutes inline when it loads the skill (the variable is not in the Bash environment), and passes it to its agents
- `buildCommand` / `testCommand`: full build / test-only command (defaults `{gradleCommand} build` / `{gradleCommand} test`). A policy-file override of these or `gradleCommand` is accepted only as `./gradlew` or `gradle` followed by plain task/flag words — anything else (a pipe, `;`, `$(…)`, another program) is rejected with a warning, because skills run the value verbatim
- `basePackage`: Root Java package — in a path such as `{sourceDir}/{basePackage}/` it stands for the package with `.` replaced by `/`
- `toolsPackage`: Package holding the `@Tool` classes (detected from existing `@Tool` usage; default `{basePackage}.tools`)
- `moduleDir`: `"."` for a single-module build; otherwise the subproject directory containing the MCP server starter (e.g. `"mcp-server"`). Gradle commands still run from the project root (`buildCommand` builds every module)
- `sourceDir` / `testDir`: Main / test source directories, relative to the project root and including `moduleDir` (e.g. `mcp-server/src/main/java`)
- `transports`: array of `"webmvc"` | `"webflux"` | `"stdio"` — the MCP server starters present
- `toolRegistration`: `"spec-list"` (hand-built `List<SyncToolSpecification>` beans — lets one choke point wrap every tool) | `"callback-provider"` (`ToolCallbackProvider` bean) | `"annotation-scanner"` (Spring AI annotation scanning) — where a new tool must be registered
- `security`: `"oauth2-resource-server"` | `"spring-security"` | `"none"`
- `readOnly`: `true` when the server must never issue a mutating upstream call (enforced by an ArchUnit rule — `templates/contract-snapshot.md`); `false` only for a server that deliberately exposes write tools. `false` alone is not consent: each write tool also needs a recorded opt-in and must be a pure pass-through of one upstream endpoint (`templates/scope-rules.md` § 6)
- `contractSnapshot` / `contractTest` / `contractActual` / `contractChangelog`: the committed tool-manifest snapshot (paths relative to the project root, under `moduleDir` in a multi-module build), the test class that compares against it, the file that test writes the current manifest to, and the contract changelog — each `null` when the project has none (the Contract row of `mcp-verify` is then `SKIP`, and the review flags the missing gate)
- `descriptionConvention`: project document that overrides the plugin's tool-description template, or `null`
- `checkstyle` / `coverage`: `true` only when the Checkstyle / `jacoco` Gradle plugin is applied (default `false`; coverage is report-only)
- `lombokEnabled`: Whether Lombok is used
- `workDocDir`: Directory for work documents (default: `work/features`)
- `workingLanguage`: Language for user-facing output (`"en"` | `"ko"` | `"vi"`)

## Communication Language

Skills read `workingLanguage` from config (`en` English, `ko` Korean, `vi` Vietnamese). All
user-facing output (summaries, questions, feedback, next-step guidance) is in that language.
