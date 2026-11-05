# be-crud: Read templates and generate files

Part of the `be-crud` skill. `{pluginRoot}` is the plugin root the skill states.

### Step 3: Read Templates

**Precondition — the project exists.** This skill writes sources and a migration *into* a Spring
Boot WebFlux project; it generates no build file, wrapper or application class. Before reading
templates, confirm `build.gradle.kts`/`build.gradle` declares what the entity's profile compiles
against — `spring-boot-starter-webflux`, `com.github.f4b6a3:uuid-creator`, the Boot 4 test starters the generated tests need — `spring-boot-starter-test`, `spring-boot-starter-webflux-test` (`WebTestClient`), `io.projectreactor:reactor-test` and, for `r2dbc`, `spring-boot-starter-data-r2dbc-test` (`@DataR2dbcTest`), for `mybatis`, `mybatis-spring-boot-starter-test` — and for `r2dbc`:
`spring-boot-starter-data-r2dbc` + `io.asyncer:r2dbc-mysql` **≥ 1.4.2** (the first release whose compatibility table lists Boot 4; 1.4.0/1.4.1 are not it — pin 1.4.3); for `mybatis`:
`org.mybatis.spring.boot:mybatis-spring-boot-starter:4.x` (the 3.0.x line targets Boot 3 and fails
auto-configuration under Boot 4 — check the version, not just the artifact) + `mysql-connector-j`.
Anything missing or on the wrong line → **release the lock from Step 2.6, then stop** and print the
dependency lines to add, rather than generating sources that cannot compile (Step 7 will not run).

