import Foundation
import Passage
import Fluent

final class RefreshTokenModel<UserModel: PassageUserModel>: Model, @unchecked Sendable {
    static var schema: String { "refresh_tokens" }

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

    @Field(key: "session_id")
    var sessionId: UUID

    init() {}

    init(
        id: UUID? = nil,
        tokenHash: String,
        userID: UserModel.IDValue,
        expiresAt: Date,
        sessionId: UUID,
        revokedAt: Date? = nil,
        replacedBy: UUID? = nil
    ) {
        self.id = id
        self.tokenHash = tokenHash
        self.$user.id = userID
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.replacedBy = replacedBy
        self.sessionId = sessionId
    }
}

extension RefreshTokenModel: RefreshToken {

}
