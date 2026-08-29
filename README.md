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
- One-shot challenge consumption with expiry for all three ceremony entry points: discoverable authentication (`createPasskeyChallenge(from:)`), authenticated user adding a passkey (`createPasskeyChallenge(for: User, from:)`), and guest registration where the user does not yet exist (`createPasskeyChallenge(for: Identifier, from:)`)
- `cleanupExpiredPasskeyChallenges(before:)` for periodic GC of abandoned ceremonies
- Cascade-delete on user removal wipes the user's credentials and user-bound challenges

`DatabaseStore` conforms to the optional `Passage.PasskeyCredentialStore` and `Passage.PasskeyChallengeStore` sub-stores out of the box — passkey flows in `Passage` light up as soon as a `PasskeyService` is registered. See [vapor-community/passage](https://github.com/vapor-community/passage) for the service-side configuration.

## Bring Your Own User Model (Overlay Mode)

By default, `DatabaseStore` creates its own `users` and `identifiers` tables (**island mode**). If your app already has a user table, use **overlay mode** to reuse it.

> **Note:** Overlay mode supports **all identifier kinds** — email, phone, username, and federated — exactly like island mode. The `identifiers` table (S1) remains the source of truth for lookups. The example below is intentionally narrow: it models an existing table with a `NOT NULL email` column, which is why `storedEmail` is non-optional and `passageMakeUser` throws for non-email identifiers. Those are constraints of the *example schema*, not of overlay mode — a model with nullable columns can accept every identifier kind (the default `passageMakeUser` already does).

### Step 1: Conform Your User Model to `PassageUserModel`

```swift
import Passage
import PassageFluent

final class AppUser: Model, PassageUserModel, ModelSessionAuthenticatable, @unchecked Sendable {
    static let schema = "app_users"
    
    @ID(custom: "id", generatedBy: .database)
    var id: Int?
    
    // Stored with a distinct name: a non-optional `String` cannot witness
    // Passage.User's `var email: String? { get }` requirement directly.
    @Field(key: "email")
    var storedEmail: String
    
    @Field(key: "email_verified")
    var emailVerified: Bool
    
    @OptionalField(key: "password_hash")
    var passwordHash: String?
    
    // ... other fields
    
    // MARK: - PassageUserModel Conformance
    
    /// Called when creating a new user (e.g., during registration).
    /// Override to populate required columns from the identifier.
    static func passageMakeUser(identifier: Identifier, passwordHash: String?) throws -> AppUser {
        // This table's NOT NULL email column can't store other kinds —
        // a schema with nullable columns can accept phone/username/federated too.
        guard identifier.kind == .email else {
            throw PassageError.unexpected(message: "Only email identifiers supported")
        }
        let user = AppUser()
        user.storedEmail = identifier.value
        user.emailVerified = false
        user.passwordHash = passwordHash
        return user
    }
    
    /// Override if you track verification state in your own columns.
    /// Called after the `IdentifierModel` row is marked verified.
    static func passageDidMarkIdentifierVerified(
        _ kind: Identifier.Kind,
        for user: AppUser,
        on db: any Database
    ) async throws {
        if kind == .email {
            user.emailVerified = true
            try await user.save(on: db)
        }
    }
}

// MARK: - Passage.User Conformance

extension AppUser: User {
    public var email: String? { storedEmail.isEmpty ? nil : storedEmail }
    public var phone: String? { nil }
    public var username: String? { nil }
    public var isAnonymous: Bool { storedEmail.isEmpty }
    public var isEmailVerified: Bool { emailVerified }
    public var isPhoneVerified: Bool { false }
}
```

**Conformance Requirements:**
- `final class` — required by `PassageUserModel`'s `Self`-returning requirements (and Fluent convention)
- `@unchecked Sendable` — required for Vapor concurrency
- `SessionAuthenticatable` — easiest via `ModelSessionAuthenticatable` mixin
- Single-column `@ID` (UUID, Int, String, or custom `Codable` type) — no `@CompositeID`
- Implement `Passage.User` computed properties (email, phone, username, isEmailVerified, etc.)

### Step 2: Register Your User Table Migration First

The FK ordering requirement: PassageFluent's dependent tables reference your user table, so your user migration must run before PassageFluent migrations.

```swift
app.migrations.add(CreateAppUser())  // Your user table
```

### Step 3a: Overlay Mode S1 — Default Stores

Inject your user model type; PassageFluent creates the `identifiers` table and all token/code tables:

```swift
let store = DatabaseStore(
    app: app,
    db: app.db,
    userModelType: AppUser.self
)
```

### Step 3b: Overlay Mode S3 — Custom User Store

Provide both the model type AND a factory for a custom `Passage.UserStore` implementation that operates on your user table. PassageFluent skips creating the `identifiers` table.

The factory receives the `Database` the store must use. `DatabaseStore.transaction` calls it again with the transaction's connection so user writes commit or roll back together with tokens, codes and credentials — bind your store to the database it is handed, never to a captured `app.db`:

```swift
struct AppUserStore: Passage.UserStore {
    typealias ConcreateUser = AppUser
    
    let db: any Database
    
    var userType: AppUser.Type { AppUser.self }
    
    func find(byIdentifier identifier: Identifier) async throws -> (any User)? {
        // Query your app_users table directly. This demo store only resolves
        // emails — implement whichever kinds your schema can answer.
        guard identifier.kind == .email else { return nil }
        return try await AppUser.query(on: db)
            .filter(\.$storedEmail == identifier.value)
            .first()
    }
    
    // ... implement other required methods
}

let store = DatabaseStore(
    app: app,
    db: app.db,
    userModelType: AppUser.self,
    userStore: { AppUserStore(db: $0) }
)
```

### ID Type Flexibility

Support any Fluent ID type — UUID (default), Int, String, or custom:

```swift
// Int ID example (supported out-of-box)
@ID(custom: "id", generatedBy: .database)
var id: Int?

// String ID example (supported out-of-box)
@ID
var id: String?

// Custom type (implement passageParseUserID and passageUserIDDataType)
@ID
var id: MyCustomID?
```

### Migration Control

Control which migrations are registered via the `registerMigrations:` parameter:

```swift
// Register Passage migrations (default = true)
let store = DatabaseStore(
    app: app,
    db: app.db,
    userModelType: AppUser.self,
    registerMigrations: true
)

// Manual control (advanced)
app.migrations.add(
    contentsOf: DatabaseStore.migrations(
        for: AppUser.self,
        includeIdentifiers: true,  // S1 mode
        isIslandMode: false
    )
)
```

### Alternative: `@Children` Pattern

If you don't override `PassageUserModel` hooks, derive Passage.User computed properties from the `identifiers` relationship:

```swift
extension AppUser: User {
    @Children(for: \.$user)
    var identifiers: [IdentifierModel<AppUser>]
    
    public var email: String? {
        identifiers.first { $0.type == "email" }?.value
    }
    
    public var isEmailVerified: Bool {
        identifiers.first { $0.type == "email" }?.verified == true
    }
}
```

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
