# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build the package
swift build

# Build for release
swift build -c release

# Resolve dependencies
swift package resolve
```

## Architecture

This is a Swift package that provides a Fluent-backed implementation of the `Passage.Store` protocol for persistent storage in Vapor applications. It supports both **island mode** (manages its own user table) and **overlay mode** (integrates with existing user tables).

### Core Components

**DatabaseStore** (`Sources/PassageFluent/DatabaseStore.swift`)
- Main entry point implementing `Passage.Store` protocol
- Composes 8 generic sub-stores from `Sources/PassageFluent/Stores/`
- Three initialization modes:
  - **Island mode** `init(app:db:)` — creates its own `users`/`identifiers` tables
  - **Overlay S1** `init<U>(app:db:userModelType:registerMigrations:)` — inject custom user model
  - **Overlay S3** `init<U>(app:db:userModelType:userStore:registerMigrations:)` — inject model + custom store factory `(any Database) -> any Passage.UserStore`; the factory is re-invoked with the transaction connection by `transaction(_:)` so custom user writes stay inside the transaction
- Migration registration with explicit control over island/overlay migrations

**PassageUserModel Protocol** (`Sources/PassageFluent/PassageUserModel.swift`)
- Protocol for user models to opt into generic store support
- Hooks: `passageMakeUser` (factory), `passageEagerLoad` (relations), `passageRefresh` (post-save load), `passageDidMarkIdentifierVerified` (verification sync)
- Constrained defaults for UUID, Int, and String ID types
- Constraint: `where Id == IDValue` ensures JWT sub/sessionID string round-trip via `passageParseUserID` is coherent
- Documented conformance requirements: `final class`, `@unchecked Sendable`, `SessionAuthenticatable`, standard `@ID`, no `@CompositeID`

**Generic Models** (`Sources/PassageFluent/Model/`)
- All 10 dependent models are generic over `<U: PassageUserModel>`: `RefreshTokenModel<U>`, `IdentifierModel<U>`, `EmailVerificationCodeModel<U>`, `PhoneVerificationCodeModel<U>`, `EmailPasswordResetCodeModel<U>`, `PhonePasswordResetCodeModel<U>`, `ExchangeTokenModel<U>`, `PasskeyCredentialModel<U>`, `MagicLinkTokenModel<U>`, `PasskeyChallengeModel<U>`
- `IdentifierModel<U>` is public (apps use it for overlay mode with custom Passage.User props)
- `UserModel` is the built-in island-mode model; conforms to `PassageUserModel` with `passageEagerLoad` loading `identifiers`, and `passageRefresh` loading them post-save
- `static var schema: String` (computed property required for generic types, not `static let`)

**Generic Sub-Stores** (`Sources/PassageFluent/Stores/`)
- 8 files, each defining a struct nested in `extension DatabaseStore`:
  - `UserStore<U>: Passage.UserStore` — user creation, lookup, verification syncing via `passageDidMarkIdentifierVerified` hook
  - `TokenStore<U>: Passage.TokenStore` — refresh token lifecycle
  - `VerificationCodeStore<U>: Passage.VerificationCodeStore` — email/phone verification codes
  - `ResetCodeStore<U>: Passage.RestorationCodeStore` — password reset codes
  - `MagicLinkTokenStore<U>: Passage.MagicLinkTokenStore` — magic link tokens
  - `ExchangeTokenStore<U>: Passage.ExchangeTokenStore` — OAuth exchange tokens
  - `PasskeyCredentialStore<U>: Passage.PasskeyCredentialStore` — W3C credentials
  - `PasskeyChallengeStore<U>: Passage.PasskeyChallengeStore` — WebAuthn challenges
- All use `U.passageEagerLoad` at eager-load sites, `passageRefresh` at post-save hydration, `as? U` for downcasts

**Generic Migrations** (`Sources/PassageFluent/Migrations/`)
- 10 generic migrations + 1 island-only migration (CreateUserModel.swift, left untouched)
- All generic migrations have explicit `var name: String` pinned to exact legacy strings (`"PassageFluent.CreateXModel"`)
- **CRITICAL:** Migration names are frozen forever — never change them. Existing databases will re-run migrations if names change.
- FK definitions use `U.passageUserIDDataType`, `U.schema`, `U.space`, `U.passageUserIDFieldKey`
- Migration registration matrix:
  - Island: CreateUserModel + CreateIdentifierModel + 9 dependent
  - S1: CreateIdentifierModel + 9 dependent (skip CreateUserModel)
  - S3: 9 dependent only (skip CreateUserModel and CreateIdentifierModel)

### Key Patterns

**Overlay Mode Workflow**
1. App defines user model conforming to `PassageUserModel` (see example in README)
2. App registers its own user-table migration BEFORE creating DatabaseStore
3. App creates `DatabaseStore(app:db:userModelType: MyUser.self)` (S1) or adds custom `userStore:` (S3)
4. PassageFluent skips the `users` migration (S1) or both `users` and `identifiers` (S3); the generic sub-stores are erased behind the existing `any Passage.XStore` properties, so `Passage.Store` conformance is unchanged

**Eager Loading and Post-Save Hydration**
- `PassageUserModel.passageEagerLoad` called on QueryBuilder at all fetch sites (~13 nested)
- `passageRefresh(on:)` called post-save to load relations (replaces in-memory `$children.value` priming in island mode)
- DefaultUserModel overrides both: eager load with `.with(\.$identifiers)`, refresh with `try await self.$identifiers.load(on: db)`

**Verification Sync Hook**
- After store marks IdentifierModel rows verified, calls `passageDidMarkIdentifierVerified` on the user model type so models backing `isEmailVerified`/`isPhoneVerified` via own columns can sync
- AppUser example: set `email_verified = true` and save

**Type-Safe FK Filtering**
- Generic stores use `\._$id` keypath for ID filtering (public route into FluentKit's ID column)
- `find(byId:)` uses the user model's `passageParseUserID` to parse String back to native IDValue

### Supported ID Types

**Out-of-box defaults (via constrained `PassageUserModel` extensions):**
- UUID: `passageParseUserID(_ string: String) -> UUID?` via `UUID(uuidString:)`; `passageUserIDDataType = .uuid`
- Int: `passageParseUserID(_ string: String) -> Int?` via `Int(_:)`; `passageUserIDDataType = .int`
- String: `passageParseUserID(_ string: String) -> String?` identity; `passageUserIDDataType = .string`

**Custom types:**
- Conform to `PassageUserModel` and override `passageParseUserID` and `passageUserIDDataType`
- Example: custom UUID wrapper, ULID, or Hashids-encoded Int

### Dependencies

- Vapor 4.121+
- Fluent 4.13+
- Passage 0.5.12+ (remote dependency: vapor-community/passage)
- Swift tools 6.3, macOS 13+

### Testing

- `Tests/PassageFluentTests/TestHelpers.swift` — module-level typealiases bind generics to `DefaultUserModel` (including a test-only `typealias UserModel = DefaultUserModel`) so existing tests compile unchanged
- `Tests/PassageFluentTests/Unit/MigrationNameTests.swift` — verifies all 11 migration names are pinned, guards against re-run on deployed databases
- `Tests/PassageFluentTests/Overlay/OverlayFixtures.swift` — AppUser fixture (Int ID, stored email_verified) + helper
- `Tests/PassageFluentTests/Overlay/OverlayStoreIntegrationTests.swift` — S1 mode via Passage.Store APIs (create, find, verify, token lifecycle)
- `Tests/PassageFluentTests/Overlay/CustomUserStoreIntegrationTests.swift` — S3 mode with custom AppUserStore (no identifiers table)
