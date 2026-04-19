import Foundation
import Passage
import Fluent

final class PasskeyChallengeModel: Model, @unchecked Sendable {
    static let schema = "passkey_challenges"

    @ID(key: .id)
    var id: UUID?

    @OptionalParent(key: "user_id")
    var user: UserModel?

    @Field(key: "kind")
    var kindRaw: String

    @Field(key: "challenge_hash")
    var challengeHash: String

    @Field(key: "expires_at")
    var expiresAt: Date

    @OptionalField(key: "consumed_at")
    var consumedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID?,
        kind: PasskeyChallengeKind,
        challengeHash: String,
        expiresAt: Date,
        consumedAt: Date? = nil
    ) {
        self.id = id
        self.$user.id = userID
        self.kindRaw = kind.rawValue
        self.challengeHash = challengeHash
        self.expiresAt = expiresAt
        self.consumedAt = consumedAt
    }
}

extension PasskeyChallengeModel: StoredPasskeyChallenge {
    var kind: PasskeyChallengeKind {
        PasskeyChallengeKind(rawValue: kindRaw) ?? .authentication
    }
}
