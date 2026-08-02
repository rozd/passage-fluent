import Fluent

// MARK: - CreateUserModel

struct CreateUserModel: AsyncMigration {
    var name: String { "PassageFluent.CreateUserModel" }

    func prepare(on database: any Database) async throws {
        try await database.schema(DefaultUserModel.schema)
            .id()
            .field("password_hash", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(DefaultUserModel.schema).delete()
    }
}
