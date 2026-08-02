import Fluent
import SQLKit

struct CreateRefreshTokenModel<UserModel: PassageUserModel>: AsyncMigration {
    var name: String { "PassageFluent.CreateRefreshTokenModel" }

    func prepare(on database: any Database) async throws {
        try await database.schema(RefreshTokenModel<UserModel>.schema)
            .id()
            .field("token_hash", .string, .required)
            .field("user_id", UserModel.passageUserIDDataType, .required, .references(UserModel.schema, space: UserModel.space, UserModel.passageUserIDFieldKey, onDelete: .cascade))
            .field("expires_at", .datetime, .required)
            .field("created_at", .datetime)
            .field("revoked_at", .datetime)
            .field("replaced_by", .uuid)
            .unique(on: "token_hash")
            .create()

        // Add index on user_id for revokeRefreshToken(for:) query performance
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_refresh_tokens_user_id ON \(unsafeRaw: RefreshTokenModel<UserModel>.schema) (user_id)"
        ).run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(RefreshTokenModel<UserModel>.schema).delete()
    }
}
