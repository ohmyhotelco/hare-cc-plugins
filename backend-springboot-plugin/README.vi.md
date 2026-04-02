# Backend Spring Boot Plugin

> **Ohmyhotel & Co** — Plugin Claude Code cho phát triển backend Spring Boot với TDD

## Giới thiệu

Plugin Claude Code cung cấp pipeline phát triển đầy đủ cho backend Spring Boot sử dụng kiến trúc CQRS và phương pháp Test-Driven Development (TDD) nghiêm ngặt. Bao gồm toàn bộ vòng đời từ CRUD scaffolding, triển khai TDD, xác minh, review code 6 chiều, và tự động sửa — tất cả với theo dõi trạng thái pipeline.

Tính năng chính:
- **CQRS scaffold** — Tạo CRUD hoàn chỉnh với tách Command/Query (entity, repository, DTO, controller, migration) trong một lệnh
- **TDD nghiêm ngặt** — Thực thi chu kỳ RED-GREEN với theo dõi tài liệu công việc và triển khai từng scenario
- **Cổng xác minh** — Xác minh build + checkstyle + test có cấu trúc (cổng chất lượng chỉ đọc)
- **Review đa chiều** — API contract, JPA patterns, clean code, logging, test quality, architecture (+ spec compliance khi có plan.json) — với tự động sửa bằng TDD
- **Theo dõi pipeline** — Máy trạng thái cấp tính năng + dashboard tiến độ, cảnh báo hạ cấp, phát hiện thay đổi
- **An toàn trạng thái** — Cơ chế khóa, đọc-sửa-ghi, cách ly subagent trong pipeline
- **Audit độc lập** — JPA, API, clean code, logging, test quality, security audit sử dụng độc lập bất kỳ lúc nào

## Tổng quan kiến trúc

```
/backend-springboot-plugin:be-init → .claude/backend-springboot-plugin.json
        │
        ▼
/backend-springboot-plugin:be-plan <feature>  (tùy chọn, cần planning-plugin spec)
        │
        └── backend-planner agent → plan.json
        │
        ▼
/backend-springboot-plugin:be-crud <Entity> [field:Type ...] | --all <feature>
        │
        ├── Flyway migration + Entity + Repository
        ├── Command + CommandExecutor
        ├── Query + QueryProcessor
        ├── View DTO + Controller + Exception
        └── Tài liệu công việc với test scenario
        │
        ▼
/backend-springboot-plugin:be-code <feature>
        │
        └── implement agent (từng scenario):
            ├── Chọn scenario - [ ] tiếp theo
            ├── Viết test (RED) → xác nhận thất bại
            ├── Triển khai code tối thiểu (GREEN) → xác nhận thành công
            └── Đánh dấu - [x] → lặp lại
        │
        ▼
/backend-springboot-plugin:be-verify <feature>
        │
        ├── Kiểm tra compilation
        ├── Kiểm tra checkstyle (nếu bật)
        ├── Kiểm tra test
        └── Kiểm tra full build
        │
        ▼
Vòng lặp — Review & Fix:
/backend-springboot-plugin:be-review <feature>
        │
        └── code-reviewer agent (6 chiều)
        │
        ▼ (nếu có issue)
/backend-springboot-plugin:be-fix <feature>
        │
        └── review-fixer agent
            ├── TDD fix (thay đổi hành vi — test trước)
            └── Direct fix (thay đổi cơ học — edit trực tiếp)
        │
        ▼
/backend-springboot-plugin:be-review <feature> (re-review cho đến khi pass)
        │
        ▼
/backend-springboot-plugin:be-commit

Interrupt skills (dùng ở bất kỳ giai đoạn nào):
  be-debug    — debug hệ thống (4 giai đoạn giả thuyết-kiểm chứng)
  be-progress — dashboard trạng thái pipeline
  be-build    — build + tự động sửa (độc lập)
  be-recall   — tham chiếu quy tắc và kiểm tra vi phạm

Audit độc lập (dùng độc lập với pipeline):
  be-jpa, be-api-review, be-clean-code, be-logging, be-test-review, be-security
```

