# src/orm/orm.nim
# Professional ORM for PostgreSQL in Nim with JSON and pgvector support

import "../../../lowdb_baraba/lowdb/postgres"
import strutils
import macros
import options
import sequtils
import json
import tables
import math
import times
import logger as l
import os
import std/re
import std/random

# PostgreSQL timestamp parser - handles format like "2025-12-17 22:31:57.18652+02"
proc parsePgTimestamp*(s: string): DateTime =
  ## Parse PostgreSQL TIMESTAMP WITH TIME ZONE format manually
  ## Handles: "2025-12-17 22:31:57.123456+02" or "2025-12-17 22:31:57+02:00"
  if s.len == 0 or s == "null" or s == "NULL":
    return now()

  try:
    # Parse date part: YYYY-MM-DD
    let year = parseInt(s[0..3])
    let month = parseInt(s[5..6])
    let day = parseInt(s[8..9])

    # Find time start (after space or T)
    var timeStart = 11
    if s.len > 10 and s[10] == 'T':
      timeStart = 11
    elif s.len > 10 and s[10] == ' ':
      timeStart = 11

    # Parse time part: HH:MM:SS
    var hour = 0
    var minute = 0
    var second = 0

    if s.len >= timeStart + 8:
      hour = parseInt(s[timeStart..timeStart+1])
      minute = parseInt(s[timeStart+3..timeStart+4])
      second = parseInt(s[timeStart+6..timeStart+7])

    # Create DateTime (ignoring timezone for now - using local time)
    result = dateTime(year, Month(month), day, hour, minute, second)
  except:
    # If all parsing fails, return current time
    result = now()

# PostgreSQL boolean parser - handles 't'/'f' format
proc parsePgBool*(s: string): bool =
  ## Parse PostgreSQL boolean values: 't', 'f', 'true', 'false', '1', '0'
  case s.toLowerAscii()
  of "t", "true", "1", "yes": true
  of "f", "false", "0", "no", "": false
  else: false

# Get raw string from DbValue (without SQL quoting)
proc getRawString*(v: DbValue): string =
  ## Extract the raw string value from a DbValue without SQL quoting
  case v.kind
  of dvkString: v.s
  of dvkOther: v.o.value
  of dvkNull: ""
  else: $v

type
  Model* = object of RootObj
    id*: int

  # UUID-based model for Phoenix/Ecto compatibility
  UuidModel* = object of RootObj
    id*: string  # UUID as string

  # JSON field wrapper for JSONB columns
  JsonField* = object
    data*: JsonNode

  # Vector field wrapper for pgvector columns
  VectorField* = object
    data*: seq[float32]
    dimensions*: int

  # Distance metric types for vector search
  DistanceMetric* = enum
    Cosine      # <=> operator - cosine distance
    L2          # <-> operator - Euclidean distance
    InnerProduct # <#> operator - negative inner product


# ============================================================================
# VectorField - pgvector support
# ============================================================================

proc newVectorField*(): VectorField =
  result.data = @[]
  result.dimensions = 0

proc newVectorField*(dimensions: int): VectorField =
  result.data = newSeq[float32](dimensions)
  result.dimensions = dimensions

proc newVectorField*(data: seq[float32]): VectorField =
  result.data = data
  result.dimensions = data.len

proc newVectorField*(data: seq[float]): VectorField =
  result.data = data.mapIt(it.float32)
  result.dimensions = data.len

proc newVectorField*(s: string): VectorField =
  ## Parse PostgreSQL vector format: [1.0,2.0,3.0]
  if s == "" or s == "null" or s == "NULL":
    return newVectorField()
  var cleaned = s.strip()
  if cleaned.startsWith("["):
    cleaned = cleaned[1..^1]
  if cleaned.endsWith("]"):
    cleaned = cleaned[0..^2]
  if cleaned == "":
    return newVectorField()
  let parts = cleaned.split(",")
  result.data = parts.mapIt(it.strip().parseFloat().float32)
  result.dimensions = result.data.len

proc `$`*(vf: VectorField): string =
  ## Convert to PostgreSQL vector format: [1.0,2.0,3.0]
  if vf.data.len == 0:
    return "[]"
  result = "[" & vf.data.mapIt($it).join(",") & "]"

proc toSql*(vf: VectorField): string =
  ## Convert to SQL-safe vector literal
  $vf

proc dbValue*(vf: VectorField): DbValue =
  dbValue($vf)

proc dbValue*[T](v: seq[T]): DbValue =
  dbValue($(%v))

proc `[]`*(vf: VectorField, idx: int): float32 =
  vf.data[idx]

proc `[]=`*(vf: var VectorField, idx: int, val: float32) =
  vf.data[idx] = val

proc len*(vf: VectorField): int =
  vf.data.len

proc normalize*(vf: VectorField): VectorField =
  ## Normalize vector to unit length (for cosine similarity)
  var magnitude = 0.0
  for v in vf.data:
    magnitude += v * v
  magnitude = sqrt(magnitude)
  if magnitude == 0:
    return vf
  result.data = vf.data.mapIt(it / magnitude.float32)
  result.dimensions = vf.dimensions

proc dot*(a, b: VectorField): float =
  ## Dot product of two vectors
  assert a.len == b.len, "Vectors must have same dimensions"
  result = 0.0
  for i in 0..<a.len:
    result += a.data[i].float * b.data[i].float

proc magnitude*(vf: VectorField): float =
  ## Calculate vector magnitude (L2 norm)
  result = 0.0
  for v in vf.data:
    result += v * v
  result = sqrt(result)

proc cosineSimilarity*(a, b: VectorField): float =
  ## Calculate cosine similarity (1 = identical, 0 = orthogonal, -1 = opposite)
  let dotProd = dot(a, b)
  let magA = magnitude(a)
  let magB = magnitude(b)
  if magA == 0 or magB == 0:
    return 0.0
  return dotProd / (magA * magB)

