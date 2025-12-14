import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("DatabaseStore Tests")
struct DatabaseStoreTests {

    // MARK: - Initialization Tests

    @Test("DatabaseStore initializes with all sub-stores")
    func testInitialization() async throws {
        let app = try await createTestApplication()
        defer { Task { try? await shutdownTestApplication(app) } }

        let store = DatabaseStore(app: app, db: app.db)

        #expect(store.users is DatabaseStore.UserStore)
        #expect(store.tokens is DatabaseStore.TokenStore)
        #expect(store.verificationCodes is DatabaseStore.VerificationCodeStore)
        #expect(store.restorationCodes is DatabaseStore.ResetCodeStore)
        #expect(store.magicLinkTokens is DatabaseStore.MagicLinkTokenStore)
        #expect(store.exchangeTokens is DatabaseStore.ExchangeTokenStore)
    }

    @Test("DatabaseStore registers all migrations")
    func testMigrationsRegistered() async throws {
        let app = try await createTestApplication()
        defer { Task { try? await shutdownTestApplication(app) } }

        _ = DatabaseStore(app: app, db: app.db)

        // Run migrations - this will fail if migrations aren't properly registered
        try await app.autoMigrate()

        // Verify tables exist by attempting queries
        let users = try await UserModel.query(on: app.db).count()
        #expect(users == 0)

        let identifiers = try await IdentifierModel.query(on: app.db).count()
        #expect(identifiers == 0)

        let tokens = try await RefreshTokenModel.query(on: app.db).count()
        #expect(tokens == 0)

        let emailCodes = try await EmailVerificationCodeModel.query(on: app.db).count()
        #expect(emailCodes == 0)

        let phoneCodes = try await PhoneVerificationCodeModel.query(on: app.db).count()
        #expect(phoneCodes == 0)

        let emailResetCodes = try await EmailPasswordResetCodeModel.query(on: app.db).count()
        #expect(emailResetCodes == 0)

        let phoneResetCodes = try await PhonePasswordResetCodeModel.query(on: app.db).count()
        #expect(phoneResetCodes == 0)

        let exchangeTokens = try await ExchangeTokenModel.query(on: app.db).count()
        #expect(exchangeTokens == 0)
    }
}

// MARK: - UserStore Tests

@Suite("DatabaseStore.UserStore Tests")
struct UserStoreTests {

    // MARK: - Find By ID Tests