## Tech Stack

| Danh mục | Công nghệ |
|----------|-----------|
| Ngôn ngữ | Java 21+ |
| Framework | Spring Boot 4.x + Spring MVC (REST) + Spring Validation |
| Build | Gradle (Kotlin DSL hoặc Groovy) hoặc Maven |
| Database | PostgreSQL (mặc định), MySQL, MariaDB, H2 |
| ORM | Spring Data JPA (Hibernate) |
| Migration | Flyway (mặc định), Liquibase, hoặc none |
| Testing | JUnit 5 + TestRestTemplate + AssertJ (không Mockito) |
| Chất lượng code | Checkstyle (không dung thứ: maxErrors=0, maxWarnings=0) |
| Tiện ích | Lombok, UUID Creator (UUID v7) |

## Cài đặt

```
# 1. Đăng ký nguồn marketplace
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. Cài đặt plugin (phạm vi project — lưu vào .claude/settings.json, chia sẻ với team)
/plugin install backend-springboot-plugin@ohmyhotelco --scope project
```

Xác nhận cài đặt:
```
/plugin
```

## Cập nhật & Quản lý

**Cập nhật marketplace** để lấy phiên bản plugin mới nhất:
```
/plugin marketplace update ohmyhotelco
```

**Vô hiệu hóa / Kích hoạt** plugin mà không gỡ bỏ:
```
/plugin disable backend-springboot-plugin@ohmyhotelco
/plugin enable backend-springboot-plugin@ohmyhotelco
```

**Gỡ bỏ**:
```
/plugin uninstall backend-springboot-plugin@ohmyhotelco --scope project
```

**Giao diện quản lý plugin**: Chạy `/plugin` để mở giao diện tab (Discover, Installed, Marketplaces, Errors).

## Bắt đầu nhanh

### Chế độ thủ công (không có spec)

```
1. /backend-springboot-plugin:be-init                          # cấu hình plugin (tự động phát hiện project)
2. /backend-springboot-plugin:be-crud Employee email:String displayName:String   # scaffold CQRS CRUD
3. /backend-springboot-plugin:be-code work/features/employee.md                  # triển khai TDD
4. /backend-springboot-plugin:be-verify employee                                 # cổng xác minh
5. /backend-springboot-plugin:be-review employee                                 # review code
6. /backend-springboot-plugin:be-commit                                          # smart commit
```

### Chế độ spec-driven (với planning-plugin)

```
1. /backend-springboot-plugin:be-init                          # cấu hình plugin
2. /planning-plugin:spec employee-management                   # tạo functional spec
3. /backend-springboot-plugin:be-plan employee-management      # spec → plan.json
4. /backend-springboot-plugin:be-crud --all employee-management # scaffold tất cả entity từ plan
5. /backend-springboot-plugin:be-code employee-management      # TDD (tài liệu công việc bổ sung từ plan)
6. /backend-springboot-plugin:be-verify employee               # cổng xác minh (theo entity)
7. /backend-springboot-plugin:be-review employee               # review 7 chiều (theo entity)
8. /backend-springboot-plugin:be-commit                        # smart commit
```

> **Lưu ý**: Bước 1-5 sử dụng **tên feature** của planning-plugin (ví dụ: `employee-management`).
> Bước 6-7 sử dụng **tên entity** riêng (ví dụ: `employee`, `department`) vì tiến độ được theo dõi theo entity.
> Sau bước 5, `be-code` hiển thị lệnh bước tiếp theo cho từng entity.

## Chi tiết Skills

### `/backend-springboot-plugin:be-init`

**Cú pháp**: `/backend-springboot-plugin:be-init`

**Khi nào dùng**: Cài đặt lần đầu trong project, hoặc cấu hình lại.

**Hoạt động**:
1. Tự động phát hiện build tool (Gradle Kotlin/Groovy, Maven), phiên bản Java, phiên bản Spring Boot
2. Tự động phát hiện base package, loại database, migration tool
3. Kiểm tra cấu hình Checkstyle và Lombok
4. Tạo `.claude/backend-springboot-plugin.json`
5. Tạo thư mục tài liệu công việc (mặc định: `work/features/`)

