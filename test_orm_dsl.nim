import src/orm/orm
import src/orm/migrations
import lowdb/postgres
import options
import times

# Test comprehensive ORM DSL functionality
type
  User* = object of Model
    name*: string
    email*: string
    phone*: string

proc testOrmSave(db: DbConn) =
  echo "\n=== Testing Save Functionality ==="

  # Test INSERT (new record)
  var newUser = User(name: "Jane Wilson", email: "jane.wilson." & $getTime() & "@example.com", phone: "123-456-7890")
  echo "Before save - ID: ", newUser.id
  save(newUser, db)
  echo "After save - ID: ", newUser.id

  # Test UPDATE (existing record)
  newUser.phone = "098-765-4321"
  save(newUser, db)
  echo "After update - ID: ", newUser.id

proc testOrmFind(db: DbConn) =
  echo "\n=== Testing Find Functionality ==="

  # Test find by ID
  let foundUser = find(User, 1, db)
  if foundUser.isSome:
    let user = foundUser.get()
    echo "Found user: ", user.name, " <", user.email, "> Phone: ", user.phone
  else:
    echo "User not found"

  # Test findAll
  let allUsers = findAll(User, db)
  echo "Total users found: ", allUsers.len
  for user in allUsers:
    echo "  - ", user.name, " <", user.email, ">"

proc testOrmCount(db: DbConn) =
  echo "\n=== Testing Count Functionality ==="
  let userCount = count(User, db)
  echo "Total user count: ", userCount

proc testOrmExists(db: DbConn) =
  echo "\n=== Testing Exists Functionality ==="
  let user1Exists = exists(User, 1, db)
  let user999Exists = exists(User, 999, db)
  echo "User 1 exists: ", user1Exists
  echo "User 999 exists: ", user999Exists

proc testOrmDelete(db: DbConn) =
  echo "\n=== Testing Delete Functionality ==="

  # Find a user to delete
  let userToDelete = find(User, 2, db)
  if userToDelete.isSome:
    var user = userToDelete.get()
    echo "Deleting user: ", user.name
    delete(user, db)
    echo "Delete completed"
  else:
    echo "No user with ID 2 to delete"

proc main() =
  echo "=== Comprehensive ORM DSL Test ==="

  let db = initDb()
  try:
    # Apply migrations first
    echo "Applying migrations..."
    applyMigrations(db)

    # Test all CRUD operations
    testOrmSave(db)
    testOrmFind(db)
    testOrmCount(db)
    testOrmExists(db)
    testOrmDelete(db)

    echo "\n=== DSL Test Completed Successfully! ==="

  except Exception as e:
    echo "Test failed: ", e.msg
    quit(1)
  finally:
    closeDb(db)

when isMainModule:
  main()