proc euclideanDistance*(a, b: VectorField): float =
  ## Calculate Euclidean (L2) distance
  assert a.len == b.len, "Vectors must have same dimensions"
  result = 0.0
  for i in 0..<a.len:
    let diff = a.data[i].float - b.data[i].float
    result += diff * diff
  result = sqrt(result)

# pgvector SQL query helpers
proc vectorDistance*(column: string, vector: VectorField, metric: DistanceMetric): string =
  ## Generate distance expression for ORDER BY
  let vecStr = $vector
  case metric:
  of Cosine:
    result = column & " <=> '" & vecStr & "'"
  of L2:
    result = column & " <-> '" & vecStr & "'"
  of InnerProduct:
    result = column & " <#> '" & vecStr & "'"

proc vectorDistanceWhere*(column: string, vector: VectorField, metric: DistanceMetric, maxDistance: float): string =
  ## Generate WHERE clause for distance threshold
  let vecStr = $vector
  let op = case metric:
    of Cosine: "<=>"
    of L2: "<->"
    of InnerProduct: "<#>"
  result = column & " " & op & " '" & vecStr & "' < " & $maxDistance

proc vectorKnn*(column: string, vector: VectorField, k: int, metric: DistanceMetric = L2): string =
  ## Generate ORDER BY + LIMIT for K-nearest neighbors
  result = "ORDER BY " & vectorDistance(column, vector, metric) & " LIMIT " & $k

proc vectorSearchQuery*(tableName: string, vectorColumn: string, vector: VectorField,
                        k: int = 10, metric: DistanceMetric = L2,
                        selectColumns: seq[string] = @["*"],
                        whereClause: string = ""): string =
  ## Generate complete vector similarity search query
  let cols = selectColumns.join(", ")
  let distExpr = vectorDistance(vectorColumn, vector, metric)
  result = "SELECT " & cols & ", " & distExpr & " AS distance FROM " & tableName
  if whereClause != "":
    result &= " WHERE " & whereClause
  result &= " ORDER BY " & distExpr & " LIMIT " & $k

# Vector index helpers
proc createVectorIndex*(tableName: string, column: string, indexType: string = "ivfflat",
                        lists: int = 100, metric: DistanceMetric = L2): string =
  ## Generate CREATE INDEX statement for vector column
  let opClass = case metric:
    of L2: "vector_l2_ops"
    of Cosine: "vector_cosine_ops"
    of InnerProduct: "vector_ip_ops"

  let indexName = "idx_" & tableName & "_" & column & "_" & $metric

  case indexType:
  of "ivfflat":
    result = "CREATE INDEX " & indexName & " ON " & tableName &
             " USING ivfflat (" & column & " " & opClass & ") WITH (lists = " & $lists & ")"
  of "hnsw":
    result = "CREATE INDEX " & indexName & " ON " & tableName &
             " USING hnsw (" & column & " " & opClass & ")"
  else:
    result = "CREATE INDEX " & indexName & " ON " & tableName &
             " USING " & indexType & " (" & column & " " & opClass & ")"

proc dropVectorIndex*(tableName: string, column: string, metric: DistanceMetric = L2): string =
  let indexName = "idx_" & tableName & "_" & column & "_" & $metric
  result = "DROP INDEX IF EXISTS " & indexName

# High-level vector search function
proc searchSimilar*(db: DbConn, tableName: string, vectorColumn: string, queryVector: VectorField,
                    k: int = 10, metric: DistanceMetric = L2,
                    whereClause: string = ""): seq[tuple[id: int, distance: float]] =
  ## Execute similarity search and return (id, distance) pairs
  let query = vectorSearchQuery(tableName, vectorColumn, queryVector, k, metric, @["id"], whereClause)
  result = @[]
  try:
    for row in rows(db, sql(query)):
      if len($row[0]) > 0:
        result.add((id: parseInt($row[0]), distance: parseFloat($row[1])))
  except Exception as e:
    echo "Vector search failed: ", e.msg

proc searchSimilarWithData*(db: DbConn, tableName: string, vectorColumn: string, queryVector: VectorField,
                            selectColumns: seq[string], k: int = 10,
                            metric: DistanceMetric = L2): seq[Row] =
  ## Execute similarity search and return full rows
  let query = vectorSearchQuery(tableName, vectorColumn, queryVector, k, metric, selectColumns)
  result = @[]
  try:
    for row in rows(db, sql(query)):
      result.add(row)
  except Exception as e:
    echo "Vector search failed: ", e.msg

# JSON field constructors and helpers
proc newJsonField*(): JsonField =
  result.data = newJObject()

proc newJsonField*(j: JsonNode): JsonField =
  result.data = j

proc newJsonField*(s: string): JsonField =
  if s == "" or s == "null" or s == "NULL":
    result.data = newJObject()
  else:
    result.data = parseJson(s)

proc `$`*(jf: JsonField): string =
  if jf.data.isNil:
    return "{}"
  return $jf.data

proc `%`*(jf: JsonField): JsonNode =
  if jf.data.isNil:
    return newJObject()
  return jf.data

proc dbValue*(jf: JsonField): DbValue =
  dbValue($jf)

# JSON field access helpers
proc `[]`*(jf: JsonField, key: string): JsonNode =
  if jf.data.isNil:
    return newJNull()
  return jf.data{key}

proc `[]=`*(jf: var JsonField, key: string, val: JsonNode) =
  if jf.data.isNil:
    jf.data = newJObject()
  jf.data[key] = val

proc `[]=`*(jf: var JsonField, key: string, val: string) =
  jf[key] = newJString(val)

proc `[]=`*(jf: var JsonField, key: string, val: int) =
  jf[key] = newJInt(val)

proc `[]=`*(jf: var JsonField, key: string, val: float) =
  jf[key] = newJFloat(val)

proc `[]=`*(jf: var JsonField, key: string, val: bool) =
  jf[key] = newJBool(val)

