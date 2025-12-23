# ORM Baraba

Professional PostgreSQL ORM и миграционна система за PostgreSQL в Nim 2.2.4, вдъхновена от Flyway с enterprise-grade функционалности. **✅ Production Ready**

## Инсталация

### Изисквания

- Nim >= 2.2.0 (включително 2.2.4+)
- PostgreSQL >= 12
- lowdb пакет
- checksums пакет
- pgvector extension (за vector search)

```bash
nimble install lowdb
nimble install checksums
```

**⚠️ Важно:** ORM Baraba v2.2.4 е тестван и съвместим с Nim 2.2.0 и 2.2.4. Автоматично се справя с промените в синтаксиса между версиите.

### Компилация

```bash
nimble build
```

### Quick Start

```bash
# Задай environment променливи
export DB_PASSWORD="your_password"
export DB_NAME="your_database"

# Приложи миграциите
./main migrate

# Провери статуса
./main info

# Стартирай interactive CLI
./main interactive
```

## Конфигурация на базата данни

ORM-ът използва environment променливи за конфигурация:

```bash
export DB_HOST="localhost"        # PostgreSQL сървър
export DB_PORT="5432"            # Порт
export DB_USER="postgres"        # Потребител
export DB_PASSWORD="your_pass"   # Парола (ЗАДЪЛЖИТЕЛНА)
export DB_NAME="orm-baraba"      # Име на базата
export VERBOSE="true"             # Опционално: verbose логове
export NO_COLOR="false"          # Опционално: без цветове
```

**⚠️ Важно:** `DB_PASSWORD` е задължителна променлива. Ако не е зададена, програмата ще прекъсне с грешка.

## Миграционна система

Миграционната система е базирана на Flyway и поддържа:

- Версионирани SQL миграции
- Checksum валидация
- Rollback с undo миграции
- Проследяване на историята в `schema_history` таблица

### Формат на миграционни файлове

Миграциите се намират в `src/migrations/` и следват конвенция:

```
V<версия>__<описание>.sql    # Миграция (forward)
U<версия>__<описание>.sql    # Undo миграция (rollback)
```

**Примери:**
```
V1__create_users_table.sql
V2__add_users_phone.sql
V3__create_orders_table.sql
U1__create_users_table.sql
U2__add_users_phone.sql
```

## CLI Интерфейс

### Command Line Commands

```bash
# Миграции
./main migrate                    # Прилага всички pending миграции
./main rollback [N]              # Rollback до версия N
./main info                      # Показва статус на миграциите
./main validate                  # Валидира checksums
./main repair                    # Поправя checksums след edit
./main clean                     # Изтрива цялата history (ОПАСНО!)

# ORM операции
./main demo                      # Демонстрация на CRUD операции
./main seed                      # Създава тестови данни

# Utility
./main interactive               # Стартира TUI интерфейс
./main help                      # Помощ
./main version                   # Показва версия
```

### Interactive TUI

Стартирай `./main interactive` за пълен графичен интерфейс:

- **Migration Management** - Управление на миграции
- **Database Information** - Информация за базата
- **ORM Demo & Examples** - Примери и демонстрации
- **Database Operations** - CRUD операции през UI
- **Settings & Configuration** - Конфигурационни настройки
- **Help & Documentation** - Вградена помощ

### Пример за миграция

**V1__create_users_table.sql:**
```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**U1__create_users_table.sql:**
```sql
DROP TABLE IF EXISTS users CASCADE;
```

### Schema History таблица

Системата автоматично създава `schema_history` таблица:

| Колона | Тип | Описание |
|--------|-----|----------|
| installed_rank | SERIAL | Пореден номер |
| version | INT | Версия на миграцията |
| description | VARCHAR(200) | Описание |
| type | VARCHAR(20) | Тип (SQL) |
| script | VARCHAR(1000) | Име на файла |
| checksum | VARCHAR(32) | MD5 checksum |
| installed_by | VARCHAR(100) | Потребител |
| installed_on | TIMESTAMP | Дата на прилагане |
| execution_time | INT | Време за изпълнение (ms) |
| success | BOOLEAN | Успешна ли е |

## ORM

### Дефиниране на модели

Всички модели наследяват от `Model`:

```nim
import orm/orm

type
  User* = object of Model
    name*: string
    email*: string
    phone*: string

  Order* = object of Model
    userId*: int
    total*: float
    status*: string
```

**Важно:** Полетата трябва да са `public` (с `*`).

### Конвенции за именуване

- Име на тип `User` → таблица `users`
- Име на тип `OrderItem` → таблица `order_items`
- Поле `userId` → колона `user_id`
- Поле `createdAt` → колона `created_at`

### CRUD операции

Всички ORM операции изискват explicit database connection като последен параметър.

#### Създаване (INSERT)

```nim
let db = getDbConn()
defer: releaseDbConn(db)

