import Fluent
import SQLKit

struct CreatePasskeyCredentialModel: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PasskeyCredentialModel.schema)
            .id()
            .field("user_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .field("credential_id", .string, .required)
            .field("public_key", .data, .required)
            .field("sign_count", .uint32, .required)
            .field("uv_initialized", .bool, .required)
            .field("transports", .array(of: .string), .required)
            .field("backup_eligible", .bool, .required)
            .field("is_backed_up", .bool, .required)
            .field("aaguid", .string)
            .field("attestation_format", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "credential_id")
            .create()

        // Index on credential_id for find(byCredentialID:) query performance.
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_passkey_credentials_credential_id ON \(unsafeRaw: PasskeyCredentialModel.schema) (credential_id)"
        ).run()

        // Index on user_id for listPasskeyCredentials(forUser:) query performance.
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_passkey_credentials_user_id ON \(unsafeRaw: PasskeyCredentialModel.schema) (user_id)"
        ).run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PasskeyCredentialModel.schema).delete()
    }
}