proc hasKey*(jf: JsonField, key: string): bool =
  if jf.data.isNil:
    return false
  return jf.data.hasKey(key)

proc getStr*(jf: JsonField, key: string, default: string = ""): string =
  if jf.data.isNil or not jf.data.hasKey(key):
    return default
  let node = jf.data{key}
  if node.isNil or node.kind != JString:
    return default
  return node.getStr()

proc getInt*(jf: JsonField, key: string, default: int = 0): int =
  if jf.data.isNil or not jf.data.hasKey(key):
    return default
  let node = jf.data{key}
  if node.isNil or node.kind != JInt:
    return default
  return node.getInt()

proc getFloat*(jf: JsonField, key: string, default: float = 0.0): float =
  if jf.data.isNil or not jf.data.hasKey(key):
    return default
  let node = jf.data{key}
  if node.isNil or node.kind != JFloat:
    return default
  return node.getFloat()

proc getBool*(jf: JsonField, key: string, default: bool = false): bool =
  if jf.data.isNil or not jf.data.hasKey(key):
    return default
  let node = jf.data{key}
  if node.isNil or node.kind != JBool:
    return default
  return node.getBool()

proc getArray*(jf: JsonField, key: string): seq[JsonNode] =
  if jf.data.isNil or not jf.data.hasKey(key):
    return @[]
  let node = jf.data{key}
  if node.isNil or node.kind != JArray:
    return @[]
  return node.getElems()

proc toJsonField*(t: Table[string, string]): JsonField =
  result = newJsonField()
  for k, v in t:
    result[k] = v

proc initDb*(): DbConn =
  let
    dbHost = getEnv("DB_HOST", "localhost")
    dbPort = getEnv("DB_PORT", "5432")
    dbUser = getEnv("DB_USER", "postgres")
    dbPass = getEnv("DB_PASSWORD")
    dbName = getEnv("DB_NAME", "orm-baraba")
    # Include port in connection string
    connStr = if dbPort == "5432": dbHost else: dbHost & ":" & dbPort

  if dbPass.len == 0:
    l.error("FATAL: DB_PASSWORD environment variable is not set.")
    quit(1)

  try:
    result = open(connStr, dbUser, dbPass, dbName)
    l.success("Successfully connected to PostgreSQL database: " & dbName)
    l.debug("Connection: postgresql://$1:@$2:$3/$4" % [dbUser, dbHost, dbPort, dbName])
  except Exception as e:
    l.error("Failed to connect to PostgreSQL: " & e.msg)
    l.error("Connection string: postgresql://$1:@$2:$3/$4" % [dbUser, dbHost, dbPort, dbName])
    quit(1)

proc closeDb*(db: DbConn) =
  if db != nil:
    try:
      close(db)
      l.info("Disconnected from PostgreSQL.")
    except Exception as e:
      l.error("Error closing database connection: " & e.msg)
  else:
    l.warn("Database connection was already null.")

# =============================================================================
# Type Mapping: Nim -> PostgreSQL
# =============================================================================

proc nimTypeToPostgres*(nimType: string): string =
  ## Maps Nim types to PostgreSQL column types
  case nimType
  of "string":
    "TEXT"
  of "int":
    "INTEGER"
  of "int32":
    "INTEGER"
  of "int64":
    "BIGINT"
  of "float", "float64":
    "DOUBLE PRECISION"
  of "float32":
    "REAL"
  of "bool":
    "BOOLEAN"
  of "DateTime":
    "TIMESTAMP WITH TIME ZONE"
  of "JsonField":
    "JSONB"
  of "VectorField":
    "vector(1536)"  # Default OpenAI embedding size
  else:
    if nimType.startsWith("Option["):
      # Extract inner type and make it nullable
      let innerType = nimType[7..^2]
      nimTypeToPostgres(innerType)
    elif nimType.startsWith("seq["):
      "JSONB"  # Store arrays as JSONB
    else:
      "TEXT"  # Fallback

proc isNullableType*(nimType: string): bool =
  ## Check if a Nim type maps to a nullable PostgreSQL column
  nimType.startsWith("Option[")

# =============================================================================
# Schema Generation Macros
# =============================================================================

macro getFieldTypes*(T: typedesc): untyped =
  ## Returns seq of (fieldName, fieldType) tuples for a model
  let typeImpl = T.getTypeInst()[1].getImpl()
  let recList = typeImpl[2][2]  # TypeDef -> ObjectTy -> RecList

  result = newNimNode(nnkBracket)

  for fieldDef in recList:
    let nameNode = fieldDef[0]
    let fieldName = if nameNode.kind == nnkPostfix:
      nameNode[1]
    else:
      nameNode
    let fieldType = fieldDef[1]

    let fieldTuple = newNimNode(nnkTupleConstr)
    fieldTuple.add(newStrLitNode($fieldName))
    fieldTuple.add(newStrLitNode(fieldType.repr))
    result.add(fieldTuple)

  result = quote do:
    @`result`

proc toSnakeCaseCompile(s: string): string {.compileTime.} =
  ## Compile-time version of toSnakeCase
  result = ""
  for i, c in s:
    if c.isUpperAscii():
      if i > 0:
        result.add('_')
      result.add(c.toLowerAscii())
    else:
      result.add(c)

proc nimTypeToPostgresCompile(nimType: string): string {.compileTime.} =
  ## Compile-time version of type mapping
  if nimType == "string": return "TEXT"
  if nimType == "int": return "INTEGER"
  if nimType == "int32": return "INTEGER"
  if nimType == "int64": return "BIGINT"
  if nimType == "float" or nimType == "float64": return "DOUBLE PRECISION"
  if nimType == "float32": return "REAL"
  if nimType == "bool": return "BOOLEAN"
  if nimType == "DateTime": return "TIMESTAMP WITH TIME ZONE"
  if nimType == "JsonField": return "JSONB"
  if nimType == "VectorField": return "vector(1536)"
  if nimType.len > 7 and nimType[0..6] == "Option[":
    let innerType = nimType[7..^2]
    return nimTypeToPostgresCompile(innerType)
  if nimType.len > 4 and nimType[0..3] == "seq[":
    return "JSONB"
  return "TEXT"

