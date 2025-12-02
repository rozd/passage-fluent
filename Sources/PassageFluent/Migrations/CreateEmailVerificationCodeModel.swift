import Fluent
import SQLKit

struct CreateEmailVerificationCodeModel: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(EmailVerificationCodeModel.schema)
            .id()
            .field("email", .string, .required)
            .field("code_hash", .string, .required)
            .field("user_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .field("expires_at", .datetime, .required)
            .field("failed_attempts", .int, .required)
            .field("invalidated_at", .datetime)
            .field("created_at", .datetime)
            .create()

        // Index on email for lookup queries
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_email_verification_codes_email ON \(unsafeRaw: EmailVerificationCodeModel.schema) (email)"
        ).run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(EmailVerificationCodeModel.schema).delete()
    }
}