---

### `/backend-springboot-plugin:be-plan`

**Cú pháp**: `/backend-springboot-plugin:be-plan <tên-feature>`

**Khi nào dùng**: Sau khi tạo functional spec với planning-plugin, trước khi scaffold.

**Hoạt động**:
1. Phát hiện spec tại `docs/specs/{feature}/.progress/{feature}.json`
2. Xác minh trạng thái spec (phải là `reviewing` hoặc `finalized`)
3. Đọc file spec + UI DSL (nếu có) qua `backend-planner` agent
4. Trích xuất entity, command, query, endpoint, exception, validation rule, test scenario
5. Tạo `docs/specs/{feature}/.implementation/backend/plan.json`
6. Cập nhật file tiến độ spec với trạng thái `implementation.backend`

---

### `/backend-springboot-plugin:be-crud`

**Cú pháp**: `/backend-springboot-plugin:be-crud <TênEntity> [field:Type ...]` hoặc `/backend-springboot-plugin:be-crud --all <tên-feature>`

**Khi nào dùng**: Tạo domain entity mới với toàn bộ cấu trúc CQRS.

**Chế độ**:
- **Thủ công**: `be-crud Employee email:String displayName:String` — chỉ định field trực tiếp
- **Spec-driven**: `be-crud Employee` — tự động đọc từ plan.json khi có
- **Batch**: `be-crud --all employee-management` — scaffold tất cả entity từ plan theo thứ tự phụ thuộc

**Hoạt động**:
1. Tự động tạo phiên bản Flyway migration tiếp theo
2. Tạo entity với BaseEntity, dual key (sequence + UUID v7), và các cột field
3. Tạo repository, command/executor, query/processor, view DTO
4. Tạo controller (record DI) với REST endpoint
5. Tạo domain exception
6. Tạo tài liệu công việc với test scenario ban đầu
7. Đặt trạng thái pipeline thành `scaffolded`
8. (Spec-driven) Bao gồm tất cả command/query/endpoint/exception từ plan.json

---

### `/backend-springboot-plugin:be-code`

**Cú pháp**: `/backend-springboot-plugin:be-code <tên-feature hoặc đường-dẫn-tài-liệu>`

**Khi nào dùng**: Sau scaffolding, hoặc khi tài liệu công việc với scenario `- [ ]` đã sẵn sàng.

**Hoạt động**:
1. Nếu cho tên feature: khám phá code hiện có, soạn test scenario, yêu cầu phê duyệt
2. Nếu cho đường dẫn tài liệu: đọc trực tiếp scenario `- [ ]` hiện có
3. Kiểm tra hạ cấp pipeline (cảnh báo nếu trạng thái bị lùi)
4. Lấy khóa trên file tiến độ
5. Chạy `implement` agent cho từng scenario: RED (viết test, xác nhận thất bại) → GREEN (triển khai, xác nhận thành công)
6. Chạy full build sau khi hoàn thành tất cả scenario
7. Cập nhật trạng thái pipeline (`implemented` hoặc `implementing`)
8. Giải phóng khóa

---

### `/backend-springboot-plugin:be-verify`

**Cú pháp**: `/backend-springboot-plugin:be-verify [tên-feature]`

**Khi nào dùng**: Sau triển khai, làm cổng chất lượng trước review. Chỉ đọc — KHÔNG sửa gì.

**Hoạt động**:
1. Kiểm tra hạ cấp pipeline (cảnh báo nếu tiến độ review bị mất)
2. Kiểm tra thay đổi tài liệu công việc (cảnh báo nếu có scenario mới từ lần triển khai cuối)
3. Lấy khóa
4. Chạy 4 bước kiểm tra tuần tự: compilation, checkstyle, test, full build
5. Tạo báo cáo xác minh có cấu trúc
6. Cập nhật trạng thái pipeline (`verified` hoặc `verify-failed`)
7. Giải phóng khóa

---

### `/backend-springboot-plugin:be-review`

**Cú pháp**: `/backend-springboot-plugin:be-review <tên-feature hoặc đường-dẫn>`

