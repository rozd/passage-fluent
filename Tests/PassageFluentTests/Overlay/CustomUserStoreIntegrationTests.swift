import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

// MARK: - AppUserStore (Custom S3 Store)

/// Custom user store implementation that operates directly on AppUser columns.
/// Demonstrates S3 overlay mode: neither users nor identifiers tables are created.
struct AppUserStore: Passage.UserStore {
    typealias ConcreateUser = AppUser

    let db: any Database

    var userType: AppUser.Type { AppUser.self }

    func find(byId id: String) async throws -> (any User)? {
        guard let intId = Int(id) else { return nil }
        return try await AppUser.find(intId, on: db)
    }

    func create(identifier: Identifier, with credential: Credential?) throws -> (any User) {
        throw PassageError.unexpected(message: "Not implemented for custom store")
    }

    func find(byIdentifier identifier: Identifier) async throws -> (any User)? {
        // Only handle email identifiers for this demo
        guard identifier.kind == .email else { return nil }
        return try await AppUser.query(on: db)
            .filter(\.$storedEmail == identifier.value)
            .first()
    }

    func addIdentifier(_ identifier: Identifier, to user: any User, with credential: Credential?) async throws {
        throw PassageError.unexpected(message: "Not implemented for custom store")
    }

    func markEmailVerified(for user: any User) async throws {
        guard let appUser = user as? AppUser else { return }
        appUser.emailVerified = true
        try await appUser.save(on: db)
    }

    func markPhoneVerified(for user: any User) async throws {
        // No-op for custom store
    }

    func setPassword(for user: any User, passwordHash: String) async throws {
        guard let appUser = user as? AppUser else { return }
        appUser.passwordHash = passwordHash
        try await appUser.save(on: db)
    }

    func createWithEmail(_ email: String, verified: Bool) async throws -> any User {
        throw PassageError.unexpected(message: "Not implemented for custom store")
    }

    func createWithPhone(_ phone: String, verified: Bool) async throws -> any User {
        throw PassageError.unexpected(message: "Not implemented for custom store")
    }
}

// MARK: - Custom Store Integration Tests

@Suite("Overlay Mode S3 Integration Tests (Custom UserStore)")
struct CustomUserStoreIntegrationTests {

    @Test("Refresh token workflow with custom store")
    func testRefreshTokenWithCustomStore() async throws {
        let app = try await createTestApplicationForOverlay()
        defer { Task { try? await shutdownTestApplication(app) } }

        let store = DatabaseStore(
            app: app,
            db: app.db,
            userModelType: AppUser.self,
            userStore: { AppUserStore(db: $0) }
        )
        try await app.autoMigrate()

        // Create AppUser directly since custom store doesn't implement create
        try await app.db.transaction { db in
            let appUser = AppUser(
                email: "user@example.com",
                passwordHash: "hash123"
            )
            try await appUser.create(on: db)
        }

        // Find user via custom store
        let user = try await store.users.find(byIdentifier: .email("user@example.com"))
        #expect(user != nil)

        // Use token store (not custom, uses generic store)
        let futureDate = Date().addingTimeInterval(3600)
        _ = try await store.tokens.createRefreshToken(
            for: user!,
            tokenHash: "customtoken",
            expiresAt: futureDate, sessionId: UUID()
        )

        let found = try await store.tokens.find(refreshTokenHash: "customtoken")
        #expect(found != nil)
    }

