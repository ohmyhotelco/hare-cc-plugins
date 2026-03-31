# {Feature Name}

<!-- Template used by: be-code (when drafting scenarios for a feature name without existing work document) -->

## Related Documents

- CLAUDE.md (development rules)
- AGENT.md or plugin CLAUDE.md (architecture and conventions)

## Context

- Package: `{basePackage}.{domain}`
- Test Package: `{basePackage}.{domain}.api.{resource}`

## Test Scenarios

Write scenarios following these rules:
1. One scenario at a time, most important first
2. Single sentence in English, present tense
3. Refer to the system under test as `sut`
4. Start with lowercase (usable as test method name in snake_case)
5. Concise while preserving meaning
6. Use to-do checkbox format

### {HTTP Method} /{domain}/{resource}

- [ ] valid request returns {expected status code}
- [ ] {validation rule} returns 400 Bad Request
- [ ] {duplicate condition} returns 409 Conflict
- [ ] {not found condition} returns 404 Not Found

## Implementation Notes

- Test Type: `@SpringBootTest` (Integration) / `@DataJpaTest` (Repository)
- Test Class: `{HttpMethod}Tests.java`
- Test method naming: `snake_case` in English
- Use `@ParameterizedTest` + `@MethodSource` for multiple invalid inputs
- Use generator classes for test data (`{Entity}Generator`, `EmailGenerator`, etc.)