**Khi nào dùng**: Sau xác minh, hoặc trực tiếp sau triển khai, để review chất lượng code.

**Hoạt động**:
1. Giải quyết đối tượng (tên feature → thư mục source, hoặc đường dẫn trực tiếp)
2. Kiểm tra thay đổi tài liệu công việc (cảnh báo nếu có scenario mới từ lần triển khai cuối)
3. Lấy khóa
4. Chạy `code-reviewer` agent đánh giá 6 chiều:
   - API Contract (HTTP semantic, URL, status code)
   - JPA Patterns (N+1, transaction, index)
   - Clean Code (DRY, KISS, YAGNI, naming)
   - Logging (SLF4J, MDC, bảo mật)
   - Test Quality (naming, assertion, coverage)
   - Architecture Compliance (CQRS, naming convention)
   - Spec Compliance (khi có plan.json — FR/BR/E-nnn/TS-nnn coverage)
5. Lưu `review-report-{feature}.json` (điểm từng chiều + issue bổ sung: severity, suggestion, refs)
6. Cập nhật trạng thái pipeline (`done` / `reviewed` / `review-failed`)
7. Giải phóng khóa

**Quy tắc kết luận**:
- **PASS**: Tất cả chiều >= 7, không có issue nghiêm trọng
- **FAIL**: Bất kỳ chiều nào < 7 HOẶC có issue nghiêm trọng

---

### `/backend-springboot-plugin:be-fix`

**Cú pháp**: `/backend-springboot-plugin:be-fix <tên-feature>`

**Khi nào dùng**: Sau khi `be-review` tìm thấy issue.

**Hoạt động**:
1. Đọc `review-report-{feature}.json`
2. Kiểm tra bộ đếm vòng sửa (chặn sau 3 vòng — hỏi người dùng trước khi tiếp tục)
3. Lấy khóa
4. Chạy `review-fixer` agent phân loại từng issue:
   - **TDD required**: Thay đổi hành vi — viết test thất bại trước rồi sửa
   - **Direct fix**: Thay đổi cơ học (naming, annotation) — edit trực tiếp
   - **Skip**: Issue đã được giải quyết
   - **Escalated**: Cần thay đổi kiến trúc ngoài phạm vi tự động sửa
5. Chạy xác minh full build sau khi sửa
6. Tạo `fix-report.json`
7. Cập nhật trạng thái pipeline và giải phóng khóa

**Vòng lặp review-fix**:
```
be-review → FAIL → be-fix → be-review → PASS → be-commit
              ^                 |
              └─────────────────┘ (nếu vẫn thất bại)
```

---

### `/backend-springboot-plugin:be-build`

**Cú pháp**: `/backend-springboot-plugin:be-build`

**Khi nào dùng**: Khi build thất bại và cần tự động chẩn đoán và sửa. Độc lập với pipeline.

**Hoạt động**:
1. Chạy `build-doctor` agent
2. Phân loại lỗi: compilation, test, checkstyle, dependency, configuration
3. Áp dụng sửa có mục tiêu với tối đa 3 lần thử lại
4. Báo cáo tất cả thay đổi đã áp dụng

---

### `/backend-springboot-plugin:be-debug`

**Cú pháp**: `/backend-springboot-plugin:be-debug <mô-tả-lỗi hoặc tên-feature>`

**Khi nào dùng**: Cho runtime error, test failure, hoặc build issue ở bất kỳ điểm nào trong pipeline.

**Hoạt động**:
1. Thu thập ngữ cảnh vấn đề (error message, stack trace, source file liên quan)
2. Lấy khóa (nếu có ngữ cảnh feature)
3. Chạy `debugger` agent với phương pháp 4 giai đoạn:
   - **Reproduce**: Phân tích lỗi, xác nhận tái tạo được
   - **Hypothesize**: Lập chính xác 3 giả thuyết xếp hạng
   - **Test**: Áp dụng sửa theo giả thuyết, xác minh, hoàn tác nếu thất bại
   - **Confirm**: Kiểm tra hồi quy + full build