proc isNullableTypeCompile(nimType: string): bool {.compileTime.} =
  nimType.len > 7 and nimType[0..6] == "Option["

macro createTableSql*(T: typedesc): string =
  ## Generates CREATE TABLE SQL for a model type
  let typeInst = T.getTypeInst()[1]
  let typeName = $typeInst
  let typeImpl = typeInst.getImpl()
  let recList = typeImpl[2][2]

  var columns = newSeq[string]()
  columns.add("id SERIAL PRIMARY KEY")

  for fieldDef in recList:
    let nameNode = fieldDef[0]
    let fieldName = if nameNode.kind == nnkPostfix:
      $nameNode[1]
    else:
      $nameNode

    if fieldName == "id":
      continue

    let fieldType = fieldDef[1].repr
    let snakeName = toSnakeCaseCompile(fieldName)
    let pgType = nimTypeToPostgresCompile(fieldType)
    let nullable = if isNullableTypeCompile(fieldType): "" else: " NOT NULL"

    # Handle default values for common types
    var default = ""
    if fieldType == "DateTime": default = " DEFAULT CURRENT_TIMESTAMP"
    elif fieldType == "bool": default = " DEFAULT false"
    elif fieldType == "JsonField": default = " DEFAULT '{}'"

    columns.add(snakeName & " " & pgType & nullable & default)

  let tableName = toSnakeCaseCompile(typeName)
  # Proper pluralization at compile time
  let tableNamePlural =
    if tableName.endsWith("y") and tableName.len > 1 and tableName[^2] notin {'a', 'e', 'i', 'o', 'u'}:
      tableName[0..^2] & "ies"
    elif tableName.endsWith("s") or tableName.endsWith("x") or tableName.endsWith("ch") or tableName.endsWith("sh"):
      tableName & "es"
    elif not tableName.endsWith("s"):
      tableName & "s"
    else:
      tableName

  result = newStrLitNode("CREATE TABLE IF NOT EXISTS " & tableNamePlural & " (\n  " & columns.join(",\n  ") & "\n)")

proc createTable*[T: Model](db: DbConn, _: typedesc[T]) =
  ## Creates a table for the given model type
  let createSql = createTableSql(T)
  try:
    exec(db, sql(createSql))
    l.success("Created table for " & $T)
  except Exception as e:
    # Table might already exist or other issue
    l.warn("Could not create table for " & $T & ": " & e.msg)

proc tableExists*(db: DbConn, tableName: string): bool =
  ## Check if a table exists in the database
  let query = """
    SELECT EXISTS (
      SELECT FROM information_schema.tables
      WHERE table_schema = 'public'
      AND table_name = $1
    )
  """
  try:
    let rowOpt = getRow(db, sql(query), [dbValue(tableName)])
    if rowOpt.isSome:
      let row = rowOpt.get()
      return $row[0] == "t" or $row[0] == "true"
  except:
    discard
  return false

# Helper to convert camelCase to snake_case for table/column names
proc toSnakeCase*(s: string): string =
  result = ""
  for i, c in s:
    if c.isUpperAscii():
      if i > 0:
        result.add('_')
      result.add(c.toLowerAscii())
    else:
      result.add(c)

# Helper to get table name from type name (with proper pluralization)
proc getTableName*(typeName: string): string =
  result = toSnakeCase(typeName)
  if result.endsWith("y") and result.len > 1 and result[^2] notin {'a', 'e', 'i', 'o', 'u'}:
    # currency -> currencies, company -> companies
    result = result[0..^2] & "ies"
  elif result.endsWith("s") or result.endsWith("x") or result.endsWith("ch") or result.endsWith("sh"):
    result.add("es")
  elif not result.endsWith("s"):
    result.add('s')

proc dropTable*[T: Model](db: DbConn, _: typedesc[T]) =
  ## Drops the table for the given model type (DANGEROUS!)
  let typeName = $T
  let tableName = getTableName(typeName)
  try:
    exec(db, sql("DROP TABLE IF EXISTS " & tableName & " CASCADE"))
    l.warn("Dropped table: " & tableName)
  except Exception as e:
    l.error("Could not drop table " & tableName & ": " & e.msg)

proc ensureTable*[T: Model](db: DbConn, _: typedesc[T]) =
  ## Creates the table if it doesn't exist (safe for production)
  let typeName = $T
  let tableName = getTableName(typeName)
  if not tableExists(db, tableName):
    createTable(db, T)
  else:
    l.debug("Table already exists: " & tableName)

# Macro to generate field information at compile time
macro getFieldNames*(T: typedesc): untyped =
  result = quote do:
    var fieldNames: seq[string]
    for name, _ in fieldPairs(default(`T`)):
      if name != "id":
        fieldNames.add(name)
    fieldNames

