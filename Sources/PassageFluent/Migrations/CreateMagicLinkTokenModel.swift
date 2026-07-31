import Fluent
import SQLKit

struct CreateMagicLinkTokenModel: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(MagicLinkTokenModel.schema)
            .id()
            .field("email", .string, .required)
            .field("token_hash", .string, .required)
            .field("user_id", .uuid, .references(UserModel.schema, "id", onDelete: .cascade))
            .field("session_token_hash", .string)
            .field("expires_at", .datetime, .required)
            .field("failed_attempts", .int, .required)
            .field("invalidated_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "token_hash")
            .create()

        // Index on token_hash for findEmailMagicLink(tokenHash:) query performance
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_magic_link_tokens_token_hash ON \(unsafeRaw: MagicLinkTokenModel.schema) (token_hash)"
        ).run()

        // Index on email for invalidateEmailMagicLinks(for:) query performance
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_magic_link_tokens_email ON \(unsafeRaw: MagicLinkTokenModel.schema) (email)"
        ).run()

        // Index on expires_at for future cleanup queries
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_magic_link_tokens_expires_at ON \(unsafeRaw: MagicLinkTokenModel.schema) (expires_at)"
        ).run()

        // Index on invalidated_at for active-row filtering in findEmailMagicLink
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_magic_link_tokens_invalidated_at ON \(unsafeRaw: MagicLinkTokenModel.schema) (invalidated_at)"
        ).run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(MagicLinkTokenModel.schema).delete()
    }
}
