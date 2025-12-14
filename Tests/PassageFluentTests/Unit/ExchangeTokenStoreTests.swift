import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("DatabaseStore.ExchangeTokenStore Tests")
struct ExchangeTokenStoreTests {

    // MARK: - Create Tests

    @Test("createExchangeToken creates token for user")
    func testCreateExchangeToken() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(60) // 60 seconds
        let token = try await store.exchangeTokens.createExchangeToken(
            for: user,
            tokenHash: "exchangehash123",
            expiresAt: expiresAt
        )

        #expect(token.tokenHash == "exchangehash123")
        #expect(token.isConsumed == false)
        #expect(token.isExpired == false)
        #expect(token.isValid == true)
        #expect(token.user.email == "test@example.com")
    }

    // MARK: - Find Tests

    @Test("find(exchangeTokenHash:) returns nil when not found")
    func testFindByHashNotFound() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let result = try await store.exchangeTokens.find(exchangeTokenHash: "nonexistent")
        #expect(result == nil)
    }

    @Test("find(exchangeTokenHash:) returns token when found")
    func testFindByHashFound() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and token
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(60)
        _ = try await store.exchangeTokens.createExchangeToken(
            for: user,
            tokenHash: "exchangehash123",
            expiresAt: expiresAt
        )

        let result = try await store.exchangeTokens.find(exchangeTokenHash: "exchangehash123")

        #expect(result != nil)
        #expect(result?.tokenHash == "exchangehash123")
        #expect(result?.user.email == "test@example.com")
    }

    // MARK: - Consume Tests

    @Test("consume marks token as consumed")
    func testConsumeToken() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and token
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(60)
        let token = try await store.exchangeTokens.createExchangeToken(
            for: user,
            tokenHash: "exchangehash123",
            expiresAt: expiresAt
        )

        #expect(token.isConsumed == false)

        // Consume token
        try await store.exchangeTokens.consume(exchangeToken: token)

        // Verify consumption
        let foundToken = try await store.exchangeTokens.find(exchangeTokenHash: "exchangehash123")
        #expect(foundToken?.isConsumed == true)
        #expect(foundToken?.isValid == false)
    }

    @Test("consumed token is invalid")
    func testConsumedTokenInvalid() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and token
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(60)
        let token = try await store.exchangeTokens.createExchangeToken(
            for: user,
            tokenHash: "exchangehash123",
            expiresAt: expiresAt
        )

        // Token is valid before consumption
        #expect(token.isValid == true)

        // Consume token
        try await store.exchangeTokens.consume(exchangeToken: token)

        // Token is invalid after consumption
        let foundToken = try await store.exchangeTokens.find(exchangeTokenHash: "exchangehash123")
        #expect(foundToken?.isValid == false)
    }

    // MARK: - Cleanup Tests

    @Test("cleanupExpiredTokens deletes expired tokens")
    func testCleanupExpiredTokens() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        // Create expired token
        let pastDate = Date().addingTimeInterval(-60) // 60 seconds ago
        _ = try await store.exchangeTokens.createExchangeToken(
            for: user,
            tokenHash: "expiredhash",
            expiresAt: pastDate
        )

        // Create valid token
        let futureDate = Date().addingTimeInterval(60)
        _ = try await store.exchangeTokens.createExchangeToken(
            for: user,
            tokenHash: "validhash",
            expiresAt: futureDate
        )

        // Cleanup expired tokens
        try await store.exchangeTokens.cleanupExpiredTokens(before: Date())

        // Expired token should be gone
        let expiredToken = try await store.exchangeTokens.find(exchangeTokenHash: "expiredhash")
        #expect(expiredToken == nil)

        // Valid token should still exist
        let validToken = try await store.exchangeTokens.find(exchangeTokenHash: "validhash")
        #expect(validToken != nil)
    }

    @Test("cleanupExpiredTokens handles no expired tokens")
    func testCleanupNoExpiredTokens() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        // Create only valid tokens
        let futureDate = Date().addingTimeInterval(60)
        _ = try await store.exchangeTokens.createExchangeToken(
            for: user,
            tokenHash: "validhash1",
            expiresAt: futureDate
        )
        _ = try await store.exchangeTokens.createExchangeToken(
            for: user,
            tokenHash: "validhash2",
            expiresAt: futureDate
        )

        // Cleanup - should not throw
        try await store.exchangeTokens.cleanupExpiredTokens(before: Date())

        // Both tokens should still exist
        let token1 = try await store.exchangeTokens.find(exchangeTokenHash: "validhash1")
        let token2 = try await store.exchangeTokens.find(exchangeTokenHash: "validhash2")
        #expect(token1 != nil)
        #expect(token2 != nil)
    }

    @Test("cleanupExpiredTokens deletes all expired tokens")
    func testCleanupAllExpiredTokens() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        // Create multiple expired tokens
        let pastDate = Date().addingTimeInterval(-60)
        _ = try await store.exchangeTokens.createExchangeToken(
            for: user,
            tokenHash: "expired1",
            expiresAt: pastDate
        )
        _ = try await store.exchangeTokens.createExchangeToken(
            for: user,
            tokenHash: "expired2",
            expiresAt: pastDate
        )
        _ = try await store.exchangeTokens.createExchangeToken(
            for: user,
            tokenHash: "expired3",
            expiresAt: pastDate
        )

        // Cleanup expired tokens
        try await store.exchangeTokens.cleanupExpiredTokens(before: Date())

        // All expired tokens should be gone
        let token1 = try await store.exchangeTokens.find(exchangeTokenHash: "expired1")
        let token2 = try await store.exchangeTokens.find(exchangeTokenHash: "expired2")
        let token3 = try await store.exchangeTokens.find(exchangeTokenHash: "expired3")
        #expect(token1 == nil)
        #expect(token2 == nil)
        #expect(token3 == nil)
    }
}
