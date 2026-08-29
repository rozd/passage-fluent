import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

/// Integration tests for S1 overlay mode (custom user model, default stores).
/// Exercises the Passage.Store protocol APIs with AppUser (Int ID, stored email_verified).
@Suite("Overlay Mode S1 Integration Tests")
struct OverlayStoreIntegrationTests {

    @Test("Create user via store")
    func testCreateUser() async throws {
        let app = try await createTestApplicationForOverlay()
        defer { Task { try? await shutdownTestApplication(app) } }

        let store = DatabaseStore(
            app: app,
            db: app.db,
            userModelType: AppUser.self
        )
        try await app.autoMigrate()

        let identifier = Identifier.email("test@example.com")
        let credential = Credential.password("hashedpassword123")

        let user = try await store.users.create(identifier: identifier, with: credential)

        #expect(user.email == "test@example.com")
        #expect(user.isEmailVerified == false)
    }

    @Test("Find user by identifier")
    func testFindByIdentifier() async throws {
        let app = try await createTestApplicationForOverlay()
        defer { Task { try? await shutdownTestApplication(app) } }

        let store = DatabaseStore(
            app: app,
            db: app.db,
            userModelType: AppUser.self
        )
        try await app.autoMigrate()

        let identifier = Identifier.email("user@example.com")
        _ = try await store.users.create(identifier: identifier, with: nil)

        let found = try await store.users.find(byIdentifier: identifier)
        #expect(found != nil)
        #expect(found?.email == "user@example.com")
    }

    @Test("Find user by ID (Int string round-trip)")
    func testFindByID() async throws {
        let app = try await createTestApplicationForOverlay()
        defer { Task { try? await shutdownTestApplication(app) } }

        let store = DatabaseStore(
            app: app,
            db: app.db,
            userModelType: AppUser.self
        )
        try await app.autoMigrate()

        let user = try await store.users.create(identifier: .email("test@example.com"), with: nil)
        guard let appUser = user as? AppUser, let userId = appUser.id else {
            #expect(Bool(false), "User must be AppUser with Int id")
            return
        }

        // Round-trip: Int -> String -> Int
        let userStringId = String(describing: userId)
        let found = try await store.users.find(byId: userStringId)

        #expect(found != nil)
        #expect((found as? AppUser)?.id == userId)
    }

    @Test("Int ID parsing")
    func testIntIDParsing() async throws {
        let app = try await createTestApplicationForOverlay()
        defer { Task { try? await shutdownTestApplication(app) } }

        let store = DatabaseStore(
            app: app,
            db: app.db,
            userModelType: AppUser.self
        )
        try await app.autoMigrate()

        let user = try await store.users.create(identifier: .email("parse@example.com"), with: nil)
        guard let appUser = user as? AppUser, let userId = appUser.id else {
            #expect(Bool(false), "User must be AppUser with Int id")
            return
        }

        // Verify Int -> String round-trip works
        let stringId = String(describing: userId)
        #expect(Int(stringId) == userId)

        let found = try await store.users.find(byId: stringId)
        #expect((found as? AppUser)?.id == userId)
    }

    @Test("Duplicate identifier throws")
    func testDuplicateIdentifierThrows() async throws {
        let app = try await createTestApplicationForOverlay()
        defer { Task { try? await shutdownTestApplication(app) } }

        let store = DatabaseStore(
            app: app,
            db: app.db,
            userModelType: AppUser.self
        )
        try await app.autoMigrate()

        let identifier = Identifier.email("duplicate@example.com")
        _ = try await store.users.create(identifier: identifier, with: nil)

        do {
            _ = try await store.users.create(identifier: identifier, with: nil)
            #expect(Bool(false), "Should throw on duplicate identifier")
        } catch {
            #expect(Bool(true), "Correctly threw on duplicate")
        }
    }

    @Test("Refresh token lifecycle with Int FK")
    func testRefreshTokenLifecycle() async throws {
        let app = try await createTestApplicationForOverlay()
        defer { Task { try? await shutdownTestApplication(app) } }

        let store = DatabaseStore(
            app: app,
            db: app.db,
            userModelType: AppUser.self
        )
        try await app.autoMigrate()

        let user = try await store.users.create(identifier: .email("test@example.com"), with: nil)
        let futureDate = Date().addingTimeInterval(3600)

        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "testhash",
            expiresAt: futureDate, sessionId: UUID()
        )

        let found = try await store.tokens.find(refreshTokenHash: "testhash")
        #expect(found != nil)

