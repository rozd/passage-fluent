import Fluent
import SQLKit

struct CreatePasskeyChallengeModel: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PasskeyChallengeModel.schema)
            .id()
            .field("identifier", .json)
            .field("user_id", .uuid, .references(UserModel.schema, "id", onDelete: .cascade))
            .field("kind", .string, .required)
            .field("challenge_hash", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("consumed_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "challenge_hash")
            .create()

        // Index on challenge_hash for find(passkeyChallengeMatching:) query performance.
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_passkey_challenges_challenge_hash ON \(unsafeRaw: PasskeyChallengeModel.schema) (challenge_hash)"
        ).run()

        // Index on expires_at for cleanupExpiredPasskeyChallenges(before:) query performance.
        try await (database as? any SQLDatabase)?.raw(
            "CREATE INDEX idx_passkey_challenges_expires_at ON \(unsafeRaw: PasskeyChallengeModel.schema) (expires_at)"
        ).run()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PasskeyChallengeModel.schema).delete()
    }
}
