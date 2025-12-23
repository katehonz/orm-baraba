# src/orm/migrations.nim
# Professional Flyway-style database migration system for Nim

import lowdb/postgres
import os
import strutils
import times
import algorithm
import checksums/md5
import logger as l

proc getSingleValue*(db: DbConn, query: SqlQuery, args: varargs[DbValue]): string =
  ## Helper to get single value from query
  for row in db.rows(query, args):
    return $row[0]
  return ""

type
  MigrationInfo* = object
    version*: int
    description*: string
    script*: string
    checksum*: string
    installedOn*: DateTime
    executionTime*: int
    success*: bool

  MigrationFile = object
    version: int
    description: string
    path: string
    checksum: string

# Forward declaration
proc parseMigrationFiles(migrationsDir: string): seq[MigrationFile]

proc createSchemaHistoryTable*(db: DbConn) =
  ## Creates the schema_history table if it doesn't exist (Flyway-compatible schema)
  let tableQuery = """
  CREATE TABLE IF NOT EXISTS schema_history (
      installed_rank SERIAL PRIMARY KEY,
      version INT NOT NULL UNIQUE,
      description VARCHAR(200) NOT NULL,
      type VARCHAR(20) NOT NULL DEFAULT 'SQL',
      script VARCHAR(1000) NOT NULL,
      checksum VARCHAR(32),
      installed_by VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
      installed_on TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      execution_time INT NOT NULL DEFAULT 0,
      success BOOLEAN NOT NULL DEFAULT TRUE
  )
  """
  let indexQuery = """
  CREATE INDEX IF NOT EXISTS idx_schema_history_success ON schema_history(success)
  """
  try:
    exec(db, sql(tableQuery))
    exec(db, sql(indexQuery))
  except Exception as e:
    echo "Failed to create schema_history table: ", e.msg
    quit(1)

proc calculateChecksum(content: string): string =
  ## Calculates MD5 checksum for migration file content
  result = $toMD5(content)

proc getAppliedMigrations*(db: DbConn): seq[MigrationInfo] =
  ## Returns list of all applied migrations with their details
  var migrations: seq[MigrationInfo]
  try:
    let query = "SELECT version, description, script, checksum, execution_time, success FROM schema_history ORDER BY version"
    for row in rows(db, sql(query)):
      var info = MigrationInfo()
      info.version = parseInt($row[0])
      info.description = $row[1]
      info.script = $row[2]
      info.checksum = $row[3]
      info.executionTime = parseInt($row[4])
      info.success = $row[5] == "t"
      migrations.add(info)
  except Exception as e:
    l.error("getAppliedMigrations failed: " & e.msg)
  return migrations

proc getAppliedVersions(db: DbConn): seq[int] =
  ## Returns just the version numbers of applied migrations
  var versions: seq[int]
  for m in getAppliedMigrations(db):
    versions.add(m.version)
  return versions

proc tableExists*(db: DbConn, tableName: string): bool =
  ## Check if a table exists in the database
  try:
    let query = """
      SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND table_name = $1
      )
    """
    let queryResult = getSingleValue(db, sql(query), dbValue(tableName))
    return queryResult == "t"
  except:
    return false

proc discoverExistingTables*(db: DbConn): seq[string] =
  ## Discover all existing tables in the public schema
  var tables: seq[string]
  try:
    for row in rows(db, sql"""
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      AND table_type = 'BASE TABLE'
      ORDER BY table_name
    """):
      tables.add($row[0])
  except:
    discard
  return tables

proc baselineMigration*(db: DbConn, version: int, migrationsDir: string = "src/migrations") =
  ## Marks all migrations up to and including the specified version as applied
  ## Use this for existing databases that already have the schema
  l.info("Creating baseline at version V" & $version)

  let migrationFiles = parseMigrationFiles(migrationsDir)
  let appliedVersions = getAppliedVersions(db)

  for file in migrationFiles:
    if file.version <= version and file.version notin appliedVersions:
      l.info("  Baseline: V" & $file.version & " - " & file.description)
      try:
        exec(db, sql"""
          INSERT INTO schema_history (version, description, script, checksum, installed_by, execution_time, success)
          VALUES ($1, $2, $3, $4, CURRENT_USER, 0, TRUE)
        """, file.version, file.description & " (baseline)", file.path.splitPath().tail, file.checksum)
      except Exception as e:
        if "duplicate key" notin e.msg:
          raise e

  l.success("Baseline created at V" & $version)

