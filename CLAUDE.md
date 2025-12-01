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

**Migrations** (`Sources/IdentityFluent/Migrations/`)
- One migration per model, all use `AsyncMigration`

### Key Patterns

- All models use `@unchecked Sendable` for Vapor concurrency
- Fluent property wrappers: `@ID`, `@Field`, `@OptionalField`, `@Timestamp`, `@Parent`, `@Children`
- Type-safe filtering with key paths (e.g., `\.$email == email`)
- Nested eager loading via `.with(\.$user) { user in user.with(\.$identifiers) }`
- Token rotation uses `replacedBy` field to track token chain for family revocation

### Dependencies

- Requires sibling `vapor-identity` package at `../vapor-identity`
- Built on Fluent 4.13+ and targets macOS 13+
