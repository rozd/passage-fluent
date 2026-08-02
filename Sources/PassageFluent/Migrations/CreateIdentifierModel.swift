import Fluent

// MARK: - CreateIdentifierModel

struct CreateIdentifierModel<UserModel: PassageUserModel>: AsyncMigration {
    var name: String { "PassageFluent.CreateIdentifierModel" }

    func prepare(on database: any Database) async throws {
        try await database.schema(IdentifierModel<UserModel>.schema)
            .id()
            .field("user_id", UserModel.passageUserIDDataType, .required, .references(UserModel.schema, space: UserModel.space, UserModel.passageUserIDFieldKey, onDelete: .cascade))
            .field("type", .string, .required)
            .field("value", .string, .required)
            .field("provider", .string)
            .field("verified", .bool, .required)
            .field("created_at", .datetime)
            .unique(on: "type", "provider", "value")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(IdentifierModel<UserModel>.schema).delete()
    }
}
