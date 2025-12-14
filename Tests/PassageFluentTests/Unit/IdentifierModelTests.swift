import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("IdentifierModel Tests")
struct IdentifierModelTests {

    // MARK: - Initialization Tests

    @Test("Default initialization creates identifier with nil values")
    func testDefaultInitialization() {
        let identifier = IdentifierModel()

        #expect(identifier.id == nil)
        #expect(identifier.createdAt == nil)
    }

    @Test("Full initialization sets all provided values")
    func testFullInitialization() {
        let uuid = UUID()
        let userID = UUID()
        let identifier = IdentifierModel(
            id: uuid,
            userID: userID,
            type: "email",
            value: "test@example.com",
            provider: nil,
            verified: true
        )

        #expect(identifier.id == uuid)
        #expect(identifier.$user.id == userID)
        #expect(identifier.type == "email")
        #expect(identifier.value == "test@example.com")
        #expect(identifier.provider == nil)
        #expect(identifier.verified == true)
    }

    @Test("Initialization with provider for federated identifier")
    func testFederatedInitialization() {
        let userID = UUID()
        let identifier = IdentifierModel(
            userID: userID,
            type: "federated",
            value: "google-user-123",
            provider: "google",
            verified: true
        )

        #expect(identifier.$user.id == userID)
        #expect(identifier.type == "federated")
        #expect(identifier.value == "google-user-123")
        #expect(identifier.provider == "google")
        #expect(identifier.verified == true)
    }

    @Test("Default verified value is false")
    func testDefaultVerifiedIsFalse() {
        let userID = UUID()
        let identifier = IdentifierModel(
            userID: userID,
            type: "email",
            value: "test@example.com"
        )

        #expect(identifier.verified == false)
    }

    @Test("Default provider value is nil")
    func testDefaultProviderIsNil() {
        let userID = UUID()
        let identifier = IdentifierModel(
            userID: userID,
            type: "email",
            value: "test@example.com"
        )

        #expect(identifier.provider == nil)
    }

    // MARK: - Schema Tests

    @Test("Schema name is 'identifiers'")
    func testSchemaName() {
        #expect(IdentifierModel.schema == "identifiers")
    }

    // MARK: - Type Tests

    @Test("Email type identifier")
    func testEmailType() {
        let identifier = IdentifierModel(
            userID: UUID(),
            type: "email",
            value: "test@example.com"
        )

        #expect(identifier.type == "email")
    }

    @Test("Phone type identifier")
    func testPhoneType() {
        let identifier = IdentifierModel(
            userID: UUID(),
            type: "phone",
            value: "+1234567890"
        )

        #expect(identifier.type == "phone")
    }

    @Test("Username type identifier")
    func testUsernameType() {
        let identifier = IdentifierModel(
            userID: UUID(),
            type: "username",
            value: "testuser"
        )

        #expect(identifier.type == "username")
    }

    @Test("Federated type identifier")
    func testFederatedType() {
        let identifier = IdentifierModel(
            userID: UUID(),
            type: "federated",
            value: "oauth-user-id",
            provider: "github"
        )

        #expect(identifier.type == "federated")
        #expect(identifier.provider == "github")
    }
}
