# orm_baraba.nimble

version       = "2.2.5"
author        = "ORM Baraba Team"
description   = "Professional PostgreSQL ORM and migration system with interactive CLI, JSON, pgvector support, and thread-safe operations. Built with Nim 2.2.x. Production Ready v2.2.5"
license       = "MIT"
srcDir        = "src"
bin           = @["main"]

# Dependencies
requires "nim >= 2.2.0"
requires "lowdb"
requires "checksums"

# Installation and deployment
installDirs = @["/usr/local/bin"]
installFiles = @["main"]
