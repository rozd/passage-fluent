import Foundation
import Passage
import Fluent

final class RefreshTokenModel: Model, @unchecked Sendable {
    static let schema = "refresh_tokens"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "token_hash")
    var tokenHash: String

    @Parent(key: "user_id")
    var user: UserModel

    @Field(key: "expires_at")
    var expiresAt: Date

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @OptionalField(key: "revoked_at")
    var revokedAt: Date?

    @OptionalField(key: "replaced_by")
    var replacedBy: UUID?

    init() {}

    init(
        id: UUID? = nil,
        tokenHash: String,
        userID: UUID,
        expiresAt: Date,
        revokedAt: Date? = nil,
        replacedBy: UUID? = nil
    ) {
        self.id = id
        self.tokenHash = tokenHash
        self.$user.id = userID
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.replacedBy = replacedBy
    }
}

extension RefreshTokenModel: RefreshToken {

}
