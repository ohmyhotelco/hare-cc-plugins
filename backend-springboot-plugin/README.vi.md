# Backend Spring Boot Plugin

> **Ohmyhotel & Co** — Plugin Claude Code cho phat trien backend Spring Boot voi TDD

## Gioi thieu

Plugin Claude Code cung cap pipeline phat trien day du cho backend Spring Boot su dung kien truc CQRS va phuong phap Test-Driven Development (TDD) nghiem ngat. Bao gom toan bo vong doi tu CRUD scaffolding, trien khai TDD, xac minh, review code 6 chieu, va tu dong sua — tat ca voi theo doi trang thai pipeline.

Tinh nang chinh:
- **CQRS scaffold** — Tao CRUD hoan chinh voi tach Command/Query (entity, repository, DTO, controller, migration) trong mot lenh
- **TDD nghiem ngat** — Thuc thi chu ky RED-GREEN voi theo doi tai lieu cong viec va trien khai tung scenario
- **Cong xac minh** — Xac minh build + checkstyle + test co cau truc (cong chat luong chi doc)
- **Review 6 chieu** — API contract, JPA patterns, clean code, logging, test quality, architecture — voi tu dong sua bang TDD
- **Theo doi pipeline** — May trang thai cap tinh nang + dashboard tien do, canh bao ha cap, phat hien thay doi
- **An toan trang thai** — Co che khoa, doc-sua-ghi, cach ly subagent trong pipeline
- **Audit doc lap** — JPA, API, clean code, logging, test quality audit su dung doc lap bat ky luc nao

## Tong quan kien truc

```
/backend-springboot-plugin:be-init → .claude/backend-springboot-plugin.json
        │
        ▼
/backend-springboot-plugin:be-crud <Entity> [field:Type ...]
        │
        ├── Flyway migration + Entity + Repository
        ├── Command + CommandExecutor
        ├── Query + QueryProcessor
        ├── View DTO + Controller + Exception
        └── Tai lieu cong viec voi test scenario
        │
        ▼
/backend-springboot-plugin:be-code <feature>
        │
        └── implement agent (tung scenario):
            ├── Chon scenario - [ ] tiep theo
            ├── Viet test (RED) → xac nhan that bai
            ├── Trien khai code toi thieu (GREEN) → xac nhan thanh cong
            └── Danh dau - [x] → lap lai
        │
        ▼
/backend-springboot-plugin:be-verify <feature>
        │
        ├── Kiem tra compilation
        ├── Kiem tra checkstyle (neu bat)
        ├── Kiem tra test
        └── Kiem tra full build
        │
        ▼
Vong lap — Review & Fix:
/backend-springboot-plugin:be-review <feature>
        │
        └── code-reviewer agent (6 chieu)
        │
        ▼ (neu co issue)
/backend-springboot-plugin:be-fix <feature>
        │
        └── review-fixer agent
            ├── TDD fix (thay doi hanh vi — test truoc)
            └── Direct fix (thay doi co hoc — edit truc tiep)
        │
        ▼
/backend-springboot-plugin:be-review <feature> (re-review cho den khi pass)
        │
        ▼
/backend-springboot-plugin:be-commit

Interrupt skills (dung o bat ky giai doan nao):
  be-debug    — debug he thong (4 giai doan gia thuyet-kiem chung)
  be-progress — dashboard trang thai pipeline
  be-build    — build + tu dong sua (doc lap)

Audit doc lap (dung doc lap voi pipeline):
  be-jpa, be-api-review, be-clean-code, be-logging, be-test-review
```

## Tech Stack

| Danh muc | Cong nghe |
|----------|-----------|
| Ngon ngu | Java 21+ |
| Framework | Spring Boot 4.x + Spring MVC (REST) + Spring Validation |
| Build | Gradle (Kotlin DSL hoac Groovy) hoac Maven |
| Database | PostgreSQL (mac dinh), MySQL, MariaDB, H2 |
| ORM | Spring Data JPA (Hibernate) |
| Migration | Flyway (mac dinh), Liquibase, hoac none |
| Testing | JUnit 5 + TestRestTemplate + AssertJ (khong Mockito) |
| Chat luong code | Checkstyle (khong dung thu: maxErrors=0, maxWarnings=0) |
| Tien ich | Lombok, UUID Creator (UUID v7) |

## Cai dat