# Generic save procedure - INSERT or UPDATE based on id
# Builds dbValues directly from field values to preserve types (bool, int, etc.)
macro save*(obj: typed, db: DbConn): untyped =
  let objType = obj.getTypeInst()
  let typeName = $objType

  result = quote do:
    let tableName = getTableName(`typeName`)
    let fieldNames = getFieldNames(type(`obj`))

    # Build dbValues directly from object fields to preserve types
    var dbValues: seq[DbValue]
    for name, val in fieldPairs(`obj`):
      if name != "id":
        dbValues.add(dbValue(val))

    if `obj`.id == 0:
      # INSERT - exclude id field (auto-generated)
      let columns = fieldNames.map(toSnakeCase).join(", ")
      let placeholders = toSeq(1..fieldNames.len).map(proc (i: int): string = "$" & $i).join(", ")
      let insertQuery = "INSERT INTO " & tableName & " (" & columns & ") VALUES (" & placeholders & ") RETURNING id"

      try:
        let rowOpt = getRow(db, sql(insertQuery), dbValues)

        if rowOpt.isSome:
          let row = rowOpt.get()
          if len($row[0]) > 0:
            `obj`.id = parseInt($row[0])
            echo "Inserted ", `typeName`, " with id: ", `obj`.id
      except Exception as e:
        echo "Failed to save ", `typeName`, ": ", e.msg
        raise e
    else:
      # UPDATE - update all fields except id
      var setClauses: seq[string]
      for i, name in fieldNames:
        setClauses.add(toSnakeCase(name) & " = $" & $(i + 1))
      let updateQuery = "UPDATE " & tableName & " SET " & setClauses.join(", ") & " WHERE id = $" & $(fieldNames.len + 1)

      try:
        dbValues.add(dbValue(`obj`.id))
        exec(db, sql(updateQuery), dbValues)
        echo "Updated ", `typeName`, " with id: ", `obj`.id
      except Exception as e:
        echo "Failed to update ", `typeName`, " with id: ", `obj`.id, " ", e.msg
        raise e

# Helper to extract field name from IdentDefs (handles exported fields like name*)
proc getFieldNameFromDef(fieldDef: NimNode): NimNode =
  let nameNode = fieldDef[0]
  if nameNode.kind == nnkPostfix:
    result = nameNode[1]  # name* -> name
  else:
    result = nameNode

# Helper macro to generate object population code from a DB row
macro populateObject(T: typedesc, obj: var typed, row: typed): untyped =
  let typeImpl = T.getTypeInst()[1].getImpl()
  let recList = typeImpl[2][2]  # TypeDef -> ObjectTy -> RecList

  result = newNimNode(nnkStmtList)
  var index = 1 # Start from index 1, as index 0 is the 'id' field

  for fieldDef in recList:
    let fieldName = getFieldNameFromDef(fieldDef)
    let fieldType = fieldDef[1]
    let rowValue = newNimNode(nnkBracketExpr).add(row, newLit(index))
    inc index

    let assignment = newNimNode(nnkAsgn)
    assignment.add(newNimNode(nnkDotExpr).add(obj, fieldName))

    let fieldTypeStr = fieldType.repr
    let parser = if fieldTypeStr == "string" or fieldTypeStr == "EmailAddress" or fieldTypeStr == "Encrypted":
        quote do: getRawString(`rowValue`)
      elif fieldTypeStr == "int":
        quote do: parseInt($`rowValue`)
      elif fieldTypeStr == "int64":
        quote do: parseBiggestInt($`rowValue`)
      elif fieldTypeStr == "float" or fieldTypeStr == "float32":
        quote do: parseFloat($`rowValue`)
      elif fieldTypeStr == "bool":
        quote do: parsePgBool($`rowValue`)
      elif fieldTypeStr == "DateTime":
        quote do: parsePgTimestamp($`rowValue`)
      elif fieldTypeStr.startsWith("Option["):
        # Handle Option types - check if value is empty or NULL
        let innerType = fieldTypeStr[7..^2]  # Extract inner type from "Option[X]"
        if innerType == "DateTime":
          quote do:
            if $`rowValue` == "" or $`rowValue` == "null" or $`rowValue` == "NULL":
              none(DateTime)
            else:
              some(parsePgTimestamp($`rowValue`))
        elif innerType == "int64":
          quote do:
            if $`rowValue` == "" or $`rowValue` == "null" or $`rowValue` == "NULL":
              none(int64)
            else:
              some(parseBiggestInt($`rowValue`))
        elif innerType == "int":
          quote do:
            if $`rowValue` == "" or $`rowValue` == "null" or $`rowValue` == "NULL":
              none(int)
            else:
              some(parseInt($`rowValue`))
        elif innerType == "float" or innerType == "float64":
          quote do:
            if $`rowValue` == "" or $`rowValue` == "null" or $`rowValue` == "NULL":
              none(float)
            else:
              some(parseFloat($`rowValue`))
        elif innerType == "bool":
          quote do:
            if $`rowValue` == "" or $`rowValue` == "null" or $`rowValue` == "NULL":
              none(bool)
            else:
              some(parsePgBool($`rowValue`))
        elif innerType == "string":
          quote do:
            if $`rowValue` == "" or $`rowValue` == "null" or $`rowValue` == "NULL":
              none(string)
            else:
              some(getRawString(`rowValue`))
        else:
          quote do:
            if $`rowValue` == "" or $`rowValue` == "null" or $`rowValue` == "NULL":
              none(typeof(`obj`.`fieldName`).T)
            else:
              some($`rowValue`)
      elif fieldTypeStr == "JsonField":
        quote do: newJsonField($`rowValue`)
      elif fieldTypeStr == "VectorField":
        quote do: newVectorField($`rowValue`)
      elif fieldTypeStr.startsWith("seq["):
        quote do:
          if $`rowValue` == "" or $`rowValue` == "null" or $`rowValue` == "NULL":
            newSeq[typeof(`obj`.`fieldName`[0])](0)
          else:
            parseJson($`rowValue`).to(typeof(`obj`.`fieldName`))
      else:
        quote do: $`rowValue`

    assignment.add(parser)
    result.add(assignment)

# Generic find by id
macro find*(T: typedesc, id: int, db: DbConn): untyped =
  let typeName = $T.getTypeInst()[1]
  result = quote do:
    let tableName = getTableName(`typeName`)
    var fieldNames = getFieldNames(`T`)
    fieldNames.insert("id", 0)

    let columns = fieldNames.map(toSnakeCase).join(", ")
    let selectQuery = "SELECT " & columns & " FROM " & tableName & " WHERE id = $1"

    var resultObj: Option[`T`]

    try:
      let rowOpt = getRow(db, sql(selectQuery), [dbValue(`id`)])
      if rowOpt.isSome:
        let row = rowOpt.get()
        if len($row[0]) > 0:
          var obj: `T`
          obj.id = parseInt($row[0])

          populateObject(`T`, obj, row)

          resultObj = some(obj)
        else:
          resultObj = none(`T`)
      else:
        resultObj = none(`T`)
    except Exception as e:
      echo "Failed to find ", `typeName`, ": ", e.msg
      resultObj = none(`T`)

    resultObj