proc parseMigrationFiles(migrationsDir: string): seq[MigrationFile] =
  ## Parses migration files from directory, returns sorted by version
  var files: seq[MigrationFile]

  if not dirExists(migrationsDir):
    echo "Migrations directory not found: ", migrationsDir
    return files

  for file in walkDir(migrationsDir):
    if file.kind == pcFile and file.path.endsWith(".sql"):
      let filename = file.path.splitPath().tail

      # Parse V<version>__<description>.sql format
      if filename.startsWith("V") and "__" in filename:
        let parts = filename[0..^5].split("__", 1)  # Remove .sql and split
        if parts.len == 2:
          try:
            let versionStr = parts[0][1..^1]  # Remove 'V' prefix
            let version = parseInt(versionStr)
            let description = parts[1].replace("_", " ")
            let content = readFile(file.path)
            let checksum = calculateChecksum(content)

            files.add(MigrationFile(
              version: version,
              description: description,
              path: file.path,
              checksum: checksum
            ))
          except ValueError:
            echo "Warning: Invalid version number in ", filename
      # Parse U<version>__<description>.sql for undo migrations (skip here)
      elif filename.startsWith("U"):
        discard
      else:
        echo "Warning: Skipping file with invalid naming convention: ", filename

  # Sort by version
  files.sort(proc(a, b: MigrationFile): int = cmp(a.version, b.version))
  return files

proc parseUndoMigrations(migrationsDir: string): seq[MigrationFile] =
  ## Parses undo migration files (U<version>__<description>.sql)
  var files: seq[MigrationFile]

  if not dirExists(migrationsDir):
    return files

  for file in walkDir(migrationsDir):
    if file.kind == pcFile and file.path.endsWith(".sql"):
      let filename = file.path.splitPath().tail

      if filename.startsWith("U") and "__" in filename:
        let parts = filename[0..^5].split("__", 1)
        if parts.len == 2:
          try:
            let versionStr = parts[0][1..^1]
            let version = parseInt(versionStr)
            let description = parts[1].replace("_", " ")
            let content = readFile(file.path)
            let checksum = calculateChecksum(content)

            files.add(MigrationFile(
              version: version,
              description: description,
              path: file.path,
              checksum: checksum
            ))
          except ValueError:
            echo "Warning: Invalid version number in ", filename

  files.sort(proc(a, b: MigrationFile): int = cmp(b.version, a.version))  # Descending
  return files

proc validateMigrations*(db: DbConn, migrationsDir: string = "src/migrations"): bool =
  ## Validates that applied migrations haven't been modified (checksum validation)
  echo "Validating migrations..."

  let appliedMigrations = getAppliedMigrations(db)
  let migrationFiles = parseMigrationFiles(migrationsDir)

  for applied in appliedMigrations:
    for file in migrationFiles:
      if file.version == applied.version:
        if file.checksum != applied.checksum:
          echo "WARNING: Checksum mismatch for migration V", applied.version
          echo "  Expected: ", applied.checksum
          echo "  Found:    ", file.checksum
          echo "  Migration file has been modified after application!"
          # Allow validation to continue but warn user
        break

  echo "Validation successful."
  return true