```
# 1. Dang ky nguon marketplace
/plugin marketplace add ohmyhotelco/hare-cc-plugins

# 2. Cai dat plugin (pham vi project — luu vao .claude/settings.json, chia se voi team)
/plugin install backend-springboot-plugin@ohmyhotelco --scope project
```

Xac nhan cai dat:
```
/plugin
```

## Cap nhat & Quan ly

**Cap nhat marketplace** de lay phien ban plugin moi nhat:
```
/plugin marketplace update ohmyhotelco
```

**Vo hieu hoa / Kich hoat** plugin ma khong go bo:
```
/plugin disable backend-springboot-plugin@ohmyhotelco
/plugin enable backend-springboot-plugin@ohmyhotelco
```

**Go bo**:
```
/plugin uninstall backend-springboot-plugin@ohmyhotelco --scope project
```

**Giao dien quan ly plugin**: Chay `/plugin` de mo giao dien tab (Discover, Installed, Marketplaces, Errors).

## Bat dau nhanh

```
1. /backend-springboot-plugin:be-init                          # cau hinh plugin (tu dong phat hien project)
2. /backend-springboot-plugin:be-crud Employee email:String displayName:String   # scaffold CQRS CRUD
3. /backend-springboot-plugin:be-code work/features/employee.md                  # trien khai TDD
4. /backend-springboot-plugin:be-verify employee                                 # cong xac minh
5. /backend-springboot-plugin:be-review employee                                 # review 6 chieu
6. /backend-springboot-plugin:be-commit                                          # smart commit
```

## Chi tiet Skills

### `/backend-springboot-plugin:be-init`

**Cu phap**: `/backend-springboot-plugin:be-init`

**Khi nao dung**: Cai dat lan dau trong project, hoac cau hinh lai.

**Hoat dong**:
1. Tu dong phat hien build tool (Gradle Kotlin/Groovy, Maven), phien ban Java, phien ban Spring Boot
2. Tu dong phat hien base package, loai database, migration tool
3. Kiem tra cau hinh Checkstyle va Lombok
4. Tao `.claude/backend-springboot-plugin.json`
5. Tao thu muc tai lieu cong viec (mac dinh: `work/features/`)

---

### `/backend-springboot-plugin:be-crud`

**Cu phap**: `/backend-springboot-plugin:be-crud <TenEntity> [field:Type ...]`

**Khi nao dung**: Tao domain entity moi voi toan bo cau truc CQRS.

**Hoat dong**:
1. Tu dong tao phien ban Flyway migration tiep theo
2. Tao entity voi BaseEntity, dual key (sequence + UUID v7), va cac cot field
3. Tao repository, command/executor, query/processor, view DTO
4. Tao controller (record DI) voi REST endpoint
5. Tao domain exception
6. Tao tai lieu cong viec voi test scenario ban dau
7. Dat trang thai pipeline thanh `scaffolded`

---

### `/backend-springboot-plugin:be-code`

**Cu phap**: `/backend-springboot-plugin:be-code <ten-feature hoac duong-dan-tai-lieu>`

**Khi nao dung**: Sau scaffolding, hoac khi tai lieu cong viec voi scenario `- [ ]` da san sang.

**Hoat dong**:
1. Neu cho ten feature: kham pha code hien co, soan test scenario, yeu cau phe duyet
2. Neu cho duong dan tai lieu: doc truc tiep scenario `- [ ]` hien co
3. Kiem tra ha cap pipeline (canh bao neu trang thai bi lui)
4. Lay khoa tren file tien do
5. Chay `implement` agent cho tung scenario: RED (viet test, xac nhan that bai) → GREEN (trien khai, xac nhan thanh cong)
6. Chay full build sau khi hoan thanh tat ca scenario
7. Cap nhat trang thai pipeline (`implemented` hoac `implementing`)
8. Giai phong khoa

---

### `/backend-springboot-plugin:be-verify`

**Cu phap**: `/backend-springboot-plugin:be-verify [ten-feature]`

**Khi nao dung**: Sau trien khai, lam cong chat luong truoc review. Chi doc — KHONG sua gi.

**Hoat dong**:
1. Kiem tra ha cap pipeline (canh bao neu tien do review bi mat)
2. Kiem tra thay doi tai lieu cong viec (canh bao neu co scenario moi tu lan trien khai cuoi)
3. Lay khoa
4. Chay 4 buoc kiem tra tuan tu: compilation, checkstyle, test, full build
5. Tao bao cao xac minh co cau truc
6. Cap nhat trang thai pipeline (`verified` hoac `verify-failed`)
7. Giai phong khoa

