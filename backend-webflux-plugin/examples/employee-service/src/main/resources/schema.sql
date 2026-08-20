-- Sample-only H2 schema, kept in sync by hand with
-- src/main/resources/migration/V1__create_employee_table.sql (the real, MySQL-syntax
-- migration this plugin's be-crud would generate for production -- see
-- docs/decisions.md Decision 3: migrations are manual SQL, never auto-applied by this
-- plugin). H2 does not support MySQL's AUTO_INCREMENT/ENGINE/CHARSET syntax, so this
-- file translates the same table to H2 dialect purely so the sample can boot and run
-- its own verification gate without an external MySQL instance.
--
-- Identifiers are double-quoted (lowercase) because Spring Data R2DBC always quotes
-- generated SQL identifiers. H2 folds unquoted identifiers to uppercase by default,
-- so an unquoted CREATE TABLE here would create EMPLOYEE while Spring Data queries
-- for "employee", producing a "table not found" error at runtime.
CREATE TABLE IF NOT EXISTS "employee" (
    "sequence"     BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    "id"           CHAR(36)     NOT NULL UNIQUE,
    "email"        VARCHAR(255) NOT NULL UNIQUE,
    "display_name" VARCHAR(20)  NOT NULL,
    "created_at"   TIMESTAMP    NOT NULL,
    "updated_at"   TIMESTAMP    NOT NULL
);
