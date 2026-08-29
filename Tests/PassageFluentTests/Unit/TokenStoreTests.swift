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
            expiresAt: expiresAt, sessionId: UUID()
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
            expiresAt: expiresAt, sessionId: UUID()
        )

        #expect(oldToken.isRevoked == false)

        // Create replacement token
        let newToken = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "newhash",
            expiresAt: expiresAt, sessionId: UUID(),
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
            expiresAt: expiresAt, sessionId: UUID()
        )

        let result = try await store.tokens.find(refreshTokenHash: "tokenhash123")

        #expect(result != nil)
        #expect(result?.tokenHash == "tokenhash123")
        #expect(result?.user.email == "test@example.com")
    }

    // MARK: - Revoke Token Tests

    @Test("revokeRefreshTokens(for:) revokes all user tokens")
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
            expiresAt: expiresAt, sessionId: UUID()
        )
        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hash2",
            expiresAt: expiresAt, sessionId: UUID()
        )
        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hash3",
            expiresAt: expiresAt, sessionId: UUID()
        )

        // Revoke all tokens for user
        try await store.tokens.revokeRefreshTokens(for: user)

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
            expiresAt: expiresAt, sessionId: UUID()
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
            expiresAt: expiresAt, sessionId: UUID()
        )

        let token2 = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hash2",
            expiresAt: expiresAt, sessionId: UUID(),
            replacing: token1
        )

        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hash3",
            expiresAt: expiresAt, sessionId: UUID(),
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
            expiresAt: expiresAt, sessionId: UUID()
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
            expiresAt: expiresAt, sessionId: UUID()
        )

        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hash2",
            expiresAt: expiresAt, sessionId: UUID(),
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

    @Test("revokeRefreshTokens(for:keepingNewestSessions:) keeps N most recent sessions")
    func testRevokeKeepingNewestSessions() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        let baseTime = Date()

        let sessionA = UUID()
        let sessionB = UUID()
        let sessionC = UUID()

        var token = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hashA1",
            expiresAt: expiresAt, sessionId: sessionA
        )
        guard var model = token as? RefreshTokenModel else {
            #expect(Bool(false), "Expected RefreshTokenModel")
            return
        }
        model.createdAt = baseTime
        try await model.save(on: app.db)

        token = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hashB1",
            expiresAt: expiresAt, sessionId: sessionB
        )
        guard var model = token as? RefreshTokenModel else {
            #expect(Bool(false), "Expected RefreshTokenModel")
            return
        }
        model.createdAt = baseTime.addingTimeInterval(10)
        try await model.save(on: app.db)

        token = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hashC1",
            expiresAt: expiresAt, sessionId: sessionC
        )
        guard var model = token as? RefreshTokenModel else {
            #expect(Bool(false), "Expected RefreshTokenModel")
            return
        }
        model.createdAt = baseTime.addingTimeInterval(20)
        try await model.save(on: app.db)

        let revoked = try await store.tokens.revokeRefreshTokens(for: user, keepingNewestSessions: 1)

        #expect(revoked.count == 2)
        #expect(revoked.contains(sessionB))
        #expect(revoked.contains(sessionA))
        #expect(!revoked.contains(sessionC))

        let tokenA = try await store.tokens.find(refreshTokenHash: "hashA1")
        let tokenB = try await store.tokens.find(refreshTokenHash: "hashB1")
        let tokenC = try await store.tokens.find(refreshTokenHash: "hashC1")

        #expect(tokenA?.isRevoked == true)
        #expect(tokenB?.isRevoked == true)
        #expect(tokenC?.isRevoked == false)
    }

    @Test("revokeRefreshTokens(for:keepingNewestSessions:) recency follows session newest row")
    func testRevokeRecencyFollowsSessionNewestRow() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        let baseTime = Date()

        let sessionA = UUID()
        let sessionB = UUID()

        var token = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hashA1",
            expiresAt: expiresAt, sessionId: sessionA
        )
        guard let model = token as? RefreshTokenModel else {
            #expect(Bool(false), "Expected RefreshTokenModel")
            return
        }
        model.createdAt = baseTime
        try await model.save(on: app.db)

        token = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hashB1",
            expiresAt: expiresAt, sessionId: sessionB
        )
        guard let model = token as? RefreshTokenModel else {
            #expect(Bool(false), "Expected RefreshTokenModel")
            return
        }
        model.createdAt = baseTime.addingTimeInterval(10)
        try await model.save(on: app.db)

        token = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hashA2",
            expiresAt: expiresAt, sessionId: sessionA
        )
        guard let model = token as? RefreshTokenModel else {
            #expect(Bool(false), "Expected RefreshTokenModel")
            return
        }
        model.createdAt = baseTime.addingTimeInterval(20)
        try await model.save(on: app.db)

        let revoked = try await store.tokens.revokeRefreshTokens(for: user, keepingNewestSessions: 1)

        #expect(revoked.count == 1)
        #expect(revoked.contains(sessionB))
        #expect(!revoked.contains(sessionA))

        let tokenB1 = try await store.tokens.find(refreshTokenHash: "hashB1")
        #expect(tokenB1?.isRevoked == true)
    }

    @Test("revokeRefreshTokens(for:keepingNewestSessions:) ignores expired sessions when ranking")
    func testRevokeKeepingNewestSessionsIgnoresExpired() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let baseTime = Date()

        let validSession = UUID()
        let expiredSession = UUID()

        // Older row, still valid.
        var token = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hashValid",
            expiresAt: baseTime.addingTimeInterval(3600), sessionId: validSession
        )
        guard let model = token as? RefreshTokenModel else {
            #expect(Bool(false), "Expected RefreshTokenModel")
            return
        }
        model.createdAt = baseTime
        try await model.save(on: app.db)

        // Newer row, but already expired (never revoked).
        token = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hashExpired",
            expiresAt: baseTime.addingTimeInterval(-60), sessionId: expiredSession
        )
        guard let model = token as? RefreshTokenModel else {
            #expect(Bool(false), "Expected RefreshTokenModel")
            return
        }
        model.createdAt = baseTime.addingTimeInterval(10)
        try await model.save(on: app.db)

        let revoked = try await store.tokens.revokeRefreshTokens(for: user, keepingNewestSessions: 1)

        #expect(revoked.isEmpty)
        #expect(!revoked.contains(validSession))

        let validToken = try await store.tokens.find(refreshTokenHash: "hashValid")
        #expect(validToken?.isRevoked == false)
    }

    @Test("revokeRefreshTokens(for:keepingNewestSessions:) count 0 revokes all")
    func testRevokeCountZeroRevokesAll() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)

        let sessionA = UUID()
        let sessionB = UUID()

        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hashA1",
            expiresAt: expiresAt, sessionId: sessionA
        )

        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hashB1",
            expiresAt: expiresAt, sessionId: sessionB
        )

        let revoked = try await store.tokens.revokeRefreshTokens(for: user, keepingNewestSessions: 0)

        #expect(revoked.count == 2)

        let tokenA = try await store.tokens.find(refreshTokenHash: "hashA1")
        let tokenB = try await store.tokens.find(refreshTokenHash: "hashB1")

        #expect(tokenA?.isRevoked == true)
        #expect(tokenB?.isRevoked == true)
    }

    @Test("revokeRefreshTokens(for:keepingNewestSessions:) ignores already revoked rows")
    func testRevokeIgnoresAlreadyRevoked() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        let baseTime = Date()

        let sessionA = UUID()
        let sessionB = UUID()

        var token = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hashA1",
            expiresAt: expiresAt, sessionId: sessionA
        )
        guard let model = token as? RefreshTokenModel else {
            #expect(Bool(false), "Expected RefreshTokenModel")
            return
        }
        model.createdAt = baseTime
        try await model.save(on: app.db)

        token = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "hashB1",
            expiresAt: expiresAt, sessionId: sessionB
        )
        guard let model = token as? RefreshTokenModel else {
            #expect(Bool(false), "Expected RefreshTokenModel")
            return
        }
        model.createdAt = baseTime.addingTimeInterval(10)
        try await model.save(on: app.db)

        try await store.tokens.revokeRefreshToken(withHash: "hashA1")

        let revoked = try await store.tokens.revokeRefreshTokens(for: user, keepingNewestSessions: 0)

        #expect(revoked.count == 1)
        #expect(revoked.contains(sessionB))
    }

    @Test("revokeRefreshTokens(for:keepingNewestSessions:) does not affect other users")
    func testRevokeDoesNotAffectOtherUsers() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user1 = try await store.users.create(
            identifier: .email("test1@example.com"),
            with: nil
        )

        let user2 = try await store.users.create(
            identifier: .email("test2@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)

        let sessionA = UUID()
        let sessionB = UUID()

        _ = try await store.tokens.createRefreshToken(
            for: user1,
            tokenHash: "hashA1",
            expiresAt: expiresAt, sessionId: sessionA
        )

        _ = try await store.tokens.createRefreshToken(
            for: user2,
            tokenHash: "hashB1",
            expiresAt: expiresAt, sessionId: sessionB
        )

        try await store.tokens.revokeRefreshTokens(for: user1, keepingNewestSessions: 0)

        let tokenUser1 = try await store.tokens.find(refreshTokenHash: "hashA1")
        let tokenUser2 = try await store.tokens.find(refreshTokenHash: "hashB1")

        #expect(tokenUser1?.isRevoked == true)
        #expect(tokenUser2?.isRevoked == false)
    }
}