---

### `/backend-springboot-plugin:be-review`

**Cu phap**: `/backend-springboot-plugin:be-review <ten-feature hoac duong-dan>`

**Khi nao dung**: Sau xac minh, hoac truc tiep sau trien khai, de review chat luong code.

**Hoat dong**:
1. Giai quyet doi tuong (ten feature → thu muc source, hoac duong dan truc tiep)
2. Kiem tra thay doi tai lieu cong viec (canh bao neu co scenario moi tu lan trien khai cuoi)
3. Lay khoa
4. Chay `code-reviewer` agent danh gia 6 chieu:
   - API Contract (HTTP semantic, URL, status code)
   - JPA Patterns (N+1, transaction, index)
   - Clean Code (DRY, KISS, YAGNI, naming)
   - Logging (SLF4J, MDC, bao mat)
   - Test Quality (naming, assertion, coverage)
   - Architecture Compliance (CQRS, naming convention)
5. Luu `review-report.json` (diem tung chieu + issue bo sung: severity, fixHint, refs)
6. Cap nhat trang thai pipeline (`done` / `reviewed` / `review-failed`)
7. Giai phong khoa

**Quy tac ket luan**:
- **PASS**: Tat ca chieu >= 7, khong co issue nghiem trong
- **FAIL**: Bat ky chieu nao < 7 HOAC co issue nghiem trong

---

### `/backend-springboot-plugin:be-fix`

**Cu phap**: `/backend-springboot-plugin:be-fix <ten-feature>`

**Khi nao dung**: Sau khi `be-review` tim thay issue.

**Hoat dong**:
1. Doc `review-report.json`
2. Kiem tra bo dem vong sua (chan sau 3 vong — hoi nguoi dung truoc khi tiep tuc)
3. Lay khoa
4. Chay `review-fixer` agent phan loai tung issue:
   - **TDD required**: Thay doi hanh vi — viet test that bai truoc roi sua
   - **Direct fix**: Thay doi co hoc (naming, annotation) — edit truc tiep
   - **Skip**: Issue da duoc giai quyet
   - **Escalated**: Can thay doi kien truc ngoai pham vi tu dong sua
5. Chay xac minh full build sau khi sua
6. Tao `fix-report.json`
7. Cap nhat trang thai pipeline va giai phong khoa

**Vong lap review-fix**:
```
be-review → FAIL → be-fix → be-review → PASS → be-commit
              ^                 |
              └─────────────────┘ (neu van that bai)
```

---

### `/backend-springboot-plugin:be-build`

**Cu phap**: `/backend-springboot-plugin:be-build`

**Khi nao dung**: Khi build that bai va can tu dong chan doan va sua. Doc lap voi pipeline.

**Hoat dong**:
1. Chay `build-doctor` agent
2. Phan loai loi: compilation, test, checkstyle, dependency, configuration
3. Ap dung sua co muc tieu voi toi da 3 lan thu lai
4. Bao cao tat ca thay doi da ap dung

---

### `/backend-springboot-plugin:be-debug`

**Cu phap**: `/backend-springboot-plugin:be-debug <mo-ta-loi hoac ten-feature>`

**Khi nao dung**: Cho runtime error, test failure, hoac build issue o bat ky diem nao trong pipeline.

**Hoat dong**:
1. Thu thap ngu canh van de (error message, stack trace, source file lien quan)
2. Lay khoa (neu co ngu canh feature)
3. Chay `debugger` agent voi phuong phap 4 giai doan:
   - **Reproduce**: Phan tich loi, xac nhan tai tao duoc
   - **Hypothesize**: Lap chinh xac 3 gia thuyet xep hang
   - **Test**: Ap dung sua theo gia thuyet, xac minh, hoan tac neu that bai
   - **Confirm**: Kiem tra hoi quy + full build
4. Neu ca 3 gia thuyet that bai: escalate cho can thiep thu cong
5. Cap nhat trang thai pipeline (`resolved` hoac `escalated`) va giai phong khoa

---

### `/backend-springboot-plugin:be-commit`

**Cu phap**: `/backend-springboot-plugin:be-commit`

**Khi nao dung**: Sau khi pipeline dat trang thai `done` hoac `reviewed`.

**Hoat dong**: Tao commit tu staged changes theo quy uoc project (tieng Anh, thi hien tai, tieu de 50 ky tu, khong prefix, khong de cap test code).

