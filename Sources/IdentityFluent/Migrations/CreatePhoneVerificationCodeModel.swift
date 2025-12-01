//
//  CreatePhoneVerificationCodeModel.swift
//  passten
//
//  Created by Max Rozdobudko on 11/29/25.
//

import Fluent
import SQLKit

struct CreatePhoneVerificationCodeModel: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PhoneVerificationCodeModel.schema)
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
            "CREATE INDEX idx_phone_verification_codes_phone ON \(unsafeRaw: PhoneVerificationCodeModel.schema) (phone)"
        ).run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PhoneVerificationCodeModel.schema).delete()
    }
}
