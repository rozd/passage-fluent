//
//  CreateEmailResetCodeModel.swift
//  passten
//
//  Created by Max Rozdobudko on 12/01/25.
//

import Fluent
import SQLKit

struct CreateEmailResetCodeModel: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(EmailResetCodeModel.schema)
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
            "CREATE INDEX idx_email_reset_codes_email ON \(unsafeRaw: EmailResetCodeModel.schema) (email)"
        ).run()

        // Index on expires_at for cleanup queries
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_email_reset_codes_expires_at ON \(unsafeRaw: EmailResetCodeModel.schema) (expires_at)"
        ).run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(EmailResetCodeModel.schema).delete()
    }
}
