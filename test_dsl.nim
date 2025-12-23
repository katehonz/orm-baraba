import src/orm/orm
import src/orm/migrations
import options

# Test DSL functionality
type
  User* = object of Model
    name*: string
    email*: string

proc testOrmDsl() =
  echo "Testing ORM DSL..."
  
  # Test the getFieldNames macro
  let fieldNames = getFieldNames(User)
  echo "Field names: ", fieldNames
  
  # Test a basic object
  var user = User(name: "Test User", email: "test@example.com")
  echo "Created user: ", user.name, " <", user.email, ">"
  
  # Test field values macro
  let fieldValues = getFieldValues(user)
  echo "Field values: ", fieldValues
  
  # Test table name conversion
  echo "Table name: ", getTableName("User")
  
  echo "DSL test completed successfully!"

when isMainModule:
  initDb()
  try:
    testOrmDsl()
  finally:
    closeDb()