import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("Token Workflow Integration Tests")
struct TokenWorkflowIntegrationTests {

    // MARK: - Complete Authentication Flow

    @Test("Complete login with refresh token flow")
    func testLoginWithRefreshToken() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // 1. Register user
        let user = try await store.users.create(
            identifier: .email("login@example.com"),
            with: .password("hashedpassword")
        )

        // 2. Create refresh token on login
        let expiresAt = Date().addingTimeInterval(86400 * 30) // 30 days
        let refreshToken = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "initialrefreshhash",
            expiresAt: expiresAt
        )

        #expect(refreshToken.isValid == true)

        // 3. Verify token can be found and has user loaded
        let foundToken = try await store.tokens.find(refreshTokenHash: "initialrefreshhash")
        #expect(foundToken != nil)
        #expect(foundToken?.user.email == "login@example.com")
    }

    // MARK: - Token Rotation Flow

    @Test("Complete token rotation flow")
    func testTokenRotationFlow() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // 1. Register user
        let user = try await store.users.create(
            identifier: .email("rotate@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(86400)

        // 2. Create initial token
        let token1 = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "token1hash",
            expiresAt: expiresAt
        )

        #expect(token1.isValid == true)
        #expect(token1.replacedBy == nil)

        // 3. Rotate to token 2
        let token2 = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "token2hash",
            expiresAt: expiresAt,
            replacing: token1
        )

        #expect(token2.isValid == true)

        // 4. Verify token1 is revoked and points to token2
        let foundToken1 = try await store.tokens.find(refreshTokenHash: "token1hash")
        #expect(foundToken1?.isRevoked == true)
        // replacedBy should be set (can't compare existential types directly)
        #expect(foundToken1?.replacedBy != nil)

        // 5. Rotate to token 3
        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "token3hash",
            expiresAt: expiresAt,
            replacing: token2
        )

        // 6. Verify complete chain
        let finalToken1 = try await store.tokens.find(refreshTokenHash: "token1hash")
        let finalToken2 = try await store.tokens.find(refreshTokenHash: "token2hash")
        let finalToken3 = try await store.tokens.find(refreshTokenHash: "token3hash")

        #expect(finalToken1?.isRevoked == true)
        #expect(finalToken1?.replacedBy != nil) // points to token2
        #expect(finalToken2?.isRevoked == true)
        #expect(finalToken2?.replacedBy != nil) // points to token3
        #expect(finalToken3?.isRevoked == false)
        #expect(finalToken3?.isValid == true)
    }

    // MARK: - Token Reuse Detection

    @Test("Detect and handle token reuse attack")
    func testTokenReuseDetection() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // 1. Register user
        let user = try await store.users.create(
            identifier: .email("reuse@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(86400)

        // 2. Create initial token
        let token1 = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "originalhash",
            expiresAt: expiresAt
        )

        // 3. Token is rotated legitimately
        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "newhash",
            expiresAt: expiresAt,
            replacing: token1
        )

        // 4. Attacker tries to use token1 (already rotated)
        // Application would detect token1.isRevoked == true
        let reusedToken = try await store.tokens.find(refreshTokenHash: "originalhash")
        #expect(reusedToken?.isRevoked == true)

        // 5. Application revokes entire token family starting from reused token
        try await store.tokens.revoke(refreshTokenFamilyStartingFrom: reusedToken!)

        // 6. All tokens in family should be revoked
        let finalToken1 = try await store.tokens.find(refreshTokenHash: "originalhash")
        let finalToken2 = try await store.tokens.find(refreshTokenHash: "newhash")

        #expect(finalToken1?.isRevoked == true)
        #expect(finalToken2?.isRevoked == true)

        // 7. User must re-authenticate
    }

    // MARK: - Logout Flow

    @Test("Complete logout flow revokes all tokens")
    func testLogoutFlow() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // 1. Register user
        let user = try await store.users.create(
            identifier: .email("logout@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(86400)

        // 2. User logs in from multiple devices (multiple tokens)
        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "device1hash",
            expiresAt: expiresAt
        )
        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "device2hash",
            expiresAt: expiresAt
        )
        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "device3hash",
            expiresAt: expiresAt
        )

        // 3. Verify all tokens are valid
        let device1 = try await store.tokens.find(refreshTokenHash: "device1hash")
        let device2 = try await store.tokens.find(refreshTokenHash: "device2hash")
        let device3 = try await store.tokens.find(refreshTokenHash: "device3hash")

        #expect(device1?.isValid == true)
        #expect(device2?.isValid == true)
        #expect(device3?.isValid == true)

        // 4. User logs out from all devices
        try await store.tokens.revokeRefreshToken(for: user)

        // 5. All tokens should be revoked
        let finalDevice1 = try await store.tokens.find(refreshTokenHash: "device1hash")
        let finalDevice2 = try await store.tokens.find(refreshTokenHash: "device2hash")
        let finalDevice3 = try await store.tokens.find(refreshTokenHash: "device3hash")

        #expect(finalDevice1?.isRevoked == true)
        #expect(finalDevice2?.isRevoked == true)
        #expect(finalDevice3?.isRevoked == true)
    }

    @Test("Single device logout revokes only that token")
    func testSingleDeviceLogout() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // 1. Register user
        let user = try await store.users.create(
            identifier: .email("single@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(86400)

        // 2. User logs in from multiple devices
        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "keepthis",
            expiresAt: expiresAt
        )
        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "revokethis",
            expiresAt: expiresAt
        )

        // 3. User logs out from only one device
        try await store.tokens.revokeRefreshToken(withHash: "revokethis")

        // 4. Only that token should be revoked
        let keptToken = try await store.tokens.find(refreshTokenHash: "keepthis")
        let revokedToken = try await store.tokens.find(refreshTokenHash: "revokethis")

        #expect(keptToken?.isValid == true)
        #expect(revokedToken?.isRevoked == true)
    }

    // MARK: - Exchange Token Flow

    @Test("Complete OAuth exchange token flow")
    func testOAuthExchangeTokenFlow() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // 1. User authenticates via OAuth, create exchange token
        let user = try await store.users.create(
            identifier: .federated("google", userId: "google-123"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(60) // 60 second TTL
        let exchangeToken = try await store.exchangeTokens.createExchangeToken(
            for: user,
            tokenHash: "oauthexchangehash",
            expiresAt: expiresAt
        )

        #expect(exchangeToken.isValid == true)
        // user is always loaded for exchange tokens

        // 2. Client receives exchange code in redirect URL

        // 3. Client exchanges code for tokens
        let foundToken = try await store.exchangeTokens.find(exchangeTokenHash: "oauthexchangehash")
        #expect(foundToken != nil)
        #expect(foundToken?.isValid == true)

        // 4. Mark exchange token as consumed
        try await store.exchangeTokens.consume(exchangeToken: foundToken!)

        // 5. Token should no longer be valid
        let consumedToken = try await store.exchangeTokens.find(exchangeTokenHash: "oauthexchangehash")
        #expect(consumedToken?.isConsumed == true)
        #expect(consumedToken?.isValid == false)

        // 6. Attempted reuse should fail (token is invalid)
        let reusedToken = try await store.exchangeTokens.find(exchangeTokenHash: "oauthexchangehash")
        #expect(reusedToken?.isValid == false)
    }

    @Test("Exchange token cleanup removes expired tokens")
    func testExchangeTokenCleanup() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // 1. Create user
        let user = try await store.users.create(
            identifier: .email("cleanup@example.com"),
            with: nil
        )

        // 2. Create mix of expired and valid tokens
        let pastDate = Date().addingTimeInterval(-120) // 2 minutes ago
        let futureDate = Date().addingTimeInterval(60)

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
            tokenHash: "valid1",
            expiresAt: futureDate
        )

        // 3. Run cleanup
        try await store.exchangeTokens.cleanupExpiredTokens(before: Date())

        // 4. Verify cleanup results
        let findExpired1 = try await store.exchangeTokens.find(exchangeTokenHash: "expired1")
        let findExpired2 = try await store.exchangeTokens.find(exchangeTokenHash: "expired2")
        let findValid1 = try await store.exchangeTokens.find(exchangeTokenHash: "valid1")

        #expect(findExpired1 == nil) // Cleaned up
        #expect(findExpired2 == nil) // Cleaned up
        #expect(findValid1 != nil)   // Still exists
    }

    // MARK: - Token Expiration

    @Test("Expired tokens are marked invalid")
    func testTokenExpiration() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // 1. Create user
        let user = try await store.users.create(
            identifier: .email("expire@example.com"),
            with: nil
        )

        // 2. Create expired token
        let pastDate = Date().addingTimeInterval(-3600) // 1 hour ago
        _ = try await store.tokens.createRefreshToken(
            for: user,
            tokenHash: "expiredhash",
            expiresAt: pastDate
        )

        // 3. Token should be found but invalid
        let expiredToken = try await store.tokens.find(refreshTokenHash: "expiredhash")
        #expect(expiredToken != nil)
        #expect(expiredToken?.isExpired == true)
        #expect(expiredToken?.isValid == false)
    }
}
