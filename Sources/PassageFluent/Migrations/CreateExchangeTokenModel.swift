import Fluent
import SQLKit

struct CreateExchangeTokenModel<UserModel: PassageUserModel>: AsyncMigration {
    var name: String { "PassageFluent.CreateExchangeTokenModel" }

    func prepare(on database: any Database) async throws {
        try await database.schema(ExchangeTokenModel<UserModel>.schema)
            .id()
            .field("token_hash", .string, .required)
            .field("user_id", UserModel.passageUserIDDataType, .required, .references(UserModel.schema, space: UserModel.space, UserModel.passageUserIDFieldKey, onDelete: .cascade))
            .field("expires_at", .datetime, .required)
            .field("consumed_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "token_hash")
            .create()

        // Add index on token_hash for find(exchangeTokenHash:) query performance
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_exchange_tokens_token_hash ON \(unsafeRaw: ExchangeTokenModel<UserModel>.schema) (token_hash)"
        ).run()

        // Add index on expires_at for cleanup queries
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_exchange_tokens_expires_at ON \(unsafeRaw: ExchangeTokenModel<UserModel>.schema) (expires_at)"
        ).run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(ExchangeTokenModel<UserModel>.schema).delete()
    }
}
