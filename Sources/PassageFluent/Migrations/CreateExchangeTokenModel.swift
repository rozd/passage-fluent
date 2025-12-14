import Fluent
import SQLKit

struct CreateExchangeTokenModel: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(ExchangeTokenModel.schema)
            .id()
            .field("token_hash", .string, .required)
            .field("user_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .field("expires_at", .datetime, .required)
            .field("consumed_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "token_hash")
            .create()

        // Add index on token_hash for find(exchangeTokenHash:) query performance
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_exchange_tokens_token_hash ON \(unsafeRaw: ExchangeTokenModel.schema) (token_hash)"
        ).run()

        // Add index on expires_at for cleanup queries
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_exchange_tokens_expires_at ON \(unsafeRaw: ExchangeTokenModel.schema) (expires_at)"
        ).run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(ExchangeTokenModel.schema).delete()
    }
}