4. Nếu cả 3 giả thuyết thất bại: escalate cho can thiệp thủ công
5. Cập nhật trạng thái pipeline (`resolved` hoặc `escalated`) và giải phóng khóa

---

### `/backend-springboot-plugin:be-commit`

**Cú pháp**: `/backend-springboot-plugin:be-commit`

**Khi nào dùng**: Sau khi pipeline đạt trạng thái `done` hoặc `reviewed`.

**Hoạt động**: Chạy quét bảo mật pre-commit (secret, file nguy hiểm), sau đó tạo commit từ staged changes theo quy ước project (tiếng Anh, thì hiện tại, tiêu đề 50 ký tự, không prefix, không đề cập test code). Hủy bỏ nếu phát hiện secret.

---

### `/backend-springboot-plugin:be-recall`

**Cú pháp**: `/backend-springboot-plugin:be-recall [section]`

**Khi nào dùng**: Tham khảo quy tắc hoặc kiểm tra vi phạm trong công việc gần đây.

**Hoạt động**: Hiển thị quy tắc từ CLAUDE.md theo section (commit, tdd, build, coding, api, jpa) và kiểm tra vi phạm trong công việc gần đây. Có thể tự động sửa vi phạm đơn giản (ví dụ: thiếu newline cuối file).

---

### `/backend-springboot-plugin:be-progress`

**Cú pháp**: `/backend-springboot-plugin:be-progress [tên-feature]`

**Khi nào dùng**: Bất kỳ lúc nào để kiểm tra trạng thái pipeline hiện tại.

**Hoạt động**:
- **Không có tên feature**: Bảng tóm tắt tất cả feature (trạng thái pipeline, tiến độ scenario, kết quả xác minh, điểm review, vòng sửa)
- **Có tên feature**: Xem chi tiết (lịch sử pipeline, scenario hoàn thành/còn lại, kiểm tra thay đổi tài liệu, hướng dẫn bước tiếp theo)

## Audit độc lập

Các skill này chạy độc lập với pipeline. Sử dụng bất kỳ lúc nào cho audit có mục tiêu.

| Skill | Nội dung kiểm tra |
|-------|-------------------|
| `be-api-review` | HTTP method semantic, URL pattern (kebab-case, số nhiều), status code, pagination, error response |
| `be-jpa` | N+1 query, thiếu @Transactional, rủi ro lazy loading, query không giới hạn, thiếu index, cascade, thiết kế schema, an toàn migration, toàn vẹn dữ liệu |
| `be-clean-code` | Vi phạm DRY/KISS/YAGNI, god class, nest sâu, method dài, vấn đề naming |
| `be-logging` | Sử dụng System.out, lộ dữ liệu nhạy cảm, nối chuỗi, log level sai, sử dụng MDC |
| `be-test-review` | Quy ước naming, chất lượng assertion, anti-pattern, phân tích coverage, phát hiện test chậm |
| `be-security` | Authentication, authorization, input validation, PII exposure, injection, secret |

## Workflow pipeline đầy đủ

### Bước 1: Khởi tạo

```
/backend-springboot-plugin:be-init
```

Tự động phát hiện cài đặt project (build tool, phiên bản Java, phiên bản Spring Boot, base package, database, migration tool). Tạo `.claude/backend-springboot-plugin.json`.

### Bước 2: Scaffold CRUD

```
/backend-springboot-plugin:be-crud Employee email:String displayName:String
```

Tạo toàn bộ cấu trúc CQRS: Flyway migration, entity, repository, command/executor, query/processor, view, controller, exception, và tài liệu công việc với test scenario ban đầu.

### Bước 3: Triển khai với TDD

```
/backend-springboot-plugin:be-code work/features/employee.md
```

`implement` agent xử lý từng scenario `- [ ]` một lần:
1. **RED** — Viết test, chạy test class, xác nhận thất bại
2. **GREEN** — Viết code tối thiểu, chạy toàn bộ test class, xác nhận tất cả pass
3. **Đánh dấu** — Cập nhật `- [ ]` thành `- [x]`, chuyển sang scenario tiếp

