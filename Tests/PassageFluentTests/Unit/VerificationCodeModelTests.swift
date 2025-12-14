import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("EmailVerificationCodeModel Tests")
struct EmailVerificationCodeModelTests {

    // MARK: - Initialization Tests

    @Test("Default initialization creates code with nil values")
    func testDefaultInitialization() {
        let code = EmailVerificationCodeModel()

        #expect(code.id == nil)
        #expect(code.createdAt == nil)
        #expect(code.invalidatedAt == nil)
    }

    @Test("Full initialization sets all provided values")
    func testFullInitialization() {
        let uuid = UUID()
        let userID = UUID()
        let expiresAt = Date().addingTimeInterval(3600)

        let code = EmailVerificationCodeModel(
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
        let code = EmailVerificationCodeModel(
            email: "test@example.com",
            codeHash: "codehash123",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(3600)
        )

        #expect(code.failedAttempts == 0)
    }

    // MARK: - Schema Tests

    @Test("Schema name is 'email_verification_codes'")
    func testSchemaName() {
        #expect(EmailVerificationCodeModel.schema == "email_verification_codes")
    }

    // MARK: - VerificationCode Protocol Tests

    @Test("isExpired returns false for future expiration")
    func testIsExpiredFalseForFuture() {
        let code = EmailVerificationCodeModel(
            email: "test@example.com",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(3600)
        )

        #expect(code.isExpired == false)
    }

    @Test("isExpired returns true for past expiration")
    func testIsExpiredTrueForPast() {
        let code = EmailVerificationCodeModel(
            email: "test@example.com",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(-3600)
        )

        #expect(code.isExpired == true)
    }

    @Test("isValid returns true when not expired and under max attempts")
    func testIsValidTrue() {
        let code = EmailVerificationCodeModel(
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
        let code = EmailVerificationCodeModel(
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
        let code = EmailVerificationCodeModel(
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
        let code = EmailVerificationCodeModel(
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
        let code = EmailVerificationCodeModel(
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

@Suite("PhoneVerificationCodeModel Tests")
struct PhoneVerificationCodeModelTests {

    // MARK: - Initialization Tests

    @Test("Default initialization creates code with nil values")
    func testDefaultInitialization() {
        let code = PhoneVerificationCodeModel()

        #expect(code.id == nil)
        #expect(code.createdAt == nil)
        #expect(code.invalidatedAt == nil)
    }

    @Test("Full initialization sets all provided values")
    func testFullInitialization() {
        let uuid = UUID()
        let userID = UUID()
        let expiresAt = Date().addingTimeInterval(3600)

        let code = PhoneVerificationCodeModel(
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
        let code = PhoneVerificationCodeModel(
            phone: "+1234567890",
            codeHash: "codehash123",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(3600)
        )

        #expect(code.failedAttempts == 0)
    }

    // MARK: - Schema Tests

    @Test("Schema name is 'phone_verification_codes'")
    func testSchemaName() {
        #expect(PhoneVerificationCodeModel.schema == "phone_verification_codes")
    }

    // MARK: - VerificationCode Protocol Tests

    @Test("isExpired returns false for future expiration")
    func testIsExpiredFalseForFuture() {
        let code = PhoneVerificationCodeModel(
            phone: "+1234567890",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(3600)
        )

        #expect(code.isExpired == false)
    }

    @Test("isExpired returns true for past expiration")
    func testIsExpiredTrueForPast() {
        let code = PhoneVerificationCodeModel(
            phone: "+1234567890",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(-3600)
        )

        #expect(code.isExpired == true)
    }

    @Test("isValid returns true when not expired and under max attempts")
    func testIsValidTrue() {
        let code = PhoneVerificationCodeModel(
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
        let code = PhoneVerificationCodeModel(
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
        let code = PhoneVerificationCodeModel(
            phone: "+1234567890",
            codeHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(3600),
            failedAttempts: 5
        )

        #expect(code.isValid(maxAttempts: 5) == false)
    }
}