var user = User(name: "Иван", email: "ivan@example.com")
save(user, db)
echo user.id  # Автоматично попълнен след INSERT
```

#### UUID базирани модели (UuidModel)

```nim
let db = getDbConn()
defer: releaseDbConn(db)

type
  Profile* = object of UuidModel  # ID е UUID string
    name*: string
    bio*: string

var profile = Profile(name: "Мария", bio: "Developer")
save(profile, db)
echo profile.id  # UUID като "550e8400-e29b-41d4-a716-446655440000"

# Намери по UUID
let found = findUuid(Profile, "550e8400-e29b-41d4-a716-446655440000", db)
if found.isSome:
  echo "Намерен: ", found.get().name

# Изтрий UUID модел
deleteUuid(Profile, "550e8400-e29b-41d4-a716-446655440000", db)
```

#### Четене (SELECT)

```nim
let db = getDbConn()
defer: releaseDbConn(db)

# Намери по id - връща Option[T]
let userOpt = find(User, 1, db)
if userOpt.isSome:
  echo userOpt.get().name

# Намери всички
let users = findAll(User, db)
for u in users:
  echo u.name

# Намери с условие
let activeUsers = findWhere(User, db, "status = $1", "active")
```

#### Обновяване (UPDATE)

```nim
let db = getDbConn()
defer: releaseDbConn(db)

let userOpt = find(User, 1, db)
if userOpt.isSome:
  var user = userOpt.get()
  user.name = "Ново име"
  save(user, db)  # UPDATE защото id != 0
```

#### Изтриване (DELETE)

```nim
let db = getDbConn()
defer: releaseDbConn(db)

# Изтрий по обект
let userOpt = find(User, 1, db)
if userOpt.isSome:
  var user = userOpt.get()
  delete(user, db)

# Изтрий по id
deleteById(User, 1, db)
```

#### Помощни функции

```nim
let db = getDbConn()
defer: releaseDbConn(db)

# Брой записи
let cnt = count(User, db)

# Проверка за съществуване
if exists(User, 1, db):
  echo "Потребителят съществува"

# Raw SQL заявки
let rows = rawQuery(db, "SELECT * FROM users WHERE active = $1", "true")
rawExec(db, "UPDATE users SET active = $1 WHERE id = $2", "false", "1")

# UUID операции
let uuidCnt = count(Profile, db)
let uuidExists = existsUuid(Profile, "550e8400-e29b-41d4-a716-446655440000", db)
```

### Транзакции

```nim
# Ръчно управление
beginTransaction()
try:
  save(user1)
  save(user2)
  commitTransaction()
except:
  rollbackTransaction()
  raise

# С template (препоръчително)
withTransaction:
  save(user1)
  save(user2)
  # Автоматичен commit при успех
  # Автоматичен rollback при грешка
```

### Автоматична генерация на схема

ORM-ът може да генерира CREATE TABLE SQL от дефинициите на моделите:

```nim
import orm/orm

type
  User* = object of Model
    username*: string
    email*: string
    is_active*: bool
    created_at*: DateTime

# Генериране на SQL (compile-time)
echo createTableSql(User)
# Резултат:
# CREATE TABLE IF NOT EXISTS users (
#   id SERIAL PRIMARY KEY,
#   username TEXT NOT NULL,
#   email TEXT NOT NULL,
#   is_active BOOLEAN NOT NULL DEFAULT false,
#   created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
# )

# Създаване на таблица в базата
let db = getDbConn()
defer: releaseDbConn(db)

createTable(db, User)      # Създава таблицата
ensureTable(db, User)      # Създава само ако не съществува
dropTable(db, User)        # Изтрива таблицата (ОПАСНО!)

# Проверка дали таблицата съществува
if tableExists(db, "users"):
  echo "Таблицата users съществува"
```

#### Type Mapping: Nim → PostgreSQL

| Nim тип | PostgreSQL тип |
|---------|----------------|
| `string` | TEXT |
| `int` | INTEGER |
| `int64` | BIGINT |
| `float`, `float64` | DOUBLE PRECISION |
| `float32` | REAL |
| `bool` | BOOLEAN |
| `DateTime` | TIMESTAMP WITH TIME ZONE |
| `JsonField` | JSONB |
| `VectorField` | vector(1536) |
| `Option[T]` | T (nullable) |
| `seq[T]` | JSONB |

#### Нови типове във v2.2.5

##### UuidModel - UUID базирани модели
За Phoenix/Ecto съвместимост и distributed системи:

```nim
type
  User* = object of UuidModel  # Наследява от UuidModel вместо Model
    name*: string
    email*: string

