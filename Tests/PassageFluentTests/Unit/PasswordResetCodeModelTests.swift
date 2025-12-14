import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("EmailPasswordResetCodeModel Tests")
struct EmailPasswordResetCodeModelTests {

    // MARK: - Initialization Tests

    @Test("Default initialization creates code with nil values")
    func testDefaultInitialization() {
        let code = EmailPasswordResetCodeModel()

        #expect(code.id == nil)
        #expect(code.createdAt == nil)
        #expect(code.invalidatedAt == nil)
    }

    @Test("Full initialization sets all provided values")
    func testFullInitialization() {
        let uuid = UUID()
        let userID = UUID()
        let expiresAt = Date().addingTimeInterval(3600)

        let code = EmailPasswordResetCodeModel(
            id: uuid,
            email: "test@example.com",
            codeHash: "codehash123",
            userID: userID,
            expiresAt: expiresAt,
            failedAttempts: 3
        )

        #expect(code.id == uuid)
        #expect(code.email == "test@example.com")
        #expect(code.codeHash == "codehash123")
        #expect(code.$user.id == userID)
        #expect(code.expiresAt == expiresAt)
        #expect(code.failedAttempts == 3)
    }

    @Test("Default failedAttempts is 0")
    func testDefaultFailedAttempts() {
        let code = EmailPasswordResetCodeModel(
            email: "test@example.com",
            codeHash: "codehash123",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(3600)
        )

        #expect(code.failedAttempts == 0)
    }

    // MARK: - Schema Tests

    @Test("Schema name is 'email_password_reset_codes'")
    func testSchemaName() {
        #expect(EmailPasswordResetCodeModel.schema == "email_password_reset_codes")
    }

    // MARK: - RestorationCode Protocol Tests

    @Test("isExpired returns false for future expiration")
    func testIsExpiredFalseForFuture() {
        let code = EmailPasswordResetCodeModel(
            email: "test@example.com",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(3600)
        )

        #expect(code.isExpired == false)
    }

    @Test("isExpired returns true for past expiration")
    func testIsExpiredTrueForPast() {
        let code = EmailPasswordResetCodeModel(
            email: "test@example.com",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(-3600)
        )

        #expect(code.isExpired == true)
    }

    @Test("isValid returns true when not expired and under max attempts")
    func testIsValidTrue() {
        let code = EmailPasswordResetCodeModel(
            email: "test@example.com",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(3600),
            failedAttempts: 2
        )

        #expect(code.isValid(maxAttempts: 5) == true)
    }

    @Test("isValid returns false when expired")
    func testIsValidFalseWhenExpired() {
        let code = EmailPasswordResetCodeModel(
            email: "test@example.com",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(-3600),
            failedAttempts: 0
        )

        #expect(code.isValid(maxAttempts: 5) == false)
    }

    @Test("isValid returns false when at max attempts")
    func testIsValidFalseAtMaxAttempts() {
        let code = EmailPasswordResetCodeModel(
            email: "test@example.com",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(3600),
            failedAttempts: 5
        )

        #expect(code.isValid(maxAttempts: 5) == false)
    }

    @Test("isValid returns false when over max attempts")
    func testIsValidFalseOverMaxAttempts() {
        let code = EmailPasswordResetCodeModel(
            email: "test@example.com",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(3600),
            failedAttempts: 10
        )

        #expect(code.isValid(maxAttempts: 5) == false)
    }

    // MARK: - Failed Attempts Tracking Tests

    @Test("Failed attempts can be incremented")
    func testFailedAttemptsIncrement() {
        let code = EmailPasswordResetCodeModel(
            email: "test@example.com",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(3600),
            failedAttempts: 0
        )

        code.failedAttempts += 1
        #expect(code.failedAttempts == 1)

        code.failedAttempts += 1
        #expect(code.failedAttempts == 2)
    }
}

@Suite("PhonePasswordResetCodeModel Tests")
struct PhonePasswordResetCodeModelTests {

    // MARK: - Initialization Tests

    @Test("Default initialization creates code with nil values")
    func testDefaultInitialization() {
        let code = PhonePasswordResetCodeModel()

        #expect(code.id == nil)
        #expect(code.createdAt == nil)
        #expect(code.invalidatedAt == nil)
    }

    @Test("Full initialization sets all provided values")
    func testFullInitialization() {
        let uuid = UUID()
        let userID = UUID()
        let expiresAt = Date().addingTimeInterval(3600)

        let code = PhonePasswordResetCodeModel(
            id: uuid,
            phone: "+1234567890",
            codeHash: "codehash123",
            userID: userID,
            expiresAt: expiresAt,
            failedAttempts: 3
        )

        #expect(code.id == uuid)
        #expect(code.phone == "+1234567890")
        #expect(code.codeHash == "codehash123")
        #expect(code.$user.id == userID)
        #expect(code.expiresAt == expiresAt)
        #expect(code.failedAttempts == 3)
    }

    @Test("Default failedAttempts is 0")
    func testDefaultFailedAttempts() {
        let code = PhonePasswordResetCodeModel(
            phone: "+1234567890",
            codeHash: "codehash123",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(3600)
        )

        #expect(code.failedAttempts == 0)
    }

    // MARK: - Schema Tests

    @Test("Schema name is 'phone_password_reset_codes'")
    func testSchemaName() {
        #expect(PhonePasswordResetCodeModel.schema == "phone_password_reset_codes")
    }

    // MARK: - RestorationCode Protocol Tests

    @Test("isExpired returns false for future expiration")
    func testIsExpiredFalseForFuture() {
        let code = PhonePasswordResetCodeModel(
            phone: "+1234567890",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(3600)
        )

        #expect(code.isExpired == false)
    }

    @Test("isExpired returns true for past expiration")
    func testIsExpiredTrueForPast() {
        let code = PhonePasswordResetCodeModel(
            phone: "+1234567890",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(-3600)
        )

        #expect(code.isExpired == true)
    }

    @Test("isValid returns true when not expired and under max attempts")
    func testIsValidTrue() {
        let code = PhonePasswordResetCodeModel(
            phone: "+1234567890",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(3600),
            failedAttempts: 2
        )

        #expect(code.isValid(maxAttempts: 5) == true)
    }

    @Test("isValid returns false when expired")
    func testIsValidFalseWhenExpired() {
        let code = PhonePasswordResetCodeModel(
            phone: "+1234567890",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(-3600),
            failedAttempts: 0
        )

        #expect(code.isValid(maxAttempts: 5) == false)
    }

    @Test("isValid returns false when at max attempts")
    func testIsValidFalseAtMaxAttempts() {
        let code = PhonePasswordResetCodeModel(
            phone: "+1234567890",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(3600),
            failedAttempts: 5
        )

        #expect(code.isValid(maxAttempts: 5) == false)
    }
}
