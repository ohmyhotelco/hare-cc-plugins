-- Real production migration (MySQL 8.0.33 syntax) that be-crud generates per
-- docs/decisions.md Decision 3 (manual SQL, no Flyway/Liquibase) and Decision 4
-- (MySQL default). This file is generated only -- this plugin never applies it.
-- The sample project also boots from THIS file (application.yml points spring.sql.init
-- at it, with H2 in MySQL mode), so there is no hand-kept H2 copy to drift from it.
-- IF NOT EXISTS makes the DDL rerunnable -- a manual migration applied twice, or two test
-- contexts (@DataR2dbcTest and @SpringBootTest) initialising one in-memory database.
CREATE TABLE IF NOT EXISTS employee (
    sequence     BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id           CHAR(36)     NOT NULL,
    email        VARCHAR(255) NOT NULL,
    display_name VARCHAR(20)  NOT NULL,
    created_at   DATETIME(6)  NOT NULL,
    updated_at   DATETIME(6)  NOT NULL,
    -- named, so an executor can map exactly this constraint's rejection to Duplicate{Field}Exception
    CONSTRAINT uk_employee_id UNIQUE (id),
    CONSTRAINT uk_employee_email UNIQUE (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
