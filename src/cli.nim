# src/cli.nim
# Interactive CLI module for ORM Baraba

import strutils
import os
import sequtils
import sugar
import lowdb/postgres
import orm/logger
import orm/migrations
import orm/orm

# Forward declarations
proc migrationMenu*()
proc databaseInfoMenu*()
proc ormDemoMenu*()
proc databaseOpsMenu*()
proc settingsMenu*()
proc helpMenu*()

type
  MenuItem = object
    key*: string
    description*: string
    action*: proc()

proc clearScreen*() =
  ## Clear the terminal screen
  discard execShellCmd("clear")

proc waitForKey*() =
  ## Wait for user to press any key
  stdout.write("\nPress Enter to continue...")
  discard stdin.readLine()

proc confirm*(message: string): bool =
  ## Ask for user confirmation
  stdout.write(message & " [y/N]: ")
  let response = stdin.readLine().toLowerAscii()
  return response == "y" or response == "yes"

proc input*(prompt: string): string =
  ## Get user input
  stdout.write(prompt & ": ")
  return stdin.readLine()

proc inputInt*(prompt: string, default: int = 0): int =
  ## Get integer input with validation
  while true:
    try:
      stdout.write(prompt & " []: " % $default)
      let response = stdin.readLine()
      if response.strip() == "":
        return default
      return parseInt(response)
    except:
      error("Please enter a valid number.")

proc mainMenu*() =
  ## Display main interactive menu
  while true:
    clearScreen()
    printHeader("ORM BARABA - PostgreSQL ORM & Migration System")
    
    echo ColorCyan & """
    ╔══════════════════════════════════════════════════════════════════════════════╗
    ║                          MAIN MENU                                           ║
    ╠══════════════════════════════════════════════════════════════════════════════╣
    ║  1. Migration Management                                                        ║
    ║  2. Database Information                                                       ║
    ║  3. ORM Demo & Examples                                                        ║
    ║  4. Database Operations                                                        ║
    ║  5. Settings & Configuration                                                   ║
    ║  6. Help & Documentation                                                       ║
    ║  0. Exit                                                                       ║
    ╚══════════════════════════════════════════════════════════════════════════════╝
    """ & ColorReset
    
    let choice = input("Select an option (0-6)")
    
    case choice:
    of "1": migrationMenu()
    of "2": databaseInfoMenu()
    of "3": ormDemoMenu()
    of "4": databaseOpsMenu()
    of "5": settingsMenu()
    of "6": helpMenu()
    of "0": 
      if confirm("Are you sure you want to exit?"):
        info("Goodbye! 👋")
        break
    else:
      error("Invalid option. Please try again.")

proc migrationMenu*() =
  ## Migration management menu
  while true:
    clearScreen()
    printHeader("MIGRATION MANAGEMENT")
    
    echo ColorYellow & """
    ┌─ Migration Operations ──────────────────────────────────────────────┐
    │ 1. Apply Pending Migrations                                           │
    │ 2. Rollback Migration                                                 │
    │ 3. View Migration Status                                              │
    │ 4. Validate Migrations                                               │
    │ 5. Repair Checksums                                                  │
    │ 6. Clean Migration History (DANGER!)                                 │
    │ 0. Back to Main Menu                                                 │
    └─────────────────────────────────────────────────────────────────────┘
    """ & ColorReset
    
    let choice = input("Select an option (0-6)")
    var db: DbConn

    case choice:
    of "1":
      try:
        db = initDb()
        applyMigrations(db)
        waitForKey()
      except Exception as e:
        error("Migration failed: " & e.msg)
        waitForKey()
      finally:
        if db != nil: closeDb(db)
    
    of "2":
      try:
        db = initDb()
        let targetVersion = inputInt("Rollback to version (0 for last)", 0)
        if targetVersion == 0:
          rollbackMigration(db)
        else:
          rollbackMigration(db, targetVersion)
        waitForKey()
      except Exception as e:
        error("Rollback failed: " & e.msg)
        waitForKey()
      finally:
        if db != nil: closeDb(db)
    
    of "3":
      try:
        db = initDb()
        migrationInfo(db)
        waitForKey()
      except Exception as e:
        error("Failed to get migration info: " & e.msg)
        waitForKey()
      finally:
        if db != nil: closeDb(db)
    
    of "4":
      try:
        db = initDb()
        if validateMigrations(db):
          success("All migrations are valid! ✅")
        else:
          error("Migration validation failed! ❌")
        waitForKey()
      except Exception as e:
        error("Validation failed: " & e.msg)
        waitForKey()
      finally:
        if db != nil: closeDb(db)
    
    of "5":
      try:
        db = initDb()
        repairMigrations(db)
        success("Checksums repaired successfully! ✅")
        waitForKey()
      except Exception as e:
        error("Repair failed: " & e.msg)
        waitForKey()
      finally:
        if db != nil: closeDb(db)
    
    of "6":
      if confirm("⚠️  This will delete ALL migration history! Are you absolutely sure?"):
        if confirm("This action cannot be undone. Continue?"):
          try:
            db = initDb()
            cleanMigrations(db)
            success("Migration history cleaned! 🧹")
            waitForKey()
          except Exception as e:
            error("Clean failed: " & e.msg)
            waitForKey()
          finally:
            if db != nil: closeDb(db)
    
    of "0": break
    else:
      error("Invalid option. Please try again.")
      waitForKey()

