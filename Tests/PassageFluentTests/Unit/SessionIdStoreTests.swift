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

    @Test("AddRefreshTokenSessionId migration creates index")
    func testMigrationCreatesIndex() async throws {
        let app = try await createTestApplication()
        defer { Task { try? await shutdownTestApplication(app) } }

        _ = DatabaseStore(app: app, db: app.db)
        try await app.autoMigrate()

        guard let sqlDb = app.db as? any SQLDatabase else {
            #expect(Bool(false), "Database must be SQLDatabase")
            return
        }

        // Check that the index exists
        let indexRows = try await sqlDb.raw(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_refresh_tokens_session_id'"
        ).all()

        #expect(indexRows.count == 1, "Index idx_refresh_tokens_session_id should exist after migration")

        // Revert migrations
        try await app.autoRevert()

        // Check that the index is gone
        let indexRowsAfterRevert = try await sqlDb.raw(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_refresh_tokens_session_id'"
        ).all()

        #expect(indexRowsAfterRevert.count == 0, "Index idx_refresh_tokens_session_id should be gone after revert")
    }

    @Test("AddRefreshTokenSessionId drops existing refresh tokens on upgrade")
    func testMigrationDropsExistingTokensOnUpgrade() async throws {
        let app = try await createTestApplication()
        defer { Task { try? await shutdownTestApplication(app) } }

        guard let sqlDb = app.db as? any SQLDatabase else {
            #expect(Bool(false), "Database must be SQLDatabase")
            return
        }

        // Manually register only migrations up to and including CreateRefreshTokenModel
        // This simulates a database with the old schema (no session_id column)
        app.migrations.add(CreateUserModel())
        app.migrations.add(CreateIdentifierModel<DefaultUserModel>())
        app.migrations.add(CreateRefreshTokenModel<DefaultUserModel>())

        try await app.autoMigrate()

        // Insert test data: create a user and a refresh token in the old schema
        let userId = UUID()
        try await sqlDb.raw(
            "INSERT INTO users (id, password_hash, created_at) VALUES (\(bind: userId.uuidString), 'hash', datetime('now'))"
        ).run()

        let tokenId = UUID()
        let tokenHash = "old-token-hash"
        let expiresAt = Date().addingTimeInterval(3600)
        try await sqlDb.raw(
            """
            INSERT INTO refresh_tokens (id, token_hash, user_id, expires_at, created_at)
            VALUES (\(bind: tokenId.uuidString), \(bind: tokenHash), \(bind: userId.uuidString), \(bind: expiresAt.ISO8601Format()), datetime('now'))
            """
        ).run()

        // Verify the token was inserted
        let countBefore = try await sqlDb.raw(
            "SELECT COUNT(*) as count FROM refresh_tokens"
        ).all()
        let rowBefore = try #require(countBefore.first)
        let countBeforeValue = try rowBefore.decode(column: "count", as: Int.self)
        #expect(countBeforeValue == 1, "Should have inserted 1 refresh token before upgrade")

        // Now register and run the AddRefreshTokenSessionId migration
        app.migrations.add(AddRefreshTokenSessionId<DefaultUserModel>())
        try await app.autoMigrate()

        // Verify the table now has session_id column by checking table schema
        let tableInfo = try await sqlDb.raw("PRAGMA table_info(refresh_tokens)").all()
        let columnNames: [String] = try tableInfo.map { row in
            try row.decode(column: "name", as: String.self)
        }
        #expect(columnNames.contains("session_id"), "Table should have session_id column after migration")

        // Verify all old tokens were dropped (data loss on upgrade is intentional)
        let countAfter = try await sqlDb.raw(
            "SELECT COUNT(*) as count FROM refresh_tokens"
        ).all()
        let rowAfter = try #require(countAfter.first)
        let countAfterValue = try rowAfter.decode(column: "count", as: Int.self)
        #expect(countAfterValue == 0, "All existing refresh tokens should be dropped on upgrade to session_id schema")
    }
}
