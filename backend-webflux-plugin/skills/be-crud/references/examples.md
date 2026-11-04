# be-crud: Examples

Part of the `be-crud` skill. `{pluginRoot}` is the plugin root the skill states.

## Examples

### Example 1 — easy case: manual mode, R2DBC

Input: `be-crud Employee email:String:unique:pattern=email displayName:String:max=20`

1. Step 0 reads config: `dataProfile: "both"`, `webLayer: "functional"` → Step 1 asks for the data profile; user accepts the default, `r2dbc`.
2. Step 2 asks for the domain; user answers `hr`.
3. Step 4 generates `Employee.java` (excerpt — full template in `{pluginRoot}/templates/entity-conventions-r2dbc.md`):

   ```java
   @Table("employee")
   public class Employee {
       @Id
       @Column("sequence")
       private Long sequence;

       @Column("id")
       private UUID id;

       @Column("email")
       private String email;

       @Column("display_name")
       private String displayName;

       @Column("created_at")
       private LocalDateTime createdAt;

       @Column("updated_at")
       private LocalDateTime updatedAt;
   }
   ```

4. Step 4 also generates the router bean (excerpt — full template in `{pluginRoot}/templates/web-layer-functional.md`):

   ```java
   @Bean
   public RouterFunction<ServerResponse> employeeRoutes(EmployeeHandler handler) {
       return RouterFunctions.route()
           .POST("/hr/employees", handler::create)
           .GET("/hr/employees", handler::list)
           .GET("/hr/employees/{id}", handler::find)
           .build();
   }
   ```

5. Step 5.1 Globs every path just written and confirms all files landed; Step 5.2 reports:

   ```
   CRUD Scaffold Generated: Employee (dataProfile: r2dbc, webLayer: functional)
   ======================================

   Files created (verified):
     src/main/resources/migration/V1__create_employee_table.sql
     src/main/java/com/example/data/Employee.java
     src/main/java/com/example/data/EmployeeRepository.java
     src/main/java/com/example/command/CreateEmployee.java
     src/main/java/com/example/commandmodel/CreateEmployeeCommandExecutor.java
     src/main/java/com/example/query/GetEmployeePage.java
     src/main/java/com/example/query/FindEmployee.java
     src/main/java/com/example/querymodel/GetEmployeePageQueryProcessor.java
     src/main/java/com/example/querymodel/FindEmployeeQueryProcessor.java
     src/main/java/com/example/view/EmployeeView.java
     src/main/java/com/example/hr/api/EmployeeRouter.java
     src/main/java/com/example/hr/api/EmployeeHandler.java
     src/main/java/com/example/hr/EmployeePropertyValidator.java
     src/main/java/com/example/hr/InvalidEmailFormatException.java
     src/main/java/com/example/hr/InvalidDisplayNameException.java
     src/main/java/com/example/hr/DuplicateEmailException.java
     work/features/employee.md

   Failed (not created — investigate before proceeding):
     (none)

   API Endpoints:
     POST   /hr/employees           -> 201 Created
     GET    /hr/employees?page&size -> 200 OK
     GET    /hr/employees/{id}      -> 200 OK / 404
   ```

### Example 2 — tricky case: `--all` with one entity already mid-pipeline

Input: `be-crud --all leave-management`, where `plan.json` lists `LeaveType` then `LeaveRequest` in `entityDependencyOrder`, and `{workDocDir}/.progress/leave-request.json` already has `pipeline.status: "implementing"` from a prior run.

1. Step 2.6 acquires the lock once, before `LeaveType`.
2. `LeaveType` has no existing progress file — Steps 1–6 run normally for it.
3. For `LeaveRequest`, Step 2.5 finds the existing progress file and warns: "Entity 'LeaveRequest' already has pipeline progress (status: 'implementing'). Re-running scaffold will reset the status to 'scaffolded', discarding all pipeline history. Continue?"
4. The user declines. Per Step 2.5's spec-all rule, `LeaveRequest` is skipped — not the whole `--all` run — and the lock stays held.
5. Step 7 releases the lock once, after both entities have been attempted. The combined report separates what was generated from what was skipped:

   ```
   CRUD Scaffold Generated: leave-management (2 entities in plan)
   ============================================================

   Entities scaffolded (in dependency order):
     1. LeaveType (r2dbc) — 3 endpoints, 5 scenarios

   Entities skipped (demotion declined):
     2. LeaveRequest — existing status was 'implementing'; no files touched

   Total files created: 15
   ```
