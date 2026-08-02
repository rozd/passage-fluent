import Fluent
import SQLKit

struct CreatePhoneResetCodeModel<UserModel: PassageUserModel>: AsyncMigration {
    var name: String { "PassageFluent.CreatePhoneResetCodeModel" }

    func prepare(on database: any Database) async throws {
        try await database.schema(PhonePasswordResetCodeModel<UserModel>.schema)
            .id()
            .field("phone", .string, .required)
            .field("code_hash", .string, .required)
            .field("user_id", UserModel.passageUserIDDataType, .required, .references(UserModel.schema, space: UserModel.space, UserModel.passageUserIDFieldKey, onDelete: .cascade))
            .field("expires_at", .datetime, .required)
            .field("failed_attempts", .int, .required)
            .field("invalidated_at", .datetime)
            .field("created_at", .datetime)
            .create()

        // Index on phone for lookup queries
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_phone_reset_codes_phone ON \(unsafeRaw: PhonePasswordResetCodeModel<UserModel>.schema) (phone)"
        ).run()

        // Index on expires_at for cleanup queries
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_phone_reset_codes_expires_at ON \(unsafeRaw: PhonePasswordResetCodeModel<UserModel>.schema) (expires_at)"
        ).run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PhonePasswordResetCodeModel<UserModel>.schema).delete()
    }
}
