# Backend WebFlux Plugin

> **Ohmyhotel & Co** — Plugin Claude Code cho phát triển backend Spring WebFlux với TDD

## Ghi chú về bản dịch

Bản dịch tiếng Việt đầy đủ chưa hoàn thành. Tài liệu này tóm tắt nhanh những gì
plugin cung cấp; xem `README.md` (tiếng Anh) và `docs/decisions.md` (bản ghi quyết
định về data profile, web layer, migration, database, driver, và công cụ coverage)
để có nội dung đầy đủ và cập nhật nhất.

## Plugin này cung cấp gì

Pipeline phát triển backend Spring WebFlux hoàn chỉnh, dùng kiến trúc CQRS và TDD
nghiêm ngặt:

- Tầng dữ liệu: **hỗ trợ song song R2DBC và MyBatis**
  (`dataProfile`: `r2dbc` | `mybatis` | `both`, mặc định `both`)
- Tầng web: **`RouterFunction`/`HandlerFunction` là mặc định, `@RestController` là
  ngoại lệ được nêu rõ**
- Migration: **file SQL thủ công** (`src/main/resources/migration/`), không dùng
  Flyway/Liquibase
- Database mặc định: **MySQL 8.0.33**
- Test: **`WebTestClient`/`@DataR2dbcTest`/`StepVerifier`**, Mockito được dùng tự do
- Coverage: **JaCoco, cổng kiểm tra chỉ để báo cáo** (không fail theo ngưỡng)
- Vendor/tích hợp bên ngoài (khi có): timeout, retry, circuit breaker theo
  `templates/vendor-integration.md`

Pipeline (`be-init` → `be-crud` → `be-code` → `be-verify` → `be-review` ↔ `be-fix` →
`be-commit`), state machine, và cơ chế khóa (lock) được mô tả đầy đủ trong
`README.md`.

Xem `README.md` để có tài liệu đầy đủ và cập nhật nhất.
