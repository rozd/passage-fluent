//
//  CreateUserModel.swift
//  passten
//
//  Created by Max Rozdobudko on 11/26/25.
//

import Fluent

// MARK: - CreateUserModel

struct CreateUserModel: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(UserModel.schema)
            .id()
            .field("password_hash", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(UserModel.schema).delete()
    }
}