proc databaseInfoMenu*() =
  ## Database information menu
  clearScreen()
  printHeader("DATABASE INFORMATION")
  
  var db: DbConn
  try:
    db = initDb()
    # Get database info
    printSection("Database Connection")
    echo "Host: " & getEnv("DB_HOST", "localhost")
    echo "Port: " & getEnv("DB_PORT", "5432")
    echo "Database: " & getEnv("DB_NAME", "orm-baraba")
    echo "User: " & getEnv("DB_USER", "postgres")
    
    # Get table info
    printSection("Database Schema")
    let tables = discoverExistingTables(db)
    if tables.len > 0:
      printTable(@["Table Name"], tables.map(t => @[t]))
    else:
      printInfoBox("No tables found in public schema")
    
    # Get migration status
    printSection("Migration Status")
    let applied = getAppliedMigrations(db)
    if applied.len > 0:
      var rows: seq[seq[string]]
      for m in applied:
        rows.add(@[$m.version, m.description, $m.success])
      printTable(@["Version", "Description", "Success"], rows)
    else:
      printInfoBox("No migrations applied")
    
  except Exception as e:
    error("Failed to get database info: " & e.msg)
  finally:
    if db != nil: closeDb(db)
  
  waitForKey()

proc ormDemoMenu*() =
  ## ORM demonstration menu
  while true:
    clearScreen()
    printHeader("ORM DEMO & EXAMPLES")
    
    echo ColorGreen & """
    ┌─ ORM Demonstrations ───────────────────────────────────────────────┐
    │ 1. Basic CRUD Operations                                            │
    │ 2. JSON/JSONB Field Examples                                        │
    │ 3. Vector Search (pgvector)                                         │
    │ 4. Transaction Examples                                             │
    │ 5. Advanced Queries                                                  │
    │ 6. Seed Test Data                                                   │
    │ 0. Back to Main Menu                                                │
    └──────────────────────────────────────────────────────────────────────┘
    """ & ColorReset
    
    let choice = input("Select an option (0-6)")
    var db: DbConn

    case choice:
    of "1":
      printInfoBox("Basic CRUD demo would run here...")
      waitForKey()
    of "2":
      printInfoBox("JSON/JSONB demo would run here...")
      waitForKey()
    of "3":
      printInfoBox("Vector search demo would run here...")
      waitForKey()
    of "4":
      printInfoBox("Transaction demo would run here...")
      waitForKey()
    of "5":
      printInfoBox("Advanced queries demo would run here...")
      waitForKey()
    of "6":
      try:
        db = initDb()
        # You might want to apply migrations before seeding
        # applyMigrations(db) 
        # runSeedData(db)
        printSuccessBox("Seeding data would happen here.")
      except Exception as e:
        error("Seeding failed: " & e.msg)
      finally:
        if db != nil: closeDb(db)
      waitForKey()
    of "0": break
    else:
      error("Invalid option. Please try again.")
      waitForKey()