    @Test("find(byId:) returns nil for invalid UUID string")
    func testFindByIdInvalidUUID() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let result = try await store.users.find(byId: "not-a-uuid")
        #expect(result == nil)
    }

    @Test("find(byId:) returns nil when user doesn't exist")
    func testFindByIdNonExistent() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let result = try await store.users.find(byId: UUID().uuidString)
        #expect(result == nil)
    }

    @Test("find(byId:) returns user when exists")
    func testFindByIdExists() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create a user directly
        let user = UserModel(passwordHash: "hash")
        try await user.save(on: app.db)
        let identifier = IdentifierModel(
            userID: try user.requireID(),
            type: "email",
            value: "test@example.com"
        )
        try await identifier.save(on: app.db)

        let result = try await store.users.find(byId: user.id!.uuidString)

        #expect(result != nil)
        #expect(result?.id as? UUID == user.id)
    }

    // MARK: - Create Tests

    @Test("create with email identifier creates user and identifier")
    func testCreateWithEmail() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let identifier = Identifier.email("test@example.com")
        let credential = Credential.password("hashedpassword")

        let user = try await store.users.create(identifier: identifier, with: credential)

        #expect(user.email == "test@example.com")
        #expect(user.passwordHash == "hashedpassword")
        #expect(user.isEmailVerified == false)
    }

    @Test("create with phone identifier creates user and identifier")
    func testCreateWithPhone() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let identifier = Identifier.phone("+1234567890")
        let credential = Credential.password("hashedpassword")

        let user = try await store.users.create(identifier: identifier, with: credential)

        #expect(user.phone == "+1234567890")
        #expect(user.passwordHash == "hashedpassword")
        #expect(user.isPhoneVerified == false)
    }

    @Test("create with username identifier creates user and identifier")
    func testCreateWithUsername() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let identifier = Identifier.username("testuser")
        let credential = Credential.password("hashedpassword")

        let user = try await store.users.create(identifier: identifier, with: credential)

        #expect(user.username == "testuser")
        #expect(user.passwordHash == "hashedpassword")
    }

    @Test("create with federated identifier creates pre-verified user")
    func testCreateWithFederated() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let identifier = Identifier.federated("google", userId: "google-user-123")

        let user = try await store.users.create(identifier: identifier, with: nil)

        #expect(user.passwordHash == nil)
        #expect(user.isAnonymous == true) // Federated doesn't count as email/phone/username
    }

    @Test("create without credential creates user without password")
    func testCreateWithoutCredential() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let identifier = Identifier.email("test@example.com")

        let user = try await store.users.create(identifier: identifier, with: nil)

        #expect(user.email == "test@example.com")
        #expect(user.passwordHash == nil)
    }

    @Test("create throws error when identifier already exists")
    func testCreateDuplicateIdentifier() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let identifier = Identifier.email("test@example.com")

        // Create first user
        _ = try await store.users.create(identifier: identifier, with: nil)

        // Try to create second user with same identifier
        await #expect(throws: AuthenticationError.self) {
            _ = try await store.users.create(identifier: identifier, with: nil)
        }
    }

    // MARK: - Find By Identifier Tests

    @Test("find(byIdentifier:) returns nil when not found")
    func testFindByIdentifierNotFound() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let result = try await store.users.find(byIdentifier: .email("nonexistent@example.com"))
        #expect(result == nil)
    }

    @Test("find(byIdentifier:) returns user when found")
    func testFindByIdentifierFound() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let identifier = Identifier.email("test@example.com")
        _ = try await store.users.create(identifier: identifier, with: nil)

        let result = try await store.users.find(byIdentifier: identifier)

        #expect(result != nil)
        #expect(result?.email == "test@example.com")
    }

    @Test("find(byIdentifier:) finds federated identifier with provider")
    func testFindByFederatedIdentifier() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let identifier = Identifier.federated("google", userId: "google-user-123")
        _ = try await store.users.create(identifier: identifier, with: nil)

        let result = try await store.users.find(byIdentifier: identifier)

        #expect(result != nil)
    }

    // MARK: - Add Identifier Tests

    @Test("addIdentifier adds new identifier to existing user")
    func testAddIdentifier() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user with email
        let emailIdentifier = Identifier.email("test@example.com")
        let user = try await store.users.create(identifier: emailIdentifier, with: nil)

        // Add phone identifier
        let phoneIdentifier = Identifier.phone("+1234567890")
        try await store.users.addIdentifier(phoneIdentifier, to: user, with: nil)

        // Verify
        let foundUser = try await store.users.find(byIdentifier: phoneIdentifier)
        #expect(foundUser?.phone == "+1234567890")
    }

    @Test("addIdentifier throws error for duplicate identifier")
    func testAddIdentifierDuplicate() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let identifier = Identifier.email("test@example.com")

        // Create first user
        let user1 = try await store.users.create(identifier: identifier, with: nil)

        // Create second user with different email
        let user2 = try await store.users.create(
            identifier: .email("other@example.com"),
            with: nil
        )

        // Try to add same email to second user
        await #expect(throws: AuthenticationError.self) {
            try await store.users.addIdentifier(identifier, to: user2, with: nil)
        }
    }

    @Test("addIdentifier with credential updates password")
    func testAddIdentifierWithCredential() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user without password (federated)
        let federatedIdentifier = Identifier.federated("google", userId: "google-123")
        let user = try await store.users.create(identifier: federatedIdentifier, with: nil)

        #expect(user.passwordHash == nil)

        // Add email with password
        let emailIdentifier = Identifier.email("test@example.com")
        let credential = Credential.password("newpassword")
        try await store.users.addIdentifier(emailIdentifier, to: user, with: credential)

        // Reload user
        let foundUser = try await store.users.find(byIdentifier: emailIdentifier)
        #expect(foundUser?.passwordHash == "newpassword")
    }

    // MARK: - Mark Verified Tests

    @Test("markEmailVerified sets email identifier as verified")
    func testMarkEmailVerified() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let identifier = Identifier.email("test@example.com")
        let user = try await store.users.create(identifier: identifier, with: nil)

        #expect(user.isEmailVerified == false)

        try await store.users.markEmailVerified(for: user)

        let foundUser = try await store.users.find(byIdentifier: identifier)
        #expect(foundUser?.isEmailVerified == true)
    }

    @Test("markPhoneVerified sets phone identifier as verified")
    func testMarkPhoneVerified() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let identifier = Identifier.phone("+1234567890")
        let user = try await store.users.create(identifier: identifier, with: nil)

        #expect(user.isPhoneVerified == false)

        try await store.users.markPhoneVerified(for: user)

        let foundUser = try await store.users.find(byIdentifier: identifier)
        #expect(foundUser?.isPhoneVerified == true)
    }

    // MARK: - Set Password Tests

    @Test("setPassword updates user password hash")
    func testSetPassword() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let identifier = Identifier.email("test@example.com")
        let user = try await store.users.create(identifier: identifier, with: nil)

        #expect(user.passwordHash == nil)

        try await store.users.setPassword(for: user, passwordHash: "newpasswordhash")

        let foundUser = try await store.users.find(byIdentifier: identifier)
        #expect(foundUser?.passwordHash == "newpasswordhash")
    }

    // MARK: - Unimplemented Methods Tests

    @Test("createWithEmail throws not implemented error")
    func testCreateWithEmailNotImplemented() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        await #expect(throws: PassageError.self) {
            _ = try await store.users.createWithEmail("test@example.com", verified: false)
        }
    }

    @Test("createWithPhone throws not implemented error")
    func testCreateWithPhoneNotImplemented() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        await #expect(throws: PassageError.self) {
            _ = try await store.users.createWithPhone("+1234567890", verified: false)
        }
    }
}
