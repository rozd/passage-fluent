import Fluent
import SQLKit

struct CreatePhoneResetCodeModel: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PhoneResetCodeModel.schema)
            .id()
            .field("phone", .string, .required)
            .field("code_hash", .string, .required)
            .field("user_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .field("expires_at", .datetime, .required)
            .field("failed_attempts", .int, .required)
            .field("invalidated_at", .datetime)
            .field("created_at", .datetime)
            .create()

        // Index on phone for lookup queries
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_phone_reset_codes_phone ON \(unsafeRaw: PhoneResetCodeModel.schema) (phone)"
        ).run()

        // Index on expires_at for cleanup queries
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_phone_reset_codes_expires_at ON \(unsafeRaw: PhoneResetCodeModel.schema) (expires_at)"
        ).run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PhoneResetCodeModel.schema).delete()
    }
}