proc databaseOpsMenu*() =
  ## Database operations menu
  while true:
    clearScreen()
    printHeader("DATABASE OPERATIONS")
    
    echo ColorMagenta & """
    ┌─ Database Operations ─────────────────────────────────────────────┐
    │ 1. Execute Raw SQL                                                   │
    │ 2. Export Schema                                                     │
    │ 3. Import Data                                                       │
    │ 4. Backup Database                                                   │
    │ 5. Analyze Performance                                               │
    │ 0. Back to Main Menu                                                 │
    └──────────────────────────────────────────────────────────────────────┘
    """ & ColorReset
    
    let choice = input("Select an option (0-5)")
    var db: DbConn

    case choice:
    of "1":
      let sql = input("Enter SQL statement")
      if sql.len > 0:
        try:
          db = initDb()
          rawExec(db, sql)
          success("SQL executed successfully!")
        except Exception as e:
          error("SQL execution failed: " & e.msg)
        finally:
          if db != nil: closeDb(db)
      waitForKey()
    
    of "2":
      printInfoBox("Schema export would run here...")
      waitForKey()
    of "3":
      printInfoBox("Data import would run here...")
      waitForKey()
    of "4":
      printInfoBox("Database backup would run here...")
      waitForKey()
    of "5":
      printInfoBox("Performance analysis would run here...")
      waitForKey()
    of "0": break
    else:
      error("Invalid option. Please try again.")
      waitForKey()

proc settingsMenu*() =
  ## Settings and configuration menu
  while true:
    clearScreen()
    printHeader("SETTINGS & CONFIGURATION")
    
    printSection("Current Settings")
    echo "Log Level: " & $defaultLogger.level
    echo "Verbose Mode: " & $defaultLogger.verbose
    echo "Color Output: " & $defaultLogger.colors
    
    echo "\n" & ColorCyan & """
    ┌─ Settings Options ────────────────────────────────────────────────┐
    │ 1. Toggle Verbose Mode                                              │
    │ 2. Toggle Color Output                                              │
    │ 3. Set Log Level                                                     │
    │ 4. View Environment Variables                                         │
    │ 0. Back to Main Menu                                                │
    └──────────────────────────────────────────────────────────────────────┘
    """ & ColorReset
    
    let choice = input("Select an option (0-4)")
    
    case choice:
    of "1":
      setVerbose(not defaultLogger.verbose)
      success("Verbose mode " & (if defaultLogger.verbose: "enabled" else: "disabled"))
      waitForKey()
    of "2":
      setColors(not defaultLogger.colors)
      success("Color output " & (if defaultLogger.colors: "enabled" else: "disabled"))
      waitForKey()
    of "3":
      echo "Available log levels: DEBUG, INFO, WARN, ERROR"
      let levelStr = input("Enter log level").toUpperAscii()
      try:
        let level = parseEnum[LogLevel](levelStr)
        setLevel(level)
        success("Log level set to: " & levelStr)
      except:
        error("Invalid log level")
      waitForKey()
    of "4":
      clearScreen()
      printHeader("ENVIRONMENT VARIABLES")
      printSection("Database Configuration")
      echo "DB_HOST: " & getEnv("DB_HOST", "localhost")
      echo "DB_PORT: " & getEnv("DB_PORT", "5432")
      echo "DB_USER: " & getEnv("DB_USER", "postgres")
      let dbPass = getEnv("DB_PASSWORD")
      if dbPass.len > 0:
        echo "DB_PASSWORD: " & "*".repeat(dbPass.len)
      else:
        echo "DB_PASSWORD: (not set)"
      echo "DB_NAME: " & getEnv("DB_NAME", "orm-baraba")
      waitForKey()
    of "0": break
    else:
      error("Invalid option. Please try again.")
      waitForKey()

proc helpMenu*() =
  ## Help and documentation menu
  clearScreen()
  printHeader("HELP & DOCUMENTATION")
  
  printSection("Quick Start")
  echo """
  1. Configure database connection (via environment variables or code)
  2. Run migrations to create database schema
  3. Use ORM for CRUD operations
  4. Explore advanced features (JSON, Vector Search, etc.)
  """
  
  printSection("Common Commands")
  echo """
  • migrate - Apply pending database migrations
  • rollback - Rollback last migration
  • info - Show migration and database status
  • validate - Validate migration checksums
  • demo - Run ORM demonstration
  """
  
  printSection("Environment Variables")
  echo """
  • DB_HOST - PostgreSQL server host (default: localhost)
  • DB_PORT - PostgreSQL server port (default: 5432)
  • DB_USER - Database username (default: postgres)
  • DB_PASSWORD - Database password
  • DB_NAME - Database name (default: orm-baraba)
  """
  
  printSection("Getting Help")
  echo """
  • README.md - Complete documentation
  • https://github.com/your-repo/orm-baraba - GitHub repository
  • Issues/Support - Create GitHub issue for problems
  """
  
  waitForKey()

when isMainModule:
  mainMenu()