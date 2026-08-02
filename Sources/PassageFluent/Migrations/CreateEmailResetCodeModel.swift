import Fluent
import SQLKit

struct CreateEmailResetCodeModel<UserModel: PassageUserModel>: AsyncMigration {
    var name: String { "PassageFluent.CreateEmailResetCodeModel" }

    func prepare(on database: any Database) async throws {
        try await database.schema(EmailPasswordResetCodeModel<UserModel>.schema)
            .id()
            .field("email", .string, .required)
            .field("code_hash", .string, .required)
            .field("user_id", UserModel.passageUserIDDataType, .required, .references(UserModel.schema, space: UserModel.space, UserModel.passageUserIDFieldKey, onDelete: .cascade))
            .field("expires_at", .datetime, .required)
            .field("failed_attempts", .int, .required)
            .field("invalidated_at", .datetime)
            .field("created_at", .datetime)
            .create()

        // Index on email for lookup queries
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_email_reset_codes_email ON \(unsafeRaw: EmailPasswordResetCodeModel<UserModel>.schema) (email)"
        ).run()

        // Index on expires_at for cleanup queries
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_email_reset_codes_expires_at ON \(unsafeRaw: EmailPasswordResetCodeModel<UserModel>.schema) (expires_at)"
        ).run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(EmailPasswordResetCodeModel<UserModel>.schema).delete()
    }
}
