# passage-fluent

[![Release](https://img.shields.io/github/v/release/rozd/passage-fluent)](https://github.com/rozd/passage-fluent/releases)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![License](https://img.shields.io/github/license/rozd/passage-fluent)](LICENSE)
[![codecov](https://codecov.io/gh/rozd/passage-fluent/branch/main/graph/badge.svg)](https://codecov.io/gh/rozd/passage-fluent)

Fluent database storage implementation for [Passage](https://github.com/vapor-community/passage) authentication framework.

This package provides persistent storage for all Passage authentication data using Vapor's Fluent ORM, including users, refresh tokens, verification codes, password reset codes, and passkey (WebAuthn) credentials and challenges.

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
| `passkey_credentials` | WebAuthn credential records (credential ID, COSE public key, sign count, transports, backup state) |
| `passkey_challenges` | One-shot passkey ceremony challenges, stored as SHA-256 hashes with TTL and consumption tracking |

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

### Passkey Storage (WebAuthn)
- Full W3C credential record persistence: credential ID, COSE public key, sign count, transports, backup-eligibility, AAGUID, attestation format
- Transparent SHA-256 hashing of challenge bytes — plain-text challenges never touch the database
- One-shot challenge consumption with expiry for both registration and authentication ceremonies
- Nullable user binding for discoverable-authentication flows (where the user is unknown at challenge issuance)
- `cleanupExpiredPasskeyChallenges(before:)` for periodic GC of abandoned ceremonies
- Cascade-delete on user removal wipes the user's credentials and user-bound challenges

`DatabaseStore` conforms to the optional `Passage.PasskeyCredentialStore` and `Passage.PasskeyChallengeStore` sub-stores out of the box — passkey flows in `Passage` light up as soon as a `PasskeyService` is registered. See [vapor-community/passage](https://github.com/vapor-community/passage) for the service-side configuration.

## Using a Different Database

Pass any Fluent database to `DatabaseStore`:

```swift
// Use a specific database (e.g., for multi-database setups)
let store = DatabaseStore(app: app, db: app.db(.auth))

// Or use the default database
let store = DatabaseStore(app: app, db: app.db)
```

## Requirements

- Swift 6.2+
- macOS 13+ / Linux
- Vapor 4.119+
- Fluent 4.13+

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
