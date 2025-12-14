import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("DatabaseStore.TokenStore Tests")
struct TokenStoreTests {

    // MARK: - Create Refresh Token Tests

    @Test("createRefreshToken creates token for user")
    func testCreateRefreshToken() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        let token = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "tokenhash123",
            expiresAt: expiresAt
        )

        #expect(token.tokenHash == "tokenhash123")
        #expect(token.isRevoked == false)
        #expect(token.isExpired == false)
        #expect(token.isValid == true)
    }

    @Test("createRefreshToken with replacement revokes old token")
    func testCreateRefreshTokenWithReplacement() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)

        // Create first token
        let oldToken = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "oldhash",
            expiresAt: expiresAt
        )

        #expect(oldToken.isRevoked == false)

        // Create replacement token
        let newToken = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "newhash",
            expiresAt: expiresAt,
            replacing: oldToken
        )

        #expect(newToken.tokenHash == "newhash")
        #expect(newToken.isRevoked == false)

        // Verify old token is revoked
        let foundOldToken = try await store.tokens.find(refreshTokenHash: "oldhash")
        #expect(foundOldToken?.isRevoked == true)
        #expect(foundOldToken?.replacedBy != nil) // points to newToken
    }

    // MARK: - Find Token Tests

    @Test("find(refreshTokenHash:) returns nil when not found")
    func testFindByHashNotFound() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let result = try await store.tokens.find(refreshTokenHash: "nonexistent")
        #expect(result == nil)
    }

    @Test("find(refreshTokenHash:) returns token when found")
    func testFindByHashFound() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and token
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "tokenhash123",
            expiresAt: expiresAt
        )

        let result = try await store.tokens.find(refreshTokenHash: "tokenhash123")

        #expect(result != nil)
        #expect(result?.tokenHash == "tokenhash123")
        #expect(result?.user.email == "test@example.com")
    }

    // MARK: - Revoke Token Tests

    @Test("revokeRefreshToken(for:) revokes all user tokens")
    func testRevokeAllUserTokens() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)

        // Create multiple tokens
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
        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hash3",
            expiresAt: expiresAt
        )

        // Revoke all tokens for user
        try await store.tokens.revokeRefreshToken(for: user)

        // Verify all tokens are revoked
        let token1 = try await store.tokens.find(refreshTokenHash: "hash1")
        let token2 = try await store.tokens.find(refreshTokenHash: "hash2")
        let token3 = try await store.tokens.find(refreshTokenHash: "hash3")

        #expect(token1?.isRevoked == true)
        #expect(token2?.isRevoked == true)
        #expect(token3?.isRevoked == true)
    }

    @Test("revokeRefreshToken(withHash:) revokes specific token")
    func testRevokeTokenByHash() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and token
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "tokenhash123",
            expiresAt: expiresAt
        )

        // Revoke by hash
        try await store.tokens.revokeRefreshToken(withHash: "tokenhash123")

        // Verify token is revoked
        let token = try await store.tokens.find(refreshTokenHash: "tokenhash123")
        #expect(token?.isRevoked == true)
    }

    @Test("revokeRefreshToken(withHash:) does nothing for non-existent token")
    func testRevokeNonExistentToken() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Should not throw
        try await store.tokens.revokeRefreshToken(withHash: "nonexistent")
    }

    // MARK: - Token Family Revocation Tests

    @Test("revoke(refreshTokenFamilyStartingFrom:) revokes entire token chain")
    func testRevokeTokenFamily() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)

        // Create token chain: token1 -> token2 -> token3
        let token1 = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hash1",
            expiresAt: expiresAt
        )

        let token2 = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hash2",
            expiresAt: expiresAt,
            replacing: token1
        )

        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hash3",
            expiresAt: expiresAt,
            replacing: token2
        )

        // Revoke starting from token1 (should revoke token1 and follow chain to token2, token3)
        let reloadedToken1 = try await store.tokens.find(refreshTokenHash: "hash1")
        try await store.tokens.revoke(refreshTokenFamilyStartingFrom: reloadedToken1!)

        // Verify all tokens in chain are revoked
        let foundToken1 = try await store.tokens.find(refreshTokenHash: "hash1")
        let foundToken2 = try await store.tokens.find(refreshTokenHash: "hash2")
        let foundToken3 = try await store.tokens.find(refreshTokenHash: "hash3")

        #expect(foundToken1?.isRevoked == true)
        #expect(foundToken2?.isRevoked == true)
        #expect(foundToken3?.isRevoked == true)
    }

    @Test("revoke(refreshTokenFamilyStartingFrom:) handles single token")
    func testRevokeTokenFamilySingleToken() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)

        // Create single token (no chain)
        let token = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hash1",
            expiresAt: expiresAt
        )

        // Revoke starting from the only token
        try await store.tokens.revoke(refreshTokenFamilyStartingFrom: token)

        // Verify token is revoked
        let foundToken = try await store.tokens.find(refreshTokenHash: "hash1")
        #expect(foundToken?.isRevoked == true)
    }

    @Test("revoke(refreshTokenFamilyStartingFrom:) skips already revoked tokens")
    func testRevokeTokenFamilySkipsRevoked() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)

        // Create token chain
        let token1 = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hash1",
            expiresAt: expiresAt
        )

        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hash2",
            expiresAt: expiresAt,
            replacing: token1
        )

        // token1 should now be revoked (replaced)
        let foundToken1 = try await store.tokens.find(refreshTokenHash: "hash1")
        #expect(foundToken1?.isRevoked == true)

        // Revoke family starting from token1
        try await store.tokens.revoke(refreshTokenFamilyStartingFrom: foundToken1!)

        // All should be revoked
        let finalToken1 = try await store.tokens.find(refreshTokenHash: "hash1")
        let finalToken2 = try await store.tokens.find(refreshTokenHash: "hash2")

        #expect(finalToken1?.isRevoked == true)
        #expect(finalToken2?.isRevoked == true)
    }
}