# Автоматично генерира UUID при създаване
var user = User(name: "Иван", email: "ivan@example.com")
save(user, db)  # user.id ще бъде UUID като "550e8400-e29b-41d4-a716-446655440000"
```

##### JsonField - JSONB поддръжка
За PostgreSQL JSONB колони:

```nim
type
  Document* = object of Model
    title*: string
    metadata*: JsonField  # JSONB колона

# Създаване и манипулация
var doc = Document(title: "Документ")
doc.metadata["author"] = "Иван"
doc.metadata["tags"] = %*["nim", "database"]
doc.metadata["published"] = true
save(doc, db)

// Четене
let found = find(Document, 1, db).get()
echo found.metadata.getStr("author")  # "Иван"
echo found.metadata.getBool("published")  # true
```

##### VectorField - pgvector поддръжка
За AI/ML similarity search:

```nim
type
  Embedding* = object of Model
    content*: string
    vector*: VectorField  # vector(1536) колона

# Създаване на вектор
var emb = Embedding(content: "Текст")
emb.vector = newVectorField(@[0.1'f32, 0.2, 0.3, 0.4])
save(emb, db)

# Similarity search
let queryVec = newVectorField(@[0.1'f32, 0.2, 0.3, 0.5])
let results = searchSimilar("embeddings", "vector", queryVec, k=5, metric=Cosine)
```

##### DistanceMetric - Векторни distance metrics
```nim
type DistanceMetric* = enum
  Cosine       # <=> - cosine distance
  L2           # <-> - Euclidean distance  
  InnerProduct # <#> - negative inner product
```

#### Pluralization

Имената на таблиците се плурализират автоматично:
- `User` → `users`
- `Company` → `companies`
- `Currency` → `currencies`
- `JournalEntry` → `journal_entries`
- `UserGroup` → `user_groups`

### Thread-safe операции

ORM-ът използва explicit connection passing за всички операции:

```nim
import lowdb/postgres

# Създаване на отделна връзка за thread
let db = open("localhost", "user", "pass", "dbname")
defer: db.close()

# Thread-safe операции с explicit връзка
save(user, db)  # INSERT с конкретна връзка
let found = find(User, 1, db)  # SELECT с конкретна връзка

# В многонишкова среда
import threadpool

proc processUser(userId: int) {.thread.} =
  let db = open("localhost", "user", "pass", "dbname")
  defer: db.close()

  let userOpt = find(User, userId, db)
  if userOpt.isSome:
    var u = userOpt.get()
    u.name = "Processed"
    save(u, db)

# Стартиране на множество threads
var threads: seq[FlowVar[void]]
for id in [1, 2, 3, 4, 5]:
  threads.add(spawn processUser(id))

for thread in threads:
  sync(thread)
```

## JSON/JSONB поддръжка

ORM-ът поддържа PostgreSQL JSONB колони чрез типа `JsonField`.

### Дефиниране на модел с JSON поле

```nim
import orm/orm
import json

type
  User* = object of Model
    name*: string
    email*: string
    metadata*: JsonField    # JSONB колона
    settings*: JsonField    # JSONB колона
```

### Миграция за JSONB колона

```sql
-- V3__add_users_metadata.sql
ALTER TABLE users ADD COLUMN metadata JSONB DEFAULT '{}';
CREATE INDEX idx_users_metadata ON users USING GIN (metadata);
```

### Създаване и работа с JsonField

```nim
# Създаване на празен JsonField
var meta = newJsonField()

# Създаване от JSON string
var meta2 = newJsonField("""{"role": "admin", "level": 5}""")

# Създаване от JsonNode
var meta3 = newJsonField(%*{"key": "value"})

# Задаване на стойности
meta["role"] = "admin"
meta["level"] = 5
meta["active"] = true
meta["score"] = 99.5

# Създаване на потребител с JSON
var user = User(
  name: "Иван",
  email: "ivan@example.com",
  metadata: meta,
  settings: newJsonField("""{"theme": "dark"}""")
)
save(user)
```

### Четене на стойности от JsonField

```nim
let user = find(User, 1).get()

# Достъп до стойности с типизирани методи
let role = user.metadata.getStr("role")           # string
let level = user.metadata.getInt("level")         # int
let score = user.metadata.getFloat("score")       # float
let active = user.metadata.getBool("active")      # bool

# Стойности по подразбиране
let name = user.metadata.getStr("name", "Unknown")
let count = user.metadata.getInt("count", 0)

# Проверка за ключ
if user.metadata.hasKey("role"):
  echo "Има роля: ", user.metadata.getStr("role")

# Достъп до масиви
let tags = user.metadata.getArray("tags")
for tag in tags:
  echo tag.getStr()

# Директен достъп до JsonNode
let node = user.metadata["role"]
```

### JSONB заявки в PostgreSQL

```nim
let db = getDbConn()
defer: releaseDbConn(db)

# Търсене по JSON стойност
let admins = findWhere(User, db, "metadata->>'role' = $1", "admin")

# Търсене по число в JSON
let highLevel = findWhere(User, db, "(metadata->>'level')::int > $1", "5")

# Проверка дали JSON съдържа ключ
let withRole = findWhere(User, db, "metadata ? $1", "role")

# Проверка дали JSON съдържа стойност
let darkTheme = findWhere(User, db, "settings @> $1", """{"theme": "dark"}""")
```

### JSON Query помощни функции

```nim
# Генериране на WHERE клаузи за JSON
let where1 = jsonQuery("users", "metadata", "role", "admin")
# Резултат: metadata->>'role' = 'admin'

let where2 = jsonQueryInt("users", "metadata", "level", 5)
# Резултат: (metadata->>'level')::int = 5

let where3 = jsonContains("metadata", """{"active": true}""")
# Резултат: metadata @> '{"active": true}'

let where4 = jsonHasKey("metadata", "role")
# Резултат: metadata ? 'role'

let where5 = jsonHasAllKeys("metadata", @["role", "level"])
# Резултат: metadata ?& array['role','level']

let where6 = jsonHasAnyKey("metadata", @["admin", "superuser"])
# Резултат: metadata ?| array['admin','superuser']
```

### Raw SQL заявки

За сложни JSON заявки можете да използвате директно SQL:

```nim
# Заявка с резултати
let rows = rawQuery("""
  SELECT id, name, metadata->>'role' as role
  FROM users
  WHERE metadata @> '{"active": true}'
  ORDER BY (metadata->>'level')::int DESC
""")

for row in rows:
  echo "ID: ", row[0], ", Name: ", row[1], ", Role: ", row[2]

# Изпълнение без резултати
rawExec("""
  UPDATE users
  SET metadata = metadata || '{"verified": true}'
  WHERE id = $1
""", userId)
```

### JsonField API Reference

| Функция | Описание |
|---------|----------|
| `newJsonField()` | Създава празен JsonField |
| `newJsonField(s: string)` | Създава от JSON string |
| `newJsonField(j: JsonNode)` | Създава от JsonNode |
| `jf[key]` | Достъп до JsonNode по ключ |
| `jf[key] = value` | Задава стойност |
| `jf.hasKey(key)` | Проверява за ключ |
| `jf.getStr(key, default)` | Връща string |
| `jf.getInt(key, default)` | Връща int |
| `jf.getFloat(key, default)` | Връща float |
| `jf.getBool(key, default)` | Връща bool |
| `jf.getArray(key)` | Връща seq[JsonNode] |
| `$jf` | Конвертира до JSON string |

### JSON Query помощници

| Функция | Описание |
|---------|----------|
| `jsonQuery(table, col, path, val)` | `col->>'path' = 'val'` |
| `jsonQueryInt(table, col, path, val)` | `(col->>'path')::int = val` |
| `jsonContains(col, json)` | `col @> 'json'` |
| `jsonHasKey(col, key)` | `col ? 'key'` |
| `jsonHasAllKeys(col, keys)` | `col ?& array[...]` |
| `jsonHasAnyKey(col, keys)` | `col ?| array[...]` |
| `rawQuery(sql, args)` | Изпълнява SQL, връща rows |
| `rawExec(sql, args)` | Изпълнява SQL без резултат |

## pgvector - Векторно търсене

ORM-ът поддържа pgvector за similarity search и AI embeddings.

### Инсталация на pgvector

```sql
-- В PostgreSQL
CREATE EXTENSION IF NOT EXISTS vector;
```

### Дефиниране на модел с вектор

```nim
import orm/orm

type
  Document* = object of Model
    title*: string
    content*: string
    embedding*: VectorField  # vector(1536) колона
```

### Миграция за векторна колона

```sql
-- V4__enable_pgvector.sql
CREATE EXTENSION IF NOT EXISTS vector;

ALTER TABLE documents ADD COLUMN embedding vector(1536);

-- IVFFlat индекс (бърз, по-малко памет)
CREATE INDEX idx_docs_embedding ON documents
  USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);

-- Или HNSW индекс (по-добър recall, повече памет)
CREATE INDEX idx_docs_embedding_hnsw ON documents
  USING hnsw (embedding vector_cosine_ops);
```

### Създаване на вектори

```nim
# Празен вектор
var vec = newVectorField()

# Вектор с фиксирани размерности
var vec2 = newVectorField(1536)

# От seq[float32] или seq[float]
var vec3 = newVectorField(@[0.1'f32, 0.2, 0.3, 0.4])
var vec4 = newVectorField(@[0.1, 0.2, 0.3, 0.4])

# От PostgreSQL string формат
var vec5 = newVectorField("[0.1,0.2,0.3,0.4]")

# Достъп до елементи
echo vec3[0]  # 0.1
vec3[0] = 0.5
```

### Векторни операции

```nim
let a = newVectorField(@[1.0, 0.0, 0.0])
let b = newVectorField(@[0.0, 1.0, 0.0])

# Нормализиране (unit vector)
let normalized = a.normalize()

# Dot product
let dotProd = dot(a, b)  # 0.0

# Magnitude (L2 norm)
let mag = magnitude(a)  # 1.0

# Cosine similarity (-1 до 1)
let similarity = cosineSimilarity(a, b)  # 0.0

# Euclidean distance
let distance = euclideanDistance(a, b)  # 1.414...
```

### Distance Metrics

```nim
type DistanceMetric* = enum
  Cosine       # <=> - cosine distance (1 - similarity)
  L2           # <-> - Euclidean distance
  InnerProduct # <#> - negative inner product
```

### Similarity Search

```nim
# Подготовка на query vector (от AI embedding API)
let queryVec = newVectorField(embeddingFromOpenAI)

# Намери 10 най-близки документа
let results = searchSimilar("documents", "embedding", queryVec, k=10, metric=Cosine)

for r in results:
  echo "ID: ", r.id, ", Distance: ", r.distance

# С допълнителни колони
let rows = searchSimilarWithData(
  "documents", "embedding", queryVec,
  @["id", "title", "content"],
  k=10, metric=Cosine
)

for row in rows:
  echo "Title: ", row[1], ", Distance: ", row[3]

# С WHERE филтър
let filtered = searchSimilar(
  "documents", "embedding", queryVec,
  k=10, metric=Cosine,
  whereClause="metadata->>'category' = 'tech'"
)
```

### Генериране на SQL заявки

```nim
let vec = newVectorField(@[0.1, 0.2, 0.3])

# Distance expression за ORDER BY
let dist = vectorDistance("embedding", vec, Cosine)
# Резултат: embedding <=> '[0.1,0.2,0.3]'

# WHERE clause за максимална дистанция
let where = vectorDistanceWhere("embedding", vec, Cosine, 0.5)
# Резултат: embedding <=> '[0.1,0.2,0.3]' < 0.5

# KNN clause
let knn = vectorKnn("embedding", vec, 10, L2)
# Резултат: ORDER BY embedding <-> '[0.1,0.2,0.3]' LIMIT 10

# Пълна search query
let query = vectorSearchQuery(
  "documents", "embedding", vec,
  k=10, metric=Cosine,
  selectColumns=@["id", "title"],
  whereClause="active = true"
)
```

### Създаване на индекси

```nim
# IVFFlat индекс (препоръчително за < 1M записа)
let idx1 = createVectorIndex("documents", "embedding", "ivfflat", lists=100, metric=Cosine)
rawExec(idx1)

# HNSW индекс (по-добър recall, повече памет)
let idx2 = createVectorIndex("documents", "embedding", "hnsw", metric=L2)
rawExec(idx2)

# Изтриване на индекс
let drop = dropVectorIndex("documents", "embedding", Cosine)
rawExec(drop)
```

### RAG (Retrieval Augmented Generation) пример

```nim
import orm/orm
import orm/migrations
import httpclient, json

type
  Document* = object of Model
    title*: string
    content*: string
    embedding*: VectorField
    metadata*: JsonField

proc getEmbedding(text: string): VectorField =
  # Извикване на OpenAI Embeddings API
  let client = newHttpClient()
  client.headers = newHttpHeaders({
    "Authorization": "Bearer " & getEnv("OPENAI_API_KEY"),
    "Content-Type": "application/json"
  })

  let body = %*{
    "input": text,
    "model": "text-embedding-ada-002"
  }

  let resp = client.postContent("https://api.openai.com/v1/embeddings", $body)
  let data = parseJson(resp)
  let embedding = data["data"][0]["embedding"]

  var vec = newSeq[float32](embedding.len)
  for i, v in embedding:
    vec[i] = v.getFloat().float32

  return newVectorField(vec)

proc indexDocument(title, content: string) =
  var doc = Document(
    title: title,
    content: content,
    embedding: getEmbedding(content)
  )
  doc.metadata["indexed_at"] = $now()
  save(doc)

proc searchDocuments(query: string, k: int = 5): seq[Row] =
  let queryVec = getEmbedding(query)
  return searchSimilarWithData(
    "documents", "embedding", queryVec,
    @["id", "title", "content"], k, Cosine
  )

proc main() =
  initDb()
  applyMigrations()

  # Индексиране на документи
  indexDocument("Nim Programming", "Nim is a statically typed language...")
  indexDocument("PostgreSQL Guide", "PostgreSQL is an advanced database...")

  # Семантично търсене
  echo "Резултати за 'database programming':"
  for doc in searchDocuments("database programming"):
    echo "  - ", doc[1], " (distance: ", doc[4], ")"

  closeDb()

main()
```

### VectorField API Reference

| Функция | Описание |
|---------|----------|
| `newVectorField()` | Празен вектор |
| `newVectorField(n: int)` | Вектор с n нули |
| `newVectorField(data: seq[float32])` | От seq |
| `newVectorField(s: string)` | От PostgreSQL формат |
| `vf[i]` | Достъп до елемент |
| `vf.len` | Брой измерения |
| `vf.normalize()` | Unit vector |
| `dot(a, b)` | Dot product |
| `magnitude(vf)` | L2 норма |
| `cosineSimilarity(a, b)` | Cosine similarity |
| `euclideanDistance(a, b)` | Euclidean distance |

### Vector Search помощници

| Функция | Описание |
|---------|----------|
| `vectorDistance(col, vec, metric)` | Distance expression |
| `vectorDistanceWhere(col, vec, metric, max)` | WHERE с праг |
| `vectorKnn(col, vec, k, metric)` | ORDER BY + LIMIT |
| `vectorSearchQuery(...)` | Пълна search query |
| `createVectorIndex(...)` | CREATE INDEX SQL |
| `dropVectorIndex(...)` | DROP INDEX SQL |
| `searchSimilar(...)` | Изпълнява search |
| `searchSimilarWithData(...)` | Search с данни |

## Пълен пример

```nim
import orm/orm
import orm/migrations
import options
import db/config

type
  User* = object of Model
    name*: string
    email*: string

proc main() =
  # Инициализация - използвай connection pool
  let db = getDbConn()
  defer: releaseDbConn(db)

  # Създаване
  var user = User(name: "Мария", email: "maria@example.com")
  save(user, db)
  echo "Създаден потребител с id: ", user.id

  # Четене
  let found = find(User, user.id, db)
  if found.isSome:
    echo "Намерен: ", found.get().name

  # Обновяване
  user.name = "Мария Иванова"
  save(user, db)

  # Списък
  echo "Всички потребители:"
  for u in findAll(User, db):
    echo "  - ", u.id, ": ", u.name

  # Изтриване
  delete(user, db)

main()
```

## Структура на проекта

```
orm-baraba/
├── orm_baraba.nimble      # Nimble конфигурация v2.2.4
├── README.md              # Документация
├── audit-gemini.md        # Security audit отчет
├── main                   # Компилирано приложение
├── src/
│   ├── main.nim           # Входна точка / CLI
│   ├── cli.nim            # Interactive TUI интерфейс
│   └── orm/
│       ├── orm.nim        # ORM имплементация
│       ├── migrations.nim # Миграционна система
│       └── logger.nim     # Logging система
└── src/migrations/
    ├── V1__create_users_table.sql
    ├── V2__add_users_phone.sql
    ├── V3__add_users_metadata.sql
    ├── V4__enable_pgvector.sql
    ├── V5__create_documents_table.sql
    └── U*__*.sql           # Undo миграции
```

## Нови функции във v2.2.5

### 🆕 Нови типове данни (NEW!)
- **UuidModel** - UUID базирани модели за Phoenix/Ecto съвместимост
- **JsonField** - JSONB поддръжка с type-safe API
- **VectorField** - pgvector поддръжка за AI/ML similarity search
- **DistanceMetric** - Enum за векторни distance metrics (Cosine, L2, InnerProduct)

### 🆕 Schema Generation (NEW!)
- **Автоматична генерация на CREATE TABLE SQL** от Nim типове
- Compile-time type mapping (Nim → PostgreSQL)
- Proper pluralization (currency→currencies, company→companies)
- `createTable`, `ensureTable`, `dropTable`, `tableExists` helpers
- Поддръжка на всички основни типове + Option[T] за nullable

### ✅ Security Improvements
- Премахнати hardcoded пароли
- Параметризирани SQL заявки (защита от SQL Injection)
- Валидация на environment конфигурация

### 🚀 Enhanced Features
- Interactive TUI CLI с пълен контрол
- pgvector поддръжка за AI/ML приложения
- JSONB helpers и query генерация
- Production-ready logging система
- Comprehensive error handling
- **Thread-safe database операции** с explicit connection passing
- **Nim 2.2.x compatibility** - автоматично справяне със синтаксични промени

### 🛠️ Production Fixes
- Fixed SQL injection vulnerabilities
- Database connection error handling
- Transaction rollback при грешки
- Checksum validation за миграции
- Thread-safe database операции с explicit connection passing
- Nim 2.2.x compatibility fixes и build подобрения

### 🔧 Code Improvements
- **DRY принцип**: Елиминирано дублиране на код в ORM macros
- **Error handling**: Подобрено обработване на грешки с rollback
- **Connection management**: Поддръжка за explicit connection passing
- **Build stability**: Фиксирани build errors и compatibility проблеми

## API Reference

### orm.nim

Всички функции използват explicit database connection като последен параметър.

#### CRUD операции
| Функция | Описание |
|---------|----------|
| `save(obj, db)` | INSERT (ако id=0) или UPDATE (ако id>0) |
| `find(T, id, db)` | Намира по id, връща `Option[T]` |
| `findAll(T, db)` | Връща всички записи като `seq[T]` |
| `findWhere(T, db, where, args...)` | Търси с WHERE клауза |
| `delete(obj, db)` | Изтрива запис |
| `deleteById(T, id, db)` | Изтрива по id |
| `count(T, db)` | Връща брой записи |
| `exists(T, id, db)` | Проверява съществуване |

#### UUID CRUD операции
| Функция | Описание |
|---------|----------|
| `saveUuid(obj, db)` | INSERT/UPDATE за UUID модели |
| `findUuid(T, id, db)` | Намира UUID модел по string ID |
| `findAllUuid(T, db)` | Връща всички UUID модели |
| `findWhereUuid(T, db, where, args...)` | Търси UUID модели с WHERE |
| `deleteUuid(obj, db)` | Изтрива UUID модел |
| `deleteByUuid(T, id, db)` | Изтрива UUID модел по ID |

#### JsonField операции
| Функция | Описание |
|---------|----------|
| `newJsonField()` | Създава празен JsonField |
| `newJsonField(s: string)` | Създава от JSON string |
| `newJsonField(j: JsonNode)` | Създава от JsonNode |
| `jf[key]` | Достъп до JsonNode по ключ |
| `jf[key] = value` | Задава стойност |
| `jf.hasKey(key)` | Проверява за ключ |
| `jf.getStr(key, default)` | Връща string |
| `jf.getInt(key, default)` | Връща int |
| `jf.getFloat(key, default)` | Връща float |
| `jf.getBool(key, default)` | Връща bool |
| `jf.getArray(key)` | Връща seq[JsonNode] |

#### VectorField операции
| Функция | Описание |
|---------|----------|
| `newVectorField()` | Празен вектор |
| `newVectorField(n: int)` | Вектор с n нули |
| `newVectorField(data: seq[float32])` | От seq |
| `newVectorField(s: string)` | От PostgreSQL формат |
| `vf[i]` | Достъп до елемент |
| `vf.len` | Брой измерения |
| `vf.normalize()` | Unit vector |
| `dot(a, b)` | Dot product |
| `magnitude(vf)` | L2 норма |
| `cosineSimilarity(a, b)` | Cosine similarity |
| `euclideanDistance(a, b)` | Euclidean distance |

#### Vector Search операции
| Функция | Описание |
|---------|----------|
| `vectorDistance(col, vec, metric)` | Distance expression |
| `vectorDistanceWhere(col, vec, metric, max)` | WHERE с праг |
| `vectorKnn(col, vec, k, metric)` | ORDER BY + LIMIT |
| `vectorSearchQuery(...)` | Пълна search query |
| `createVectorIndex(...)` | CREATE INDEX SQL |
| `dropVectorIndex(...)` | DROP INDEX SQL |
| `searchSimilar(...)` | Изпълнява search |
| `searchSimilarWithData(...)` | Search с данни |
| `genUuid()` | Генерира UUID v4 |

#### Schema операции
| Функция | Описание |
|---------|----------|
| `createTableSql(T)` | Генерира CREATE TABLE SQL за тип T |
| `createTable(db, T)` | Създава таблица за тип T |
| `ensureTable(db, T)` | Създава таблица само ако не съществува |
| `dropTable(db, T)` | Изтрива таблица за тип T (CASCADE) |
| `tableExists(db, name)` | Проверява дали таблица съществува |

#### Raw SQL операции
| Функция | Описание |
|---------|----------|
| `rawQuery(db, sql, args...)` | Изпълнява SELECT заявка, връща `seq[Row]` |
| `rawExec(db, sql, args...)` | Изпълнява INSERT/UPDATE/DELETE без резултат |

#### Connection management (от db/config)
| Функция | Описание |
|---------|----------|
| `getDbConn()` | Взима връзка от pool-а |
| `releaseDbConn(db)` | Връща връзката в pool-а |

### migrations.nim

| Функция | Описание |
|---------|----------|
| `applyMigrations(dir)` | Прилага pending миграции |
| `rollbackMigration(version, dir)` | Rollback до версия |
| `migrationInfo(dir)` | Показва статус |
| `validateMigrations(dir)` | Валидира checksums |
| `repairMigrations(dir)` | Поправя checksums |
| `cleanMigrations()` | Изтрива history |
| `getAppliedMigrations()` | Връща приложени миграции |
| `createSchemaHistoryTable()` | Създава history таблица |

## Security & Production Usage

### Security Fixes (v2.2.4)

✅ **Critical Vulnerabilities Fixed:**
- SQL injection в JSON query helpers - параметризирани заявки
- Hardcoded passwords - премахнати, задължителни environment променливи
- Raw SQL injection в seed/demo функции - параметризирани

✅ **Production Best Practices:**
- Connection pooling готово (но не имплементирано)
- Error handling с rollback при transaction грешки
- Checksum validation за migration integrity
- Environment-based configuration

### Production Deployment

```bash
# 1. Setup environment
export DB_PASSWORD="<secure_password>"
export DB_HOST="your-db-host"
export DB_NAME="production_db"

# 2. Run migrations
./main migrate

# 3. Validate deployment
./main validate
./main info

# 4. Seed initial data (ако е нужно)
./main seed
```

### Monitoring & Maintenance

```bash
# Провери за migration drift
./main validate

# Interactive режим за日常 операции
./main interactive

# Verbose логове за debugging
VERBOSE=true ./main migrate
```

## Тестване

### Изисквания за тестване

- Docker (за pgvector контейнер)
- Nim >= 2.2.0

### Стартиране на pgvector контейнер

```bash
# Изтегли и стартирай pgvector контейнер
docker pull pgvector/pgvector:pg16
docker run -d --name pgvector-test \
  -e POSTGRES_PASSWORD="pas+123" \
  -e POSTGRES_DB=ormb2b \
  -p 5433:5432 \
  pgvector/pgvector:pg16

# Изчакай няколко секунди за стартиране
sleep 3
```

### Стартиране на тестовете

```bash
# Компилирай и стартирай ORM тестовете
DB_HOST=localhost DB_PORT=5433 DB_USER=postgres \
  DB_PASSWORD="pas+123" DB_NAME=ormb2b \
  nim c -r test_orm_dsl.nim
```

### Тестови сценарии

Тестовете покриват:

| Тест | Описание |
|------|----------|
| **Миграции** | Прилагане на V1-V5 миграции |
| **Save (INSERT)** | Създаване на нов запис |
| **Save (UPDATE)** | Обновяване на съществуващ запис |
| **Find** | Търсене по ID |
| **FindAll** | Извличане на всички записи |
| **Count** | Броене на записи |
| **Exists** | Проверка за съществуване |
| **Delete** | Изтриване на запис |
| **Rollback** | Връщане на миграция назад |
| **pgvector** | Създаване на vector(1536) колона |

### Примерен тестов изход

```
=== Comprehensive ORM DSL Test ===
[SUCCESS] Successfully connected to PostgreSQL database: ormb2b

=== DATABASE MIGRATIONS ===
[INFO] Found 5 pending migration(s)
[SUCCESS] ✓ V1 applied (0ms)
[SUCCESS] ✓ V2 applied (0ms)
[SUCCESS] ✓ V3 applied (0ms)
[SUCCESS] ✓ V4 applied (0ms)
[SUCCESS] ✓ V5 applied (0ms)
[SUCCESS] Successfully applied 5 migration(s)

=== Testing Save Functionality ===
Before save - ID: 0
Inserted User with id: 1
After save - ID: 1
Updated User with id: 1
After update - ID: 1

=== Testing Find Functionality ===
Found user: Jane Wilson <jane.wilson...@example.com> Phone: 098-765-4321
Total users found: 1

=== Testing Count Functionality ===
Total user count: 1

=== Testing Exists Functionality ===
User 1 exists: true
User 999 exists: false

=== DSL Test Completed Successfully! ===
```

### Спиране на тестовия контейнер

```bash
docker stop pgvector-test
docker rm pgvector-test
```

## Лиценз

MIT License

---

## 🎯 Production Status

✅ **Ready for Production** - ORM Baraba v2.2.4 е production-ready със:

- Enterprise-grade migration система (Flyway-съвместима)
- Full CRUD операции с ORM
- Vector search поддръжка (pgvector)
- JSONB helper функции
- Security fixes от independent audit
- Interactive CLI за лесна работа
- Comprehensive logging

**Виж `audit-gemini.md` за пълен security audit отчет.**