# Find all records of a type
macro findAll*(T: typedesc, db: DbConn): untyped =
  let typeName = $T.getTypeInst()[1]
  result = quote do:
    let tableName = getTableName(`typeName`)
    var fieldNames = getFieldNames(`T`)
    fieldNames.insert("id", 0)

    let columns = fieldNames.map(toSnakeCase).join(", ")
    let selectQuery = "SELECT " & columns & " FROM " & tableName

    var results: seq[`T`]

    try:
      for row in rows(db, sql(selectQuery)):
        if len($row[0]) > 0:
          var obj: `T`
          obj.id = parseInt($row[0])

          populateObject(`T`, obj, row)

          results.add(obj)
    except Exception as e:
      echo "Failed to find all ", `typeName`, ": ", e.msg

    results

# Find with custom WHERE clause
macro findWhere*(T: typedesc, db: DbConn, whereClause: string, args: varargs[string]): untyped =
  let typeName = $T.getTypeInst()[1]

  # Build array of args at macro level
  var argsArray = newNimNode(nnkBracket)
  for i in 0..<args.len:
    argsArray.add(args[i])

  result = quote do:
    let tableName = getTableName(`typeName`)
    var fieldNames = getFieldNames(`T`)
    fieldNames.insert("id", 0)

    let columns = fieldNames.map(toSnakeCase).join(", ")
    let selectQuery = "SELECT " & columns & " FROM " & tableName & " WHERE " & `whereClause`

    var results: seq[`T`]
    let argsSeq: seq[string] = @`argsArray`
    var dbArgs: seq[DbValue] = @[]
    for a in argsSeq:
      dbArgs.add(dbValue(a))

    try:
      for row in rows(`db`, sql(selectQuery), dbArgs):
        if len($row[0]) > 0:
          var obj: `T`
          obj.id = parseInt($row[0])

          populateObject(`T`, obj, row)

          results.add(obj)
    except Exception as e:
      echo "Failed to find ", `typeName`, " with condition: ", e.msg

    results

# Delete by id
macro delete*(obj: typed, db: DbConn): untyped =
  let objType = obj.getTypeInst()
  let typeName = $objType

  result = quote do:
    if `obj`.id == 0:
      echo "Cannot delete ", `typeName`, " without id"
    else:
      let tableName = getTableName(`typeName`)
      let deleteQuery = "DELETE FROM " & tableName & " WHERE id = $1"

      try:
        exec(db, sql(deleteQuery), [dbValue(`obj`.id)])
        echo "Deleted ", `typeName`, " with id: ", `obj`.id
        `obj`.id = 0
      except Exception as e:
        echo "Failed to delete ", `typeName`, ": ", e.msg
        raise e

# Delete by id directly
macro deleteById*(T: typedesc, id: int, db: DbConn): untyped =
  let typeName = $T.getTypeInst()[1]

  result = quote do:
    let tableName = getTableName(`typeName`)
    let deleteQuery = "DELETE FROM " & tableName & " WHERE id = $1"

    try:
      exec(db, sql(deleteQuery), [dbValue(`id`)])
      echo "Deleted ", `typeName`, " with id: ", `id`
    except Exception as e:
      echo "Failed to delete ", `typeName`, ": ", e.msg
      raise e

# Count records
macro count*(T: typedesc, db: DbConn): untyped =
  let typeName = $T.getTypeInst()[1]

  result = quote do:
    let tableName = getTableName(`typeName`)
    let countQuery = "SELECT COUNT(*) FROM " & tableName

    var cnt = 0
    try:
      let rowOpt = getRow(db, sql(countQuery), [])
      if rowOpt.isSome:
        let row = rowOpt.get()
        if len($row[0]) > 0:
          cnt = parseInt($row[0])
    except Exception as e:
      echo "Failed to count ", `typeName`, ": ", e.msg

    cnt

# Check if record exists
macro exists*(T: typedesc, id: int, db: DbConn): untyped =
  let typeName = $T.getTypeInst()[1]

  result = quote do:
    let tableName = getTableName(`typeName`)
    let existsQuery = "SELECT 1 FROM " & tableName & " WHERE id = $1 LIMIT 1"

    var found = false
    try:
      let rowOpt = getRow(db, sql(existsQuery), [dbValue(`id`)])
      if rowOpt.isSome:
        let row = rowOpt.get()
        found = len($row[0]) > 0
    except Exception as e:
      echo "Failed to check existence of ", `typeName`, ": ", e.msg

    found

# Transaction support
proc beginTransaction*(db: DbConn) =
  exec(db, sql"BEGIN")

proc commitTransaction*(db: DbConn) =
  exec(db, sql"COMMIT")

proc rollbackTransaction*(db: DbConn) =
  exec(db, sql"ROLLBACK")

template withTransaction*(db: DbConn, body: untyped) =
  beginTransaction(db)
  try:
    body
    commitTransaction(db)
  except:
    rollbackTransaction(db)
    raise

# JSON Query helpers for PostgreSQL JSONB
proc jsonQuery*(jsonColumn: string, path: string): string =
  ## Generates a parameterized WHERE clause for a JSONB text query.
  ## Use with findWhere: findWhere(User, jsonQuery("metadata", "city"), "New York")
  result = jsonColumn & "->>'" & path & "' = $1"

