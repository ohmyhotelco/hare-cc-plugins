# Backend Spring Boot Plugin

Plugin Claude Code cho phat trien backend Spring Boot voi kien truc CQRS, phuong phap TDD nghiem ngat, tu dong hoa build Gradle, theo doi trang thai pipeline, va vong lap review-fix da chieu.

## Tinh nang

- **CQRS Scaffold**: Tao CRUD hoan chinh voi tach Command/Query trong mot lenh
- **TDD nghiem ngat**: Thuc thi chu ky RED-GREEN voi theo doi tai lieu cong viec
- **Cong xac minh**: Xac minh build + checkstyle + test co cau truc
- **Vong lap Review-Fix**: Review code 6 chieu + tu dong sua bang TDD + chu ky re-review
- **Build Doctor**: Tu dong chan doan va sua loi build (toi da 3 lan)
- **Debug he thong**: Phuong phap luan 4 giai doan gia thuyet-kiem chung
- **Theo doi Pipeline**: May trang thai cap tinh nang + dashboard tien do
- **Smart Commit**: Tao commit message theo quy uoc du an

## Pipeline

```
be-init → be-crud (scaffold) → be-code (TDD) → be-verify → be-review ↔ be-fix → be-commit
                                    ↕                          ↕
                           implement agent            code-reviewer agent
                          (RED → GREEN cycle)         (6-dimension review)

Interrupt skills:
  be-debug    — debug he thong (4 giai doan)
  be-progress — dashboard trang thai pipeline
  be-build    — build + tu dong sua (doc lap)

Standalone audits:
  be-jpa, be-api-review, be-clean-code, be-logging, be-test-review
```

## Cai dat

```bash
claude plugin add ./backend-springboot-plugin
```

Khoi tao trong du an:

```
/backend-springboot-plugin:be-init
```

## Skills

### Pipeline chinh

| Skill | Mo ta |
|-------|-------|
| `be-init` | Khoi tao cau hinh plugin (tu dong phat hien) |
| `be-crud <Entity>` | Tao scaffold CQRS CRUD |
| `be-code <feature>` | Trien khai tinh nang bang TDD |
| `be-verify [feature]` | Cong xac minh (build + checkstyle + test) |
| `be-review <feature>` | Review code 6 chieu |
| `be-fix <feature>` | Sua loi tu review report bang TDD |
| `be-commit` | Smart commit tu staged changes |

### Tien ich

| Skill | Mo ta |
|-------|-------|
| `be-build` | Build + tu dong chan doan + sua (3 lan) |
| `be-debug <feature>` | Debug he thong (4 giai doan) |
| `be-recall [section]` | Tham khao quy tac + kiem tra vi pham |
| `be-progress [feature]` | Dashboard tien do pipeline |

### Audit doc lap

| Skill | Mo ta |
|-------|-------|
| `be-api-review` | Kiem tra API REST contract |
| `be-jpa` | Kiem tra JPA/Hibernate patterns |
| `be-clean-code` | Kiem tra DRY/KISS/YAGNI |
| `be-logging` | Kiem tra structured logging |
| `be-test-review` | Kiem tra chat luong test |

## Agents

| Agent | Model | Mo ta |
|-------|-------|-------|
| `implement` | opus | TDD tu tai lieu cong viec |
| `build-doctor` | sonnet | Chan doan va sua loi build |
| `code-reviewer` | opus | Review code 6 chieu |
| `review-fixer` | opus | Sua loi tu review report bang TDD |
| `debugger` | opus | Debug he thong (4 giai doan) |

## Tech Stack ho tro

- Java 21+ / Spring Boot 4.x
- Gradle (Kotlin DSL hoac Groovy) hoac Maven
- PostgreSQL, MySQL, MariaDB, H2
- Spring Data JPA / Flyway hoac Liquibase
- JUnit 5 / Checkstyle / Lombok
