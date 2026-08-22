-- Real production migration (MySQL 8.0.33 syntax) that be-crud generates per
-- docs/decisions.md Decision 3 (manual SQL, no Flyway/Liquibase) and Decision 4
-- (MySQL default). This file is generated only -- this plugin never applies it.
-- The sample project's runtime schema (src/main/resources/schema.sql) is a hand-kept
-- H2-dialect translation of this table, used only so the sample can run without an
-- external MySQL instance.
CREATE TABLE employee (
    sequence     BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    id           CHAR(36)     NOT NULL UNIQUE,
    email        VARCHAR(255) NOT NULL UNIQUE,
    display_name VARCHAR(20)  NOT NULL,
    created_at   DATETIME(6)  NOT NULL,
    updated_at   DATETIME(6)  NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
