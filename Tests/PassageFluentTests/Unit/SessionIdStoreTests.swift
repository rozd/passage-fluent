import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("Session Id Store Tests")
struct SessionIdStoreTests {

    private struct Rollback: Error {}

    private func makeUser(_ store: DatabaseStore, email: String = "session@example.com") async throws -> any User {
        try await store.users.create(identifier: .email(email), with: nil)
    }

    @Test("createRefreshToken persists sessionId")
    func testCreatePersistsSessionId() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await makeUser(store)
        let sessionId = UUID()
        let expiresAt = Date().addingTimeInterval(3600)

        try await store.tokens.createRefreshToken(
            for: user, tokenHash: "with-sid", expiresAt: expiresAt, sessionId: sessionId, replacing: nil
        )

        #expect(try await store.tokens.find(refreshTokenHash: "with-sid")?.sessionId == sessionId)
    }

    @Test("Replacement token created with sessionId keeps it on the new row")
    func testReplacementKeepsSessionId() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await makeUser(store)
        let sessionId = UUID()
        let expiresAt = Date().addingTimeInterval(3600)

        let old = try await store.tokens.createRefreshToken(
            for: user, tokenHash: "old", expiresAt: expiresAt, sessionId: sessionId, replacing: nil
        )
        let new = try await store.tokens.createRefreshToken(
            for: user, tokenHash: "new", expiresAt: expiresAt, sessionId: sessionId, replacing: old
        )

        #expect(new.sessionId == sessionId)
        #expect(try await store.tokens.find(refreshTokenHash: "old")?.isRevoked == true)
    }

    @Test("revokeRefreshTokens(for:) returns distinct session ids of the rows it revoked")
    func testRevokeForUserReturnsSessionIds() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await makeUser(store)
        let other = try await makeUser(store, email: "other@example.com")
        let expiresAt = Date().addingTimeInterval(3600)
        let sessionA = UUID()
        let sessionB = UUID()
        let sessionOther = UUID()

        try await store.tokens.createRefreshToken(for: user, tokenHash: "a1", expiresAt: expiresAt, sessionId: sessionA, replacing: nil)
        try await store.tokens.createRefreshToken(for: user, tokenHash: "a2", expiresAt: expiresAt, sessionId: sessionA, replacing: nil)
        try await store.tokens.createRefreshToken(for: user, tokenHash: "b1", expiresAt: expiresAt, sessionId: sessionB, replacing: nil)
        try await store.tokens.createRefreshToken(for: other, tokenHash: "o1", expiresAt: expiresAt, sessionId: sessionOther, replacing: nil)
        try await store.tokens.revokeRefreshToken(withHash: "b1")

        let revoked = try await store.tokens.revokeRefreshTokens(for: user)

        #expect(revoked == [sessionA])
        #expect(try await store.tokens.find(refreshTokenHash: "a1")?.isRevoked == true)
        #expect(try await store.tokens.find(refreshTokenHash: "a2")?.isRevoked == true)
        #expect(try await store.tokens.find(refreshTokenHash: "o1")?.isRevoked == false)
    }

    @Test("revokeRefreshTokens(sessionId:) revokes only that session")
    func testRevokeBySessionId() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await makeUser(store)
        let expiresAt = Date().addingTimeInterval(3600)
        let sessionA = UUID()
        let sessionB = UUID()

        try await store.tokens.createRefreshToken(for: user, tokenHash: "a1", expiresAt: expiresAt, sessionId: sessionA, replacing: nil)
        try await store.tokens.createRefreshToken(for: user, tokenHash: "b1", expiresAt: expiresAt, sessionId: sessionB, replacing: nil)

        try await store.tokens.revokeRefreshTokens(sessionId: sessionA)

        #expect(try await store.tokens.find(refreshTokenHash: "a1")?.isRevoked == true)
        #expect(try await store.tokens.find(refreshTokenHash: "b1")?.isRevoked == false)
    }

    @Test("transaction rolls back rows written through the bound store when body throws")
    func testTransactionRollsBack() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await makeUser(store)
        let expiresAt = Date().addingTimeInterval(3600)

        await #expect(throws: Rollback.self) {
            try await store.transaction { bound in
                try await bound.tokens.createRefreshToken(
                    for: user, tokenHash: "rolled-back", expiresAt: expiresAt, sessionId: UUID(), replacing: nil
                )
                throw Rollback()
            }
        }

        #expect(try await store.tokens.find(refreshTokenHash: "rolled-back") == nil)
        #expect(try await RefreshTokenModel.query(on: app.db).count() == 0)
    }

    @Test("transaction commits rows written through the bound store when body returns")
    func testTransactionCommits() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await makeUser(store)
        let expiresAt = Date().addingTimeInterval(3600)
        let sessionId = UUID()

        let returned: UUID = try await store.transaction { bound in
            #expect((bound as? DatabaseStore)?.database != nil)
            let token = try await bound.tokens.createRefreshToken(
                for: user, tokenHash: "committed", expiresAt: expiresAt, sessionId: sessionId, replacing: nil
            )
            return token.sessionId
        }

        #expect(returned == sessionId)
        #expect(try await store.tokens.find(refreshTokenHash: "committed")?.sessionId == sessionId)
    }

    @Test("Nested replacing write inside transaction rolls back with the outer throw")
    func testNestedTransactionRollsBack() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await makeUser(store)
        let expiresAt = Date().addingTimeInterval(3600)
        let sessionId = UUID()

        let old = try await store.tokens.createRefreshToken(
            for: user, tokenHash: "old", expiresAt: expiresAt, sessionId: sessionId, replacing: nil
        )

        await #expect(throws: Rollback.self) {
            try await store.transaction { bound in
                _ = try await bound.tokens.revokeRefreshTokens(for: user)
                try await bound.tokens.createRefreshToken(
                    for: user, tokenHash: "new", expiresAt: expiresAt, sessionId: sessionId, replacing: old
                )
                throw Rollback()
            }
        }

        #expect(try await store.tokens.find(refreshTokenHash: "new") == nil)
        #expect(try await store.tokens.find(refreshTokenHash: "old")?.isRevoked == false)
    }

    @Test("Migration round trip with session_id column")
    func testMigrateRevertRoundTrip() async throws {
        let app = try await createTestApplication()
        _ = DatabaseStore(app: app, db: app.db)
        try await app.autoMigrate()
        try await app.autoRevert()
        try await app.autoMigrate()
        try await shutdownTestApplication(app)
    }
}
