# src/main.nim
# Professional ORM + Migration System with Interactive CLI

import lowdb/postgres
import orm/orm
import orm/migrations
import orm/logger
import cli
import os
import strutils

proc showUsage() =
  printHeader("ORM BARABA - PostgreSQL ORM with Flyway-style Migrations")
  
  echo ColorCyan & """
🚀 USAGE:
  main migrate         Apply pending migrations
  main rollback [N]    Rollback to version N (or last if omitted)
  main info            Show migration status
  main validate        Validate migration checksums
  main repair          Repair checksums (if files were modified)
  main clean           Remove all migration history (DANGEROUS!)
  main demo            Run ORM demo with CRUD operations
  main interactive     Launch interactive CLI menu
  main help            Show this help message

🔧 ENVIRONMENT VARIABLES:
  DB_HOST=localhost    PostgreSQL server host
  DB_PORT=5432        PostgreSQL server port  
  DB_USER=postgres    Database username
  DB_PASSWORD=pass    Database password
  DB_NAME=orm-baraba  Database name

📖 EXAMPLES:
  main migrate                    # Apply all pending migrations
  main rollback 2                 # Rollback to version 2
  main rollback                   # Rollback last migration
  DB_NAME=mydb main info          # Use custom database name
  verbose=true main migrate       # Enable verbose logging
  
💡 TIP: Run 'main interactive' for the full GUI experience!
""" & ColorReset

proc runDemo*(db: DbConn) =
  printHeader("ORM DEMO - Raw SQL Examples")

  try:
    printSection("1. Creating Users (INSERT)")
    rawExec(db, "INSERT INTO users (name, email) VALUES ($1, $2)", "Alice Johnson", "alice@example.com")
    printSuccessBox("Created user Alice Johnson")

    rawExec(db, "INSERT INTO users (name, email) VALUES ($1, $2)", "Bob Smith", "bob@example.com")
    printSuccessBox("Created user Bob Smith")

    printSection("2. Querying Users (SELECT)")
    let rows = rawQuery(db, "SELECT id, name, email FROM users LIMIT 5")
    for row in rows:
      printInfoBox("User: $1 <$2>" % [$row[1], $row[2]])

    printSection("3. Counting Records")
    let countRows = rawQuery(db, "SELECT COUNT(*) FROM users")
    if countRows.len > 0:
      printInfoBox("Total users in database: " & $countRows[0][0])

    printSuccessBox("ORM Demo completed successfully!")

  except Exception as e:
    printErrorBox("Demo failed: " & e.msg)
    raise

proc runSeedData*(db: DbConn) =
  printHeader("SEEDING TEST DATA")

  try:
    printSection("Creating sample users...")

    let sampleUsers = [
      ("John Doe", "john.doe@example.com"),
      ("Jane Smith", "jane.smith@example.com"),
      ("Mike Johnson", "mike.j@example.com"),
      ("Sarah Williams", "sarah.w@example.com"),
      ("Tom Brown", "tom.brown@example.com")
    ]

    var createdCount = 0

    for (name, email) in sampleUsers:
      try:
        rawExec(db, "INSERT INTO users (name, email) VALUES ($1, $2)", name, email)
        inc(createdCount)
        printSuccessBox("Created user: $1 <$2>" % [name, email])
      except:
        printInfoBox("User may already exist: $1 <$2>" % [name, email])

    printSuccessBox("Seeding completed! Created $1 new users." % $createdCount)

  except Exception as e:
    printErrorBox("Seeding failed: " & e.msg)
    raise

proc main() =
  # Parse command line arguments
  let args = commandLineParams()
  
  # Check for verbose flag
  if "--verbose" in args or "-v" in args or getEnv("VERBOSE", "false") == "true":
    setVerbose(true)
    setLevel(Debug)
    debug("Verbose mode enabled")
  
  # Check for no-color flag
  if "--no-color" in args or getEnv("NO_COLOR", "false") == "true":
    setColors(false)
  
  # Parse main command
  if args.len == 0:
    showUsage()
    return

  let command = args[0].toLowerAscii()

  # Commands that do not require a database connection
  let noDbCommands = ["interactive", "menu", "help", "--help", "-h", "version", "--version"]
  if command in noDbCommands or command == "-v": # handle -v as a special case for version
    case command:
    of "interactive", "menu":
      mainMenu()
    of "help", "--help", "-h":
      showUsage()
    of "version", "--version", "-v":
      echo "ORM Baraba v2.2.4 - Professional PostgreSQL ORM & Migration System"
      echo "Built with Nim 2.2.4 ❤️"
    else:
      # Should be unreachable
      showUsage()
    return

  # All other commands require a database connection
  var db: DbConn
  try:
    db = initDb() # Create connection once

    case command:
    of "migrate":
      applyMigrations(db)
    of "rollback":
      if args.len > 1:
        let targetVersion = parseInt(args[1])
        rollbackMigration(db, targetVersion)
      else:
        rollbackMigration(db)
    of "info":
      migrationInfo(db)
    of "validate":
      if validateMigrations(db):
        success("All migrations are valid! ✅")
      else:
        error("Validation failed! ❌")
        quit(1)
    of "repair":
      repairMigrations(db)
      success("Checksums repaired successfully! ✅")
    of "clean":
      if confirm("⚠️  This will delete ALL migration history! Are you sure?"):
        if confirm("This action cannot be undone. Continue?"):
          cleanMigrations(db)
          success("Migration history cleaned! 🧹")
    of "demo":
      applyMigrations(db)
      runDemo(db)
    of "seed":
      applyMigrations(db)
      runSeedData(db)
    else:
      error("Unknown command: " & command)
      printWarningBox("Run 'main help' for available commands")
      quit(1)

  except Exception as e:
    # A generic catch-all for DB connection errors or command errors
    error(e.msg)
    quit(1)
  finally:
    if db != nil:
      closeDb(db)

main()
