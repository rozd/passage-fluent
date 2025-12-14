import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("Database Integration Tests")
struct DatabaseIntegrationTests {

    // MARK: - Migration Tests

    @Test("All migrations run successfully")
    func testMigrationsRun() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Verify all tables exist by querying them
        let userCount = try await UserModel.query(on: app.db).count()
        let identifierCount = try await IdentifierModel.query(on: app.db).count()
        let tokenCount = try await RefreshTokenModel.query(on: app.db).count()
        let emailVerifCount = try await EmailVerificationCodeModel.query(on: app.db).count()
        let phoneVerifCount = try await PhoneVerificationCodeModel.query(on: app.db).count()
        let emailResetCount = try await EmailPasswordResetCodeModel.query(on: app.db).count()
        let phoneResetCount = try await PhonePasswordResetCodeModel.query(on: app.db).count()
        let exchangeCount = try await ExchangeTokenModel.query(on: app.db).count()

        #expect(userCount == 0)
        #expect(identifierCount == 0)
        #expect(tokenCount == 0)
        #expect(emailVerifCount == 0)
        #expect(phoneVerifCount == 0)
        #expect(emailResetCount == 0)
        #expect(phoneResetCount == 0)
        #expect(exchangeCount == 0)
    }

    @Test("Migrations can be reverted")
    func testMigrationsRevert() async throws {
        let app = try await createTestApplication()

        // Add migrations
        _ = DatabaseStore(app: app, db: app.db)

        // Run migrations
        try await app.autoMigrate()

        // Revert migrations
        try await app.autoRevert()

        // Shutdown
        try await app.asyncShutdown()
    }

    // MARK: - Cascade Delete Tests

    @Test("Deleting user cascades to identifiers")
    func testUserCascadeToIdentifiers() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user with identifier
        let user = try await store.users.create(
            identifier: .email("cascade@example.com"),
            with: nil
        )

        // Add more identifiers
        try await store.users.addIdentifier(.phone("+1234567890"), to: user, with: nil)

        // Verify identifiers exist
        let identifierCount = try await IdentifierModel.query(on: app.db).count()
        #expect(identifierCount == 2)

        // Delete user directly
        let userModel = user as! UserModel
        try await userModel.delete(on: app.db)

        // Identifiers should be cascade deleted
        let finalIdentifierCount = try await IdentifierModel.query(on: app.db).count()
        #expect(finalIdentifierCount == 0)
    }

    @Test("Deleting user cascades to refresh tokens")
    func testUserCascadeToRefreshTokens() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user with tokens
        let user = try await store.users.create(
            identifier: .email("cascade@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(86400)
        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hash1",
            expiresAt: expiresAt
        )
        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hash2",
            expiresAt: expiresAt
        )

        // Verify tokens exist
        let tokenCount = try await RefreshTokenModel.query(on: app.db).count()
        #expect(tokenCount == 2)

        // Delete user directly
        let userModel = user as! UserModel
        try await userModel.delete(on: app.db)

        // Tokens should be cascade deleted
        let finalTokenCount = try await RefreshTokenModel.query(on: app.db).count()
        #expect(finalTokenCount == 0)
    }

    @Test("Deleting user cascades to verification codes")
    func testUserCascadeToVerificationCodes() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user with verification codes
        let user = try await store.users.create(
            identifier: .email("cascade@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.verificationCodes.createEmailCode(
            for: user,
            email: "cascade@example.com",
            codeHash: "hash1",
            expiresAt: expiresAt
        )

        // Verify code exists
        let codeCount = try await EmailVerificationCodeModel.query(on: app.db).count()
        #expect(codeCount == 1)

        // Delete user directly
        let userModel = user as! UserModel
        try await userModel.delete(on: app.db)

        // Code should be cascade deleted
        let finalCodeCount = try await EmailVerificationCodeModel.query(on: app.db).count()
        #expect(finalCodeCount == 0)
    }

    @Test("Deleting user cascades to reset codes")
    func testUserCascadeToResetCodes() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user with reset code
        let user = try await store.users.create(
            identifier: .email("cascade@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.restorationCodes.createPasswordResetCode(
            for: user,
            email: "cascade@example.com",
            codeHash: "resethash",
            expiresAt: expiresAt
        )

        // Verify code exists
        let codeCount = try await EmailPasswordResetCodeModel.query(on: app.db).count()
        #expect(codeCount == 1)

        // Delete user directly
        let userModel = user as! UserModel
        try await userModel.delete(on: app.db)

        // Code should be cascade deleted
        let finalCodeCount = try await EmailPasswordResetCodeModel.query(on: app.db).count()
        #expect(finalCodeCount == 0)
    }

    @Test("Deleting user cascades to exchange tokens")
    func testUserCascadeToExchangeTokens() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user with exchange token
        let user = try await store.users.create(
            identifier: .email("cascade@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(60)
        _ = try await store.exchangeTokens.createExchangeToken(
            for: user,
            tokenHash: "exchangehash",
            expiresAt: expiresAt
        )

        // Verify token exists
        let tokenCount = try await ExchangeTokenModel.query(on: app.db).count()
        #expect(tokenCount == 1)

        // Delete user directly
        let userModel = user as! UserModel
        try await userModel.delete(on: app.db)

        // Token should be cascade deleted
        let finalTokenCount = try await ExchangeTokenModel.query(on: app.db).count()
        #expect(finalTokenCount == 0)
    }

    // MARK: - Unique Constraint Tests

    @Test("Unique constraint on identifier type, provider, value")
    func testIdentifierUniqueConstraint() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create first user with email
        _ = try await store.users.create(
            identifier: .email("unique@example.com"),
            with: nil
        )

        // Try to create second user with same email
        await #expect(throws: AuthenticationError.self) {
            _ = try await store.users.create(
                identifier: .email("unique@example.com"),
                with: nil
            )
        }
    }

    @Test("Same value different type is allowed")
    func testSameValueDifferentType() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user with value as email
        _ = try await store.users.create(
            identifier: .email("value123"),
            with: nil
        )

        // Create user with same value as username (different type)
        let user2 = try await store.users.create(
            identifier: .username("value123"),
            with: nil
        )

        #expect(user2.username == "value123")
    }

    @Test("Same federated value different provider is allowed")
    func testSameFederatedValueDifferentProvider() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user with google federated ID
        _ = try await store.users.create(
            identifier: .federated("google", userId: "user-123"),
            with: nil
        )

        // Create user with same ID but different provider
        let user2 = try await store.users.create(
            identifier: .federated("github", userId: "user-123"),
            with: nil
        )

        // User was successfully created (federated identifiers are separate)
        #expect(user2.id != nil)
    }

    // MARK: - Eager Loading Tests

    @Test("User eager loads identifiers")
    func testUserEagerLoadsIdentifiers() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user with multiple identifiers
        let user = try await store.users.create(
            identifier: .email("eager@example.com"),
            with: nil
        )
        try await store.users.addIdentifier(.phone("+1234567890"), to: user, with: nil)

        // Find user - should have identifiers loaded
        let foundUser = try await store.users.find(byId: (user.id as? UUID)!.uuidString)

        #expect(foundUser?.email == "eager@example.com")
        #expect(foundUser?.phone == "+1234567890")
    }

    @Test("Refresh token eager loads user with identifiers")
    func testRefreshTokenEagerLoadsUserAndIdentifiers() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and token
        let user = try await store.users.create(
            identifier: .email("eager@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(86400)
        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "tokenhash",
            expiresAt: expiresAt
        )

        // Find token - should have user and identifiers loaded
        let foundToken = try await store.tokens.find(refreshTokenHash: "tokenhash")

        #expect(foundToken?.user.email == "eager@example.com")
    }

    @Test("Verification code eager loads user with identifiers")
    func testVerificationCodeEagerLoadsUserAndIdentifiers() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and code
        let user = try await store.users.create(
            identifier: .email("eager@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.verificationCodes.createEmailCode(
            for: user,
            email: "eager@example.com",
            codeHash: "codehash",
            expiresAt: expiresAt
        )

        // Find code - should have user and identifiers loaded
        let foundCode = try await store.verificationCodes.findEmailCode(
            forEmail: "eager@example.com",
            codeHash: "codehash"
        )

        #expect(foundCode?.user.email == "eager@example.com")
    }

    // MARK: - Transaction Tests

    @Test("User creation is atomic")
    func testUserCreationAtomic() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user - this should be atomic (user + identifier created together)
        let user = try await store.users.create(
            identifier: .email("atomic@example.com"),
            with: .password("password")
        )

        // Verify both user and identifier exist
        let userCount = try await UserModel.query(on: app.db).count()
        let identifierCount = try await IdentifierModel.query(on: app.db).count()

        #expect(userCount == 1)
        #expect(identifierCount == 1)

        // Verify they're linked
        let foundUser = try await store.users.find(byIdentifier: .email("atomic@example.com"))
        #expect(foundUser?.id as? UUID == user.id as? UUID)
    }
}
