import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("RefreshTokenModel Tests")
struct RefreshTokenModelTests {

    // MARK: - Schema Tests

    @Test("Schema name is 'refresh_tokens'")
    func testSchemaName() {
        #expect(RefreshTokenModel.schema == "refresh_tokens")
    }

    // MARK: - Initialization Tests with Database

    @Test("Full initialization sets all provided values")
    func testFullInitialization() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let uuid = UUID()
        let expiresAt = Date().addingTimeInterval(3600)
        let revokedAt = Date()
        let replacedBy = UUID()

        let token = RefreshTokenModel(
            id: uuid,
            tokenHash: "tokenhash123",
            userID: try user.requireID(),
            expiresAt: expiresAt,
            revokedAt: revokedAt,
            replacedBy: replacedBy
        )
        try await token.save(on: app.db)

        #expect(token.id == uuid)
        #expect(token.tokenHash == "tokenhash123")
        #expect(token.expiresAt == expiresAt)
        #expect(token.revokedAt == revokedAt)
        #expect(token.replacedBy == replacedBy)
    }

    @Test("Minimal initialization with required values")
    func testMinimalInitialization() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let expiresAt = Date().addingTimeInterval(3600)

        let token = RefreshTokenModel(
            tokenHash: "tokenhash123",
            userID: try user.requireID(),
            expiresAt: expiresAt
        )
        try await token.save(on: app.db)

        #expect(token.id != nil)
        #expect(token.tokenHash == "tokenhash123")
        #expect(token.expiresAt == expiresAt)
        #expect(token.revokedAt == nil)
        #expect(token.replacedBy == nil)
    }

    // MARK: - RefreshToken Protocol Tests

    @Test("isExpired returns false for future expiration date")
    func testIsExpiredFalseForFuture() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let token = RefreshTokenModel(
            tokenHash: "hash",
            userID: try user.requireID(),
            expiresAt: Date().addingTimeInterval(3600)
        )
        try await token.save(on: app.db)

        #expect(token.isExpired == false)
    }

    @Test("isExpired returns true for past expiration date")
    func testIsExpiredTrueForPast() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let token = RefreshTokenModel(
            tokenHash: "hash",
            userID: try user.requireID(),
            expiresAt: Date().addingTimeInterval(-3600)
        )
        try await token.save(on: app.db)

        #expect(token.isExpired == true)
    }

    @Test("isRevoked returns false when revokedAt is nil")
    func testIsRevokedFalseWhenNil() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let token = RefreshTokenModel(
            tokenHash: "hash",
            userID: try user.requireID(),
            expiresAt: Date().addingTimeInterval(3600),
            revokedAt: nil
        )
        try await token.save(on: app.db)

        #expect(token.isRevoked == false)
    }

    @Test("isRevoked returns true when revokedAt is set")
    func testIsRevokedTrueWhenSet() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let token = RefreshTokenModel(
            tokenHash: "hash",
            userID: try user.requireID(),
            expiresAt: Date().addingTimeInterval(3600),
            revokedAt: Date()
        )
        try await token.save(on: app.db)

        #expect(token.isRevoked == true)
    }

    @Test("isValid returns true when not expired and not revoked")
    func testIsValidTrueWhenValid() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let token = RefreshTokenModel(
            tokenHash: "hash",
            userID: try user.requireID(),
            expiresAt: Date().addingTimeInterval(3600),
            revokedAt: nil
        )
        try await token.save(on: app.db)

        #expect(token.isValid == true)
    }

    @Test("isValid returns false when expired")
    func testIsValidFalseWhenExpired() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let token = RefreshTokenModel(
            tokenHash: "hash",
            userID: try user.requireID(),
            expiresAt: Date().addingTimeInterval(-3600),
            revokedAt: nil
        )
        try await token.save(on: app.db)

        #expect(token.isValid == false)
    }

    @Test("isValid returns false when revoked")
    func testIsValidFalseWhenRevoked() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let token = RefreshTokenModel(
            tokenHash: "hash",
            userID: try user.requireID(),
            expiresAt: Date().addingTimeInterval(3600),
            revokedAt: Date()
        )
        try await token.save(on: app.db)

        #expect(token.isValid == false)
    }

    @Test("isValid returns false when both expired and revoked")
    func testIsValidFalseWhenBoth() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let token = RefreshTokenModel(
            tokenHash: "hash",
            userID: try user.requireID(),
            expiresAt: Date().addingTimeInterval(-3600),
            revokedAt: Date()
        )
        try await token.save(on: app.db)

        #expect(token.isValid == false)
    }

    // MARK: - Token Chain Tests

    @Test("replacedBy tracks token rotation chain")
    func testReplacedByTracking() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = UserModel()
        try await user.save(on: app.db)

        let oldTokenId = UUID()
        let newTokenId = UUID()

        let oldToken = RefreshTokenModel(
            id: oldTokenId,
            tokenHash: "oldhash",
            userID: try user.requireID(),
            expiresAt: Date().addingTimeInterval(3600),
            revokedAt: Date(),
            replacedBy: newTokenId
        )
        try await oldToken.save(on: app.db)

        #expect(oldToken.id == oldTokenId)
        #expect(oldToken.replacedBy == newTokenId)
        #expect(oldToken.isRevoked == true)
    }
}
