//
//  CreateIdentifierModel.swift
//  passten
//
//  Created by Max Rozdobudko on 11/26/25.
//

import Fluent

// MARK: - CreateIdentifierModel

struct CreateIdentifierModel: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(IdentifierModel.schema)
            .id()
            .field("user_id", .uuid, .required, .references(UserModel.schema, "id", onDelete: .cascade))
            .field("type", .string, .required)
            .field("value", .string, .required)
            .field("verified", .bool, .required)
            .field("created_at", .datetime)
            .unique(on: "type", "value")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(IdentifierModel.schema).delete()
    }
}
