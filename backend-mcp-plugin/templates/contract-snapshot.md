# Tool Contract Snapshot, Changelog, and Architecture Rules

A published MCP tool contract — name, description, input schema, output shape, error behavior —
is an API that models and client configurations depend on. It must only change **deliberately**
and **visibly**. Three mechanisms make that a build property instead of a review hope. Used by
`detect-project.sh` (detection), `mcp-code` and the `implement` agent (writing), `mcp-verify` (Contract
row), the `code-reviewer` agent, and `mcp-commit` (pairing check).

## 1. Contract snapshot test

A test builds the tool manifest the server publishes — for every registered
`McpServerFeatures.SyncToolSpecification`, `spec.tool()`'s `name`, `description`, `inputSchema`,
`outputSchema` and `annotations`, sorted by name — writes it to `config.contractActual`, and
asserts it equals the committed `config.contractSnapshot`. Any drift fails the build, so every
contract change shows up in a PR diff. Building from the registered specs (not from
`MethodToolCallbackProvider`) covers output schemas, annotations and `@McpTool` tools too.

Jackson: Boot 4 → `tools.jackson.databind.*` (unchecked exceptions); Boot 3 →
`com.fasterxml.jackson.databind.*`, where `readTree(String)` throws a checked exception — wrap it
when called inside a lambda.

```java
/**
 * Contract snapshot gate: the published tool manifest is frozen in
 * src/test/resources/tool-contract.snapshot.json; drift fails the build. On an intentional change,
 * copy build/tool-contract.actual.json over the snapshot and add a contract changelog entry in
 * the same commit.
 */
class ToolContractSnapshotTest {

    private static final Path ACTUAL_OUT = Path.of("build", "tool-contract.actual.json");

    private final ObjectMapper mapper = new ObjectMapper();

    @Test
    void toolContractsMatchCommittedSnapshot() throws Exception {
        ArrayNode actual = currentManifest();
        Files.createDirectories(ACTUAL_OUT.getParent());
        Files.writeString(ACTUAL_OUT, actual.toPrettyString(), StandardCharsets.UTF_8);

        JsonNode expected;
        try (InputStream in = getClass().getResourceAsStream("/tool-contract.snapshot.json")) {
            assertThat(in).as("Missing snapshot — copy %s to src/test/resources/", ACTUAL_OUT).isNotNull();
            expected = mapper.readTree(new String(in.readAllBytes(), StandardCharsets.UTF_8));
        }
        assertThat((JsonNode) actual)
                .as("Tool contract drifted. If intentional: copy %s over the snapshot AND add a "
                        + "contract changelog entry in the same commit.", ACTUAL_OUT)
                .isEqualTo(expected);
    }

    private ArrayNode currentManifest() {
        // Every registered spec: call the registration config's @Bean methods with tool objects
        // built from mocked collaborators (never invoked while building specs), or inject the
        // spec beans in a @SpringBootTest.
        List<McpServerFeatures.SyncToolSpecification> specs = /* every registered spec */;
        ArrayNode arr = mapper.createArrayNode();
        specs.stream()
                .map(McpServerFeatures.SyncToolSpecification::tool)
                .sorted(Comparator.comparing(McpSchema.Tool::name))
                .forEach(t -> {
                    ObjectNode o = arr.addObject();
                    o.put("name", t.name());
                    o.put("description", t.description());
                    o.set("inputSchema", mapper.valueToTree(t.inputSchema()));
                    o.set("outputSchema", mapper.valueToTree(t.outputSchema()));   // null -> JSON null
                    o.set("annotations", mapper.valueToTree(t.annotations()));
                });
        return arr;
    }
}
```

A new tool class must reach the spec list the test reads — a snapshot that silently omits a class
is a gate with a hole.

## 2. Accepting a deliberate contract change (the one bounded TDD exception)

The snapshot is the only test expectation an agent may replace, and only like this:

1. Run the contract test (`{testCommand} --tests {contractTest}`) and confirm it fails on drift
2. Diff `config.contractActual` against `config.contractSnapshot` and confirm the drift is
   **exactly** the tools the current work document or review issue names — added tools, or the
   named fields of the named tools. Any other difference (a tool you did not touch, a schema field
   you did not change) is unexplained drift: stop and report it, never copy it in
3. Copy `config.contractActual` over `config.contractSnapshot`
4. Add the changelog entry (§ 3) in the same change
5. Re-run the contract test — GREEN

## 3. Contract changelog

`config.contractChangelog` (e.g. `docs/tool-contract-changelog.md`) gets one entry per contract
change, newest first under `## Unreleased`:

```markdown
### {tool_name}: {one-line change} ({ticket}, {yyyy-MM-dd})
- **Added | Changed — {description | input schema | output shape | error behavior}**: what changed
  and why, in terms a client integrator acts on
- Breaking? Additive changes only for non-breaking evolution; a breaking change is a new tool name
- Tests: the test methods that pin the new behavior
```

Rules: additive only for non-breaking changes (new optional input, new output field, new error
detail key); never rename a tool in place; a removed field or tightened input is breaking. A
snapshot change with no changelog change fails `mcp-verify`'s Contract row, and `mcp-commit` warns
when one is staged without the other.

## 4. ArchUnit rules

The read-only rule is the **second** line of defense; the first is a read-only upstream
credential (`templates/upstream-client.md` § Credentials) — ArchUnit sees only the call sites it
knows.

```java
class ArchitectureTest {

    private static final JavaClasses CLASSES = new ClassFileImporter()
            .withImportOption(ImportOption.Predefined.DO_NOT_INCLUDE_TESTS)
            .importPackages("{basePackage}");

    // Only when readOnly: true — the server never issues a mutating call to the upstream.
    // POST stays allowed: some upstreams use POST for reads (functional-routing admin APIs).
    // method(HttpMethod) is banned too: its verb is invisible to this rule.
    @Test
    void nowhereIssuesAMutatingHttpCall() {
        noClasses().should().callMethod(RestClient.class, "put")
                .orShould().callMethod(RestClient.class, "patch")
                .orShould().callMethod(RestClient.class, "delete")
                .orShould().callMethod(RestClient.class, "method", HttpMethod.class)
                .because("the MCP server is read-only")
                .check(CLASSES);
    }

    // Only the sanctioned client may speak HTTP: no RestTemplate anywhere, no raw JDK HttpClient
    // outside client/ and config/ (where a request factory may wrap it).
    @Test
    void noSideChannelHttpClients() {
        noClasses().should().dependOnClassesThat()
                .haveFullyQualifiedName("org.springframework.web.client.RestTemplate")
                .check(CLASSES);
        noClasses().that().resideOutsideOfPackages("..client..", "..config..")
                .should().dependOnClassesThat().resideInAPackage("java.net.http..")
                .check(CLASSES);
    }

    // Tools orchestrate through the upstream client (cache, credentials, timeouts, resilience
    // live there) and never touch the HTTP client directly.
    @Test
    void toolLayerDoesNotCallHttpDirectly() {
        noClasses().that().resideInAPackage("..tools..")
                .should().dependOnClassesThat().resideInAPackage("org.springframework.web.client..")
                .because("tool methods must go through the upstream client")
                .check(CLASSES);
    }
}
```

For a `webflux` server, apply the same verbs to `WebClient` (`put()`, `patch()`, `delete()`,
`method(HttpMethod)`) and use `org.springframework.web.reactive.function.client..` for the
layering rule. A client that genuinely needs a dynamic verb narrows the `method` ban to its own
package and says why.

## Related guards worth a test each

- Server `instructions` size under the client display budget (reads the resolved property)
- Tool registration: the registered tool names equal the snapshot's names (no tool registered
  twice, none missing)
- Dependency pinning: the lockfile is present and `lockAllConfigurations()` is on
