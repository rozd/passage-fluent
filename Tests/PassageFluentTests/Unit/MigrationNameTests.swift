import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("Migration Name Tests")
struct MigrationNameTests {

    /// Assert each generic migration's `.name` is pinned to the exact legacy string.
    /// This prevents re-running migrations on deployed databases when genericizing.
    @Test("Generic migrations have pinned legacy names")
    func testGenericMigrationNames() {
        let expectedNames: [(migration: AsyncMigration, name: String)] = [
            (CreateIdentifierModel<DefaultUserModel>(), "PassageFluent.CreateIdentifierModel"),
            (CreateRefreshTokenModel<DefaultUserModel>(), "PassageFluent.CreateRefreshTokenModel"),
            (CreateEmailVerificationCodeModel<DefaultUserModel>(), "PassageFluent.CreateEmailVerificationCodeModel"),
            (CreatePhoneVerificationCodeModel<DefaultUserModel>(), "PassageFluent.CreatePhoneVerificationCodeModel"),
            (CreateEmailResetCodeModel<DefaultUserModel>(), "PassageFluent.CreateEmailResetCodeModel"),
            (CreatePhoneResetCodeModel<DefaultUserModel>(), "PassageFluent.CreatePhoneResetCodeModel"),
            (CreateExchangeTokenModel<DefaultUserModel>(), "PassageFluent.CreateExchangeTokenModel"),
            (CreateMagicLinkTokenModel<DefaultUserModel>(), "PassageFluent.CreateMagicLinkTokenModel"),
            (CreatePasskeyCredentialModel<DefaultUserModel>(), "PassageFluent.CreatePasskeyCredentialModel"),
            (CreatePasskeyChallengeModel<DefaultUserModel>(), "PassageFluent.CreatePasskeyChallengeModel"),
        ]

        for (migration, expectedName) in expectedNames {
            #expect(migration.name == expectedName, "Migration name mismatch for \(migration.name)")
        }
    }

    /// Island-mode integration: verify that autoMigrate() registers exactly the 11 expected migrations.
    @Test("Island mode registers exactly 11 migrations with correct names")
    func testIslandModeRegisters11Migrations() async throws {
        let app = try await createTestApplication()
        defer { Task { try? await shutdownTestApplication(app) } }

        _ = DatabaseStore(app: app, db: app.db)
        try await app.autoMigrate()

        // Query _fluent_migrations table for all migration names
        guard let sqlDb = app.db as? any SQLDatabase else {
            #expect(Bool(false), "Database is not a SQLDatabase")
            return
        }

        let results = try await sqlDb.raw("SELECT name FROM _fluent_migrations ORDER BY name").all()
        let migrationNames: [String] = try results.map { row in
            try row.decode(column: "name", as: String.self)
        }

        let expectedNames = [
            "PassageFluent.CreateUserModel",
            "PassageFluent.CreateIdentifierModel",
            "PassageFluent.CreateRefreshTokenModel",
            "PassageFluent.CreateEmailVerificationCodeModel",
            "PassageFluent.CreatePhoneVerificationCodeModel",
            "PassageFluent.CreateEmailResetCodeModel",
            "PassageFluent.CreatePhoneResetCodeModel",
            "PassageFluent.CreateExchangeTokenModel",
            "PassageFluent.CreateMagicLinkTokenModel",
            "PassageFluent.CreatePasskeyCredentialModel",
            "PassageFluent.CreatePasskeyChallengeModel",
        ].sorted()

        #expect(migrationNames == expectedNames, "Island mode should register exactly 11 migrations with exact names")
    }
}