    @Test("Verification code workflow with custom store")
    func testVerificationCodeWithCustomStore() async throws {
        let app = try await createTestApplicationForOverlay()
        defer { Task { try? await shutdownTestApplication(app) } }

        let store = DatabaseStore(
            app: app,
            db: app.db,
            userModelType: AppUser.self,
            userStore: { AppUserStore(db: $0) }
        )
        try await app.autoMigrate()

        try await app.db.transaction { db in
            let appUser = AppUser(email: "verify@example.com")
            try await appUser.create(on: db)
        }

        let user = try await store.users.find(byIdentifier: .email("verify@example.com"))
        #expect(user != nil)

        // Create verification code
        _ = try await store.verificationCodes.createEmailCode(
            for: user!,
            email: "verify@example.com",
            codeHash: "vcode",
            expiresAt: Date().addingTimeInterval(600)
        )

        let found = try await store.verificationCodes.findEmailCode(
            forEmail: "verify@example.com",
            codeHash: "vcode"
        )
        #expect(found != nil)

        // Mark verified via custom store
        try await store.users.markEmailVerified(for: user!)

        let reloaded = try await store.users.find(byId: String(describing: (user as! AppUser).id!))
        #expect((reloaded as? AppUser)?.isEmailVerified == true)
    }

    @Test("No 'users' or 'identifiers' tables; only app_users created")
    func testTablesAndMigrationsForS3() async throws {
        let app = try await createTestApplicationForOverlay()
        defer { Task { try? await shutdownTestApplication(app) } }

        _ = DatabaseStore(
            app: app,
            db: app.db,
            userModelType: AppUser.self,
            userStore: { AppUserStore(db: $0) }
        )
        try await app.autoMigrate()

        guard let sqlDb = app.db as? any SQLDatabase else {
            #expect(Bool(false), "Database must be SQLDatabase")
            return
        }

        // Verify no 'users' table
        let usersTable = try await sqlDb.raw("SELECT name FROM sqlite_master WHERE type='table' AND name='users'").all()
        #expect(usersTable.isEmpty, "S3 should not create 'users' table")

        // Verify no 'identifiers' table
        let identifiersTable = try await sqlDb.raw("SELECT name FROM sqlite_master WHERE type='table' AND name='identifiers'").all()
        #expect(identifiersTable.isEmpty, "S3 should not create 'identifiers' table")

        // Verify migrations exclude both CreateUserModel and CreateIdentifierModel
        let migrations = try await sqlDb.raw("SELECT name FROM _fluent_migrations ORDER BY name").all()
        let migrationNames = try migrations.map { row in try row.decode(column: "name", as: String.self) }

        #expect(!migrationNames.contains("PassageFluent.CreateUserModel"), "S3 should not register CreateUserModel")
        #expect(!migrationNames.contains("PassageFluent.CreateIdentifierModel"), "S3 should not register CreateIdentifierModel")
        #expect(migrationNames.contains("PassageFluent.CreateRefreshTokenModel"), "S3 should register dependent migrations")
    }

    @Test("Custom store user writes roll back with the DatabaseStore transaction")
    func testCustomStoreWritesRollBackInsideTransaction() async throws {
        let app = try await createTestApplicationForOverlay()
        defer { Task { try? await shutdownTestApplication(app) } }

        let store = DatabaseStore(
            app: app,
            db: app.db,
            userModelType: AppUser.self,
            userStore: { AppUserStore(db: $0) }
        )
        try await app.autoMigrate()

        try await app.db.transaction { db in
            try await AppUser(email: "tx@example.com").create(on: db)
        }
        let user = try #require(try await store.users.find(byIdentifier: .email("tx@example.com")))

        struct Rollback: Error {}
        await #expect(throws: Rollback.self) {
            try await store.transaction { bound in
                // Custom-store write (must run on the transaction connection)…
                try await bound.users.setPassword(for: user, passwordHash: "rolled-back")
                // …alongside a generic-store write.
                try await bound.tokens.createRefreshToken(
                    for: user, tokenHash: "rolled-back",
                    expiresAt: Date().addingTimeInterval(3600), sessionId: UUID()
                )
                throw Rollback()
            }
        }

        let appUserId = try #require((user as? AppUser)?.id)
        let reloaded = try #require(try await AppUser.find(appUserId, on: app.db))
        #expect(reloaded.passwordHash != "rolled-back", "custom user store write escaped the transaction")
        #expect(try await store.tokens.find(refreshTokenHash: "rolled-back") == nil)
    }
}