---

### `/backend-springboot-plugin:be-recall`

**Cu phap**: `/backend-springboot-plugin:be-recall [section]`

**Khi nao dung**: Tham khao quy tac hoac kiem tra vi pham trong cong viec gan day.

**Hoat dong**: Hien thi quy tac tu CLAUDE.md theo section (commit, tdd, build, coding, api, jpa) va kiem tra vi pham trong cong viec gan day. Co the tu dong sua vi pham don gian (vi du: thieu newline cuoi file).

---

### `/backend-springboot-plugin:be-progress`

**Cu phap**: `/backend-springboot-plugin:be-progress [ten-feature]`

**Khi nao dung**: Bat ky luc nao de kiem tra trang thai pipeline hien tai.

**Hoat dong**:
- **Khong co ten feature**: Bang tom tat tat ca feature (trang thai pipeline, tien do scenario, ket qua xac minh, diem review, vong sua)
- **Co ten feature**: Xem chi tiet (lich su pipeline, scenario hoan thanh/con lai, kiem tra thay doi tai lieu, huong dan buoc tiep theo)

## Audit doc lap

Cac skill nay chay doc lap voi pipeline. Su dung bat ky luc nao cho audit co muc tieu.

| Skill | Noi dung kiem tra |
|-------|-------------------|
| `be-api-review` | HTTP method semantic, URL pattern (kebab-case, so nhieu), status code, pagination, error response |
| `be-jpa` | N+1 query, thieu @Transactional, rui ro lazy loading, query khong gioi han, thieu index, cascade |
| `be-clean-code` | Vi pham DRY/KISS/YAGNI, god class, nest sau, method dai, van de naming |
| `be-logging` | Su dung System.out, lo du lieu nhay cam, noi chuoi, log level sai, su dung MDC |
| `be-test-review` | Quy uoc naming, chat luong assertion, anti-pattern, phan tich coverage, phat hien test cham |

## Workflow pipeline day du

### Buoc 1: Khoi tao

```
/backend-springboot-plugin:be-init
```

Tu dong phat hien cai dat project (build tool, phien ban Java, phien ban Spring Boot, base package, database, migration tool). Tao `.claude/backend-springboot-plugin.json`.

### Buoc 2: Scaffold CRUD

```
/backend-springboot-plugin:be-crud Employee email:String displayName:String
```

Tao toan bo cau truc CQRS: Flyway migration, entity, repository, command/executor, query/processor, view, controller, exception, va tai lieu cong viec voi test scenario ban dau.

### Buoc 3: Trien khai voi TDD

```
/backend-springboot-plugin:be-code work/features/employee.md
```

`implement` agent xu ly tung scenario `- [ ]` mot lan:
1. **RED** — Viet test, chay test class, xac nhan that bai
2. **GREEN** — Viet code toi thieu, chay toan bo test class, xac nhan tat ca pass
3. **Danh dau** — Cap nhat `- [ ]` thanh `- [x]`, chuyen sang scenario tiep

### Buoc 4: Xac minh

```
/backend-springboot-plugin:be-verify employee
```

Cong chi doc: compilation, checkstyle, test, full build. Bao cao pass/fail ma khong sua.

### Buoc 5: Review

```
/backend-springboot-plugin:be-review employee
```

Review code 6 chieu voi diem tung chieu. Issue bao gom severity, fix hint, va refs truy vet den API endpoint hoac test scenario.

### Buoc 6: Sua & Re-review

```
/backend-springboot-plugin:be-fix employee
/backend-springboot-plugin:be-review employee
```

Lap lai cho den khi review pass. TDD cho thay doi hanh vi, edit truc tiep cho thay doi co hoc. Vong sua duoc theo doi — canh bao sau 3 vong.

### Buoc 7: Commit

```
/backend-springboot-plugin:be-commit
```

## Agent

### Implement

**Vai tro**: Trien khai TDD tu tai lieu cong viec.

Xu ly scenario `- [ ]` tung cai theo chu ky RED-GREEN nghiem ngat. Tung scenario: viet test → xac nhan that bai → trien khai code toi thieu → xac nhan tat ca test pass → danh dau hoan thanh. Toi da 3 lan test that bai lien tiep truoc khi escalate. Su dung model Opus.

### Build Doctor

**Vai tro**: Chan doan va tu dong sua loi build.