### Bước 4: Xác minh

```
/backend-springboot-plugin:be-verify employee
```

Cổng chỉ đọc: compilation, checkstyle, test, full build. Báo cáo pass/fail mà không sửa.

### Bước 5: Review

```
/backend-springboot-plugin:be-review employee
```

Review code 6 chiều với điểm từng chiều. Issue bao gồm severity, fix hint, và refs truy vết đến API endpoint hoặc test scenario.

### Bước 6: Sửa & Re-review

```
/backend-springboot-plugin:be-fix employee
/backend-springboot-plugin:be-review employee
```

Lặp lại cho đến khi review pass. TDD cho thay đổi hành vi, edit trực tiếp cho thay đổi cơ học. Vòng sửa được theo dõi — cảnh báo sau 3 vòng.

### Bước 7: Commit

```
/backend-springboot-plugin:be-commit
```

## Agent

### Backend Planner

**Vai trò**: Agent phân tích spec cho chế độ scaffold spec-driven.

Đọc functional spec và UI DSL của planning-plugin, trích xuất entity, command, query, endpoint, exception, validation rule, và test scenario, và tạo `plan.json` có cấu trúc. Tính toán thứ tự phụ thuộc entity cho trình tự scaffold. Sử dụng model Opus.

### Implement

**Vai trò**: Triển khai TDD từ tài liệu công việc.

Xử lý scenario `- [ ]` từng cái theo chu kỳ RED-GREEN nghiêm ngặt. Từng scenario: viết test → xác nhận thất bại → triển khai code tối thiểu → xác nhận tất cả test pass → đánh dấu hoàn thành. Tối đa 3 lần test thất bại liên tiếp trước khi escalate. Sử dụng model Opus.

### Build Doctor

**Vai trò**: Chẩn đoán và tự động sửa lỗi build.

Phân loại lỗi build (compilation, test, checkstyle, dependency, configuration) và áp dụng sửa có mục tiêu. Thử lại tối đa 3 lần. Sử dụng model Sonnet.

### Code Reviewer

**Vai trò**: Review code 6 chiều.

Agent chỉ đọc, đánh giá API contract, JPA pattern, clean code, logging, test quality, và architecture compliance. Tạo báo cáo review có cấu trúc với issue xếp theo severity. Mỗi issue bao gồm dimension, severity, file, line, rule, message, suggestion, và refs (truy vết đến API endpoint hoặc test scenario). Sử dụng model Opus.

### Review Fixer

**Vai trò**: Sửa issue review bằng TDD.

Phân loại từng issue: TDD required (thay đổi hành vi — test trước), direct fix (thay đổi cơ học), skip (đã giải quyết), escalated (cần can thiệp thủ công). Tối đa 3 lần thử cho mỗi TDD fix trước khi escalate. Sử dụng model Opus.

### Debugger

**Vai trò**: Debug hệ thống với phương pháp 4 giai đoạn.

Reproduce → Hypothesize (chính xác 3) → Test → Confirm. Phân loại lỗi: type-error, test-failure, build-error, runtime-error, config-error, migration-error. Escalate nếu cả 3 giả thuyết thất bại. Sử dụng model Opus.

## Cấu hình

`.claude/backend-springboot-plugin.json` (tạo bởi `be-init`):

```json
{
  "javaVersion": "21",
  "springBootVersion": "4.0.2",
  "buildTool": "gradle-kotlin",
  "buildCommand": "./gradlew build",
  "testCommand": "./gradlew test",
  "basePackage": "com.example",
  "sourceDir": "src/main/java",
  "testDir": "src/test/java",
  "architecture": "cqrs",
  "database": "postgresql",
  "migration": "flyway",
  "checkstyle": true,
  "lombokEnabled": true,
  "workDocDir": "work/features",
  "workingLanguage": "vi"
}
```

