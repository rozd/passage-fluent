import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("ExchangeTokenModel Tests")
struct ExchangeTokenModelTests {

    // MARK: - Initialization Tests

    @Test("Default initialization creates token with nil values")
    func testDefaultInitialization() {
        let token = ExchangeTokenModel()

        #expect(token.id == nil)
        #expect(token.createdAt == nil)
        #expect(token.consumedAt == nil)
    }

    @Test("Full initialization sets all provided values")
    func testFullInitialization() {
        let uuid = UUID()
        let userID = UUID()
        let expiresAt = Date().addingTimeInterval(60) // 60 seconds
        let consumedAt = Date()

        let token = ExchangeTokenModel(
            id: uuid,
            tokenHash: "exchangehash123",
            userID: userID,
            expiresAt: expiresAt,
            consumedAt: consumedAt
        )

        #expect(token.id == uuid)
        #expect(token.tokenHash == "exchangehash123")
        #expect(token.$user.id == userID)
        #expect(token.expiresAt == expiresAt)
        #expect(token.consumedAt == consumedAt)
    }

    @Test("Minimal initialization with required values")
    func testMinimalInitialization() {
        let userID = UUID()
        let expiresAt = Date().addingTimeInterval(60)

        let token = ExchangeTokenModel(
            tokenHash: "exchangehash123",
            userID: userID,
            expiresAt: expiresAt
        )

        #expect(token.id == nil)
        #expect(token.tokenHash == "exchangehash123")
        #expect(token.$user.id == userID)
        #expect(token.expiresAt == expiresAt)
        #expect(token.consumedAt == nil)
    }

    @Test("Default consumedAt is nil")
    func testDefaultConsumedAtIsNil() {
        let token = ExchangeTokenModel(
            tokenHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(60)
        )

        #expect(token.consumedAt == nil)
    }

    // MARK: - Schema Tests

    @Test("Schema name is 'exchange_tokens'")
    func testSchemaName() {
        #expect(ExchangeTokenModel.schema == "exchange_tokens")
    }

    // MARK: - ExchangeToken Protocol Tests

    @Test("isExpired returns false for future expiration")
    func testIsExpiredFalseForFuture() {
        let token = ExchangeTokenModel(
            tokenHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(60)
        )

        #expect(token.isExpired == false)
    }

    @Test("isExpired returns true for past expiration")
    func testIsExpiredTrueForPast() {
        let token = ExchangeTokenModel(
            tokenHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(-60)
        )

        #expect(token.isExpired == true)
    }

    @Test("isConsumed returns false when consumedAt is nil")
    func testIsConsumedFalseWhenNil() {
        let token = ExchangeTokenModel(
            tokenHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(60),
            consumedAt: nil
        )

        #expect(token.isConsumed == false)
    }

    @Test("isConsumed returns true when consumedAt is set")
    func testIsConsumedTrueWhenSet() {
        let token = ExchangeTokenModel(
            tokenHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(60),
            consumedAt: Date()
        )

        #expect(token.isConsumed == true)
    }

    @Test("isValid returns true when not expired and not consumed")
    func testIsValidTrueWhenValid() {
        let token = ExchangeTokenModel(
            tokenHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(60),
            consumedAt: nil
        )

        #expect(token.isValid == true)
    }

    @Test("isValid returns false when expired")
    func testIsValidFalseWhenExpired() {
        let token = ExchangeTokenModel(
            tokenHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(-60),
            consumedAt: nil
        )

        #expect(token.isValid == false)
    }

    @Test("isValid returns false when consumed")
    func testIsValidFalseWhenConsumed() {
        let token = ExchangeTokenModel(
            tokenHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(60),
            consumedAt: Date()
        )

        #expect(token.isValid == false)
    }

    @Test("isValid returns false when both expired and consumed")
    func testIsValidFalseWhenBoth() {
        let token = ExchangeTokenModel(
            tokenHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(-60),
            consumedAt: Date()
        )

        #expect(token.isValid == false)
    }

    // MARK: - Consumption Tests

    @Test("Token can be marked as consumed")
    func testMarkAsConsumed() {
        let token = ExchangeTokenModel(
            tokenHash: "hash",
            userID: UUID(),
            expiresAt: Date().addingTimeInterval(60),
            consumedAt: nil
        )

        #expect(token.isConsumed == false)

        token.consumedAt = Date()

        #expect(token.isConsumed == true)
        #expect(token.isValid == false)
    }
}
