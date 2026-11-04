# be-code: Example run

Part of the `be-code` skill. `{pluginRoot}` is the plugin root the skill states.

## Example: Single-Entity, Non-Plan-Driven Run

Invocation: `/backend-webflux-plugin:be-code employee`

1. **Step 0-1**: Config found. Argument `employee` is a feature name, not a path.
2. **Step 1.5**: No `docs/specs/employee/.implementation/backend/plan.json` exists — `planAvailable = false`.
3. **Step 2**: No `work/features/employee.md` yet. Scan of `src/main/java/com/example/hr/` finds no existing `Employee` entity.
4. **Step 3** (manual flow): Draft scenarios and present for approval:
   ```
   Here are the test scenarios for employee:
   - [ ] valid request returns 201 Created
   - [ ] duplicate email returns 409 Conflict
   - [ ] ? empty display name returns 400 Bad Request

   Please review. I'll remove scenarios marked with `?` unless you confirm them.
   ```
   User confirms all three, including the `?` one. Saved to `work/features/employee.md`.
5. **Step 3.5**: No existing progress file for `employee` — demotion check does not apply.
6. **Step 3.6**: No `.lock` present. Lock acquired: `{"lockedAt": "2026-08-20T09:00:00Z", "operation": "be-code", "feature": "employee"}`.
7. **Step 3.7**: `work/features/.progress/employee.json` created with `pipeline.status = "implementing"`, `scenarios.total = 3`.
8. **Step 4**: Baseline captured (`git status --porcelain` → clean). `implement` agent launched with the work document. One RED-GREEN iteration, summarized:
   - RED: `PostTests.duplicate_email_returns_409_Conflict` written, fails — `DuplicateEmailException` does not exist yet.
   - GREEN: `CreateEmployeeCommandExecutor` checks `EmployeeRepository.existsByEmail`, throws `DuplicateEmailException`; the handler's `onErrorResume` maps it to 409. Test passes.
   - Scenario marked `- [x]`. The remaining two scenarios follow the same RED-GREEN pattern.
9. **Step 5**: `./gradlew build` runs, exits 0.
10. **Step 6**: Report, grounded in evidence (`git status --porcelain` against the Step 4 baseline, `git diff --stat`):
    ```
    Feature Implementation Complete: employee
    =======================================

    Scenarios: 3/3
      [x] valid request returns 201 Created
      [x] duplicate email returns 409 Conflict
      [x] empty display name returns 400 Bad Request

    Files created:
      src/main/java/com/example/command/CreateEmployee.java
      src/main/java/com/example/commandmodel/CreateEmployeeCommandExecutor.java
      src/main/java/com/example/hr/DuplicateEmailException.java
      src/test/java/com/example/hr/api/employees/PostTests.java

    Files modified:
      src/main/java/com/example/hr/api/EmployeeHandler.java

    Build: PASS
    ```
11. **Step 7**: Progress file updated to `pipeline.status = "implemented"`. Lock released. Next step suggested: `/backend-webflux-plugin:be-verify employee`.