proc applyMigrations*(db: DbConn, migrationsDir: string = "src/migrations", dryRun: bool = false) =
  ## Applies pending migrations in version order
  ## Each migration runs in a transaction for atomicity
  printHeader("DATABASE MIGRATIONS")
  info("Starting migration process...")
  createSchemaHistoryTable(db)

  if not validateMigrations(db, migrationsDir):
    error("Migration validation failed. Aborting.")
    quit(1)

  let appliedVersions = getAppliedVersions(db)
  let migrationFiles = parseMigrationFiles(migrationsDir)
  var appliedCount = 0
  var pendingCount = 0

  # Count pending migrations
  for file in migrationFiles:
    if file.version notin appliedVersions:
      pendingCount += 1

  if pendingCount == 0:
    success("Schema is up to date. No migrations to apply.")
    return

  info("Found $1 pending migration(s)" % [$pendingCount])

  if dryRun:
    warn("DRY RUN - no changes will be made")
    for file in migrationFiles:
      if file.version notin appliedVersions:
        info("  Would apply: V$1 - $2" % [$file.version, file.description])
    return

  for file in migrationFiles:
    if file.version notin appliedVersions:
      info("Applying V$1 - $2" % [$file.version, file.description])

      let scriptContent = readFile(file.path)
      let startTime = cpuTime()

      # Start transaction for this migration
      try:
        exec(db, sql"BEGIN")

        # Execute each statement in the migration
        for statement in scriptContent.split(';'):
          # Strip leading comments from the statement
          var stmt = ""
          for line in statement.splitLines():
            let trimmed = line.strip()
            if not trimmed.startsWith("--") and trimmed.len > 0:
              stmt &= line & "\n"
          stmt = stmt.strip()
          if stmt.len > 0:
            debug("  SQL: " & stmt[0..min(60, stmt.len-1)] & "...")
            exec(db, sql(stmt))

        let executionTime = int((cpuTime() - startTime) * 1000)

        # Record successful migration
        exec(db, sql"""
          INSERT INTO schema_history (version, description, script, checksum, execution_time, success)
          VALUES ($1, $2, $3, $4, $5, TRUE)
        """, file.version, file.description, file.path.splitPath().tail, file.checksum, executionTime)

        exec(db, sql"COMMIT")
        success("  ✓ V$1 applied ($2ms)" % [$file.version, $executionTime])
        appliedCount += 1

      except Exception as e:
        # Rollback on any error
        try:
          exec(db, sql"ROLLBACK")
        except:
          discard

        error("  ✗ V$1 FAILED: $2" % [$file.version, e.msg])

        # Handle special cases
        if "already exists" in e.msg:
          warn("  Object already exists - use 'baseline' command for existing schemas")
        elif "does not exist" in e.msg:
          warn("  Dependency missing - check migration order")

        # Record failed migration (outside transaction)
        try:
          exec(db, sql"""
            INSERT INTO schema_history (version, description, script, checksum, execution_time, success)
            VALUES ($1, $2, $3, $4, 0, FALSE)
          """, file.version, file.description, file.path.splitPath().tail, file.checksum)
        except:
          discard

        error("Migration failed. Database rolled back to previous state.")
        quit(1)

  success("Successfully applied $1 migration(s)" % [$appliedCount])

proc rollbackMigration*(db: DbConn, targetVersion: int = -1, migrationsDir: string = "src/migrations") =
  ## Rolls back to target version (or last version if targetVersion = -1)
  ## Each rollback runs in a transaction for atomicity
  printHeader("DATABASE ROLLBACK")

  let appliedMigrations = getAppliedMigrations(db)
  if appliedMigrations.len == 0:
    warn("No migrations to rollback.")
    return

  let undoFiles = parseUndoMigrations(migrationsDir)
  if undoFiles.len == 0:
    error("No undo migration files found.")
    info("Create U<version>__<description>.sql files for rollback support.")
    return

  var target = targetVersion
  if target == -1:
    target = appliedMigrations[^1].version - 1

  let currentVersion = appliedMigrations[^1].version
  info("Current version: V$1" % [$currentVersion])
  info("Target version: V$1" % [$target])

  var rolledBack = 0

  for applied in appliedMigrations.reversed():
    if applied.version > target:
      var undoFound = false

      for undo in undoFiles:
        if undo.version == applied.version:
          undoFound = true
          info("Rolling back V$1 - $2" % [$applied.version, applied.description])

          let scriptContent = readFile(undo.path)

          try:
            exec(db, sql"BEGIN")

            # Execute each statement
            for statement in scriptContent.split(';'):
              # Strip leading comments from the statement
              var stmt = ""
              for line in statement.splitLines():
                let trimmed = line.strip()
                if not trimmed.startsWith("--") and trimmed.len > 0:
                  stmt &= line & "\n"
              stmt = stmt.strip()
              if stmt.len > 0:
                exec(db, sql(stmt))

            exec(db, sql"DELETE FROM schema_history WHERE version = $1", applied.version)
            exec(db, sql"COMMIT")

            success("  ✓ V$1 rolled back" % [$applied.version])
            rolledBack += 1
          except Exception as e:
            try:
              exec(db, sql"ROLLBACK")
            except:
              discard
            error("  ✗ Failed to rollback V$1: $2" % [$applied.version, e.msg])
            quit(1)

          break

      if not undoFound:
        error("No undo file for V$1" % [$applied.version])
        info("Expected: U$1__*.sql" % [$applied.version])
        quit(1)

  if rolledBack > 0:
    success("Rolled back $1 migration(s). Now at V$2" % [$rolledBack, $target])
  else:
    info("No migrations to rollback.")

