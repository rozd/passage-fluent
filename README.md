# passage-fluent

[![Release](https://img.shields.io/github/v/release/rozd/passage-fluent)](https://github.com/rozd/passage-fluent/releases)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License](https://img.shields.io/github/license/rozd/passage-fluent)](LICENSE)
[![codecov](https://codecov.io/gh/rozd/passage-fluent/branch/main/graph/badge.svg)](https://codecov.io/gh/rozd/passage-fluent)

Fluent database storage implementation for [Passage](https://github.com/vapor-community/passage) authentication framework.

This package provides persistent storage for all Passage authentication data using Vapor's Fluent ORM, including users, refresh tokens, verification codes, and password reset codes.

> **Note:** This package cannot be used standalone. It requires [Passage](https://github.com/vapor-community/passage) and a Fluent database driver (PostgreSQL, MySQL, SQLite, etc.) to function.

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/rozd/passage-fluent.git", from: "0.0.1"),
]
```

Then add `PassageFluent` to your target dependencies:

```swift
.target(
    name: "App",
    dependencies: [
        .product(name: "PassageFluent", package: "passage-fluent"),
    ]
)
```

## Configuration

Configure `DatabaseStore` with your Vapor application and database:

```swift
import Passage
import PassageFluent

let store = DatabaseStore(app: app, db: app.db)
```

Then pass it to Passage during configuration:

```swift
app.passage.configure(
    services: .init(
        store: store,
        // ... other services
    ),
    configuration: .init(/* ... */)
)
```

> **Note:** `DatabaseStore` automatically registers all required migrations. Run `app.autoMigrate()` or use Vapor's migration commands to apply them.

## Database Schema

The following tables are automatically created:

| Table | Description |
|-------|-------------|
| `users` | Core user entity with password hash |
| `identifiers` | Polymorphic user identifiers (email, phone, username, federated) |
| `refresh_tokens` | JWT refresh tokens with rotation chain tracking |
| `email_verification_codes` | Email verification codes with expiration |
| `phone_verification_codes` | Phone verification codes with expiration |
| `email_password_reset_codes` | Email-based password reset codes |
| `phone_password_reset_codes` | Phone-based password reset codes |
| `exchange_tokens` | OAuth exchange tokens for federated login |

## Features

### User Management
- Create users with email, phone, username, or federated identity
- Support for multiple identifiers per user
- Email and phone verification status tracking
- Password hash storage with secure updates

### Token Management
- Refresh token storage with secure hashing
- Token rotation with family chain tracking
- Automatic revocation of compromised token families
- Per-user token revocation for logout

### Verification & Password Reset
- Time-limited verification codes
- Failed attempt tracking for rate limiting
- Automatic code invalidation after use
- Separate flows for email and phone

## Using a Different Database

Pass any Fluent database to `DatabaseStore`:

```swift
// Use a specific database (e.g., for multi-database setups)
let store = DatabaseStore(app: app, db: app.db(.auth))

// Or use the default database
let store = DatabaseStore(app: app, db: app.db)
```

## Requirements

- Swift 5.9+
- macOS 13+ / Linux
- Vapor 4.119+
- Fluent 4.13+

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
