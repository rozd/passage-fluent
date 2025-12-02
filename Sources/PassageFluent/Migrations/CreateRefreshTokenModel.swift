import Fluent
import SQLKit

struct CreateRefreshTokenModel: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(RefreshTokenModel.schema)
            .id()
            .field("token_hash", .string, .required)
            .field("user_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .field("expires_at", .datetime, .required)
            .field("created_at", .datetime)
            .field("revoked_at", .datetime)
            .field("replaced_by", .uuid)
            .unique(on: "token_hash")
            .create()

        // Add index on user_id for revokeRefreshToken(for:) query performance
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_refresh_tokens_user_id ON \(unsafeRaw: RefreshTokenModel.schema) (user_id)"
        ).run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(RefreshTokenModel.schema).delete()
    }
}