| Trường | Mô tả | Mặc định |
|--------|-------|----------|
| `javaVersion` | Phiên bản Java toolchain | `"21"` |
| `springBootVersion` | Phiên bản Spring Boot | `"4.0.2"` |
| `buildTool` | `"gradle-kotlin"` / `"gradle-groovy"` / `"maven"` | `"gradle-kotlin"` |
| `buildCommand` | Lệnh build đầy đủ | `"./gradlew build"` |
| `testCommand` | Lệnh chỉ chạy test | `"./gradlew test"` |
| `basePackage` | Package Java gốc | `"com.example"` |
| `sourceDir` | Thư mục source chính | `"src/main/java"` |
| `testDir` | Thư mục source test | `"src/test/java"` |
| `architecture` | Kiểu kiến trúc — quyết định cấu trúc package và template | `"cqrs"` |
| `database` | `"postgresql"` / `"mysql"` / `"h2"` / `"mariadb"` | `"postgresql"` |
| `migration` | `"flyway"` / `"liquibase"` / `"none"` | `"flyway"` |
| `checkstyle` | Bật Checkstyle hay không | `true` |
| `lombokEnabled` | Sử dụng Lombok hay không | `true` |
| `workDocDir` | Thư mục tài liệu công việc | `"work/features"` |
| `workingLanguage` | Ngôn ngữ output cho người dùng (`"en"` / `"ko"` / `"vi"`) | `"en"` |

## Cấu trúc package CQRS

```
{basePackage}/
├── {App}Application.java
├── command/                    <- Request command DTO (record)
│   └── Create{Entity}.java
├── commandmodel/               <- Logic thực thi command
│   └── Create{Entity}CommandExecutor.java
├── query/                      <- Request query DTO (record)
│   └── Get{Entity}Page.java
├── querymodel/                 <- Logic xử lý query
│   └── Get{Entity}PageQueryProcessor.java
├── view/                       <- Response view DTO (record)
│   └── {Entity}View.java
├── data/                       <- Entity và repository
│   ├── {Entity}.java
│   ├── {Entity}Repository.java
│   └── BaseEntity.java
├── config/                     <- Spring configuration bean
└── {domain}/                   <- Business logic theo domain
    ├── api/                    <- REST controller
    │   └── {Entity}Controller.java
    └── {Description}Exception.java
```

## Trạng thái Pipeline

### File trạng thái

Trạng thái được theo dõi trong `{workDocDir}/.progress/{feature}.json`.

| File | Mục đích |
|------|----------|
| `{feature}.json` | Trạng thái pipeline, số lượng scenario, lịch sử verify/review/fix/debug |
| `review-report-{feature}.json` | Kết quả review với điểm từng chiều và issue bổ sung |
| `fix-report-{feature}.json` | Kết quả fix với phân loại chiến lược (TDD/direct/escalated) |
| `.lock` | Ngăn thực thi đồng thời (tự động hết hạn sau 30 phút) |

### Máy trạng thái

Lưu ý: Trạng thái `planned` được theo dõi trong file tiến độ spec (bởi `be-plan`), không nằm trong backend pipeline.

```
scaffolded → implementing → implemented → verified ─→ reviewed ─→ be-commit
                                                   └→ done ────→ be-commit
                                    ↓            ↓          ↓
                              verify-failed  review-failed  fixing
                                    ↓            ↓          ↓
                                be-build     be-fix    be-review (re-review)
                                    ↓            ↓
                                verified     fixing → reviewed/done

Bất kỳ lúc nào:
  be-debug → resolved | escalated
  resolved → (tái nhập pipeline ở giai đoạn phù hợp)
  escalated → (can thiệp thủ công, sau đó tái nhập)
```

### An toàn trạng thái

- **Cơ chế khóa**: Skill sửa file tiến độ phải lấy `.lock` trước khi bắt đầu. Ngăn thực thi đồng thời trên cùng feature. Khóa cũ (>30 phút) tự động xóa.
- **Quy tắc đọc-sửa-ghi**: Luôn đọc nội dung file mới nhất trước khi ghi. Chỉ merge trường thay đổi — giữ tất cả trường hiện có.
- **Cảnh báo hạ cấp**: Chạy skill từ giai đoạn pipeline trước đó sẽ cảnh báo trước khi reset tiến độ (ví dụ: chạy lại `be-code` khi status là `verified` sẽ mất kết quả xác minh).
- **Phát hiện thay đổi**: `be-verify` và `be-review` cảnh báo khi tài liệu công việc đã được sửa từ lần cập nhật pipeline cuối, cho thấy scenario mới có thể chưa được triển khai.
- **Cách ly subagent**: Skill điều phối chỉ truyền parameter cần thiết cho agent — không có ngữ cảnh hội thoại rò rỉ giữa các giai đoạn.