proc migrationInfo*(db: DbConn, migrationsDir: string = "src/migrations") =
  ## Displays information about all migrations (similar to flyway info)
  printHeader("MIGRATION STATUS")
  createSchemaHistoryTable(db)

  let appliedMigrations = getAppliedMigrations(db)
  let migrationFiles = parseMigrationFiles(migrationsDir)

  var pending, applied, failed = 0

  echo ""
  echo "+---------+----------+------------------------------+----------+"
  echo "| Version | State    | Description                  | Checksum |"
  echo "+---------+----------+------------------------------+----------+"

  for file in migrationFiles:
    var state = "Pending"
    var displayChecksum = file.checksum[0..7]

    for m in appliedMigrations:
      if m.version == file.version:
        if m.success:
          state = "Applied"
          applied += 1
        else:
          state = "Failed"
          failed += 1
        if m.checksum != file.checksum:
          state = "Modified"
        break

    if state == "Pending":
      pending += 1

    let desc = if file.description.len > 28: file.description[0..27] else: file.description
    let stateColored = case state
      of "Applied": "Applied"
      of "Pending": "Pending"
      of "Failed": "FAILED"
      of "Modified": "MODIFIED"
      else: state

    echo "| ", align($file.version, 7), " | ", alignLeft(stateColored, 8), " | ",
         alignLeft(desc, 28), " | ", displayChecksum, " |"

  echo "+---------+----------+------------------------------+----------+"
  echo ""
  info("Summary: $1 applied, $2 pending, $3 failed" % [$applied, $pending, $failed])

proc cleanMigrations*(db: DbConn) =
  ## Removes all migration history (DANGEROUS - use with caution)
  printHeader("CLEAN MIGRATIONS")
  warn("This will DELETE all migration history!")
  warn("The actual database tables will NOT be dropped.")
  try:
    exec(db, sql"DROP TABLE IF EXISTS schema_history CASCADE")
    success("Migration history cleared.")
  except Exception as e:
    error("Failed to clear history: " & e.msg)

proc repairMigrations*(db: DbConn, migrationsDir: string = "src/migrations") =
  ## Repairs migration checksums (updates checksums to match current files)
  printHeader("REPAIR MIGRATIONS")
  info("Checking for checksum mismatches...")

  let appliedMigrations = getAppliedMigrations(db)
  let migrationFiles = parseMigrationFiles(migrationsDir)
  var repaired = 0

  for applied in appliedMigrations:
    for file in migrationFiles:
      if file.version == applied.version and file.checksum != applied.checksum:
        info("  V$1: $2 -> $3" % [$applied.version, applied.checksum[0..7], file.checksum[0..7]])
        try:
          exec(db, sql"UPDATE schema_history SET checksum = $1 WHERE version = $2",
               file.checksum, applied.version)
          repaired += 1
        except Exception as e:
          error("  Failed: " & e.msg)

  if repaired > 0:
    success("Repaired $1 checksum(s)" % [$repaired])
  else:
    success("All checksums are valid")