        // Revoke
        try await store.tokens.revokeRefreshTokens(for: user)
        let revoked = try await store.tokens.find(refreshTokenHash: "testhash")
        #expect(revoked?.revokedAt != nil)
    }

    @Test("Email verification syncs to AppUser.email_verified column")
    func testEmailVerificationSync() async throws {
        let app = try await createTestApplicationForOverlay()
        defer { Task { try? await shutdownTestApplication(app) } }

        let store = DatabaseStore(
            app: app,
            db: app.db,
            userModelType: AppUser.self
        )
        try await app.autoMigrate()

        let user = try await store.users.create(identifier: .email("verify@example.com"), with: nil)

        // Initially not verified
        #expect(user.isEmailVerified == false)

        // Mark verified through store
        try await store.verificationCodes.createEmailCode(
            for: user,
            email: "verify@example.com",
            codeHash: "hash",
            expiresAt: Date().addingTimeInterval(3600)
        )

        try await store.users.markEmailVerified(for: user)

        // Reload user and verify both identifier and user column are synced
        let reloaded = try await store.users.find(byIdentifier: .email("verify@example.com")) as? AppUser
        #expect(reloaded?.isEmailVerified == true)
    }

    @Test("Magic link with nil user")
    func testMagicLinkWithNilUser() async throws {
        let app = try await createTestApplicationForOverlay()
        defer { Task { try? await shutdownTestApplication(app) } }

        let store = DatabaseStore(
            app: app,
            db: app.db,
            userModelType: AppUser.self
        )
        try await app.autoMigrate()

        _ = try await store.magicLinkTokens.createEmailMagicLink(
            for: nil,
            identifier: .email("new@example.com"),
            tokenHash: "magichash",
            sessionTokenHash: nil,
            expiresAt: Date().addingTimeInterval(3600)
        )

        let found = try await store.magicLinkTokens.findEmailMagicLink(tokenHash: "magichash")
        #expect(found != nil)
    }

    @Test("Passkey challenge with and without user")
    func testPasskeyChallengeWithUser() async throws {
        let app = try await createTestApplicationForOverlay()
        defer { Task { try? await shutdownTestApplication(app) } }

        let store = DatabaseStore(
            app: app,
            db: app.db,
            userModelType: AppUser.self
        )
        try await app.autoMigrate()

        let user = try await store.users.create(identifier: .email("passkey@example.com"), with: nil)
        let challengeBytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let challenge = PasskeyChallenge(bytes: challengeBytes, kind: .registration, expiresAt: Date().addingTimeInterval(600))

        let stored = try await store.passkeyChallenges?.createPasskeyChallenge(for: user, from: challenge)
        #expect(stored != nil)

        let found = try await store.passkeyChallenges?.find(passkeyChallengeMatching: challengeBytes)
        #expect(found != nil)
    }

    @Test("createWithEmail in overlay mode")
    func testCreateWithEmailInOverlayMode() async throws {
        let app = try await createTestApplicationForOverlay()
        defer { Task { try? await shutdownTestApplication(app) } }

        let store = DatabaseStore(
            app: app,
            db: app.db,
            userModelType: AppUser.self
        )
        try await app.autoMigrate()

        let user = try await store.users.createWithEmail("overlay-user@example.com", verified: true)
        #expect(user.email == "overlay-user@example.com")
        #expect(user.isEmailVerified == true)

        let found = try await store.users.find(byIdentifier: .email("overlay-user@example.com"))
        #expect(found?.email == "overlay-user@example.com")
        #expect(found?.isEmailVerified == true)
        #expect((found as? AppUser)?.emailVerified == true)
    }

    @Test("No 'users' table exists; migrations correct")
    func testNoUsersTableAndCorrectMigrations() async throws {
        let app = try await createTestApplicationForOverlay()
        defer { Task { try? await shutdownTestApplication(app) } }

        _ = DatabaseStore(
            app: app,
            db: app.db,
            userModelType: AppUser.self
        )
        try await app.autoMigrate()

        guard let sqlDb = app.db as? any SQLDatabase else {
            #expect(Bool(false), "Database must be SQLDatabase")
            return
        }

        // Verify 'users' table does not exist
        let tablesResult = try await sqlDb.raw("SELECT name FROM sqlite_master WHERE type='table' AND name='users'").all()
        #expect(tablesResult.isEmpty, "Should not create 'users' table in overlay mode")

        // Verify 'app_users' table exists
        let appUsersResult = try await sqlDb.raw("SELECT name FROM sqlite_master WHERE type='table' AND name='app_users'").all()
        #expect(!appUsersResult.isEmpty, "Should create 'app_users' table")

        // Verify migrations don't include CreateUserModel
        let migrations = try await sqlDb.raw("SELECT name FROM _fluent_migrations ORDER BY name").all()
        let migrationNames = try migrations.map { row in try row.decode(column: "name", as: String.self) }

        #expect(!migrationNames.contains("PassageFluent.CreateUserModel"), "S1 should not register CreateUserModel")
        #expect(migrationNames.contains("PassageFluent.CreateIdentifierModel"), "S1 should register CreateIdentifierModel")
    }
}