## Ngôn ngữ giao tiếp

Skill đọc `workingLanguage` từ cấu hình. Tất cả output cho người dùng (tóm tắt, câu hỏi, phản hồi, hướng dẫn bước tiếp) bằng ngôn ngữ làm việc.

Ánh xạ ngôn ngữ: `en` = English, `ko` = Korean, `vi` = Tiếng Việt.

## Mẹo & Thực hành tốt

- **Xem lại tài liệu công việc trước khi code** — `be-crud` tạo scenario ban đầu, nhưng bạn có thể thêm, xóa, hoặc sắp xếp lại trước khi chạy `be-code`.

- **Dùng be-verify làm cổng nhanh** — Chỉ đọc và nhanh. Chạy sau triển khai để bắt issue compilation hoặc test trước khi đầu tư thời gian cho review đầy đủ.

- **Không bỏ qua re-review sau fix** — Luôn chạy `be-review` sau `be-fix`. Vòng review-fix đảm bảo không có hồi quy.

- **Dùng be-debug cho issue phức tạp** — Nếu test thất bại không rõ ràng, `be-debug` cung cấp kiểm tra giả thuyết hệ thống thay vì debug tùy hứng.

- **Audit độc lập miễn phí** — `be-jpa`, `be-api-review`, `be-clean-code`, `be-logging`, `be-test-review`, và `be-security` hoạt động độc lập với pipeline. Dùng bất kỳ lúc nào cho kiểm tra chất lượng có mục tiêu.

- **Tiếp tục an toàn** — Nếu `be-code` bị gián đoạn, chỉ cần chạy lại với cùng tài liệu công việc. Scenario hoàn thành (`- [x]`) được giữ lại và tiếp tục từ `- [ ]` tiếp theo.

- **Khóa bảo vệ trạng thái** — Không chạy `be-code` và `be-fix` đồng thời trên cùng feature. Cơ chế khóa ngăn hỏng file tiến độ.

## Lộ trình

- [x] Tạo CQRS CRUD scaffold
- [x] Pipeline triển khai TDD
- [x] Cổng xác minh
- [x] Review code đa chiều + vòng review-fix (6 core + spec compliance tùy chọn)
- [x] Build doctor (tự động chẩn đoán và sửa)
- [x] Debug hệ thống (4 giai đoạn giả thuyết-kiểm chứng)
- [x] Theo dõi trạng thái pipeline + dashboard tiến độ
- [x] Audit độc lập (JPA, API, clean code, logging, test quality, security)
- [x] An toàn trạng thái (khóa, hạ cấp, thay đổi, cách ly subagent)
- [x] Pre-commit security scan (secret, API key, file nguy hiểm)
- [x] Tích hợp planning-plugin (scaffold từ spec)
- [ ] Hỗ trợ project đa module
- [ ] Template kiến trúc event-driven (Kafka, RabbitMQ)

## Cấu trúc thư mục

```
agents/          Định nghĩa agent (backend-planner, implement, build-doctor,
                 code-reviewer, review-fixer, debugger)
skills/          Điểm vào skill (be-init, be-plan, be-crud, be-code, be-verify,
                 be-review, be-fix, be-commit, be-build, be-debug, be-recall,
                 be-progress, be-jpa, be-api-review, be-clean-code, be-logging,
                 be-test-review, be-security)
templates/       File template (plan-schema, tdd-rules, cqrs-module,
                 entity-conventions, test-scenario-template,
                 work-document-template, checkstyle-config, progress-schema)
docs/            Tài liệu
```

## Tác giả

Roy Im, Justin Choi — Ohmyhotel & Co
