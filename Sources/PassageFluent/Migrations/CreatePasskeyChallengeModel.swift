import Fluent
import SQLKit

struct CreatePasskeyChallengeModel<UserModel: PassageUserModel>: AsyncMigration {
    var name: String { "PassageFluent.CreatePasskeyChallengeModel" }

    func prepare(on database: any Database) async throws {
        try await database.schema(PasskeyChallengeModel<UserModel>.schema)
            .id()
            .field("identifier", .json)
            .field("user_id", UserModel.passageUserIDDataType, .references(UserModel.schema, space: UserModel.space, UserModel.passageUserIDFieldKey, onDelete: .cascade))
            .field("kind", .string, .required)
            .field("challenge_hash", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("consumed_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "challenge_hash")
            .create()

        // Index on challenge_hash for find(passkeyChallengeMatching:) query performance.
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_passkey_challenges_challenge_hash ON \(unsafeRaw: PasskeyChallengeModel<UserModel>.schema) (challenge_hash)"
        ).run()

        // Index on expires_at for cleanupExpiredPasskeyChallenges(before:) query performance.
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_passkey_challenges_expires_at ON \(unsafeRaw: PasskeyChallengeModel<UserModel>.schema) (expires_at)"
        ).run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PasskeyChallengeModel<UserModel>.schema).delete()
    }
}
