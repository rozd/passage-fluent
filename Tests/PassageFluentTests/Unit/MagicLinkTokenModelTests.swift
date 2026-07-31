import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("MagicLinkTokenModel Tests")
struct MagicLinkTokenModelTests {

    @Test("Full initialization sets all provided values")
    func testFullInitialization() {
        let uuid = UUID()
        let userID = UUID()
        let expiresAt = Date().addingTimeInterval(3600)

        let token = MagicLinkTokenModel(
            id: uuid,
            email: "test@example.com",
            tokenHash: "tokenhash",
            userID: userID,
            sessionTokenHash: "sessionhash",
            expiresAt: expiresAt,
            failedAttempts: 3
        )

        #expect(token.id == uuid)
        #expect(token.email == "test@example.com")
        #expect(token.tokenHash == "tokenhash")
        #expect(token.$user.id == userID)
        #expect(token.sessionTokenHash == "sessionhash")
        #expect(token.expiresAt == expiresAt)
        #expect(token.failedAttempts == 3)
    }

    @Test("Minimal initialization with required values")
    func testMinimalInitialization() {
        let expiresAt = Date().addingTimeInterval(3600)

        let token = MagicLinkTokenModel(
            email: "test@example.com",
            tokenHash: "tokenhash",
            userID: nil,
            expiresAt: expiresAt
        )

        #expect(token.id == nil)
        #expect(token.email == "test@example.com")
        #expect(token.tokenHash == "tokenhash")
        #expect(token.$user.id == nil)
        #expect(token.sessionTokenHash == nil)
        #expect(token.failedAttempts == 0)
    }

    // MARK: - Schema Tests

    @Test("Schema name is 'magic_link_tokens'")
    func testSchemaName() {
        #expect(MagicLinkTokenModel.schema == "magic_link_tokens")
    }

    // MARK: - MagicLinkToken Protocol Tests

    @Test("identifier is an email identifier")
    func testIdentifier() {
        let token = MagicLinkTokenModel(
            email: "test@example.com",
            tokenHash: "tokenhash",
            userID: nil,
            expiresAt: Date().addingTimeInterval(3600)
        )

        #expect(token.identifier == .email("test@example.com"))
    }

    @Test("user is nil when userID is nil")
    func testUserNilWhenNoUserID() {
        let token = MagicLinkTokenModel(
            email: "test@example.com",
            tokenHash: "tokenhash",
            userID: nil,
            expiresAt: Date().addingTimeInterval(3600)
        )

        #expect(token.user == nil)
    }

    @Test("isExpired returns false for future expiration")
    func testIsExpiredFalseForFuture() {
        let token = MagicLinkTokenModel(
            email: "test@example.com",
            tokenHash: "tokenhash",
            userID: nil,
            expiresAt: Date().addingTimeInterval(60)
        )

        #expect(token.isExpired == false)
    }

    @Test("isExpired returns true for past expiration")
    func testIsExpiredTrueForPast() {
        let token = MagicLinkTokenModel(
            email: "test@example.com",
            tokenHash: "tokenhash",
            userID: nil,
            expiresAt: Date().addingTimeInterval(-60)
        )

        #expect(token.isExpired == true)
    }

    @Test("isValid returns true when not expired and no failed attempts")
    func testIsValidTrueWhenValid() {
        let token = MagicLinkTokenModel(
            email: "test@example.com",
            tokenHash: "tokenhash",
            userID: nil,
            expiresAt: Date().addingTimeInterval(60)
        )

        #expect(token.isValid(maxAttempts: 5) == true)
    }

    @Test("isValid returns false when expired")
    func testIsValidFalseWhenExpired() {
        let token = MagicLinkTokenModel(
            email: "test@example.com",
            tokenHash: "tokenhash",
            userID: nil,
            expiresAt: Date().addingTimeInterval(-60)
        )

        #expect(token.isValid(maxAttempts: 5) == false)
    }

    @Test("isValid returns false when failed attempts reach max")
    func testIsValidFalseAtMaxAttempts() {
        let token = MagicLinkTokenModel(
            email: "test@example.com",
            tokenHash: "tokenhash",
            userID: nil,
            expiresAt: Date().addingTimeInterval(60),
            failedAttempts: 5
        )

        #expect(token.isValid(maxAttempts: 5) == false)
    }
}