Phan loai loi build (compilation, test, checkstyle, dependency, configuration) va ap dung sua co muc tieu. Thu lai toi da 3 lan. Su dung model Sonnet.

### Code Reviewer

**Vai tro**: Review code 6 chieu.

Agent chi doc, danh gia API contract, JPA pattern, clean code, logging, test quality, va architecture compliance. Tao bao cao review co cau truc voi issue xep theo severity. Moi issue bao gom dimension, severity, file, line, rule, message, suggestion, va refs (truy vet den API endpoint hoac test scenario). Su dung model Opus.

### Review Fixer

**Vai tro**: Sua issue review bang TDD.

Phan loai tung issue: TDD required (thay doi hanh vi — test truoc), direct fix (thay doi co hoc), skip (da giai quyet), escalated (can can thiep thu cong). Toi da 3 lan thu cho moi TDD fix truoc khi escalate. Su dung model Opus.

### Debugger

**Vai tro**: Debug he thong voi phuong phap 4 giai doan.

Reproduce → Hypothesize (chinh xac 3) → Test → Confirm. Phan loai loi: type-error, test-failure, build-error, runtime-error, config-error, migration-error. Escalate neu ca 3 gia thuyet that bai. Su dung model Opus.

## Cau hinh

`.claude/backend-springboot-plugin.json` (tao boi `be-init`):

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

| Truong | Mo ta | Mac dinh |
|--------|-------|----------|
| `javaVersion` | Phien ban Java toolchain | `"21"` |
| `springBootVersion` | Phien ban Spring Boot | `"4.0.2"` |
| `buildTool` | `"gradle-kotlin"` / `"gradle-groovy"` / `"maven"` | `"gradle-kotlin"` |
| `buildCommand` | Lenh build day du | `"./gradlew build"` |
| `testCommand` | Lenh chi chay test | `"./gradlew test"` |
| `basePackage` | Package Java goc | `"com.example"` |
| `sourceDir` | Thu muc source chinh | `"src/main/java"` |
| `testDir` | Thu muc source test | `"src/test/java"` |
| `architecture` | Kieu kien truc — quyet dinh cau truc package va template | `"cqrs"` |
| `database` | `"postgresql"` / `"mysql"` / `"h2"` / `"mariadb"` | `"postgresql"` |
| `migration` | `"flyway"` / `"liquibase"` / `"none"` | `"flyway"` |
| `checkstyle` | Bat Checkstyle hay khong | `true` |
| `lombokEnabled` | Su dung Lombok hay khong | `true` |
| `workDocDir` | Thu muc tai lieu cong viec | `"work/features"` |
| `workingLanguage` | Ngon ngu output cho nguoi dung (`"en"` / `"ko"` / `"vi"`) | `"en"` |

## Cau truc package CQRS

```
{basePackage}/
├── {App}Application.java
├── command/                    <- Request command DTO (record)
│   └── Create{Entity}.java
├── commandmodel/               <- Logic thuc thi command
│   └── Create{Entity}CommandExecutor.java
├── query/                      <- Request query DTO (record)
│   └── Get{Entities}.java
├── querymodel/                 <- Logic xu ly query
│   └── Get{Entity}PageQueryProcessor.java
├── view/                       <- Response view DTO (record)
│   └── {Entity}View.java
├── data/                       <- Entity va repository
│   ├── {Entity}.java
│   ├── {Entity}Repository.java
│   └── BaseEntity.java
├── config/                     <- Spring configuration bean
└── {domain}/                   <- Business logic theo domain
    ├── api/                    <- REST controller
    │   └── {Entity}Controller.java
    └── {Description}Exception.java
```

## Trang thai Pipeline

### File trang thai

Trang thai duoc theo doi trong `{workDocDir}/.progress/{feature}.json`.

| File | Muc dich |
|------|----------|
| `{feature}.json` | Trang thai pipeline, so luong scenario, lich su verify/review/fix/debug |
| `review-report.json` | Ket qua review voi diem tung chieu va issue bo sung |
| `fix-report.json` | Ket qua fix voi phan loai chien luoc (TDD/direct/escalated) |
| `.lock` | Ngan thuc thi dong thoi (tu dong het han sau 30 phut) |

### May trang thai

```
scaffolded → implementing → implemented → verified → reviewed → done
                                  ↓            ↓          ↓
                            verify-failed  review-failed  fixing
                                  ↓            ↓          ↓
                              be-build     be-fix    be-review (re-review)
                                  ↓            ↓
                              verified     fixing → reviewed/done

Bat ky luc nao:
  be-debug → resolved | escalated
  resolved → (tai nhap pipeline o giai doan phu hop)
  escalated → (can thiep thu cong, sau do tai nhap)
```