proc jsonQueryInt*(jsonColumn: string, path: string): string =
  ## Generates a parameterized WHERE clause for a JSONB integer query.
  ## Use with findWhere: findWhere(User, jsonQueryInt("metadata", "age"), "30")
  result = "(" & jsonColumn & "->>'" & path & "')::int = $1"

proc jsonContains*(jsonColumn: string): string =
  ## Generates a parameterized WHERE clause for JSONB containment.
  ## The value must be a valid JSON string.
  ## Use with findWhere: findWhere(User, jsonContains("metadata"), """{"city": "New York"}""")
  result = jsonColumn & " @> $1"

proc jsonHasKey*(jsonColumn: string, key: string): string =
  ## Generates WHERE clause for JSONB key exists: column ? 'key'
  result = jsonColumn & " ? '" & key & "'"

proc jsonHasAllKeys*(jsonColumn: string, keys: seq[string]): string =
  ## Generates WHERE clause for JSONB has all keys: column ?& array['k1','k2']
  result = jsonColumn & " ?& array[" & keys.mapIt("'" & it & "'").join(",") & "]"

proc jsonHasAnyKey*(jsonColumn: string, keys: seq[string]): string =
  ## Generates WHERE clause for JSONB has any key: column ?| array['k1','k2']
  result = jsonColumn & " ?| array[" & keys.mapIt("'" & it & "'").join(",") & "]"

# Raw query execution for complex JSON queries
proc rawQuery*(db: DbConn, query: string, args: varargs[string]): seq[Row] =
  ## Execute raw SQL query and return rows
  try:
    result = @[]
    for row in rows(db, sql(query), args.map(dbValue)):
      result.add(row)
  except Exception as e:
    echo "Query failed: ", e.msg
    raise e

proc rawExec*(db: DbConn, query: string, args: varargs[string]) =
  ## Execute raw SQL without returning results
  try:
    exec(db, sql(query), args.map(dbValue))
  except Exception as e:
    echo "Exec failed: ", e.msg
    raise e

# =============================================================================
# UUID Model Support (for Phoenix/Ecto compatibility)
# =============================================================================

proc genUuid*(): string =
  ## Generate a random UUID v4
  randomize()
  var uuid = newString(36)
  const hexChars = "0123456789abcdef"
  for i in 0..<36:
    if i == 8 or i == 13 or i == 18 or i == 23:
      uuid[i] = '-'
    elif i == 14:
      uuid[i] = '4'  # Version 4
    elif i == 19:
      uuid[i] = hexChars[8 + rand(3)]  # Variant bits
    else:
      uuid[i] = hexChars[rand(15)]
  return uuid

# Helper macro to populate UUID object from DB row
macro populateUuidObject(T: typedesc, obj: var typed, row: typed): untyped =
  let typeImpl = T.getTypeInst()[1].getImpl()
  let recList = typeImpl[2][2]

  result = newNimNode(nnkStmtList)
  var index = 1

  for fieldDef in recList:
    let fieldName = getFieldNameFromDef(fieldDef)
    let fieldType = fieldDef[1]
    let rowValue = newNimNode(nnkBracketExpr).add(row, newLit(index))
    inc index

    let assignment = newNimNode(nnkAsgn)
    assignment.add(newNimNode(nnkDotExpr).add(obj, fieldName))

    let fieldTypeStr = fieldType.repr
    let parser = if fieldTypeStr == "string":
        quote do: getRawString(`rowValue`)
      elif fieldTypeStr == "int":
        quote do: parseInt($`rowValue`)
      elif fieldTypeStr == "int64":
        quote do: parseBiggestInt($`rowValue`)
      elif fieldTypeStr == "float" or fieldTypeStr == "float32" or fieldTypeStr == "float64":
        quote do: parseFloat($`rowValue`)
      elif fieldTypeStr == "bool":
        quote do: parsePgBool($`rowValue`)
      elif fieldTypeStr == "DateTime":
        quote do: parsePgTimestamp($`rowValue`)
      elif fieldTypeStr.startsWith("Option["):
        let innerType = fieldTypeStr[7..^2]
        if innerType == "DateTime":
          quote do:
            if $`rowValue` == "" or $`rowValue` == "null" or $`rowValue` == "NULL":
              none(DateTime)
            else:
              some(parsePgTimestamp($`rowValue`))
        elif innerType == "int64":
          quote do:
            if $`rowValue` == "" or $`rowValue` == "null" or $`rowValue` == "NULL":
              none(int64)
            else:
              some(parseBiggestInt($`rowValue`))
        elif innerType == "string":
          quote do:
            if $`rowValue` == "" or $`rowValue` == "null" or $`rowValue` == "NULL":
              none(string)
            else:
              some(getRawString(`rowValue`))
        elif innerType == "float" or innerType == "float64":
          quote do:
            if $`rowValue` == "" or $`rowValue` == "null" or $`rowValue` == "NULL":
              none(float)
            else:
              some(parseFloat($`rowValue`))
        elif innerType == "bool":
          quote do:
            if $`rowValue` == "" or $`rowValue` == "null" or $`rowValue` == "NULL":
              none(bool)
            else:
              some(parsePgBool($`rowValue`))
        else:
          quote do:
            if $`rowValue` == "" or $`rowValue` == "null" or $`rowValue` == "NULL":
              none(typeof(`obj`.`fieldName`).T)
            else:
              some($`rowValue`)
      elif fieldTypeStr == "JsonField":
        quote do: newJsonField($`rowValue`)
      elif fieldTypeStr == "VectorField":
        quote do: newVectorField($`rowValue`)
      else:
        quote do: $`rowValue`

    assignment.add(parser)
    result.add(assignment)