Read these templates for code patterns:
- `{pluginRoot}/templates/cqrs-module.md` — package layout, and pointers to the profile/web-layer files below
- `{pluginRoot}/templates/entity-conventions.md` — shared DTO/exception/validator conventions
- `{pluginRoot}/templates/entity-conventions-r2dbc.md` or `{pluginRoot}/templates/entity-conventions-mybatis.md` — matching this entity's resolved `dataProfile` (never read both for one entity)
- `{pluginRoot}/templates/web-layer-functional.md` or `{pluginRoot}/templates/web-layer-annotated.md` — matching `config.webLayer`
- `{pluginRoot}/templates/checkstyle-config.md` — checkstyle rules (only when `config.checkstyle == true`)
- `{pluginRoot}/templates/coverage-gate.md` — JaCoco Gradle block (only when generating a new project's `build.gradle`, not per-entity)

### Step 3.5: Check Shared Classes

Check if the following shared classes exist and generate them if missing:

1. `{sourceDir}/{basePackage}/view/PageCarrier.java`
   - If it does not exist: generate from the Generic Pagination Wrapper template in `{pluginRoot}/templates/entity-conventions.md`
2. `{sourceDir}/{basePackage}/data/R2dbcConfig.java` (r2dbc entities only)
   - If it does not exist: generate from the UUID Conversions template in `{pluginRoot}/templates/entity-conventions-r2dbc.md` — the MySQL R2DBC driver cannot bind `java.util.UUID` on its own
3. `{sourceDir}/{basePackage}/data/UuidTypeHandler.java` (mybatis entities only)
   - If it does not exist: generate from `{pluginRoot}/templates/entity-conventions-mybatis.md`
4. `{sourceDir}/{basePackage}/data/JdbcConfig.java` (mybatis entities in a project whose build file also has `spring-boot-starter-data-r2dbc` — `config.dataProfile` `both`)
   - If it does not exist: generate from the JDBC DataSource template in `{pluginRoot}/templates/entity-conventions-mybatis.md` — Boot's `DataSource` auto-configuration backs off beside an R2DBC `ConnectionFactory`, and the mappers would have no `DataSource`

There is no `BaseEntity` shared class in this plugin (no auditing-listener equivalent — see `{pluginRoot}/templates/entity-conventions.md`). Do not generate one.

### Step 4: Generate Files

Before writing anything, Glob every entity-specific target below (migration, entity/POJO, mapper interface + XML, repository, commands, executors, queries, processors, views, validator, router/handler or controller, work document — not the domain-shared exception files, see #8). Any that already exists is about to be overwritten — a `scaffolded` entity has no demotion prompt (Step 2.5), and a hand-edited scaffold is user work:
> "{n} of this entity's files already exist: {list}. Overwrite them?"
`--yes` answers yes; a decline stops here (nothing written; in spec-all mode the entity is skipped and the lock stays held, as in Step 2.5). The run's start time for Step 5 is the lock's `lockedAt` (Step 2.6) — it precedes every write, Step 3.5's shared classes included.

Generate the following files in order. Use the entity's resolved `dataProfile` (`r2dbc` or `mybatis`, never `"both"` for a single entity) and `config.webLayer` to select which template variant applies. The templates are snippets without `import` lines; resolve them from the types used (`org.springframework.data.domain.Sort`, `org.springframework.http.ResponseEntity`, `org.springframework.web.server.ServerWebInputException`, `org.apache.ibatis.type.*` for the type handler, …) — a missing import is a compile failure `be-build` catches, not a design choice.

#### 1. Manual SQL Migration

File: `src/main/resources/migration/V{next}__create_{snake_case_entity}_table.sql`

- Determine `{next}` and `{snake_case_entity}` using the Shared Derivation Rules above
- Generate `CREATE TABLE IF NOT EXISTS` (rerunnable) with MySQL syntax; every unique field gets a **named** constraint `CONSTRAINT uk_{table}_{column} UNIQUE ({column})` — the executor maps a `DataIntegrityViolationException` to `Duplicate{Field}Exception` only when the message names that constraint: `sequence BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY`, `id CHAR(36) NOT NULL` with `CONSTRAINT uk_{table}_id UNIQUE (id)`, custom fields, `created_at DATETIME(6) NOT NULL`, `updated_at DATETIME(6) NOT NULL`, `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`
- No separate index on a unique column — the named UNIQUE constraint already is one; add `INDEX idx_{table}_{column}` only for the filter/sort columns a plan names
- This file is generated only — never executed by this skill (see `docs/decisions.md` Decision 3)

#### 2. Entity / POJO

**R2DBC**: File: `{sourceDir}/{basePackage}/data/{EntityName}.java` — `@Table`/`@Column`-annotated class per `{pluginRoot}/templates/entity-conventions-r2dbc.md` Entity Template.

**MyBatis**: File: `{sourceDir}/{basePackage}/data/{EntityName}.java` — plain POJO, no annotations, per `{pluginRoot}/templates/entity-conventions-mybatis.md` Entity (POJO) Template. Also generate `{sourceDir}/{basePackage}/data/{EntityName}Mapper.java` (interface) and `src/main/resources/mapper/{EntityName}Mapper.xml` — every interface method with a bound statement — and, once per project, `{sourceDir}/{basePackage}/data/UuidTypeHandler.java` (the template's result map and `#{id}` parameters name it; MyBatis has no built-in UUID handler — **every** `UUID`-typed field gets the same `typeHandler=` on its `<result>` and on each `#{}` that binds it, not only `id`) and the `mybatis.mapper-locations: classpath:mapper/**/*.xml` entry in `application.yml` (without it the XML is never loaded — see the template).

Both: Lombok `@Getter`, `@Setter` when `config.lombokEnabled == true`; otherwise emit a plain getter and setter per field — the executors and processors call `getId()`/`setEmail()`/…, so private fields alone do not compile.

#### 3. Repository (R2DBC only)

File: `{sourceDir}/{basePackage}/data/{EntityName}Repository.java`

- Extends `ReactiveCrudRepository<{EntityName}, Long>`
- `findByExternalId(UUID id)` returning `Mono<{EntityName}>`, with the explicit `@Query` from
  `{pluginRoot}/templates/entity-conventions-r2dbc.md` — `findById(Long)` is already the sequence-PK lookup
  `ReactiveCrudRepository` provides, and derivation cannot bind a differently named method to the
  `id` field
- `existsBy{UniqueField}` returning `Mono<Boolean>` for unique fields
- `findAllBy(Pageable)` returning `Flux<{EntityName}>` for the page query

MyBatis entities skip this file (the mapper interface + XML generated in Step 2 covers persistence).

#### 4. Command + CommandExecutor

File: `{sourceDir}/{basePackage}/command/Create{EntityName}.java`
File: `{sourceDir}/{basePackage}/commandmodel/Create{EntityName}CommandExecutor.java`

- Command: record with fields from user input
- Executor: `@Component` record returning `Mono<Void>` — R2DBC uses `flatMap`-chained repository calls (see `{pluginRoot}/templates/entity-conventions-r2dbc.md` § Command Executor); MyBatis wraps mapper calls in `Mono.fromCallable(...).subscribeOn(Schedulers.boundedElastic())` (see `{pluginRoot}/templates/entity-conventions-mybatis.md` § Command Executor). Includes validation, duplicate check, UUID v7 generation, explicit `createdAt`/`updatedAt` assignment, save/insert.

**Spec-driven enhancements**: When `mode = "spec"` or `mode = "spec-all"`:
- Generate all commands from `plan.json.commands[]` for this entity (not just Create — may include Update, Delete, or domain-specific actions)
- Include validation logic from `plan.json.commands[].validations[]` in each executor
- Include side effects as TODO comments from `plan.json.commands[].sideEffects[]`

#### 5. Query + QueryProcessor

File: `{sourceDir}/{basePackage}/query/Get{EntityName}Page.java`
File: `{sourceDir}/{basePackage}/query/Find{EntityName}.java`
File: `{sourceDir}/{basePackage}/querymodel/Get{EntityName}PageQueryProcessor.java`
File: `{sourceDir}/{basePackage}/querymodel/Find{EntityName}QueryProcessor.java`

- Get{EntityName}Page: pagination query (page, size with max 20)
- FindEntity: single lookup by UUID
- PageQueryProcessor: returns `Mono<PageCarrier<{EntityName}View>>`
- FindQueryProcessor: returns `Mono<{EntityName}View>`, empty `Mono` (mapped to 404 at the web layer) if not found

**Spec-driven enhancements**: When `mode = "spec"` or `mode = "spec-all"`:
- Generate all queries from `plan.json.queries[]` for this entity (may include search/filter queries)
- Use `plan.json.queries[].maxPageSize` if specified (override default 20)
- Include filter fields from `plan.json.queries[].filters[]`

#### 6. View

File: `{sourceDir}/{basePackage}/view/{EntityName}View.java`

- Record with `id` (UUID) + displayable fields

#### 7. Web Layer

**Functional (default, `config.webLayer == "functional"`)**:
File: `{sourceDir}/{basePackage}/{domain}/api/{EntityName}Router.java` — `@Configuration` class with a `RouterFunction<ServerResponse>` `@Bean`.
File: `{sourceDir}/{basePackage}/{domain}/api/{EntityName}Handler.java` — `@Component` record with DI (executors + processors), one method per route, `onErrorResume` chain mapping domain exceptions to HTTP status.

**Annotated (only when `config.webLayer == "annotated"`)**:
File: `{sourceDir}/{basePackage}/{domain}/api/{EntityName}Controller.java` — record class with DI, `@RestController`, methods returning `Mono`/`Flux`, `@ExceptionHandler` methods for domain exceptions.

Both styles: POST (201), GET list (200), GET single (200/404).

**Spec-driven enhancements**: When `mode = "spec"` or `mode = "spec-all"`:
- Generate all endpoints from `plan.json.endpoints[]` that reference this entity's commands/queries
- Include PUT, PATCH, DELETE routes/endpoints if defined in the plan
- Map all exceptions from `plan.json.exceptions[]` for this entity to the handler's `onErrorResume` chain or `@ExceptionHandler` methods

#### 8. Validator and Exceptions

File: `{sourceDir}/{basePackage}/{domain}/{EntityName}PropertyValidator.java` — `@Component`, one
`validate{Field}` method per validated field, per `{pluginRoot}/templates/entity-conventions.md` § Validation
Utility Template. The command executor (Step 4 #4) injects it; a scaffold without it does not compile.
File: `{sourceDir}/{basePackage}/{domain}/Invalid{Field}Exception.java` — one per validated field
(the validator throws them; the handler/controller maps them to 400)
File: `{sourceDir}/{basePackage}/{domain}/Duplicate{UniqueField}Exception.java` (for each unique field)
These are domain-shared, not entity-specific: a second entity in the same domain with the same
flagged field reuses them — generate only when missing, never prompt to overwrite (Step 4's
preamble excludes them).

No `{EntityName}NotFoundException`: not-found is the empty `Mono` the `Find` processor returns and the
web layer maps to 404 (`switchIfEmpty` / `defaultIfEmpty`) — a class nothing throws is dead code the
reviewer would flag as unmapped.

**Spec-driven enhancements**: When `mode = "spec"` or `mode = "spec-all"`:
- Generate all exceptions from `plan.json.exceptions[]` for this entity
- Use the exact class names and HTTP status codes from the plan

#### 9. Work Document

File: `{workDocDir}/{kebab-case-entity}.md`

- Generate from `{pluginRoot}/templates/work-document-template.md`
- Pre-fill entity fields, commands, queries, API endpoints
- Record the resolved `dataProfile` for this entity at the top of the document
- Generate test scenarios as `- [ ]` items

**Spec-driven enhancements**: When `mode = "spec"` or `mode = "spec-all"`:
- Include all test scenarios from `plan.json.testScenarios[]` for this entity
- Add spec source references as comments (e.g., `<!-- FR-001, TS-001 -->`)
- Include validation rules section from `plan.json.validationRules[]`
- Include exception table from `plan.json.exceptions[]`