### An toan trang thai

- **Co che khoa**: Skill sua file tien do phai lay `.lock` truoc khi bat dau. Ngan thuc thi dong thoi tren cung feature. Khoa cu (>30 phut) tu dong xoa.
- **Quy tac doc-sua-ghi**: Luon doc noi dung file moi nhat truoc khi ghi. Chi merge truong thay doi — giu tat ca truong hien co.
- **Canh bao ha cap**: Chay skill tu giai doan pipeline truoc do se canh bao truoc khi reset tien do (vi du: chay lai `be-code` khi status la `verified` se mat ket qua xac minh).
- **Phat hien thay doi**: `be-verify` va `be-review` canh bao khi tai lieu cong viec da duoc sua tu lan cap nhat pipeline cuoi, cho thay scenario moi co the chua duoc trien khai.
- **Cach ly subagent**: Skill dieu phoi chi truyen parameter can thiet cho agent — khong co ngu canh hoi thoai ro ri giua cac giai doan.

## Ngon ngu giao tiep

Skill doc `workingLanguage` tu cau hinh. Tat ca output cho nguoi dung (tom tat, cau hoi, phan hoi, huong dan buoc tiep) bang ngon ngu lam viec.

Anh xa ngon ngu: `en` = English, `ko` = Korean, `vi` = Tieng Viet.

## Meo & Thuc hanh tot

- **Xem lai tai lieu cong viec truoc khi code** — `be-crud` tao scenario ban dau, nhung ban co the them, xoa, hoac sap xep lai truoc khi chay `be-code`.

- **Dung be-verify lam cong nhanh** — Chi doc va nhanh. Chay sau trien khai de bat issue compilation hoac test truoc khi dau tu thoi gian cho review day du.

- **Khong bo qua re-review sau fix** — Luon chay `be-review` sau `be-fix`. Vong review-fix dam bao khong co hoi quy.

- **Dung be-debug cho issue phuc tap** — Neu test that bai khong ro rang, `be-debug` cung cap kiem tra gia thuyet he thong thay vi debug tuy hung.

- **Audit doc lap mien phi** — `be-jpa`, `be-api-review`, `be-clean-code`, `be-logging`, va `be-test-review` hoat dong doc lap voi pipeline. Dung bat ky luc nao cho kiem tra chat luong co muc tieu.

- **Tiep tuc an toan** — Neu `be-code` bi gian doan, chi can chay lai voi cung tai lieu cong viec. Scenario hoan thanh (`- [x]`) duoc giu lai va tiep tuc tu `- [ ]` tiep theo.

- **Khoa bao ve trang thai** — Khong chay `be-code` va `be-fix` dong thoi tren cung feature. Co che khoa ngan hong file tien do.

## Lo trinh

- [x] Tao CQRS CRUD scaffold
- [x] Pipeline trien khai TDD
- [x] Cong xac minh
- [x] Review code 6 chieu + vong review-fix
- [x] Build doctor (tu dong chan doan va sua)
- [x] Debug he thong (4 giai doan gia thuyet-kiem chung)
- [x] Theo doi trang thai pipeline + dashboard tien do
- [x] Audit doc lap (JPA, API, clean code, logging, test quality)
- [x] An toan trang thai (khoa, ha cap, thay doi, cach ly subagent)
- [ ] Tich hop planning-plugin (scaffold tu spec)
- [ ] Ho tro project da module
- [ ] Template kien truc event-driven (Kafka, RabbitMQ)
- [ ] Skill audit bao mat (OWASP, Spring Security)

## Cau truc thu muc

```
agents/          Dinh nghia agent (implement, build-doctor, code-reviewer,
                 review-fixer, debugger)
skills/          Diem vao skill (be-init, be-crud, be-code, be-verify,
                 be-review, be-fix, be-commit, be-build, be-debug, be-recall,
                 be-progress, be-jpa, be-api-review, be-clean-code, be-logging,
                 be-test-review)
templates/       File template (tdd-rules, cqrs-module, entity-conventions,
                 test-scenario-template, work-document-template, checkstyle-config,
                 progress-schema)
docs/            Tai lieu
```

## Tac gia

Justin Choi — Ohmyhotel & Co