# Find UUID model by string ID
macro findUuid*(T: typedesc, id: string, db: DbConn): untyped =
  let typeName = $T.getTypeInst()[1]
  result = quote do:
    let tableName = getTableName(`typeName`)
    var fieldNames = getFieldNames(`T`)
    fieldNames.insert("id", 0)

    let columns = fieldNames.map(toSnakeCase).join(", ")
    let selectQuery = "SELECT " & columns & " FROM " & tableName & " WHERE id = $1"

    var resultObj: Option[`T`]

    try:
      let rowOpt = getRow(db, sql(selectQuery), [dbValue(`id`)])
      if rowOpt.isSome:
        let row = rowOpt.get()
        if len($row[0]) > 0:
          var obj: `T`
          obj.id = getRawString(row[0])

          populateUuidObject(`T`, obj, row)

          resultObj = some(obj)
        else:
          resultObj = none(`T`)
      else:
        resultObj = none(`T`)
    except Exception as e:
      echo "Failed to find ", `typeName`, ": ", e.msg
      resultObj = none(`T`)

    resultObj

# Find all UUID models
macro findAllUuid*(T: typedesc, db: DbConn): untyped =
  let typeName = $T.getTypeInst()[1]
  result = quote do:
    let tableName = getTableName(`typeName`)
    var fieldNames = getFieldNames(`T`)
    fieldNames.insert("id", 0)

    let columns = fieldNames.map(toSnakeCase).join(", ")
    let selectQuery = "SELECT " & columns & " FROM " & tableName

    var results: seq[`T`]

    try:
      for row in rows(db, sql(selectQuery)):
        if len($row[0]) > 0:
          var obj: `T`
          obj.id = getRawString(row[0])

          populateUuidObject(`T`, obj, row)

          results.add(obj)
    except Exception as e:
      echo "Failed to find all ", `typeName`, ": ", e.msg

    results

# Find UUID models with WHERE clause
macro findWhereUuid*(T: typedesc, db: DbConn, whereClause: string, args: varargs[string]): untyped =
  let typeName = $T.getTypeInst()[1]

  var argsArray = newNimNode(nnkBracket)
  for i in 0..<args.len:
    argsArray.add(args[i])

  result = quote do:
    let tableName = getTableName(`typeName`)
    var fieldNames = getFieldNames(`T`)
    fieldNames.insert("id", 0)

    let columns = fieldNames.map(toSnakeCase).join(", ")
    let selectQuery = "SELECT " & columns & " FROM " & tableName & " WHERE " & `whereClause`

    var results: seq[`T`]
    let argsSeq: seq[string] = @`argsArray`
    var dbArgs: seq[DbValue] = @[]
    for a in argsSeq:
      dbArgs.add(dbValue(a))

    try:
      for row in rows(`db`, sql(selectQuery), dbArgs):
        if len($row[0]) > 0:
          var obj: `T`
          obj.id = getRawString(row[0])

          populateUuidObject(`T`, obj, row)

          results.add(obj)
    except Exception as e:
      echo "Failed to find ", `typeName`, " with condition: ", e.msg

    results

# Save UUID model (INSERT or UPDATE)
macro saveUuid*(obj: typed, db: DbConn): untyped =
  let objType = obj.getTypeInst()
  let typeName = $objType

  result = quote do:
    let tableName = getTableName(`typeName`)
    let fieldNames = getFieldNames(type(`obj`))

    var dbValues: seq[DbValue]
    for name, val in fieldPairs(`obj`):
      if name != "id":
        dbValues.add(dbValue(val))

    if `obj`.id == "":
      # INSERT with new UUID
      `obj`.id = genUuid()
      let columns = "id, " & fieldNames.map(toSnakeCase).join(", ")
      let placeholders = "$1, " & toSeq(2..fieldNames.len+1).map(proc (i: int): string = "$" & $i).join(", ")
      let insertQuery = "INSERT INTO " & tableName & " (" & columns & ") VALUES (" & placeholders & ")"

      var allValues: seq[DbValue] = @[dbValue(`obj`.id)]
      allValues.add(dbValues)

      try:
        exec(db, sql(insertQuery), allValues)
        echo "Inserted ", `typeName`, " with id: ", `obj`.id
      except Exception as e:
        echo "Failed to save ", `typeName`, ": ", e.msg
        raise e
    else:
      # UPDATE
      var setClauses: seq[string]
      for i, name in fieldNames:
        setClauses.add(toSnakeCase(name) & " = $" & $(i + 1))
      let updateQuery = "UPDATE " & tableName & " SET " & setClauses.join(", ") & " WHERE id = $" & $(fieldNames.len + 1)

      try:
        dbValues.add(dbValue(`obj`.id))
        exec(db, sql(updateQuery), dbValues)
        echo "Updated ", `typeName`, " with id: ", `obj`.id
      except Exception as e:
        echo "Failed to update ", `typeName`, " with id: ", `obj`.id, " ", e.msg
        raise e

# Delete UUID model
macro deleteUuid*(obj: typed, db: DbConn): untyped =
  let objType = obj.getTypeInst()
  let typeName = $objType

  result = quote do:
    if `obj`.id == "":
      echo "Cannot delete ", `typeName`, " without id"
    else:
      let tableName = getTableName(`typeName`)
      let deleteQuery = "DELETE FROM " & tableName & " WHERE id = $1"

      try:
        exec(db, sql(deleteQuery), [dbValue(`obj`.id)])
        echo "Deleted ", `typeName`, " with id: ", `obj`.id
        `obj`.id = ""
      except Exception as e:
        echo "Failed to delete ", `typeName`, ": ", e.msg
        raise e

# Delete UUID model by id
macro deleteByUuid*(T: typedesc, id: string, db: DbConn): untyped =
  let typeName = $T.getTypeInst()[1]

  result = quote do:
    let tableName = getTableName(`typeName`)
    let deleteQuery = "DELETE FROM " & tableName & " WHERE id = $1"

    try:
      exec(db, sql(deleteQuery), [dbValue(`id`)])
      echo "Deleted ", `typeName`, " with id: ", `id`
    except Exception as e:
      echo "Failed to delete ", `typeName`, ": ", e.msg
      raise e
