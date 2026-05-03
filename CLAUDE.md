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

This is a Swift package that provides a Fluent (database) implementation of the `Identity.Store` protocol from the companion `vapor-identity` package. It enables persistent storage for user identity management in Vapor applications.

### Core Components

**DatabaseStore** (`Sources/IdentityFluent/DatabaseStore.swift`)
- Main entry point implementing `Identity.Store`
- Composes four sub-stores: `UserStore`, `TokenStore`, `CodeStore`, `ResetCodeStore`
- Automatically registers all migrations on initialization

**Models** (`Sources/IdentityFluent/Model/`)
- `UserModel` - Core user entity with password hash; conforms to `Identity.User`
- `IdentifierModel` - Polymorphic user identifiers (email, phone, username) linked to users via parent relationship
- `RefreshTokenModel` - JWT refresh tokens with rotation/revocation chain tracking
- `EmailVerificationCodeModel` / `PhoneVerificationCodeModel` - Verification codes with expiration and attempt tracking
- `EmailResetCodeModel` / `PhoneResetCodeModel` - Password reset codes
- `PasskeyCredentialModel` - W3C credential record (credential ID, COSE public key, sign count, transports, backup state, AAGUID, attestation format); conforms to `Passage.StoredPasskeyCredential`
- `PasskeyChallengeModel` - One-shot WebAuthn challenge; stores SHA-256 hash (never plain bytes), TTL, consumption timestamp; `@OptionalParent` user (set during authenticated registration) and `@OptionalField` identifier (set during guest registration before the user exists); conforms to `Passage.StoredPasskeyChallenge`

**Migrations** (`Sources/IdentityFluent/Migrations/`)
- One migration per model, all use `AsyncMigration`

### Key Patterns

- All models use `@unchecked Sendable` for Vapor concurrency
- Fluent property wrappers: `@ID`, `@Field`, `@OptionalField`, `@Timestamp`, `@Parent`, `@OptionalParent`, `@Children`
- Type-safe filtering with key paths (e.g., `\.$email == email`)
- Nested eager loading via `.with(\.$user) { user in user.with(\.$identifiers) }`
- Token rotation uses `replacedBy` field to track token chain for family revocation
- Passkey challenges are hashed at the store boundary via `Data.sha256Hex` from the `Passage` package — callers pass raw bytes to one of the three `createPasskeyChallenge` overloads (`from:` for discoverable auth, `for: User, from:` for an authenticated user adding a passkey, `for: Identifier, from:` for guest registration) and to `find(passkeyChallengeMatching:)`, and the column is indexed on the hash

### Optional Passkey Sub-Stores

The `Passage.Store` protocol defines `passkeyCredentials` and `passkeyChallenges` with default-nil extensions. `DatabaseStore` overrides both defaults with concrete `PasskeyCredentialStore` / `PasskeyChallengeStore` implementations, so Passage's passkey routes work as soon as a `PasskeyService` is provided. The `passkey_credentials` and `passkey_challenges` migrations register automatically alongside the other tables.

### Dependencies

- Requires sibling `vapor-identity` package at `../vapor-identity`
- Built on Fluent 4.13+ and targets macOS 13+
