# Changelog

All notable changes to ORM Baraba will be documented in this file.

## [2.2.5] - 2025-12-17 - Bug Fixes & Test Suite

### 🐛 BUG FIXES
- **CRITICAL**: Fixed migration comment stripping bug - SQL statements starting with comments were being skipped entirely
- **CRITICAL**: Fixed date parsing error in `getAppliedMigrations()` - removed problematic timestamp column from query
- **Fixed**: DB_PORT environment variable now properly used in database connections
- **Fixed**: `populateObject` macro now correctly uses passed parameters instead of hardcoded identifiers

### 🧪 TEST SUITE
- Added comprehensive ORM test suite (`test_orm_dsl.nim`)
- Docker-based testing with pgvector container
- Full CRUD operations test coverage
- Migration apply/rollback tests
- pgvector integration tests

### 📚 DOCUMENTATION
- Added testing section to README with Docker setup instructions
- Documented test scenarios and expected output
- Added pgvector container setup guide

## [2.2.4] - 2025-12-17 - Production Release

### ✅ SECURITY FIXES
- **CRITICAL**: Fixed SQL injection vulnerabilities in JSON query helpers
- **CRITICAL**: Removed hardcoded database password from `initDb()`
- **CRITICAL**: Fixed SQL injection in `runSeedData()` and `runDemo()` functions
- All user inputs now use parameterized queries
- Environment variable validation added for secure configuration

### 🚀 NEW FEATURES
- **Interactive TUI CLI**: Complete menu-driven interface for all operations
- **pgvector Support**: Full vector similarity search for AI/ML applications
- **JSONB Helpers**: Comprehensive helper functions for PostgreSQL JSON operations
- **Enhanced Logging**: Production-ready colored logging system with levels
- **Migration Enhancements**: Document chunks table, full-text search indexes
- **Explicit Connection Passing**: Thread-safe database operations with explicit connection handling

### 🛠️ IMPROVEMENTS
- **Code Refactoring**: Eliminated code duplication in ORM macros
- **Error Handling**: Comprehensive error handling with proper rollbacks
- **Transaction Safety**: Automatic rollback on transaction failures
- **CLI Enhancement**: Added `seed`, `version`, and interactive commands
- **Migration Validation**: Enhanced checksum validation and repair functionality
- **Thread Safety**: Refactored to support thread-safe operations with explicit connection passing
- **Bug Fixes**: Fixed compatibility issues and build errors with Nim 2.2.x

### 📋 MIGRATION FILES
- V1: Users table with basic fields
- V2: Phone number column for users
- V3: JSONB metadata column with GIN index
- V4: pgvector extension enabled
- V5: Documents table for RAG with embeddings and full-text search

### 📚 DOCUMENTATION
- Complete README rewrite with production deployment guide
- Security audit report (`audit-gemini.md`)
- API reference documentation
- Usage examples and best practices

### 🔧 INTERNAL CHANGES
- Refactored `populateObject` helper macro for DRY code
- Enhanced vector field operations and query helpers
- Improved JSON field access patterns
- Better separation of concerns in CLI modules

## [2.2.0] - Development Phase
- Initial ORM implementation with basic CRUD operations
- Flyway-style migration system
- Basic CLI commands
- Model definition with macro-based field mapping

## 🔮 PLANNED FOR v2.3.0
- [ ] Connection pooling support
- [ ] Thread-safe operations (explicit connection passing)
- [ ] More vector index types (HNSW optimization)
- [] Batch operations for bulk inserts/updates
- [ ] GraphQL integration helpers
- [ ] Database health check endpoints