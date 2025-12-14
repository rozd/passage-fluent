import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("UserModel Tests")
struct UserModelTests {

    // MARK: - Schema Tests

    @Test("Schema name is 'users'")
    func testSchemaName() {
        #expect(UserModel.schema == "users")
    }

    // MARK: - User Protocol Tests with Database

    @Test("Default initialization creates user with nil ID")
    func testDefaultInitialization() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        #expect(user.id != nil)
        // passwordHash defaults to nil when not set
    }

    @Test("Initialization with ID sets ID correctly")
    func testInitializationWithId() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let uuid = UUID()
        let user = UserModel(id: uuid)
        try await user.save(on: app.db)

        #expect(user.id == uuid)
    }

    @Test("Initialization with password hash sets password correctly")
    func testInitializationWithPasswordHash() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let passwordHash = "hashedpassword123"
        let user = UserModel(passwordHash: passwordHash)
        try await user.save(on: app.db)

        #expect(user.passwordHash == passwordHash)
    }

    @Test("Full initialization sets all provided values")
    func testFullInitialization() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let uuid = UUID()
        let passwordHash = "hashedpassword123"
        let user = UserModel(id: uuid, passwordHash: passwordHash)
        try await user.save(on: app.db)

        #expect(user.id == uuid)
        #expect(user.passwordHash == passwordHash)
    }

    // MARK: - isAnonymous Tests

    @Test("isAnonymous returns true when no identifiers")
    func testIsAnonymousWithNoIdentifiers() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)
        try await user.$identifiers.load(on: app.db)

        #expect(user.isAnonymous == true)
        #expect(user.email == nil)
        #expect(user.phone == nil)
        #expect(user.username == nil)
    }

    @Test("isAnonymous returns false when email identifier exists")
    func testIsAnonymousWithEmail() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let identifier = IdentifierModel(
            userID: try user.requireID(),
            type: "email",
            value: "test@example.com",
            verified: false
        )
        try await identifier.save(on: app.db)
        try await user.$identifiers.load(on: app.db)

        #expect(user.isAnonymous == false)
        #expect(user.email == "test@example.com")
    }

    @Test("isAnonymous returns false when phone identifier exists")
    func testIsAnonymousWithPhone() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let identifier = IdentifierModel(
            userID: try user.requireID(),
            type: "phone",
            value: "+1234567890",
            verified: false
        )
        try await identifier.save(on: app.db)
        try await user.$identifiers.load(on: app.db)

        #expect(user.isAnonymous == false)
        #expect(user.phone == "+1234567890")
    }

    @Test("isAnonymous returns false when username identifier exists")
    func testIsAnonymousWithUsername() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let identifier = IdentifierModel(
            userID: try user.requireID(),
            type: "username",
            value: "testuser",
            verified: false
        )
        try await identifier.save(on: app.db)
        try await user.$identifiers.load(on: app.db)

        #expect(user.isAnonymous == false)
        #expect(user.username == "testuser")
    }

    // MARK: - Email Verification Tests

    @Test("isEmailVerified returns false when no email identifier")
    func testIsEmailVerifiedWithNoEmail() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)
        try await user.$identifiers.load(on: app.db)

        #expect(user.isEmailVerified == false)
    }

    @Test("isEmailVerified returns false when email not verified")
    func testIsEmailVerifiedWhenNotVerified() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let identifier = IdentifierModel(
            userID: try user.requireID(),
            type: "email",
            value: "test@example.com",
            verified: false
        )
        try await identifier.save(on: app.db)
        try await user.$identifiers.load(on: app.db)

        #expect(user.isEmailVerified == false)
    }

    @Test("isEmailVerified returns true when email is verified")
    func testIsEmailVerifiedWhenVerified() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let identifier = IdentifierModel(
            userID: try user.requireID(),
            type: "email",
            value: "test@example.com",
            verified: true
        )
        try await identifier.save(on: app.db)
        try await user.$identifiers.load(on: app.db)

        #expect(user.isEmailVerified == true)
    }

    // MARK: - Phone Verification Tests

    @Test("isPhoneVerified returns false when no phone identifier")
    func testIsPhoneVerifiedWithNoPhone() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)
        try await user.$identifiers.load(on: app.db)

        #expect(user.isPhoneVerified == false)
    }

    @Test("isPhoneVerified returns false when phone not verified")
    func testIsPhoneVerifiedWhenNotVerified() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let identifier = IdentifierModel(
            userID: try user.requireID(),
            type: "phone",
            value: "+1234567890",
            verified: false
        )
        try await identifier.save(on: app.db)
        try await user.$identifiers.load(on: app.db)

        #expect(user.isPhoneVerified == false)
    }

    @Test("isPhoneVerified returns true when phone is verified")
    func testIsPhoneVerifiedWhenVerified() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let identifier = IdentifierModel(
            userID: try user.requireID(),
            type: "phone",
            value: "+1234567890",
            verified: true
        )
        try await identifier.save(on: app.db)
        try await user.$identifiers.load(on: app.db)

        #expect(user.isPhoneVerified == true)
    }

    // MARK: - Multiple Identifiers Tests

    @Test("User with multiple identifiers returns correct values")
    func testMultipleIdentifiers() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let emailIdentifier = IdentifierModel(
            userID: try user.requireID(),
            type: "email",
            value: "test@example.com",
            verified: true
        )
        let phoneIdentifier = IdentifierModel(
            userID: try user.requireID(),
            type: "phone",
            value: "+1234567890",
            verified: false
        )
        let usernameIdentifier = IdentifierModel(
            userID: try user.requireID(),
            type: "username",
            value: "testuser",
            verified: false
        )
        try await emailIdentifier.save(on: app.db)
        try await phoneIdentifier.save(on: app.db)
        try await usernameIdentifier.save(on: app.db)
        try await user.$identifiers.load(on: app.db)

        #expect(user.email == "test@example.com")
        #expect(user.phone == "+1234567890")
        #expect(user.username == "testuser")
        #expect(user.isAnonymous == false)
        #expect(user.isEmailVerified == true)
        #expect(user.isPhoneVerified == false)
    }

    // MARK: - First Identifier Selection Tests

    @Test("Returns first email identifier when multiple email identifiers exist")
    func testFirstEmailIdentifier() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let email1 = IdentifierModel(
            userID: try user.requireID(),
            type: "email",
            value: "first@example.com",
            verified: false
        )
        let email2 = IdentifierModel(
            userID: try user.requireID(),
            type: "email",
            value: "second@example.com",
            verified: true
        )
        try await email1.save(on: app.db)
        try await email2.save(on: app.db)
        try await user.$identifiers.load(on: app.db)

        #expect(user.email == "first@example.com")
        #expect(user.isEmailVerified == false)
    }
}
