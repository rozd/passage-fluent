import Fluent
import SQLKit

struct AddRefreshTokenSessionId<UserModel: PassageUserModel>: AsyncMigration {
    var name: String { "PassageFluent.AddRefreshTokenSessionId" }

    func prepare(on database: any Database) async throws {
        try await database.schema(RefreshTokenModel<UserModel>.schema).delete()
        try await CreateRefreshTokenModel<UserModel>.createSchema(on: database, withSessionId: true)

        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_refresh_tokens_session_id ON \(unsafeRaw: RefreshTokenModel<UserModel>.schema) (session_id)"
        ).run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(RefreshTokenModel<UserModel>.schema).delete()
        try await CreateRefreshTokenModel<UserModel>.createSchema(on: database, withSessionId: false)
    }
}
